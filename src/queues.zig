const std = @import("std");
const pconsumer = @import("lib/pconsumer.zig");

pub const SyncQueueMap = struct {
    const Self = @This();
    const QueueType = pconsumer.Queue([]u8);

    arena: *std.heap.ArenaAllocator,
    arena_lock: std.Thread.Mutex,

    // handle valued to support queue buffer preinit
    router: std.StringArrayHashMap(*QueueType),
    router_lock: std.Thread.Mutex,

    pub fn init(alloc: std.mem.Allocator) !Self {
        const new_arena_ptr = try alloc.create(std.heap.ArenaAllocator);
        new_arena_ptr.* = std.heap.ArenaAllocator.init(alloc);

        return Self{
            .arena = new_arena_ptr,
            .arena_lock = .{},
            .router = std.StringArrayHashMap(*QueueType).init(new_arena_ptr.allocator()),
            .router_lock = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        const parent_alloc = self.arena.child_allocator;

        self.arena.deinit();
        self.router.deinit();

        parent_alloc.destroy(self.arena);
    }

    fn newQueue(self: *Self, name: []u8) !*QueueType {
        const new_alloc = self.arena.allocator();

        self.arena_lock.lock();
        const new_queue = try new_alloc.create(QueueType);
        errdefer new_alloc.destroy(new_queue);

        new_queue.* = try QueueType.init(new_alloc);
        errdefer new_queue.deinit();
        self.arena_lock.unlock();

        self.router_lock.lock();
        try self.router.put(name, new_queue);
        self.router_lock.unlock();

        return new_queue;
    }

    pub fn pushToQueue(self: *Self, msg: []u8, queue_name: []u8) !void {
        self.router_lock.lock();
        var queue_ptr = self.router.get(queue_name) orelse try self.newQueue(queue_name);
        self.router_lock.unlock();

        try queue_ptr.pushMsg(msg);
    }

    pub fn pullFromQueue(self: *Self, queue_name: []u8) ![]u8 {
        self.router_lock.lock();
        var queue_ptr = self.router.get(queue_name) orelse try self.newQueue(queue_name);
        self.router_lock.unlock();

        return try queue_ptr.pullMsg();
    }
};

