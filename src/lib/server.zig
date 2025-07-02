const std = @import("std");
const pconsumer = @import("pconsumer.zig");
const Connection = std.net.Server.Connection;

pub fn TcpServer(handler_type: type) type {
    if (!@hasDecl(handler_type, "Ctx")) @compileError("type must include a public Ctx type");
    if (!@hasDecl(handler_type, "handle")) @compileError("type must include a public handle function");

    const HandlerCtx = handler_type.Ctx;
    const HandlerType = fn (arg0: Connection, arg1: *HandlerCtx) void;
    if (@TypeOf(handler_type.handle) != HandlerType) @compileError("unexpected handler type");

    return struct {
        const Self = @This();
        const Options = struct {
            port: u16 = 6969,
            hostname: []const u8 = "localhost",

            /// you probably dont need more to be fair
            keepers_size: usize = 4,
        };

        p_server: std.net.Server = undefined,
        alloc: std.mem.Allocator,
        options: Options,

        fn gatekeep(server: *std.net.Server, conn_pool: *pconsumer.Queue(Connection)) void {
            while (true) {
                const conn = server.accept() catch |err| {
                    std.log.err("couldn't accept connection: {}", .{ err });
                    continue;
                };

                conn_pool.pushMsg(conn) catch |err| {
                    std.log.err("couldn't push to conn pool: {}", .{ err });

                    // it won't get handled anyways
                    conn.stream.close();
                };
            }
        }

        pub fn init(alloc: std.mem.Allocator, options: Options) Self {
            return Self{
                .alloc = alloc,
                .options = options,
            };
        }

        fn loopPullAndHandle(
            thrd_pool: *std.Thread.Pool,
            conn_pool: *pconsumer.Queue(Connection),
            handler: HandlerType,
            handler_ctx: *HandlerCtx,
        ) void {
            std.log.info("ready for connections", .{});

            while (true) {
                const conn = conn_pool.pullMsg() catch |err| {
                    std.log.err("couldn't pull message from queue: {}", .{ err });
                    continue;
                };

                std.log.info("connection pulled address({}) fd({}), deploying handler", .{
                    conn.address,
                    conn.stream.handle,
                });

                thrd_pool.spawn(handler, .{
                    conn,
                    handler_ctx,
                }) catch |err| {
                    std.log.err("couldn't deploy handler thread: {}", .{ err });
                    continue;
                };
            }
        }

        pub fn listen(self: *Self, ctx: *HandlerCtx) !void {
            const options = self.options;

            var new_pool: std.Thread.Pool = undefined;
            try new_pool.init(.{
                .allocator = self.alloc,
            });

            defer new_pool.deinit();

            const addr_list = try std.net.getAddressList(self.alloc, options.hostname, options.port);
            if (addr_list.addrs.len == 0) return error.UnknownHostName;

            const address = addr_list.addrs[0];
            var server = try std.net.Address.listen(address, .{
                // this is so the port does not "block" after a forceful kill
                // signal
                .reuse_address = true,

                // the default max backlog has been 4096 since Linux 5.4, any
                // value over it in such platform gets capped
                .kernel_backlog = 4096,
            }); defer server.deinit();

            var queue = try pconsumer.Queue(Connection).init(self.alloc);

            var keeper_threads = try self.alloc.alloc(std.Thread, options.keepers_size);
            for (0..keeper_threads.len) |index| {
                keeper_threads[index] = try std.Thread.spawn(.{}, gatekeep, .{
                    &server,
                    &queue,
                });
            }

            std.log.info("allocated {} gatekeeper threads", .{keeper_threads.len});
            loopPullAndHandle(&new_pool, &queue, handler_type.handle, ctx);

            return;
        }
    };
}


