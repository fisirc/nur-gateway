const std = @import("std");
const libthwomp = @import("libthwomp");
const dotenv = @import("dotenv");

const pq = @import("lib/pq.zig");
const server = @import("lib/server.zig");

const QueueMap = @import("queues.zig").SyncQueueMap;
const EnvMap = std.process.EnvMap;

const StompServer = struct {
    pub const Ctx = struct {
        qmap: QueueMap,
        envd: EnvMap,

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return @This(){
                .qmap = try QueueMap.init(alloc),
                .envd = try dotenv.loadEnv(512, ".env", alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.qmap.deinit();
            self.envd.deinit();
        }
    };

    fn projectIdFromTarget(target: []const u8) ![]const u8 {
        if (target[0] != '/') return error.InvalidTarget;

        const target_head = target[1..];
        if (target_head.len == 0) return error.InvalidTarget;

        var iterator = std.mem.splitScalar(u8, target_head, '/');
        const id = iterator.next() orelse return error.InvalidTarget;

        return id;
    }

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

        const handler_allocator = gpa.allocator();

        // supabase postgresql connection url
        const pg_path_nozero = srv_ctx.envd.get("PG_URL") orelse {
            std.log.err("postgres connection url is null", .{});
            return;
        };

        const pg_path = handler_allocator.allocSentinel(u8, pg_path_nozero.len, 0) catch |err| {
            std.log.err("couldnt alloc zeroed path: {}", .{ err });
            return;
        };

        defer handler_allocator.free(pg_path);
        
        var header_buffer: [4096]u8 = @splat(0);
        var ready_server = std.http.Server.init(connection, header_buffer[0..]);
        const request_with_header = ready_server.receiveHead() catch |err| {
            std.log.err("couldn't receive http header from connection: {}", .{ err });
            return;
        };

        // every (method, target) pair should correspond to a single function id
        // which will then be passed down to the worker
        const method = @tagName(request_with_header.head.method);
        const target = request_with_header.head.target;
        const project_id = projectIdFromTarget(target) catch {
            std.log.err("couldn't get project id from the target, is the target fine? target: {s}", .{ target });
            return;
        };

        // we will ignore the project id from the path (this is hwo they are stored in the db)
        const truncated_target = target[1 + project_id.len..];

        const conn = pq.connectDbSafe(pg_path) catch {
            std.log.err("couldn't establish connection with the db", .{});
            return;
        }; defer pq.finishConn(conn);

        const result = pq.execQueryWithParams(
            conn,
            "select function_id from methods m join routes r on m.route_id = r.id where r.path_absolute = $1 and m.method_name = $2 and r.project_id = $3;",
            .{
                truncated_target,
                method,
                project_id,
            },
        ) catch |err| {
            std.log.err("couldn't execute query: {}", .{ err });
            return;
        };

        const result_rows = pq.resultRowsLen(result);
        if (result_rows == 0) {
            std.log.err("no matches for method({s}), project_id({s}), target({s})", .{
                method,
                project_id,
                truncated_target,
            });
            return;
        }

        const function_id = pq.getValueAt(result, 0, 0);
        std.log.err("function_id = {s}", .{ function_id });

        // start the worker protocol
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




