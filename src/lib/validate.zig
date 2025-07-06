const std = @import("std");

pub fn env(envfile: std.process.EnvMap, comptime required: []const []const u8) void {
    for (required) |required_key| {
        _ = envfile.get(required_key) orelse {
            std.log.err("couldnt find required key in env: {s}", .{ required_key });
            @panic("env failed to provide a required key");
        };
    }
}


