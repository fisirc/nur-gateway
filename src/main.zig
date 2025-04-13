const std = @import("std");
const thwomp = @import("libthwomp");
const server = @import("lib/server.zig");

fn handleConn(connection: *std.net.Server.Connection) void {
    connection.stream.writeAll("dying spell!!!\n") catch |err| {
        std.log.err("bro wtf {}", .{err});
        return;
    };

    connection.stream.close();
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




