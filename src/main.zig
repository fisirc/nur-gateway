const std = @import("std");
const libthwomp = @import("libthwomp");

const pq = @import("lib/pq.zig");
const server = @import("lib/server.zig");

const QueueMap = @import("queues.zig").SyncQueueMap;

const StompServer = struct {
    pub const Ctx = struct {
        qmap: QueueMap,

        pub fn init(alloc: std.mem.Allocator) !@This() {
            return @This(){
                .qmap = try QueueMap.init(alloc),
            };
        }

        pub fn deinit(self: *@This()) void {
            self.qmap.deinit();
        }
    };

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

        var header_buffer: [4096]u8 = @splat(0);
        var ready_server = std.http.Server.init(connection, header_buffer[0..]);
        const request_with_header = ready_server.receiveHead() catch |err| {
            std.log.err("couldn't receive http header from connection: {}", .{ err });
            return;
        };

        // every (method, target) pair should correspond to a single function id
        // which will then be passed down to the worker
        const method = request_with_header.head.method;
        const target = request_with_header.head.target;

        const conn = pq.connectDbSafe("postgresql://postgres:3XJ6XVYhh701ybun@db.hgowvvjfbzaayphkktyo.supabase.co:5432/postgres") catch {
            std.log.err("couldn't establish connection with the db", .{});
            return;
        }; defer pq.finishConn(conn);

        const result = pq.execQueryWithParams(
            conn,
            "select function_id from methods m join routes r where m.route_id = r.route_id and r.path_absolute = $1 and m.method_name = $?",
            .{
                target,
                method,
            },
        ) catch |err| {
            std.log.err("couldn't execute query: {}", .{ err });
            return;
        };

        // check for rows amount, get text value, start the worker protocol
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

    var stomp_server = server.TcpServer(StompServer).init(server_allocator, .{
        .hostname = "0.0.0.0",
        .port = 3000,
    });

    var server_ctx = try StompServer.Ctx.init(server_allocator);
    defer server_ctx.deinit();

    try stomp_server.listen(&server_ctx);
}




