const std = @import("std");

const Command = struct {
    const Client = enum {
        send,
        subscribe,
        unsubscribe,
        begin,
        commit,
        abort,
        ack,
        nack,
        disconnect,
        connect,
        stomp,
    };

    const Server = enum {
        connected,
        message,
        receipt,
        err,
    };
};


const Lexer = struct {
    const Category = enum {
        // any available command, either client or server
        command,

        // any EOL, be it or not in the body's octets
        EOL_lf,
        EOL_crlf,

        // any NULL, be it or not in the body's octets
        NULL,

        // a "string" as in a "string of bytes" or a "string of octets" is more
        // understood like a generic array of (utf-8 or not) bytes
        string,
    };

    const Lexeme = union(Category) {
        command: Command,
        EOL_lf: u8,
        EOL_crlf: [2]u8,
        NULL: u8,
        string: []u8,
    };

    pub fn tokenizeAll(data: []u8, alloc: std.mem.Allocator) []Lexeme {
        _ = data; // autofix
        _ = alloc; // autofix
    }
};


