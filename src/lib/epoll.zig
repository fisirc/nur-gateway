const std = @import("std");


const Epoll = @This();

handle: std.posix.fd_t,

pub fn init() Epoll {
    return .{
        .handle = std.posix.epoll_create1
    };
}


