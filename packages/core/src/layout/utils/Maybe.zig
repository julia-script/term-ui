const std = @import("std");
const isOptional = @import("comptime.zig").isOptional;
const expect = std.testing.expect;
const ConcreteTypeOf = @import("comptime.zig").ConcreteTypeOf;

pub fn isTypeOptional(t: anytype) bool {
    return isOptional(@TypeOf(t));
}
pub fn hasOptional(a: anytype, b: anytype) bool {
    return isOptional(@TypeOf(a)) or isOptional(@TypeOf(b));
}

test "Maybe.hasOptional" {
    try expect(hasOptional(1, 2) == false);
    try expect(hasOptional(@as(?f32, 1.0), 2) == true);
    try expect(hasOptional(1, @as(?f32, 2.0)) == true);
}

// fn MaybeReturnType(a: type, b: type) type {
//     const a_is_optional = isOptional(a);
//     const b_is_optional = isOptional(b);
//     if (a_is_optional) {
//         return @TypeOf(a);
//     };
//     if (a_is_optional == false and b_is_optional == false) {
//         return ConcreteTypeOf(a);
//     }
//     return ?ConcreteTypeOf(a);
// }

test "MaybeReturnType" {
    // try expect(MaybeReturnType(i32, i32) == i32);
    // try expect(MaybeReturnType(?f32, i32) == ?f32);
    // try expect(MaybeReturnType(f32, ?f32) == ?f32);
    // std.debug.print("ok {any}\n", .{MaybeReturnType(i32, i32)});
}
pub fn asOptional(a: anytype) ?ConcreteTypeOf(@TypeOf(a)) {
    if (isTypeOptional(a)) {
        return a;
    }
    return @as(?ConcreteTypeOf(@TypeOf(a)), a);
}

test "Maybe.asOptional" {
    const a: ?f32 = 1.0;
    const b: f32 = 1.0;
    try expect(@TypeOf(asOptional(a)) == ?f32);
    try expect(@TypeOf(asOptional(b)) == ?f32);
}
pub fn add(a: anytype, b: anytype) @TypeOf(a) {
    const _a = if (asOptional(a)) |v| v else return a;
    const _b = if (asOptional(b)) |v| v else return a;

    return _a + _b;
}

test "Maybe.add" {
    const optional: ?f32 = 1.0;
    const concrete: f32 = 2.0;
    const none: ?f32 = null;
    try expect(add(optional, concrete) == 3.0);
    try expect(@TypeOf(add(optional, concrete)) == ?f32);

    try expect(add(optional, none) == optional);
    try expect(@TypeOf(add(optional, none)) == ?f32);

    try expect(add(concrete, none) == concrete);
    try expect(@TypeOf(add(concrete, none)) == f32);

    try expect(add(concrete, concrete) == 4.0);
    try expect(@TypeOf(add(concrete, concrete)) == f32);

    try expect(add(concrete, optional) == 3.0);
    try expect(@TypeOf(add(concrete, optional)) == f32);
}

pub fn sub(a: anytype, b: anytype) @TypeOf(a) {
    const _a = if (asOptional(a)) |v| v else return a;
    const _b = if (asOptional(b)) |v| v else return a;
    return _a - _b;
}

test "Maybe.sub" {
    const optional: ?f32 = 1.0;
    const concrete: f32 = 2.0;
    const none: ?f32 = null;
    try expect(sub(optional, concrete) == -1.0);
    try expect(@TypeOf(sub(optional, concrete)) == ?f32);

    try expect(sub(optional, none) == optional);
    try expect(@TypeOf(sub(optional, none)) == ?f32);

    try expect(sub(concrete, none) == concrete);
    try expect(@TypeOf(sub(concrete, none)) == f32);

    try expect(sub(concrete, concrete) == 0.0);
    try expect(@TypeOf(sub(concrete, concrete)) == f32);

    try expect(sub(concrete, optional) == 1.0);
    try expect(@TypeOf(sub(concrete, optional)) == f32);
}

pub fn min(a: anytype, b: anytype) @TypeOf(a) {
    const _a = if (asOptional(a)) |v| v else return a;
    const _b = if (asOptional(b)) |v| v else return a;

    return @min(_a, _b);
}

