const std = @import("std");
const builtin = @import("builtin");

pub fn assert(condition: bool, comptime fmt: []const u8, args: anytype) void {
    if (builtin.mode != .fast) if (!condition) {
        std.debug.panic(fmt, args);
    };
}

/// Prints all error types that a function can return.
/// Useful for debugging and understanding function error sets.
///
/// Example:
/// ```zig
/// fn myFunction() !void { ... }
/// debug.printFunctionErrors(myFunction);
/// ```
pub fn printFunctionErrors(comptime func: anytype) void {
    const type_info: std.builtin.Type = @typeInfo(@TypeOf(func));
    switch (type_info) {
        .@"fn" => |func_info| {
            const ReturnType = func_info.return_type orelse @compileError("No return type");
            const ret_type_info: std.builtin.Type = @typeInfo(ReturnType);
            switch (ret_type_info) {
                .error_union => |error_union_info| {
                    const error_type: std.builtin.Type = @typeInfo(error_union_info.error_set);
                    switch (error_type) {
                        .error_set => |error_set_info| {
                            inline for (error_set_info.?) |field| {
                                std.debug.print("{s}\n", .{field.name});
                            }
                        },
                        else => @compileError("No error type"),
                    }
                },
                else => @compileError("No error type"),
            }
        },
        else => unreachable,
    }
}
