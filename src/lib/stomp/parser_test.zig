const std = @import("std");
const parser = @import("parser.zig");

test "parse_minimal_frame" {
    const test_str =
        "SEND"              ++ "\r\n" ++    // COMMAND EOL
        "\n"                ++              // EOL
        [_]u8{ 0 }                          // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const parsed = try parser.parseFrame(test_str, fba.allocator());
    defer parsed.deinit();

    try std.testing.expect(parsed.frame.hvs == null);
    try std.testing.expect(parsed.frame.body == null);
}

test "repeating_headers" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "key:value"     ++ "\r\n" ++    // HEADER EOL
        "key:value3"    ++ "\r\n" ++    // HEADER EOL
        "key:value2"    ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        [_]u8{ 0 }                      // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const parsed = try parser.parseFrame(test_str, fba.allocator());
    defer parsed.deinit();

    try std.testing.expectEqualStrings("value", parsed.frame.hvs.?.get("key").?);
    try std.testing.expect(parsed.frame.body == null);
}

test "parse_headers_no_body" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "key:value"     ++ "\r\n" ++    // HEADER EOL
        "key3:value3"   ++ "\r\n" ++    // HEADER EOL
        "key2:value2"   ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        [_]u8{ 0 }                      // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const parsed = try parser.parseFrame(test_str, fba.allocator());
    defer parsed.deinit();

    try std.testing.expectEqualStrings(parsed.frame.hvs.?.get("key").?, "value");
    try std.testing.expectEqualStrings(parsed.frame.hvs.?.get("key2").?, "value2");
    try std.testing.expectEqualStrings(parsed.frame.hvs.?.get("key3").?, "value3");
    try std.testing.expect(parsed.frame.body == null);
}

test "parse_malformed_headers_no_body" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "keyvalue"      ++ "\r\n" ++    // HEADER EOL
        "key3\n:value3" ++ "\r\n" ++    // HEADER EOL
        "key2:value2"   ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        [_]u8{ 0 }                      // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = parser.parseFrame(test_str, fba.allocator());
    if (frame) |_| {
        return error.ShouldHaveFailed;
    } else |_| {}
}

test "parse_no_headers_malformed_body" {
    const test_str =
        "SEND"              ++ "\r\n" ++    // COMMAND EOL
        "\n"                ++              // EOL
        "whatever"                          // not NULL terminated = malformed
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = parser.parseFrame(test_str, fba.allocator());
    if (frame) |_| {
        return error.ShouldHaveFailed;
    } else |_| {}
}

test "parse_headers_malformed_body" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "key:value"     ++ "\r\n" ++    // HEADER EOL
        "key3:value3"   ++ "\r\n" ++    // HEADER EOL
        "key2:value2"   ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        "whatever"                      // not NULL terminated = malformed
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = parser.parseFrame(test_str, fba.allocator());
    if (frame) |_| {
        return error.ShouldHaveFailed;
    } else |_| {}
}

test "parse_malformed_headers_malformed_body" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "keyvalue"      ++ "\r\n" ++    // HEADER EOL
        "key3\n:value3" ++ "\r\n" ++    // HEADER EOL
        "key2:value2"   ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        "whatever"                      // not NULL terminated = malformed
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = parser.parseFrame(test_str, fba.allocator());
    if (frame) |_| {
        return error.ShouldHaveFailed;
    } else |_| {}
}

test "parse_no_headers_body" {
    const test_str =
        "SEND"              ++ "\r\n" ++    // COMMAND EOL
        "\n"                ++              // EOL
        "whatever"          ++ [_]u8{0}     // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const parsed = try parser.parseFrame(test_str, fba.allocator());
    defer parsed.deinit();

    try std.testing.expect(parsed.frame.hvs == null);
    try std.testing.expectEqualStrings("whatever", parsed.frame.body.?);
}

test "parse_headers_body" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "key:value"     ++ "\r\n" ++    // HEADER EOL
        "key3:value3"   ++ "\r\n" ++    // HEADER EOL
        "key2:value2"   ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        "whatever"      ++ [_]u8{0}     // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const parsed = try parser.parseFrame(test_str, fba.allocator());
    defer parsed.deinit();

    try std.testing.expectEqualStrings(parsed.frame.hvs.?.get("key").?, "value");
    try std.testing.expectEqualStrings(parsed.frame.hvs.?.get("key2").?, "value2");
    try std.testing.expectEqualStrings(parsed.frame.hvs.?.get("key3").?, "value3");

    try std.testing.expectEqualStrings("whatever", parsed.frame.body.?);
}

test "parse_malformed_headers_body" {
    const test_str =
        "SEND"          ++ "\r\n" ++    // COMMAND EOL
        "keyvalue"      ++ "\r\n" ++    // HEADER EOL
        "key3\n:value3" ++ "\r\n" ++    // HEADER EOL
        "key2:value2"   ++ "\r\n" ++    // HEADER EOL
        "\n"            ++              // EOL
        "whatever"      ++ [_]u8{0}     // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = parser.parseFrame(test_str, fba.allocator());
    if (frame) |_| {
        return error.ShouldHaveFailed;
    } else |_| {}
}




