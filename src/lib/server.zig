const std = @import("std");
const pconsumer = @import("pconsumer.zig");
const Connection = std.net.Server.Connection;

const HandlerType = fn (arg0: Connection) void;

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

fn loopPullAndHandle(
    thrd_pool: *std.Thread.Pool,
    conn_pool: *pconsumer.Queue(Connection),
    handler: HandlerType
) void {
    std.log.info("ready for connections", .{});

    while (true) {
        const conn = conn_pool.pullMsg() catch |err| {
            std.log.err("couldn't pull message from queue: {}", .{ err });
            continue;
        };

        std.log.info("connection pulled, deploying handler", .{});

        thrd_pool.spawn(handler, .{
            conn,
        }) catch |err| {
            std.log.err("couldn't deploy handler thread: {}", .{ err });
            continue;
        };
    }
}

pub const TcpServer = struct {
    const Self = @This();
    const Options = struct {
        port: u16 = 6969,
        hostname: []const u8 = "localhost",

        /// you probably dont need more to be fair
        keepers_size: usize = 4,
    };

    p_server: std.net.Server = undefined,
    alloc: std.mem.Allocator,

    pub fn default(alloc: std.mem.Allocator) Self {
        return Self{
            .alloc = alloc,
        };
    }

    pub fn listen(self: *Self, options: Options, handler: HandlerType) !void {
        var new_pool: std.Thread.Pool = undefined;
        try new_pool.init(.{
            .allocator = self.alloc,
        });

        defer new_pool.deinit();

        const host_ip = try std.net.Address.resolveIp(options.hostname, options.port);
        var server = try std.net.Address.listen(host_ip, .{
            .reuse_address = true,

            // the default max backlog has been 4096 since Linux 5.4, it
            // probably gets capped in windows too
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

        loopPullAndHandle(&new_pool, &queue, handler);
        return;
    }
};

