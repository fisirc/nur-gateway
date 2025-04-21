const std = @import("std");

pub const max_frame_size = 40 * 1024 * 1024;

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

    pub fn fromString(str: []u8) !Command {
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

        return error.InvalidCommand;
    }

    pub fn toString(self: Command) ![]const u8 {
        return switch (self) {
            .send => "SEND",
            .subscribe => "SUBSCRIBE",
            .unsubscribe => "UNSUBSCRIBE",
            .begin => "BEGIN",
            .commit => "COMMIT",
            .abort => "ABORT",
            .ack => "ACK",
            .nack => "NACK",
            .disconnect => "DISCONNECT",
            .connect => "CONNECT",
            .stomp => "STOMP",
            .connected => "CONNECTED",
            .message => "MESSAGE",
            .receipt => "RECEIPT",
            .err => "ERROR",

            .invalid => error.InvalidCommand,
        };
    }
};

command: Command = .invalid,
hvs: ?std.StringHashMap([]u8) = null,
body: ?[]u8 = &.{},

