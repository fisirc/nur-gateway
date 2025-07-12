const std = @import("std");
const libthwomp = @import("libthwomp");
const dotenv = @import("dotenv");

const worker_discovery = @import("lib/worker_discovery.zig");
const dbutils = @import("lib/dbutils.zig");
const uuid = @import("lib/uuid.zig");
const fd_logger = @import("lib/fd_logger.zig");
const forward_router = @import("lib/forward_route.zig");
const validate = @import("lib/validate.zig");

const EnvMap = std.process.EnvMap;

pub const MainServer = struct {
    pub const Ctx = struct {
        envd: EnvMap,
        worker_discovery_service: worker_discovery.WorkerDiscovery,
        router: forward_router.Router,

        pub fn init(alloc: std.mem.Allocator) @This() {
            const env = dotenv.loadEnv(512, ".env", alloc) catch |err| switch (err) {
                std.fs.File.OpenError.FileNotFound => std.process.getEnvMap(alloc) catch @panic("couldn't acquire envmap"),
                else => @panic("couldn't parse provided envfile"),
            };

            validate.env(env, &.{
                "PG_URL",
                "SV_HOSTNAME",
                "SV_PORT",
                "WORKER_HOSTNAME",
                "WORKER_PORT",
            });

            return @This(){
                .envd = env,

                .worker_discovery_service = worker_discovery.WorkerDiscovery.init(alloc, env) catch |err| {
                    std.log.err("couldn't init the worker discovery structure: {}", .{ err });
                    @panic("worker discovery init process errored");
                },

                .router = forward_router.Router.init(alloc) catch |err| {
                    std.log.err("couldn't init the forward router structure: {}", .{ err });
                    @panic("forward router init process errored");
                },
            };
        }

        pub fn deinit(self: *@This()) void {
            self.envd.deinit();
            self.worker_discovery_service.deinit();
            self.router.deinit();
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

    const PipeError = error {
        IoError,
        NoData,
    };

    pub fn handle(connection: std.net.Server.Connection, srv_ctx: *Ctx) void {
        defer libthwomp.ioutils.closeConnection(connection);

        const connection_fd = connection.stream.handle;

        var gpa: std.heap.GeneralPurposeAllocator(.{
            .thread_safe = true,
        }) = .init;

        defer switch (gpa.deinit()) {
            .leak => fd_logger.err(connection_fd, "memory leak detected", .{}),
            .ok => {},
        };

        const handler_allocator = gpa.allocator();

        // supabase postgresql connection url
        const pg_path = pg_path_blk: {
            const nozero = srv_ctx.envd.get("PG_URL") orelse {
                fd_logger.err(connection_fd, "postgres connection url is null", .{});
                return;
            };

            const zeroed_mem = handler_allocator.allocSentinel(u8, nozero.len, 0) catch |err| {
                fd_logger.err(connection_fd, "couldnt alloc zeroed path: {}", .{ err });
                return;
            };

            @memcpy(zeroed_mem[0..nozero.len], nozero);
            break :pg_path_blk zeroed_mem;
        };

        defer handler_allocator.free(pg_path);

        var header_buffer: [4096]u8 = @splat(0);
        var ready_server = std.http.Server.init(connection, header_buffer[0..]);
        const request_with_header = ready_server.receiveHead() catch |err| {
            fd_logger.err(connection_fd, "couldn't receive http header from connection: {}", .{ err });
            return;
        };

        const raw_http_target = request_with_header.head.target;

        // the connection is made non blocking only once the head has already been received
        libthwomp.ioutils.configHandleNoblock(connection) catch |err| {
            fd_logger.err(connection_fd, "couldn't configure socket into non blocking: {}", .{
                err,
            });

            return;
        };


        // every (method, target) pair should correspond to a single function id
        // which will then be passed down to the worker
        const method = @tagName(request_with_header.head.method);

        const project_id = projectIdFromTarget(raw_http_target) catch {
            fd_logger.err(connection_fd, "couldn't get project id from the target, is the target fine? target: {s}", .{ raw_http_target });
            return;
        };

        // we will ignore the project id from the path (this is how they are stored in the db)
        const target = raw_http_target[1 + project_id.len..];

        // now these are the actual pieces of data we need: struct { function_id, depl_date }
        const function_depl_date = dbutils.getFunctionDeplDate(pg_path, project_id, target, method) catch |err| {
            fd_logger.err(connection_fd, "couldn't get any rows: {}", .{ err });
            return;
        } orelse {
            fd_logger.err(connection_fd, "no rows matched pg_path({s}) project_id({s}) truncated_target({s})", .{
                pg_path,
                project_id,
                target,
            });
            return;
        };

        // now we just need a healthy worker connection to handshake
        const worker_discovery_service = srv_ctx.worker_discovery_service;
        const woke_connection = worker_discovery_service.findConn() catch |err| {
            fd_logger.err(connection_fd, "couldnt establish a worker connection: {}", .{ err });
            return;
        };

        defer woke_connection.close();

        const woke_payload = worker_discovery.initPayload(.v1, .{
            .function_id = function_depl_date[0],
            .deployment_date = function_depl_date[1],
        });

        woke_connection.handshake(woke_payload) catch |err| {
            fd_logger.err(connection_fd, "couldnt perform handshake over the worker connection: {}", .{ err });
            return;
        };

        fd_logger.info(connection_fd, "handshake succesful!", .{});

        // after the handshake, the worker still needs the original http header
        woke_connection.stream.writeAll(ready_server.read_buffer[0..ready_server.read_buffer_len]) catch |err| {
            fd_logger.err(connection_fd, "couldnt write http to worker: {}", .{ err });
            return;
        };

        fd_logger.info(connection_fd, "sent http header to worker", .{});

        // we finally delegate the connections to the forward router and wait
        var conn_worker_waiter: forward_router.Promise = .{};
        srv_ctx.router.addPipe(&connection.stream, &woke_connection.stream, &conn_worker_waiter) catch |err| {
            fd_logger.err(connection_fd, "couldnt route connection->worker: {}", .{ err });
            return;
        };

        conn_worker_waiter.wait();
    }
};
