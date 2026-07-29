const std = @import("std");

pub fn contains(list: []const []const u8, item: []const u8) bool {
    for (list) |name| {
        if (std.mem.eql(u8, name, item)) {
            return true;
        }
    }
    return false;
}
pub fn isOptional(T: type) bool {
    return switch (@typeInfo(T)) {
        .Optional => true,
        else => false,
    };
}

const Type = std.builtin.Type;
pub fn PartialBy(T: type, partial_fields: []const []const u8) type {
    const type_info = @typeInfo(T);

    const src = switch (type_info) {
        .Struct => type_info.Struct,
        else => @compileError("Partial only works with structs"),
    };

    var fields: [src.fields.len]Type.StructField = undefined;

    for (src.fields, 0..) |field, i| {
        if ((partial_fields.len > 0 and !contains(partial_fields, field.name)) or
            isOptional(field.type) //
        ) {
            fields[i] = field;
            continue;
        }
        const FieldType = @TypeOf(Type{ .Optional = .{ .child = field.type } });
        fields[i] = std.builtin.Type.StructField{
            .name = field.name,
            .type = FieldType,
            .is_comptime = field.is_comptime,
            .default_value = @as(*const anyopaque, @ptrCast(@constCast(&@as(FieldType, null)))),
            .alignment = field.alignment,
        };
    }

    return @TypeOf(Type{ .Struct = .{
        .layout = src.layout,
        .decls = &.{},
        .backing_integer = src.backing_integer,
        .is_tuple = src.is_tuple,
        .fields = &fields,
    } });
}

const expect = std.testing.expect;

test "PartialBy with explicit fields" {
    const Test = struct {
        a: ?i32 = null,
        b: i32,
        c: i32,
    };
    const PartialTest = PartialBy(Test, &.{"c"});

    const partial = PartialTest{ .b = 1 };
    try expect(isOptional(@TypeOf(partial.a)));
    try expect(!isOptional(@TypeOf(partial.b)));
    try expect(isOptional(@TypeOf(partial.c)));
}
