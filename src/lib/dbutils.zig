const std = @import("std");

const pq = @import("pq.zig");
const uuid = @import("uuid.zig");

pub fn getFunctionDeplDate(pg_path: [:0]const u8,
                           project_id: []const u8,
                           route: []const u8,
                           method_name: []const u8) !struct { uuid.UUID, u64 } {
    const conn = pq.Conn.fromUriZ(pg_path) catch return error.DbCouldntConnect;
    defer conn.finish();

    const result = conn.execQueryZWithParams(
        \\ select m.function_id as "function_id", round(extract(epoch from fd.created_at)) as "last_deploy_creation_date"
            \\ from methods m
            \\ join routes r on m.route_id = r.id
            \\ join function_deployments fd on m.function_id = fd.function_id
            \\ where
            \\   r.path_absolute = $1
            \\    and m.method_name = $2
            \\    and r.project_id = $3
            \\    and fd.status = 'success'
            \\ order by fd.created_at desc
            \\ limit 1;
            ,
        .{ route, method_name, project_id },
    ) catch return error.DbQueryFailed;
    defer result.clear();

    const result_rows = result.rowsLen();
    if (result_rows == 0) {
        return error.DbEmptyQuery;
    }

    const function_id = result.getValueAt(0, 0);    
    const deploy_date_time = result.getValueAt(0, 1);

    return .{
        try uuid.fromString(function_id),
        try std.fmt.parseUnsigned(u64, deploy_date_time, 10),
    };
}


