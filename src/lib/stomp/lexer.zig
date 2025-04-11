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

fn toCommand(str: []const u8) ?Command {
    if (false) {
    } else if (std.mem.eql(u8, str, "SEND")) {
        return Command.send;
    } else if (std.mem.eql(u8, str, "SUBSCRIBE")) {
        return Command.subscribe;
    } else if (std.mem.eql(u8, str, "UNSUBSCRIBE")) {
        return Command.unsubscribe;
    } else if (std.mem.eql(u8, str, "BEGIN")) {
        return Command.begin;
    } else if (std.mem.eql(u8, str, "COMMIT")) {
        return Command.commit;
    } else if (std.mem.eql(u8, str, "ABORT")) {
        return Command.abort;
    } else if (std.mem.eql(u8, str, "ACK")) {
        return Command.ack;
    } else if (std.mem.eql(u8, str, "NACK")) {
        return Command.nack;
    } else if (std.mem.eql(u8, str, "DISCONNECT")) {
        return Command.disconnect;
    } else if (std.mem.eql(u8, str, "CONNECT")) {
        return Command.connect;
    } else if (std.mem.eql(u8, str, "STOMP")) {
        return Command.stomp;
    } else if (std.mem.eql(u8, str, "CONNECTED")) {
        return Command.connected;
    } else if (std.mem.eql(u8, str, "MESSAGE")) {
        return Command.message;
    } else if (std.mem.eql(u8, str, "RECEIPT")) {
        return Command.receipt;
    } else if (std.mem.eql(u8, str, "ERROR")) {
        return Command.err;
    }

    return null;
}

fn clearBuffer(buffer: *std.ArrayList(u8), lexemes: *std.ArrayList(Lexeme)) !void {
    const buffer_slice = try buffer.toOwnedSlice();
    if (toCommand(buffer_slice)) |cmd| {
        try lexemes.append(Lexeme{
            .command = cmd,
        });
    } else {
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
