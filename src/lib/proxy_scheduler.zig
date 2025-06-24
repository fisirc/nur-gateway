const std = @import("std");

pub const SyncRouter = struct {
    const Self = @This();

    alloc: std.mem.Allocator,

    route_pairs: std.AutoArrayHashMap(std.net.Stream, std.net.Stream),
    route_lock: std.Thread.Mutex,

    pub fn init(alloc: std.mem.Allocator) Self {
        return Self{
            .alloc = alloc,
            .route_pairs = std.AutoArrayHashMap(std.net.Stream, std.net.Stream).init(alloc),
            .route_lock = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.route_pairs.deinit();
    }

    pub fn addRoute(self: *Self, origin: std.net.Stream, dest: std.net.Stream) error{InternalMemoryFault}!void {
        self.route_lock.lock();
        {
            self.route_pairs.put(origin, dest) catch return error.InternalMemoryFault;
        }
        self.route_lock.unlock();
    }

    pub fn removeRoute(self: *Self, origin: std.net.Stream) error{NotInRouter}!void {
        if (!self.route_pairs.remove(origin)) return error.NotInRouter;
    }

    pub fn getOrigins(self: *Self, allocator: std.mem.Allocator) ![]std.net.Stream {
        self.route_lock.lock();

        const og_keys = self.route_pairs.keys();

        var origin_keys_copy = try allocator.alloc(std.net.Stream, og_keys.len);
        for (0..origin_keys_copy.len) |idx| {
            origin_keys_copy[idx] = og_keys[idx];
        }

        self.route_lock.unlock();

        return origin_keys_copy;
    }

    pub fn destFromOrigin(self: *Self, origin: std.net.Stream) ?std.net.Stream {
        self.route_lock.lock();
        const dest = self.route_pairs.get(origin);
        self.route_lock.unlock();

        return dest;
    }
};

const PipeError = error {
    IoError,
    NoData,
};

pub fn pipeData(origin: std.net.Stream, destination: std.net.Stream) PipeError!void {
    const reader = origin.reader().any();
    const writer = destination.writer().any();

    var buffer: [4096]u8 = @splat(0);
    const read_len = reader.read(buffer[0..]) catch return PipeError.IoError;

    if (read_len == 0) return PipeError.NoData;

    writer.writeAll(buffer[0..read_len]) catch return PipeError.IoError;
}

pub fn initProxy(router: *SyncRouter) void {
    var proxy_alloc_base: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const allocator = proxy_alloc_base.allocator();

    var epoll_returned_events_buffer = allocator.alloc(std.os.linux.epoll_event, 1 * 1024 * 1024) catch unreachable;

    while (true) {
        const interested_fds = router.getOrigins(allocator) catch unreachable;
        defer allocator.free(interested_fds);

        if (interested_fds.len == 0) continue;

        const epoll_instance_fd = std.posix.epoll_create1(0) catch unreachable;

        for (0..interested_fds.len) |idx| {
            var event = std.os.linux.epoll_event{
                .data = .{ .ptr = @intFromPtr(&interested_fds[idx]) },
                .events = std.os.linux.EPOLL.IN,
            };

            std.posix.epoll_ctl(epoll_instance_fd, std.os.linux.EPOLL.CTL_ADD, interested_fds[idx].handle, &event) catch unreachable;
        }

        const epoll_returned_events = events_blk: {
            const events_size = std.posix.epoll_wait(epoll_instance_fd, epoll_returned_events_buffer[0..], 1000);
            break :events_blk epoll_returned_events_buffer[0..events_size];
        };

        if (epoll_returned_events.len == 0) unreachable;

        for (epoll_returned_events) |event| {
            const orig: *std.net.Stream = @ptrFromInt(event.data.ptr);
            const dest = router.destFromOrigin(orig.*) orelse {
                std.log.err("origin has no value match: {}", .{
                    orig,
                });

                continue;
            };

            pipeData(orig.*, dest) catch |err| {
                std.log.err("pipe io error: {}", .{
                    err,
                });

                continue;
            };
        }
    }
}
