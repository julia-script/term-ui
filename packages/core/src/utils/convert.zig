const std = @import("std");

/// Convert a value to the target type T
pub fn toType(comptime T: type, value: anytype) T {
    return switch (@TypeOf(value)) {
        u32 => switch (T) {
            u32 => value,
            usize => @intCast(value),
            f32 => @floatFromInt(value),
            i32 => @intCast(value),
            else => @compileError("Unsupported conversion from u32 to " ++ @typeName(T)),
        },
        usize => switch (T) {
            u32 => @intCast(value),
            usize => value,
            f32 => @floatFromInt(value),
            i32 => @intCast(value),
            else => @compileError("Unsupported conversion from usize to " ++ @typeName(T)),
        },
        f32 => switch (T) {
            u32 => @intFromFloat(value),
            usize => @intFromFloat(value),
            f32 => value,
            i32 => @intFromFloat(value),
            else => @compileError("Unsupported conversion from f32 to " ++ @typeName(T)),
        },
        i32 => switch (T) {
            u32 => @intCast(value),
            usize => @intCast(value),
            f32 => @floatFromInt(value),
            i32 => value,
            else => @compileError("Unsupported conversion from i32 to " ++ @typeName(T)),
        },
        comptime_int => switch (T) {
            u32 => value,
            usize => value,
            f32 => @floatFromInt(value),
            i32 => value,
            else => @compileError("Unsupported conversion from comptime_int to " ++ @typeName(T)),
        },
        comptime_float => switch (T) {
            u32 => @intFromFloat(value),
            usize => @intFromFloat(value),
            f32 => value,
            i32 => @intFromFloat(value),
            else => @compileError("Unsupported conversion from comptime_float to " ++ @typeName(T)),
        },
        else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(value))),
    };
}

test "toType conversions" {
    const testing = std.testing;
    
    // u32 conversions
    try testing.expectEqual(@as(f32, 42.0), toType(f32, @as(u32, 42)));
    try testing.expectEqual(@as(usize, 42), toType(usize, @as(u32, 42)));
    
    // f32 conversions
    try testing.expectEqual(@as(u32, 3), toType(u32, @as(f32, 3.14)));
    try testing.expectEqual(@as(i32, -3), toType(i32, @as(f32, -3.14)));
    
    // comptime values
    try testing.expectEqual(@as(u32, 42), toType(u32, 42));
    try testing.expectEqual(@as(f32, 3.14), toType(f32, 3.14));
}