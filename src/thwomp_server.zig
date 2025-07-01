const std = @import("std");
const libthwomp = @import("libthwomp");
const dotenv = @import("dotenv");

const worker_discovery = @import("lib/worker_discovery.zig");
const dbutils = @import("lib/dbutils.zig");
const uuid = @import("lib/uuid.zig");
const proxy = @import("lib/proxy_scheduler.zig");

const QueueMap = @import("queues.zig").SyncQueueMap;
const EnvMap = std.process.EnvMap;

pub const MainServer = struct {
    pub const Ctx = struct {
        qmap: QueueMap,
        envd: EnvMap,
        proxy_router: proxy.SyncRouter,
        worker_discovery_service: worker_discovery.WorkerDiscovery,

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return @This(){
                .qmap = try QueueMap.init(alloc),
                .envd = try dotenv.loadEnv(512, ".env", alloc),
                .proxy_router = proxy.SyncRouter.init(alloc),
                .worker_discovery_service = try worker_discovery.WorkerDiscovery.init(alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.qmap.deinit();
            self.envd.deinit();
            self.proxy_router.deinit();
            self.worker_discovery_service.deinit();
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
        const pg_path = pg_path_blk: {
            const nozero = srv_ctx.envd.get("PG_URL") orelse {
                std.log.err("postgres connection url is null", .{});
                return;
            };

            const zeroed_mem = handler_allocator.allocSentinel(u8, nozero.len, 0) catch |err| {
                std.log.err("couldnt alloc zeroed path: {}", .{ err });
                return;
            };

            @memcpy(zeroed_mem[0..nozero.len], nozero);

            break :pg_path_blk zeroed_mem;
        };

        defer handler_allocator.free(pg_path);

        var header_buffer: [4096]u8 = @splat(0);
        var ready_server = std.http.Server.init(connection, header_buffer[0..]);
        const request_with_header = ready_server.receiveHead() catch |err| {
            std.log.err("couldn't receive http header from connection: {}", .{ err });
            unreachable;
        };

        const raw_http_target = request_with_header.head.target;

        // every (method, target) pair should correspond to a single function id
        // which will then be passed down to the worker
        const method = @tagName(request_with_header.head.method);

        const project_id = projectIdFromTarget(raw_http_target) catch {
            std.log.err("couldn't get project id from the target, is the target fine? target: {s}", .{ raw_http_target });
            return;
        };

        // we will ignore the project id from the path (this is how they are stored in the db)
        const target = raw_http_target[1 + project_id.len..];

        // now these are the actual pieces of data we need:_struct { function_id, depl_date }
        const function_depl_date = dbutils.getFunctionDeplDate(pg_path, project_id, target, method) catch |err| {
            std.log.err("couldn't get any rows: {}", .{ err });
            return;
        } orelse {
            std.log.err("no rows matched pg_path({s}) project_id({s}) truncated_target({s})", .{
                pg_path,
                project_id,
                target,
            });
            return;
        };

        const worker_discovery_service = srv_ctx.worker_discovery_service;

        const woke_connection = worker_discovery_service.findConn() catch |err| {
            std.log.err("couldnt establish a worker connection: {}", .{ err });
            return;
        };

        defer woke_connection.close();

        const woke_payload = worker_discovery.initPayload(.v1, .{
            .function_id = function_depl_date[0],
            .deployment_date = function_depl_date[1],
        });

        woke_connection.handshake(woke_payload) catch |err| {
            std.log.err("couldnt perform handshake over the worker connection: {}", .{ err });
            return;
        };

        std.log.info("handshake succesful!", .{});

        woke_connection.stream.writeAll(ready_server.read_buffer[0..ready_server.read_buffer_len]) catch |err| {
            std.log.err("couldnt write http to worker: {}", .{ err });
            return;
        };

        std.log.info("sent http header to worker", .{});

        const epoll_instance_fd = std.posix.epoll_create1(0) catch unreachable;

        std.log.info("created new epoll instance", .{});

        var web_conn_event = std.os.linux.epoll_event{
            .data = .{ .fd = connection.stream.handle },
            .events = std.os.linux.EPOLL.IN,
        };

        std.posix.epoll_ctl(epoll_instance_fd, std.os.linux.EPOLL.CTL_ADD, connection.stream.handle, &web_conn_event) catch |err| {
            std.log.err("couldnt invoke epoll ctl: {}", .{ err });
            return;
        };

        std.log.info("added http conn to epoll", .{});

        var worker_conn_event = std.os.linux.epoll_event{
            .data = .{ .fd = woke_connection.stream.handle },
            .events = std.os.linux.EPOLL.IN,
        };

        std.posix.epoll_ctl(epoll_instance_fd, std.os.linux.EPOLL.CTL_ADD, woke_connection.stream.handle, &worker_conn_event) catch |err| {
            std.log.err("couldnt invoke epoll ctl: {}", .{ err });
            return;
        };

        std.log.info("added worker conn to epoll", .{});

        var epoll_returned_events_buffer: [8]std.os.linux.epoll_event = undefined;

        spin_on_data: while (true) {
            std.log.info("waiting for data...", .{});

            const epoll_returned_events = events_blk: {
                const events_size = std.posix.epoll_wait(epoll_instance_fd, epoll_returned_events_buffer[0..], 1000);
                break :events_blk epoll_returned_events_buffer[0..events_size];
            };

            if (epoll_returned_events.len == 0) {
                std.log.info("conn is ready but no data was received, goodbye!", .{});
                break :spin_on_data;
            }

            for (epoll_returned_events) |returned_event| {
                const fd = returned_event.data.fd;

                if (returned_event.events == std.os.linux.EPOLL.HUP) {
                    break :spin_on_data;
                }

                if (fd == connection.stream.handle) {
                    proxy.pipeData(connection.stream, woke_connection.stream) catch |err| {
                        std.log.err("pipe io error: {}", .{
                            err,
                        });

                        break :spin_on_data;
                    };
                } else if (fd == woke_connection.stream.handle) {
                    proxy.pipeData(woke_connection.stream, connection.stream) catch |err| {
                        std.log.err("pipe io error: {}", .{
                            err,
                        });

                        break :spin_on_data;
                    };
                }
            }
        }
    }
};
