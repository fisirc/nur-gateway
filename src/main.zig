const std = @import("std");
const libthwomp = @import("libthwomp");
const server = @import("lib/server.zig");

const StompServer = struct {
    pub const Ctx = struct {};

    pub fn handle(connection: std.net.Server.Connection, srv_ctx: *Ctx) void {
        _ = srv_ctx;

        const handle_fd = connection.stream.handle;
        const conn_reader = connection.stream.reader().any();
        const conn_writer = connection.stream.writer().any();

        libthwomp.ioutils.configHandleNoblock(connection) catch |err| {
            std.log.err("couldn't configure socket into non blocking: {}", .{ err });
        };

        defer {
            connection.stream.close();
            std.log.info("closed connection addr({}):fd({})", .{
                connection.address,
                connection.stream.handle,
            });
        }

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

    var stomp_server = server.TcpServer(StompServer).init(gpa.allocator(), .{
        .hostname = "0.0.0.0",
        .port = 3000,
    });

    var a = StompServer.Ctx{};

    try stomp_server.listen(&a);
}




