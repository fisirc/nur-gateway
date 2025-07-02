const std = @import("std");

alloc: std.mem.Allocator,
stream_router: std.AutoHashMap(*std.net.Stream, *std.net.Stream),
locks_router: std.AutoHashMap(*std.net.Stream, *std.Thread.Mutex),

enroute_lock: std.Thread.RwLock,



