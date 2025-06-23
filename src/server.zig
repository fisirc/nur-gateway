const std = @import("std");
const libthwomp = @import("libthwomp");
const dotenv = @import("dotenv");

const worker_discovery = @import("lib/worker_discovery.zig");
const dbutils = @import("lib/dbutils.zig");
const uuid = @import("lib/uuid.zig");

const QueueMap = @import("queues.zig").SyncQueueMap;
const EnvMap = std.process.EnvMap;

pub const StompServer = struct {
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

        @memcpy(pg_path[0..pg_path_nozero.len], pg_path_nozero);

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

        // now this are the actual pieces of data we need:_struct { function_id, depl_date }
        const function_depl_date = dbutils.getFunctionDeplDate(pg_path, project_id, truncated_target, method) catch unreachable;

        const the_woker = worker_discovery.WorkerDiscovery.init(handler_allocator) catch |err| {
            std.log.err("couldnt alloc new worker discovery unit: {}", .{ err });
            return;
        }; defer the_woker.deinit();

        const woke_connection = the_woker.findConn() catch |err| {
            std.log.err("couldnt establish a worker connection: {}", .{ err });
            return;
        };

        const woke_payload = worker_discovery.genPayload(.v1, .{
            .function_id = function_depl_date[0],
            .deployment_date = function_depl_date[1],
        });

        woke_connection.handshake(woke_payload) catch |err| {
            std.log.err("couldnt perform handshake over the worker connection: {}", .{ err });
            return;
        };

        std.log.info("handshake succesful!", .{});
    }
};


