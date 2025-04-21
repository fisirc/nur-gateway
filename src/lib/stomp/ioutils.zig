const std = @import("std");

const Frame = @import("frame.zig");

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

pub fn writeFrame(frame: Frame, writer: std.io.AnyWriter) !void {
    var buffered_stream = std.io.bufferedWriter(writer);
    const stream_writer = buffered_stream.writer().any();

    const header = try frame.command.toString();
    try stream_writer.writeAll(header);
    try stream_writer.writeAll("\r\n");

    if (frame.hvs) |_| {
        var hv_map_iter = frame.hvs.?.iterator();
        while (hv_map_iter.next()) |kv_pair| {
            try stream_writer.writeAll(kv_pair.key_ptr.*);
            try stream_writer.writeByte(':');
            try stream_writer.writeAll(kv_pair.value_ptr.*);
            try stream_writer.writeAll("\r\n");
        }
    }

    try stream_writer.writeAll("\r\n");

    if (frame.body) |body| {
        try stream_writer.writeAll(body);
    }

    try stream_writer.writeByte(0);
    try buffered_stream.flush();
}

pub fn pollAndRead(handle: std.posix.fd_t, reader: std.io.AnyReader, buffer: []u8) ![]u8 {
    var poll_fds = [_]std.posix.pollfd{
        std.posix.pollfd{
            .fd = handle,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }
    };

    while (true) {
        _ = try std.posix.poll(poll_fds[0..], -1);
        if (poll_fds[0].revents == std.posix.POLL.IN) break;
    }

    const read_size = try reader.read(buffer[0..]);
    return buffer[0..read_size];
}

