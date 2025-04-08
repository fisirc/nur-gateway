const std = @import("std");
const thwomp = @import("lib/stomp/lib.zig");

pub fn main() !void {
    const test_str =
        \\SEND
        \\is
        \\ some text
        \\ EOL
        \\
    ;

    var buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
    const lexemes = try thwomp.Lexer.tokenizeAll(test_str, fba.allocator());
    std.debug.print("lexemes:\n{any}\n", .{
        lexemes,
    });
}

