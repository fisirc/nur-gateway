const std = @import("std");

/// epoll_wait timeout value (1s is just fine)
const epoll_wait_timeout: u32 = 1000;

/// epoll can only wait for so many events on fds, we must store
/// those events in a buffer of a certain size, the router should not
/// accept any new route beyond this limit
const events_buffersize = 8192;

/// full page reads before forwarding
const static_read_size = 4096;

pub const EpollEvent = std.os.linux.epoll_event;

pub const Promise = struct {
    const Self = @This();

    cond: std.Thread.Condition = .{},
    lock: std.Thread.Mutex = .{},
    state: enum {
        pending,
        finished,
    } = .pending,

    pub fn wait(self: *Self) void {
        self.lock.lock();
        defer self.lock.unlock();

        while (self.state != .finished) {
            self.cond.wait(&self.lock);
        }
    }

    pub fn finish(self: *Self) void {
        {
            self.lock.lock();
            defer self.lock.unlock();

            self.state = .finished;
        }

        self.cond.signal();
    }
};

pub const Router = struct {
    const Self = @This();

    epoll_fd: std.posix.fd_t,

    alloc: std.mem.Allocator,
    stream_router: std.AutoHashMap(*const std.net.Stream, *const std.net.Stream),
    conds_router: std.AutoHashMap(*const std.net.Stream, *Promise),

    enroute_lock: std.Thread.RwLock = .{},

    pub fn init(alloc: std.mem.Allocator) !Router {
        const epoll_instance_fd = std.posix.epoll_create1(0) catch return error.CouldntInstanceEpoll;

        return .{
            .epoll_fd = epoll_instance_fd,
            .alloc = alloc,
            .stream_router = std.AutoHashMap(*const std.net.Stream, *const std.net.Stream).init(alloc),
            .conds_router = std.AutoHashMap(*const std.net.Stream, *Promise).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        // epoll must be closed
        std.posix.close(self.epoll_fd);

        self.stream_router.deinit();
        self.conds_router.deinit();
    }

    pub fn epollWait(self: *Self, events_buffer: []EpollEvent) []EpollEvent {
        return events_buffer[0..std.posix.epoll_wait(self.epoll_fd, events_buffer, epoll_wait_timeout)];
    }

    const DiscardError = error {
        NoMatchingLock,
        NoMatchingStream,
        EpollCtlErr,
    };

    pub fn discardPipe(self: *Self, stream_ptr: *std.net.Stream) DiscardError!void {
        // discarding routes is considered a "write lock" type of operation
        self.enroute_lock.lock();
        defer self.enroute_lock.unlock();

        const pair_ptr = self.stream_router.get(stream_ptr) orelse return DiscardError.NoMatchingStream;
        _ = self.stream_router.remove(stream_ptr);
        _ = self.stream_router.remove(pair_ptr);

        std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, stream_ptr.handle, null) catch return DiscardError.EpollCtlErr;
        std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_DEL, pair_ptr.handle, null) catch return DiscardError.EpollCtlErr;

        const promise_ptr = self.conds_router.get(stream_ptr) orelse return DiscardError.NoMatchingLock;
        _ = self.conds_router.remove(stream_ptr);

        if (self.conds_router.remove(pair_ptr) == false) return DiscardError.NoMatchingLock;

        // after removing the stream, we return the control to the routing thread to close it or whatever
        promise_ptr.finish();
    }

    pub fn addPipe(self: *Self, src_stream: *const std.net.Stream, dest_stream: *const std.net.Stream, wait_promise: *Promise) !void {
        // adding new routes is considered a "write lock" type of operation
        self.enroute_lock.lock();
        defer self.enroute_lock.unlock();

        if (self.stream_router.count() == events_buffersize) return error.OutOfSpace;

        var src_event: std.os.linux.epoll_event = .{
            .data = .{ .ptr = @intFromPtr(src_stream) },
            .events = std.os.linux.EPOLL.IN,
        };

        var dest_event: std.os.linux.epoll_event = .{
            .data = .{ .ptr = @intFromPtr(dest_stream) },
            .events = std.os.linux.EPOLL.IN,
        };

        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, src_stream.handle, &src_event);
        try std.posix.epoll_ctl(self.epoll_fd, std.os.linux.EPOLL.CTL_ADD, dest_stream.handle, &dest_event);

        try self.stream_router.put(src_stream, dest_stream);
        try self.stream_router.put(dest_stream, src_stream);

        try self.conds_router.put(src_stream, wait_promise);
        try self.conds_router.put(dest_stream, wait_promise);
    }
};

/// starts the wait->read->write forward routing loop, this is a blocking point and never returns
pub fn watchForward(router: *Router) void {
    const events_buffer = router.alloc.alloc(EpollEvent, events_buffersize) catch |err| {
        std.log.err("couldnt alloc the events buffer: {}", .{ err });
        unreachable;
    };

    defer router.alloc.free(events_buffer);

    var read_bytes_container = std.ArrayList(u8).init(router.alloc);
    defer read_bytes_container.deinit();

    var static_buffer: [static_read_size]u8 = @splat(0);

    while (true) {
        // get the reader lock before actually waiting, we consider
        // waiting a "reading" operation on the epoll instance
        router.enroute_lock.lockShared();
        const epoll_returned_events = router.epollWait(events_buffer);
        router.enroute_lock.unlockShared();

        handle_events_loop: for (epoll_returned_events) |returned_event| {
            const stream_ptr: *std.net.Stream = @ptrFromInt(returned_event.data.ptr);

            // this block should only return on error, otherwise
            // the flow should go back to the "handle events" loop
            const pipe_err = event_pipe: {
                defer read_bytes_container.clearRetainingCapacity();

                // these are both signals that the connection has closed:
                // - EPOLLHUP: the peer closed its end of the channel
                // - EPOLLERR: error condition happened on the associated file descriptor
                if (returned_event.events & (std.os.linux.EPOLL.HUP | std.os.linux.EPOLL.ERR) != 0) {
                    break :event_pipe error.StreamClosed;
                }

                while (true) {
                    const read_bytes_len = stream_ptr.read(static_buffer[0..]) catch |err| break :event_pipe err;
                    read_bytes_container.appendSlice(static_buffer[0..read_bytes_len]) catch |err| break :event_pipe err;

                    // the reading loop closes on the first partial read
                    if (read_bytes_len < static_read_size) break;
                }

                if (read_bytes_container.items.len == 0) break :event_pipe error.NoData;

                const dest_stream_ptr = router.stream_router.get(stream_ptr) orelse break :event_pipe error.UnmatchedStream;
                dest_stream_ptr.writeAll(read_bytes_container.items) catch |err| break :event_pipe err;

                continue :handle_events_loop;
            };

            std.log.err("there was a pipe error: {}, the stream will be closed", .{ pipe_err });

            router.discardPipe(stream_ptr) catch |err| {
                std.log.err("couldnt discard the stream: {}", .{ err });
                unreachable;
            };

            continue :handle_events_loop;
        }
    }
}
