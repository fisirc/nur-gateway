const std = @import("std");
const libthwomp = @import("libthwomp");
const server = @import("lib/server.zig");

fn handleConn(connection: *std.net.Server.Connection) void {
    defer connection.stream.close();

    const conn_reader = connection.stream.reader().any();

    var buffer: [4096]u8 = @splat(0);
    const read_size = conn_reader.readAll(buffer[0..]) catch |err| {
        std.log.err("couldn't read from client stream: {}", .{ err });
        return;
    };

    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    const data = buffer[0..read_size];
    const frame = libthwomp.Parser.parseData(data, gpa.allocator()) catch |err| {
        std.debug.print("{s}\n", .{data});
        std.log.err("couldn't parse client frame: {}", .{ err });
        return;
    };

    std.debug.dumpHex(data);
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




