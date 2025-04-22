const std = @import("std");
const libthwomp = @import("libthwomp");
const server = @import("lib/server.zig");

const QueueMap = @import("queues.zig").QueueMap;

const StompServer = struct {
    pub const Ctx = struct {
        qmap: QueueMap,
    };

    pub fn handle(connection: std.net.Server.Connection, srv_ctx: *Ctx) void {
        _ = srv_ctx;
        defer libthwomp.ioutils.closeConnection(connection);

        const handle_fd = connection.stream.handle;
        const conn_reader = connection.stream.reader().any();
        const conn_writer = connection.stream.writer().any();

        libthwomp.ioutils.configHandleNoblock(connection) catch |err| {
            std.log.err("couldn't configure socket into non blocking: {}", .{ err });
        };

        var gpa: std.heap.GeneralPurposeAllocator(.{
            .thread_safe = true,
        }) = .init;

        defer switch (gpa.deinit()) {
            .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
            .ok => {},
        };

        libthwomp.frameutils.handshake(conn_reader, conn_writer, handle_fd) catch |err| {
            std.log.err("couldn't establish the conn handshake: {}", .{ err });
            return;
        };
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

    var a = StompServer.Ctx{
        .qmap = try QueueMap.init(server_allocator),
    };

    try stomp_server.listen(&a);
}




