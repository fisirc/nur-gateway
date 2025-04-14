const std = @import("std");
const libthwomp = @import("libthwomp");
const server = @import("lib/server.zig");

fn handleConn(connection: std.net.Server.Connection) void {
    defer connection.stream.close();
    const conn_reader = connection.stream.reader().any();

    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    defer switch (gpa.deinit()) {
        .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
        .ok => {},
    };

    var buffer: [4096]u8 = @splat(0);
    const read_size = conn_reader.readAll(buffer[0..]) catch |err| {
        std.log.err("couldn't read from client stream: {}", .{ err });
        return;
    };

    const data = buffer[0..read_size];
    var frame = libthwomp.parser.parseFrame(data, gpa.allocator()) catch |err| {
        std.log.err("couldn't parse client frame: {}", .{ err });
        return;
    }; defer frame.deinit();

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




