const std = @import("std");
const libthwomp = @import("libthwomp");

const pq = @import("lib/pq.zig");
const server = @import("lib/server.zig");

const QueueMap = @import("queues.zig").SyncQueueMap;

const StompServer = struct {
    pub const Ctx = struct {
        qmap: QueueMap,

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return @This(){
                .qmap = try QueueMap.init(alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.qmap.deinit();
        }
    };

    pub fn handle(connection: std.net.Server.Connection, srv_ctx: *Ctx) void {
        defer libthwomp.ioutils.closeConnection(connection);

        // const handle_fd = connection.stream.handle;
        // const conn_reader = connection.stream.reader().any();
        // const conn_writer = connection.stream.writer().any();

        libthwomp.ioutils.configHandleNoblock(connection) catch |err| {
            std.log.err("couldn't configure socket into non blocking: {}", .{ err });
            return;
        };

        var gpa: std.heap.GeneralPurposeAllocator(.{
            .thread_safe = true,
        }) = .init;

        defer switch (gpa.deinit()) {
            .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
            .ok => {},
        };

        var header_buffer: [4096]u8 = @splat(0);
        var ready_server = std.http.Server.init(connection, header_buffer[0..]);
        const request_with_header = ready_server.receiveHead() catch |err| {
            std.log.err("couldn't receive http header from connection: {}", .{ err });
            return;
        };

        // every (method, target) pair should correspond to a single function id
        // which will then be passed down to the worker
        const method = request_with_header.head.method;
        const target = request_with_header.head.target;
        _ = method;
        _ = target;

        const conn = pq.connectDbSafe("postgresql://postgres:3XJ6XVYhh701ybun@db.hgowvvjfbzaayphkktyo.supabase.co:5432/postgres") catch |_| {
            std.log.err("couldn't establish connection with the db: {}", .{
                pq.PQGetErrorMessage(),
            });
            return;
        };

        const frame_buffer = handler_allocator.alloc(
            u8,
            libthwomp.Frame.max_frame_size,
        ) catch |err| {
            std.log.err("couldn't allocate frame buffer: {}", .{ err });
            return;
        };

        defer handler_allocator.free(frame_buffer);

        for (0..1) |_| {
            const frame_data = libthwomp.ioutils.pollAndRead(
                handle_fd,
                conn_reader,
                frame_buffer,
            ) catch |err| {
                std.log.err("couldn't poll and read: {}", .{ err });
                return;
            };

            const wrapped_res = libthwomp.parser.parseFrame(
                frame_data,
                handler_allocator,
            ) catch |err| {
                std.log.err("couldn't parse frame: {}", .{ err });
                return;
            };

            defer wrapped_res.deinit();

            switch (wrapped_res.frame.command) {
                .send => {
                    srv_ctx.qmap.pushToQueue(wrapped_res.frame.body orelse @constCast(""), @constCast("queue")) catch |err| {
                        std.log.err("couldn't store message: {}", .{ err });
                        return;
                    };
                },

                else => unreachable,
            }
        }
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    defer switch (gpa.deinit()) {
        .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
        .ok => {},
    };

    const server_allocator = gpa.allocator();

    var stomp_server = server.TcpServer(StompServer).init(server_allocator, .{
        .hostname = "0.0.0.0",
        .port = 3000,
    });

    var server_ctx = try StompServer.Ctx.init(server_allocator);
    defer server_ctx.deinit();

    try stomp_server.listen(&server_ctx);
}




