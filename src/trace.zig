const std = @import("std");

const root = @import("root");
const TRACE = if (@hasDecl(root, "TRACE")) root.TRACE else false;

const term_color = .{
    .dim = "\x1b[2m",
    .reset = "\x1b[0m",
};

inline fn print(comptime format_string: []const u8, args: anytype) void {
    std.debug.print(term_color.dim ++ "TRACE: " ++ format_string ++ term_color.reset ++ "\n", args);
}

pub inline fn trace(src: std.builtin.SourceLocation, args: anytype) void {
    if (TRACE) {
        if (@sizeOf(@TypeOf(args)) == 0)
            print("{s}()", .{src.fn_name})
        else
            print("{s}(): {}", .{ src.fn_name, args });
    }
}
