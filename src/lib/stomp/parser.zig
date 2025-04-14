const std = @import("std");
const lexx = @import("lexer.zig");
const Frame = @import("frame.zig").Msg;

const ParseError = error {
    InvalidFrame,
    InvalidHeader,
    InvalidBody,
    UnreachableLexeme,
};

fn fillKVheader(kv: *std.StringHashMap([]u8), line: []u8) !void {
    var split = std.mem.splitScalar(u8, line, ':');
    const head = split.next() orelse return ParseError.InvalidHeader;
    if (kv.contains(head)) return;

    const value = split.next() orelse return ParseError.InvalidHeader;

    try kv.put(@constCast(head), @constCast(value));
}

pub fn parseBody(proto: []u8) !?[]u8 {
    if (std.mem.indexOfScalar(u8, proto, 0)) |null_index| {
        const body = proto[0..null_index];
        if (body.len == 0) return null;

        return body;
    } else {
        return ParseError.InvalidBody;
    }
}

pub fn parseBodyWithSize(proto: []u8, body_size: usize) !?[]u8 {
    if (proto.len < body_size) return ParseError.InvalidBody;

    return proto[0..body_size];
}

pub fn parseData(data: []const u8, alloc: std.mem.Allocator) !Frame {
    const lexemes = try lexx.tokenizeAll(data, alloc);
    if (lexemes.len < 3) return ParseError.InvalidFrame;

    var frame: Frame = .{};
    switch (lexemes[0]) {
        .command => |cmd| frame.command = cmd,
        else => return ParseError.InvalidFrame,
    }

    switch (lexemes[1]) {
        .EOL_lf, .EOL_crlf => {},
        else => return ParseError.InvalidFrame,
    }

    const non_cmd_lexemes = lexemes[2..];

    var offset: usize = 0;
    while(offset < non_cmd_lexemes.len) : (offset += 1) {
        switch (non_cmd_lexemes[offset]) {
            .EOL_lf, .EOL_crlf => {
                offset += 1;
                break;
            },

            .string => |str| {
                if (frame.hvs == null) frame.hvs = std.StringHashMap([]u8).init(alloc);
                try fillKVheader(&frame.hvs.?, str);

                if (offset + 1 >= non_cmd_lexemes.len) return ParseError.InvalidFrame;

                switch (non_cmd_lexemes[offset + 1]) {
                    .EOL_lf, .EOL_crlf => offset += 1,
                    else => return ParseError.InvalidFrame,
                }
            },

            else => return ParseError.InvalidFrame,
        }
    }

    const body_lexemes = non_cmd_lexemes[offset..];

    var dyn_buffer = try std.ArrayList(u8).initCapacity(alloc, body_lexemes.len * @sizeOf(lexx.Lexeme));
    for (body_lexemes) |lexeme| switch (lexeme) {
        .command => return ParseError.UnreachableLexeme,
        .EOL_lf => |byte| try dyn_buffer.append(byte),
        .EOL_crlf => |bytes| try dyn_buffer.appendSlice(bytes[0..]),
        .string => |bytes| try dyn_buffer.appendSlice(bytes),
    };

    const body_buffer = try dyn_buffer.toOwnedSlice();
    frame.body = body_val: {
        if (frame.hvs) |*hvs| {
            if (hvs.contains("content-length")) {
                const size = try std.fmt.parseInt(usize, body_buffer, 10);
                break :body_val try parseBodyWithSize(body_buffer, size);
            } else {
                break :body_val try parseBody(body_buffer);
            }
        } else {
            break :body_val try parseBody(body_buffer);
        }
    };

    return frame;
}

test "parse_minimal_frame" {
    const test_str =
        "SEND"              ++ "\r\n" ++    // COMMAND EOL
        "\n"                ++              // EOL
        [_]u8{ 0 }                          // NULL
    ;

    var alloc_buffer: [4096]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);

    const frame = try parseData(test_str, fba.allocator());

    try std.testing.expect(frame.hvs == null);
    try std.testing.expect(frame.body == null);
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

    const frame = try parseData(test_str, fba.allocator());
    try std.testing.expectEqualStrings("value", frame.hvs.?.get("key").?);
    try std.testing.expect(frame.body == null);
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

    const frame = try parseData(test_str, fba.allocator());
    try std.testing.expectEqualStrings(frame.hvs.?.get("key").?, "value");
    try std.testing.expectEqualStrings(frame.hvs.?.get("key2").?, "value2");
    try std.testing.expectEqualStrings(frame.hvs.?.get("key3").?, "value3");
    try std.testing.expect(frame.body == null);
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

    const frame = parseData(test_str, fba.allocator());
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

    const frame = parseData(test_str, fba.allocator());
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

    const frame = parseData(test_str, fba.allocator());
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

    const frame = parseData(test_str, fba.allocator());
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

    const frame = try parseData(test_str, fba.allocator());
    try std.testing.expect(frame.hvs == null);
    try std.testing.expectEqualStrings("whatever", frame.body.?);
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

    const frame = try parseData(test_str, fba.allocator());
    try std.testing.expectEqualStrings(frame.hvs.?.get("key").?, "value");
    try std.testing.expectEqualStrings(frame.hvs.?.get("key2").?, "value2");
    try std.testing.expectEqualStrings(frame.hvs.?.get("key3").?, "value3");

    try std.testing.expectEqualStrings("whatever", frame.body.?);
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

    const frame = parseData(test_str, fba.allocator());
    if (frame) |_| {
        return error.ShouldHaveFailed;
    } else |_| {}
}




