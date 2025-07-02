const std = @import("std");

pub inline fn err(fd: std.posix.fd_t, comptime fmt: []const u8, args: anytype) void {
    std.log.err("[fd: {}] " ++ fmt, .{ fd } ++ args);
}

pub inline fn info(fd: std.posix.fd_t, comptime fmt: []const u8, args: anytype) void {
    std.log.info("[fd: {}] " ++ fmt, .{ fd } ++ args);
}
