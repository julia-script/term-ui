const std = @import("std");
pub fn ConcreteTypeOf(comptime T: type) type {
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .optional => return typeInfo.optional.child,
        else => return T,
    }
}

pub fn MemberType(comptime T: type) type {
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                if (std.mem.eql(u8, field.name, "x") or std.mem.eql(u8, field.name, "top")) {
                    return field.type;
                }
            }
            unreachable;
        },
        else => {
            return T;
        },
    }
}
pub fn isStruct(comptime T: type) bool {
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .Struct => return true,
        else => return false,
    }
}

pub fn isOptional(comptime T: type) bool {
    const typeInfo = @typeInfo(T);
    switch (typeInfo) {
        .optional => return true,
        else => return false,
    }
}
test "MemberType" {
    const Test = struct {
        x: f32,
        y: f32,
    };
    try std.testing.expect(MemberType(Test) == f32);
    try std.testing.expect(MemberType(f32) == f32);
}
pub inline fn assign(a: anytype, b: anytype) void {
    inline for (std.meta.fields(@TypeOf(b))) |f| {
        @field(a, f.name) = @as(f.type, @field(b, f.name));
    }
}
pub inline fn with(a: anytype, b: anytype) @TypeOf(a) {
    var copy = a;
    assign(&copy, b);
    return copy;
}

const TestStruct = struct {
    x: f32,
    y: f32,
};
test "with" {
    const a = TestStruct{
        .x = 0,
        .y = 1,
    };
    const b = with(a, .{ .y = 2.0 });
    _ = b; // autofix
    // const b = assign(&a, .{ .x = 1.0, .z = 2.0 });
    // std.debug.print("{any}, {any}\n", .{ a, b });
}
