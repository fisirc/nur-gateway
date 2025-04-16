const std = @import("std");

pub fn configHandleNoblock(conn: std.net.Server.Connection) !void {
    if (@TypeOf(conn.stream.handle) != std.posix.fd_t)
        @compileError("fuck your platform!");

    const handle = conn.stream.handle;

    const prev_flags = try std.posix.fcntl(
        handle,
        std.posix.F.GETFL,
        0
    );

    var flags_struct: std.posix.O = @bitCast(@as(u32, @intCast(prev_flags)));
    flags_struct.NONBLOCK = true;

    const flags_usize: usize = @intCast(@as(u32, @bitCast(flags_struct)));
    _ = try std.posix.fcntl(
        handle,
        std.posix.F.SETFL,
        flags_usize
    );
}
