const std = @import("std");

pub const Command = enum {
    // default command for Msg initialization, to leave this as `invalid` is
    // illegal behavior and will be considered an error
    invalid,

    // client commands
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

    // server commands
    connected,
    message,
    receipt,
    err,
};

pub const Msg = struct {
    const Self = @This();
    const MsgParseError = error {
        InvalidBody,
    };

    command: Command = .invalid,
    hvs: ?std.StringHashMap([]u8) = null,
    __body_proto: []u8 = &.{},

    pub fn getBody(self: Self) !?[]u8 {
        const proto = self.__body_proto;

        if (std.mem.indexOfScalar(u8, proto, 0)) |null_index| {
            const body = proto[0..null_index];
            if (body.len == 0) return null;

            return body;
        } else {
            return MsgParseError.InvalidBody;
        }
    }

    pub fn getBodyWithSize(self: Self, body_size: usize) !?[]u8 {
        const proto = self.__body_proto;
        if (proto.len < body_size) return MsgParseError.InvalidBody;

        return proto[0..body_size];
    }
};


