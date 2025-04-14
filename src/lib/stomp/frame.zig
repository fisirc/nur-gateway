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
    command: Command = .invalid,
    hvs: ?std.StringHashMap([]u8) = null,
    body: ?[]u8 = &.{},
};


