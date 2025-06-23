const std = @import("std");
const server = @import("lib/server.zig");

const StompServer = @import("server.zig").StompServer;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    defer switch (gpa.deinit()) {
        .leak => std.log.err("leaked memory fuckkkkk!!!!", .{}),
        .ok => {},
    };

    const server_allocator = gpa.allocator();

    var server_ctx = try StompServer.Ctx.init(server_allocator);
    defer server_ctx.deinit();

    const env_hostname = server_ctx.envd.get("SV_HOSTNAME") orelse "localhost";
    const env_port = server_ctx.envd.get("SV_PORT") orelse "3000";
    
    var stomp_server = server.TcpServer(StompServer).init(server_allocator, .{
        .hostname = env_hostname,
        .port = try std.fmt.parseUnsigned(u16, env_port, 10),
    });

    try stomp_server.listen(&server_ctx);
}




