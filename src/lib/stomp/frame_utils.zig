const std = @import("std");
const parser = @import("parser.zig");
const ioutils = @import("ioutils.zig");
const Frame = @import("frame.zig");

pub fn handshake(reader: std.io.AnyReader, writer: std.io.AnyWriter, handle: std.posix.fd_t) !void {
    var buffer: [1024 * 4]u8 = @splat(0);
    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
    const allocator = fba.allocator();

    // connection frame validation
    const connected_buffer = try allocator.alloc(u8, 1024);
    defer allocator.free(connected_buffer);

    const connected_data = try ioutils.pollAndRead(handle, reader, connected_buffer);

    const frame_wrapper = try parser.parseFrame(connected_data, allocator);
    defer frame_wrapper.deinit();

    const frame_hvs = frame_wrapper.frame.hvs orelse return error.IllegalConnectedFrame;
    const version_string = frame_hvs.get("accept-version") orelse return error.UnsupportedVersion;

    if (!std.mem.eql(u8, version_string, "1.2"))
        return error.InvalidAcceptedVersion;

    // connection frame response
    var ret_hvs = std.StringHashMap([]u8).init(allocator);
    defer ret_hvs.deinit();

    try ret_hvs.put("version", @constCast("1.2"));

    const ret_frame = Frame{
        .command = .connected,
        .hvs = ret_hvs,
    };

    try ioutils.writeFrame(ret_frame, writer);
}


