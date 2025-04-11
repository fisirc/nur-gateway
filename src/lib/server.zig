const std = @import("std");
const pconsumer = @import("pconsumer.zig");
const Connection = std.net.Server.Connection;

const HandlerType = fn (arg0: *Connection) void;

fn gatekeep(server: *std.net.Server, conn_pool: *pconsumer.Queue(Connection)) void {
    while (true) {
        const conn = server.accept() catch |err| {
            std.log.err("[ERROR] couldn't accept connection: {}\n", .{ err });
            continue;
        };

        conn_pool.pushMsg(conn) catch |err| {
            std.log.err("[ERROR] couldn't push to conn pool: {}\n", .{ err });

            // it won't get handled anyways
            conn.stream.close();
        };
    }
}

fn loopPullAndHandle(conn_pool: *pconsumer.Queue(Connection), handler: HandlerType) void {
    while (true) {
        var conn = conn_pool.pullMsg() catch |err| {
            std.log.err("[ERROR] couldn't pull message from queue: {}\n", .{ err });
            continue;
        };

        handler(&conn);
    }
}

pub const TcpServer = struct {
    const Self = @This();
    const Options = struct {
        port: u16 = 6969,
        hostname: []const u8 = "localhost",
    };

    p_server: std.net.Server = undefined,
    alloc: std.mem.Allocator,

    pub fn default(alloc: std.mem.Allocator) Self {
        return Self{
            .alloc = alloc,
        };
    }

    pub fn listen(self: *Self, options: Options, handler: HandlerType) !void {
        const gatekeepers = 4;
        const handlers = 4;

        var new_pool: std.Thread.Pool = undefined;
        try new_pool.init(.{
            .allocator = self.alloc,
        });

        defer new_pool.deinit();

        const host_ip = try std.net.Address.resolveIp(options.hostname, options.port);
        var server = try std.net.Address.listen(host_ip, .{
            .reuse_address = true,
        }); defer server.deinit();

        var queue = try pconsumer.Queue(Connection).init(self.alloc);

        var keeper_threads: [gatekeepers]std.Thread = @splat(undefined);
        for (0..keeper_threads.len) |index| {
            keeper_threads[index] = try std.Thread.spawn(.{}, gatekeep, .{
                &server,
                &queue,
            });
        }

        for (0..handlers) |_| {
            try new_pool.spawn(loopPullAndHandle, .{
                &queue,
                handler,
            });
        }

        for (0..keeper_threads.len) |index| {
            keeper_threads[index].join();
        }

        return;
    }
};

