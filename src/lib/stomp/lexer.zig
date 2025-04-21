const std = @import("std");
const Command = @import("frame.zig").Command;

pub const Category = enum {
    // any available command, either client or server
    command,

    // any EOL, be it or not in the body's octets
    EOL_lf,
    EOL_crlf,

    // a "string" as in a "string of bytes" or a "string of octets" is more
    // understood like a generic array of (utf-8 or not) bytes
    string,
};

pub const Lexeme = union(Category) {
    command: Command,
    EOL_lf: u8,
    EOL_crlf: [2]u8,
    string: []u8,
};

fn clearBuffer(buffer: *std.ArrayList(u8), lexemes: *std.ArrayList(Lexeme)) !void {
    if (Command.fromString(buffer.items)) |cmd| {
        buffer.clearRetainingCapacity();
        try lexemes.append(Lexeme{
            .command = cmd,
        });
    } else |_| {
        const buffer_slice = try buffer.toOwnedSlice();
        try lexemes.append(Lexeme{
            .string = buffer_slice,
        });
    }
}

pub fn tokenizeAll(data: []const u8, alloc: std.mem.Allocator) ![]Lexeme {
    const StateFlags = struct {};

    var flags = StateFlags{};
    _ = &flags;

    var dyn_lexeme = std.ArrayList(Lexeme).init(alloc);
    var dyn_buffer = std.ArrayList(u8).init(alloc);
    defer dyn_buffer.deinit();

    var prev: u8 = 0;
    for (data) |data_byte| {
        defer prev = data_byte;

        switch (data_byte) {
            '\n' => {
                if (dyn_buffer.items.len != 0) {
                    if (prev == '\r') {
                        _ = dyn_buffer.pop();
                    }
                }

                if (dyn_buffer.items.len != 0) {
                    try clearBuffer(&dyn_buffer, &dyn_lexeme);
                }

                if (prev == '\r') {
                    try dyn_lexeme.append(Lexeme{
                        .EOL_crlf = [2]u8{ '\r', '\n' },
                    });
                } else {
                    try dyn_lexeme.append(Lexeme{
                        .EOL_lf = '\n',
                    });
                }
            },

            else => try dyn_buffer.append(data_byte),
        }
    }

    if (dyn_buffer.items.len != 0) {
        if (prev == '\r') {
            _ = dyn_buffer.pop();
        }

        try clearBuffer(&dyn_buffer, &dyn_lexeme);
    }

    return try dyn_lexeme.toOwnedSlice();
}
