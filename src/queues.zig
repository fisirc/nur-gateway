const std = @import("std");
const pconsumer = @import("lib/pconsumer.zig");

pub const QueueMap = struct {
    const Self = @This();
    const q_init_size = 128;

    alloc: std.mem.Allocator,
    queues_buffer: std.ArrayList(pconsumer.Queue([]u8)),

    // handle valued to support queue buffer preinit
    map: std.StringArrayHashMap(u32),

    pub fn init(alloc: std.mem.Allocator) !Self {
        return .{
            .alloc = alloc,
            .queues_buffer = try std.ArrayList(pconsumer.Queue([]u8)).initCapacity(alloc, q_init_size),
            .map = std.StringArrayHashMap(u32).init(alloc),
        };
    }
};

