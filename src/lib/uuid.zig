const std = @import("std");

pub const UUID = [16]u8;

pub fn fromString(str: []const u8) !UUID {
    var ret: UUID = @splat(0);
    var ret_index: usize = 0;

    var tmp: u8 = 0;
    var index: usize = 0;
    while (index < str.len) {
        if (str[index] == '-') {
            index += 1;
            continue;
        }

        tmp += try std.fmt.charToDigit(str[index], 16) * 16;
        tmp += try std.fmt.charToDigit(str[index + 1], 16);

        ret[ret_index] = tmp;
        tmp = 0;
        
        ret_index += 1;
        index += 2;
    }

    return ret;
}


