const std = @import("std");
const uuid = @import("uuid.zig");

pub const HandshakePayloadV1 = extern struct {
    version: u8 align(1) = 1,
    function_id: uuid.UUID align(1),
    deployment_date: u64 align(1),
};

comptime {
    if (@sizeOf(HandshakePayloadV1) != @sizeOf(u8) + @sizeOf(uuid.UUID) + @sizeOf(u64)) @compileLog(@sizeOf(HandshakePayloadV1));
}

pub const HandshakePayloadV2 = extern struct {
    version: u8 = 2,
    function_uuid: [4]u32 align(1),
    deployment_date: u64 align(1),

    data_length: u16 align(1),
};

pub const HandshakeVersion = enum {
    v1,
    v2,
};

pub const HandshakePayload = union(HandshakeVersion) {
    v1: HandshakePayloadV1,
    v2: HandshakePayloadV2,
};

pub inline fn genPayload(comptime version: HandshakeVersion, data: if (version == .v1) HandshakePayloadV1 else HandshakePayloadV2) HandshakePayload {
    switch (version) {
        .v1 => return .{ .v1 = data },
        .v2 => return .{ .v2 = data },
    }
}

pub const WorkerConn = struct {
    const HandshakeAnswer = enum(u8) {
        ok,
        malformed,
        not_found,
    };

    stream: std.net.Stream,

    fn handshakeV1(self: WorkerConn, payload: HandshakePayloadV1) !void {
        const conn_writer = self.stream.writer().any();
        const conn_reader = self.stream.reader().any();

        try conn_writer.writeStructEndian(payload, .big);

        const answer: HandshakeAnswer = try conn_reader.readEnum(HandshakeAnswer, .big);
        switch (answer) {
            .ok => return,
            .malformed => return error.Malformed,
            .not_found => return error.NotFound,
        }
    }

    fn handshakeV2(self: WorkerConn, payload: HandshakePayloadV2) !void {
        _ = self;
        _ = payload;
        unreachable;
    }

    pub fn handshake(self: WorkerConn, payload: HandshakePayload) !void {
        switch (payload) {
            .v1 => |payload_v1| return self.handshakeV1(payload_v1),
            .v2 => |payload_v2| return self.handshakeV2(payload_v2),
        }
    }
};

pub const WorkerDiscovery = struct {
    const Self = @This();

    pub const WorkerInfo = std.net.Address;

    worker_infolist: std.ArrayList(?WorkerInfo),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Self {
        var ret = Self{
            .worker_infolist = std.ArrayList(?WorkerInfo).init(alloc),
            .alloc = alloc,
        };

        var addr_list = try std.net.getAddressList(alloc, "localhost", 6969);
        defer addr_list.deinit();

        if (addr_list.addrs.len == 0) return error.NoWorkerAddr;

        const addresses = addr_list.addrs;
        for (0..addresses.len) |idx| {
            try ret.worker_infolist.append(addresses[idx]);
        }

        return ret;
    }

    pub fn deinit(self: Self) void {
        self.worker_infolist.deinit();
    }

    const AvailError = error {
        NoAvailableWorkers,
        CouldntConnect,
    };

    fn findAvail(self: Self) !std.net.Stream {
        const workers = self.worker_infolist.items;
        for (workers) |*worker| {
            if (worker.*) |worker_addr| {
                const address = worker_addr;
                const connection_stream = std.net.tcpConnectToAddress(address) catch |err| switch (err) {
                    error.AddressNotAvailable,
                    error.ConnectionRefused,
                    error.ConnectionTimedOut => {
                        worker.* = null;
                        continue;
                    },

                    else => return AvailError.CouldntConnect,
                };

                return connection_stream;
            } else continue;
        }

        return AvailError.NoAvailableWorkers;
    }

    pub fn findConn(self: Self) !WorkerConn {
        return WorkerConn{
            .stream = try self.findAvail(),
        };
    }
};
