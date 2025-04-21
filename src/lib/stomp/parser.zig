const std = @import("std");
const lexx = @import("lexer.zig");

const Frame = @import("frame.zig");

const ParseError = error {
    InvalidFrame,
    InvalidHeaderString,
    InvalidHeaderNoSeparator,
    InvalidBodyTooSmall,
    InvalidBodyNoNull,
    UnreachableLexeme,
};

const Parsed = struct {
    frame: Frame,
    arena: *std.heap.ArenaAllocator,

    pub fn deinit(self: @This()) void {
        var hvs = self.frame.hvs;
        if (hvs) |_| {
            hvs.?.deinit();
        }

        self.arena.deinit();

        const og_allocator = self.arena.child_allocator;
        og_allocator.destroy(self.arena);
    }
};

fn fillKVheader(kv: *std.StringHashMap([]u8), line: []u8, alloc: std.mem.Allocator) !void {
    var line_buf = try alloc.alloc(u8, line.len);
    errdefer alloc.free(line_buf);

    var split = std.mem.splitScalar(u8, line, ':');

    const head = split.next() orelse return ParseError.InvalidHeaderString;
    var head_mirror = line_buf[0..head.len];
    @memcpy(head_mirror[0..], head);

    if (kv.contains(head)) {
        alloc.free(line_buf);
        return;
    }

    const value = split.next() orelse return ParseError.InvalidHeaderNoSeparator;
    var value_mirror = line_buf[head.len..][0..value.len];
    @memcpy(value_mirror[0..], value);

    try kv.put(head_mirror, value_mirror);
}

/// performs a copy of the contents of `proto` that's as big as needed
pub fn parseBody(proto: []u8, alloc: std.mem.Allocator) !?[]u8 {
    if (std.mem.indexOfScalar(u8, proto, 0)) |null_index| {
        const body = proto[0..null_index];
        if (body.len == 0) return null;

        var buffer = try alloc.alloc(u8, null_index);
        @memcpy(buffer[0..], body);

        return buffer;
    } else {
        return ParseError.InvalidBodyNoNull;
    }
}

/// performs a copy of the contents of `proto` that's as big as needed
pub fn parseBodyWithSize(proto: []u8, body_size: usize, alloc: std.mem.Allocator) !?[]u8 {
    if (proto.len < body_size) return ParseError.InvalidBodyTooSmall;

    var buffer = try alloc.alloc(u8, body_size);
    @memcpy(buffer[0..], proto[0..body_size]);

    return buffer;
}

fn frameFromSlice(data: []const u8, alloc: std.mem.Allocator) !Frame {
    var tmp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer tmp_arena.deinit();

    const tmp_allocator = tmp_arena.allocator();
    const lexemes = try lexx.tokenizeAll(data, tmp_allocator);

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
                try fillKVheader(&frame.hvs.?, str, alloc);

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

    var dyn_buffer = try std.ArrayList(u8).initCapacity(alloc, 4096);
    defer dyn_buffer.deinit();

    for (body_lexemes) |lexeme| switch (lexeme) {
        .command => |cmd| {
            const bytes = try cmd.toString();
            try dyn_buffer.appendSlice(bytes[0..]);
        },
        .EOL_lf => |byte| try dyn_buffer.append(byte),
        .EOL_crlf => |bytes| try dyn_buffer.appendSlice(bytes[0..]),
        .string => |bytes| try dyn_buffer.appendSlice(bytes),
    };

    const body_buffer = dyn_buffer.items;
    frame.body = body_val: {
        if (frame.hvs) |*hvs| {
            if (hvs.contains("content-length")) {
                const size = try std.fmt.parseInt(usize, body_buffer, 10);
                break :body_val try parseBodyWithSize(body_buffer, size, alloc);
            } else {
                break :body_val try parseBody(body_buffer, alloc);
            }
        } else {
            break :body_val try parseBody(body_buffer, alloc);
        }
    };

    return frame;
}

/// memory is owned by caller's allocator, you have to call `deinit` on the
/// returned frame
pub fn parseFrame(data: []const u8, alloc: std.mem.Allocator) !Parsed {
    var parsed: Parsed = .{
        .arena = try alloc.create(std.heap.ArenaAllocator),
        .frame = undefined,
    }; errdefer alloc.destroy(parsed.arena);

    parsed.arena.* = std.heap.ArenaAllocator.init(alloc);
    errdefer parsed.arena.*.deinit();

    const frame_allocator = parsed.arena.allocator();
    parsed.frame = try frameFromSlice(data, frame_allocator);

    return parsed;
}

