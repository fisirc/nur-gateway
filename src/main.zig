const std = @import("std");
const thwomp = @import("libthwomp");

pub fn main() !void {
    const test_str =
        "SEND" ++ "\r\n" ++
        "key:value" ++ "\r\n" ++
        "key2:value2" ++ "\n" ++
        "\n" ++
        "this is the body" ++ [_]u8{ 0 } ++
        "\n"
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = try thwomp.Parser.parseData(test_str, fba.allocator());
    std.debug.print("frame: {any}\n", .{
        frame.command,
    });

    if (frame.hvs) |frames| {
        var key_iter = frames.keyIterator();
        while (key_iter.next()) |key_ptr| {
            std.debug.print("key: {s} value: {s}\n", .{
                key_ptr.*,
                frame.hvs.?.get(key_ptr.*).?,
            });
        }
    }

    const body = try frame.getBody();
    std.debug.print("body: {s}\n", .{
        body.?
    });
}