pub fn max(a: anytype, b: anytype) @TypeOf(a) {
    const _a = if (asOptional(a)) |v| v else return a;
    const _b = if (asOptional(b)) |v| v else return a;

    return @max(_a, _b);
}

pub fn clamp(a: anytype, min_value: anytype, max_value: anytype) @TypeOf(a) {
    const _a = if (asOptional(a)) |v| v else return a;
    var value = _a;
    if (asOptional(min_value)) |v| value = @max(value, v);
    if (asOptional(max_value)) |v| value = @min(value, v);
    return value;
}

test "Maybe.clamp" {
    const optional: ?f32 = 1.0;
    const concrete: f32 = 2.0;
    const none: ?f32 = null;

    try expect(clamp(optional, concrete, 3.0) == 2.0);
    try expect(@TypeOf(clamp(optional, concrete, 3.0)) == ?f32);

    try expect(clamp(optional, none, 3.0) == optional);
    try expect(@TypeOf(clamp(optional, none, 3.0)) == ?f32);

    try expect(clamp(concrete, none, 3.0) == concrete);
    try expect(@TypeOf(clamp(concrete, none, 3.0)) == f32);

    try expect(clamp(concrete, concrete, 3.0) == 2.0);
    try expect(@TypeOf(clamp(concrete, concrete, 3.0)) == f32);

    try expect(clamp(concrete, optional, 3.0) == 2.0);
    try expect(@TypeOf(clamp(concrete, optional, 3.0)) == f32);
}

pub fn addMembers(a: anytype, b: anytype) @TypeOf(a) {
    var out = a;
    const T = @TypeOf(a);
    inline for (comptime std.meta.fieldNames(T)) |f_name| {
        @field(out, f_name) = add(@field(a, f_name), @field(b, f_name));
    }
    return out;
}

pub fn subMembers(a: anytype, b: anytype) @TypeOf(a) {
    var out = a;
    const T = @TypeOf(a);
    inline for (comptime std.meta.fieldNames(T)) |f_name| {
        @field(out, f_name) = sub(@field(a, f_name), @field(b, f_name));
    }
    return out;
}

pub fn minMembers(a: anytype, b: anytype) @TypeOf(a) {
    var out = a;
    const T = @TypeOf(a);
    inline for (comptime std.meta.fieldNames(T)) |f_name| {
        @field(out, f_name) = min(@field(a, f_name), @field(b, f_name));
    }
    return out;
}

pub fn maxMembers(a: anytype, b: anytype) @TypeOf(a) {
    var out = a;
    const T = @TypeOf(a);
    inline for (comptime std.meta.fieldNames(T)) |f_name| {
        @field(out, f_name) = max(@field(a, f_name), @field(b, f_name));
    }
    return out;
}

pub fn clampMembers(a: anytype, min_value: anytype, max_value: anytype) @TypeOf(a) {
    var out = a;
    const T = @TypeOf(a);
    inline for (comptime std.meta.fieldNames(T)) |f_name| {
        @field(out, f_name) = clamp(@field(a, f_name), @field(min_value, f_name), @field(max_value, f_name));
    }
    return out;
}

fn Foo(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}
test "Maybe.addMembers" {
    // const Foo = struct {
    //     x: f32,
    //     y: f32,
    // };
    const a = Foo(f32){
        .x = 1.0,
        .y = 2.0,
    };
    const b = Foo(?f32){
        .x = 2.0,
        .y = null,
    };
    const result = addMembers(a, b);
    try expect(result.x == 3.0);

    try expect(result.y == 2.0);
}

test "Maybe.clampMembers" {
    const a = Foo(?f32){
        .x = 1.0,
        .y = 2.0,
    };

    const min_value = Foo(?f32){
        .x = null,
        .y = 0.0,
    };
    const max_value = Foo(?f32){
        .x = null,
        .y = 3.0,
    };
    const result = clampMembers(a, min_value, max_value);
    _ = result; // autofix
    // try expect(result.x == 1.0);
    // try expect(result.y == 2.0);
}
