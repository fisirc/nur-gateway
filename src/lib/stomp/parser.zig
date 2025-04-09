const std = @import("std");
const lexx = @import("lexer.zig");
const Frame = @import("frame.zig").Msg;

const ParseError = error {
    InvalidFrame,
    InvalidHeader,
};

fn fillKVheader(kv: *std.AutoHashMap([]u8, []u8), line: []u8) !void {
    var split = std.mem.splitScalar(u8, line, ':');
    const head = split.next() orelse return ParseError.InvalidHeader;
    const value = split.next() orelse return ParseError.InvalidHeader;

    try kv.put(@constCast(head), @constCast(value));
}

pub fn parseData(data: []const u8, alloc: std.mem.Allocator) !Frame {
    const lexemes = try lexx.tokenizeAll(data, alloc);
    if (lexemes.len < 3) return ParseError.InvalidFrame;

    var frame: Frame = .{};
    switch (lexemes[0]) {
        .command => |cmd| frame.command = cmd,
        else => return ParseError.InvalidFrame,
    }

    const non_cmd_lexemes = lexemes[1..];
    var offset: usize = 0;
    until_EOL: while (true) : (offset += 1) {
        switch (non_cmd_lexemes[offset]) {
            .EOL_lf, .EOL_crlf => break :until_EOL,
            .string => |str| {
                if (frame.hvs == null) frame.hvs = std.AutoHashMap([]u8, []u8).init(alloc);
                try fillKVheader(&frame.hvs.?, str);
            },
            else => return ParseError.InvalidFrame,
        }
    }

    return frame;
}




