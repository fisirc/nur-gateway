const std = @import("std");
const uuid = @import("uuid.zig");

pub const PayloadV1 = extern struct {
    version: u8 = 1,
    function_id: uuid.UUID align(1),
    deployment_date: u64 align(1),
};

comptime {
    if (@sizeOf(PayloadV1) != @sizeOf(u8) + @sizeOf(uuid.UUID) + @sizeOf(u64)) @compileError("payload v1 has padding");
}

pub const PayloadV2 = extern struct {
    version: u8 = 2,
    function_uuid: uuid.UUID align(1),
    deployment_date: u64 align(1),

    data_length: u16 align(1),
};

comptime {
    if (@sizeOf(PayloadV2) != @sizeOf(u8) + @sizeOf(uuid.UUID) + @sizeOf(u64) + @sizeOf(u16)) @compileError("payload v2 has padding");
}

pub const HandshakeVersion = enum {
    v1,
    v2,
};

pub const Payload = union(HandshakeVersion) {
    v1: PayloadV1,
    v2: PayloadV2,
};

pub inline fn initPayload(comptime version: HandshakeVersion, data: if (version == .v1) PayloadV1 else PayloadV2) Payload {
    switch (version) {
        .v1 => return .{ .v1 = data },
        .v2 => return .{ .v2 = data },
    }
}

pub const WorkerConn = struct {
    const Self = @This();

    const WorkerAnswer = enum(u8) {
        ok = 0,
        malformed = 1,
        not_found = 2,
    };

    stream: std.net.Stream,

    pub inline fn close(self: Self) void {
        self.stream.close();
    }

    fn handshakeV1(self: Self, payload: PayloadV1) !void {
        const conn_writer = self.stream.writer().any();
        const conn_reader = self.stream.reader().any();

        try conn_writer.writeStructEndian(payload, .big);

        const answer = try conn_reader.readEnum(WorkerAnswer, .big);
        switch (answer) {
            .ok => return,
            .malformed => return error.Malformed,
            .not_found => return error.NotFound,
        }
    }

    fn handshakeV2(self: Self, payload: PayloadV2) !void {
        _ = self;
        _ = payload;
        unreachable;
    }

    pub fn handshake(self: Self, payload: Payload) !void {
        switch (payload) {
            .v1 => |payload_v1| return self.handshakeV1(payload_v1),
            .v2 => |payload_v2| return self.handshakeV2(payload_v2),
        }
    }
};

pub const WorkerDiscovery = struct {
    const Self = @This();

    worker_infolist: std.ArrayList(std.net.Address),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) !Self {
        var ret = Self{
            .worker_infolist = std.ArrayList(std.net.Address).init(alloc),
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
        NoWorkers,
        ConnectionError,
    };

    /// searches for a worker to establish a healthy connection with
    /// (will return an error if any worker connection results in an
    /// unexpected error)
    pub fn findConn(self: Self) !WorkerConn {
        const workers = self.worker_infolist.items;
        if (workers.len == 0) return AvailError.NoWorkers;

        for (workers) |*worker| {
            const connection_stream = std.net.tcpConnectToAddress(worker.*) catch |err| switch (err) {
                error.AddressNotAvailable,
                error.ConnectionRefused,
                error.ConnectionTimedOut => {
                    continue;
                },

                else => return AvailError.ConnectionError,
            };

            return .{ .stream = connection_stream };
        }

        return AvailError.NoAvailableWorkers;
    }
};
