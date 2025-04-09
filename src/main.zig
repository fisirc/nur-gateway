const std = @import("std");
const thwomp = @import("lib/stomp/lib.zig");

pub fn main() !void {
    const test_str =
        \\SEND
        \\key:value
        \\
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = try thwomp.Parser.parseData(test_str, fba.allocator());
    std.debug.print("frame command: {}\n", .{
        frame.command,
    });

    const key_iter = frame.hvs.?.keyIterator();
}

