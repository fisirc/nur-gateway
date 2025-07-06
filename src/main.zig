const std = @import("std");
const server = @import("lib/server.zig");
const forward_router = @import("lib/forward_route.zig");

const StompServer = @import("thwomp_server.zig").MainServer;

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true,
    }) = .init;

    defer switch (gpa.deinit()) {
        .leak => std.log.err("leaked memory from main thread", .{}),
        .ok => {},
    };

    const server_allocator = gpa.allocator();

    var server_ctx = StompServer.Ctx.init(server_allocator);
    defer server_ctx.deinit();

    std.log.info("spawning router thread", .{});
    _ = std.Thread.spawn(.{}, forward_router.watchForward, .{
        &server_ctx.router,
    }) catch {
        @panic("couldnt spawn the forward router");
    };

    const env_hostname = server_ctx.envd.get("SV_HOSTNAME").?;
    const env_port = server_ctx.envd.get("SV_PORT").?;

    std.log.info("preparing server", .{});
    var stomp_server = server.TcpServer(StompServer).init(server_allocator, .{
        .hostname = env_hostname,
        .port = try std.fmt.parseUnsigned(u16, env_port, 10),
    });

    std.log.info("listening on port {s}", .{ env_port });
    try stomp_server.listen(&server_ctx);
}
