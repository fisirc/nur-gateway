const std = @import("std");
const libthwomp = @import("libthwomp");
const server = @import("lib/server.zig");
const netutils = @import("lib/netutils.zig");

fn handleConn(connection: std.net.Server.Connection) void {
    const handle = connection.stream.handle;
    const conn_reader = connection.stream.reader().any();

    netutils.configHandleNoblock(connection) catch |err| {
        std.log.err("couldn't configure socket into non blocking: {}", .{ err });
    };

    defer connection.stream.close();

    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    defer switch (gpa.deinit()) {
        .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
        .ok => {},
    };

    var poll_fds = [_]std.posix.pollfd{
        std.posix.pollfd{
            .fd = handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }
    };

    while (true) {
        _ = std.posix.poll(poll_fds[0..], -1) catch |err| {
            std.log.err("poll failed: {}", .{ err });
            return;
        };

        if (poll_fds[0].revents == std.posix.POLL.IN) break;
    }

    var buffer: [4096]u8 = @splat(0);
    const read_size = conn_reader.read(buffer[0..]) catch |err| {
        std.log.err("couldn't read from client stream: {}", .{ err });
        return;
    };

    const data = buffer[0..read_size];
    var frame = libthwomp.parser.parseFrame(data, gpa.allocator()) catch |err| {
        std.log.err("couldn't parse client frame: {}", .{ err });
        return;
    };

    defer frame.deinit();

    std.debug.print("{any}\n", .{ frame });
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    defer switch (gpa.deinit()) {
        .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
        .ok => {},
    };

    var srv: server.TcpServer = .default(gpa.allocator());
    try srv.listen(.{
        .hostname = "0.0.0.0",
    }, handleConn);
}




