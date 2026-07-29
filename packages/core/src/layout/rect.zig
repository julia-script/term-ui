const std = @import("std");
const ConcreteTypeOf = @import("utils/comptime.zig").ConcreteTypeOf;
const Point = @import("point.zig").Point;
const Maybe = @import("utils/Maybe.zig");
const MemberType = @import("utils/comptime.zig").MemberType;
pub const CSSRect = Rect(f32);
pub const CSSMaybeRect = Rect(?f32);
pub const Of = Rect;

pub fn Rect(comptime T: type) type {
    return struct {
        top: T,
        right: T,
        bottom: T,
        left: T,

        const Self = @This();
        const ConcreteT = ConcreteTypeOf(T);
        const OptionalT = ?ConcreteT;

        pub fn from(other: anytype) Self {
            switch (@TypeOf(other)) {
                Point(T) => return Self{ .left = other.x, .right = other.x, .top = other.y, .bottom = other.y },
                Rect(T) => return other,
                else => return Self{ .left = other, .right = other, .top = other, .bottom = other },
            }
        }
        pub fn fields() @TypeOf(std.meta.fields(Self)) {
            return std.meta.fields(Self);
        }

        // pub const FIELDS = std.meta.fields(Self);
        pub fn new(left: T, right: T, top: T, bottom: T) Rect {
            return Rect{ .T = T, .left = left, .right = right, .top = top, .bottom = bottom };
        }

        pub fn orElse(self: Self, other: anytype) @TypeOf(other) {
            return .{
                .left = self.left orelse other.left,
                .right = self.right orelse other.right,
                .top = self.top orelse other.top,
                .bottom = self.bottom orelse other.bottom,
            };
        }

        pub fn resolveOrZero(self: Self, other: anytype) Rect(ConcreteT) {
            return self.orElse(other).orZero();
        }

        fn MaybeResolve(TOther: type) type {
            if (@hasField(MemberType(Self), "auto")) {
                return ?f32;
            } else {
                return MemberType(TOther);
            }
        }
        pub fn maybeResolve(self: Self, other: anytype) Rect(MaybeResolve(@TypeOf(other))) {
            switch (@TypeOf(other)) {
                f32, ?f32 => return .{
                    .left = self.left.maybeResolve(other),
                    .right = self.right.maybeResolve(other),
                    .top = self.top.maybeResolve(other),
                    .bottom = self.bottom.maybeResolve(other),
                },
                else => return .{
                    .left = self.left.maybeResolve(other.left),
                    .right = self.right.maybeResolve(other.right),
                    .top = self.top.maybeResolve(other.top),
                    .bottom = self.bottom.maybeResolve(other.bottom),
                },
            }
            // return .{
            //     .left = self.left.maybeResolve(other),
            //     .right = self.right.maybeResolve(other),
            //     .top = self.top.maybeResolve(other),
            //     .bottom = self.bottom.maybeResolve(other),
            // };
        }

        pub fn orZero(self: Self) Rect(ConcreteT) {
            return self.orElse(Rect(ConcreteT).ZERO);
        }

        pub fn add(self: Self, other: Self) Self {
            return Maybe.addMembers(self, other);
            // return Self{
            //     .left = self.left + other.left,
            //     .right = self.right + other.right,
            //     .top = self.top + other.top,
            //     .bottom = self.bottom + other.bottom,
            // };
        }

        pub fn maybeAdd(self: Self, other: Self) Self {
            return Maybe.addMembers(self, other);
            // return Self{
            //     // .top = if (self.top != null and other.top != null) self.top.? + other.top.? else null,
            // .right = if (self.right != null and other.right != null) self.right.? + other.right.? else null,
            // .bottom = if (self.bottom != null and other.bottom != null) self.bottom.? + other.bottom.? else null,
            // .left = if (self.left != null and other.left != null) self.left.? + other.left.? else null,
            // };
        }
        pub fn maybeSub(self: Self, other: Self) Self {
            return Maybe.subMembers(self, other);
            // return Self{
            //     .top = if (self.top != null and other.top != null) self.top.? - other.top.? else null,
            //     .right = if (self.right != null and other.right != null) self.right.? - other.right.? else null,
            //     .bottom = if (self.bottom != null and other.bottom != null) self.bottom.? - other.bottom.? else null,
            //     .left = if (self.left != null and other.left != null) self.left.? - other.left.? else null,
            // };
        }

        pub fn maybeMax(self: Self, other: Self) Self {
            return Maybe.maxMembers(self, other);
        }

        pub fn maybeMin(self: Self, other: Self) Self {
            return Maybe.minMembers(self, other);
        }

        pub fn maybeClamp(self: Self, min: Self, max: Self) Self {
            return Maybe.clampMembers(self, min, max);
        }

        pub fn sumAxes(self: Self) Point(T) {
            return Point(T){
                .x = self.right + self.left,
                .y = self.bottom + self.top,
            };
        }
        pub fn sumHorizontal(self: Self) T {
            return self.right + self.left;
        }

        pub fn sumVertical(self: Self) T {
            return self.bottom + self.top;
        }

        pub const ZERO = Self{ .left = 0, .right = 0, .top = 0, .bottom = 0 };
        pub const NULL = Self{ .left = null, .right = null, .top = null, .bottom = null };
        pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
            _ = fmt; // autofix
            _ = options; // autofix
            _ = fmt;
            _ = options;
            try writer.print("Rect({s}) {{", .{@typeName(T)});
            switch (@typeInfo(ConcreteT)) {
                .int, .float, .comptime_int, .comptime_float => try writer.print("l: {?d:.2}, r: {?d:.2}, t: {?d:.2}, b: {?d:.2}", .{ self.left, self.right, self.top, self.bottom }),
                else => try writer.print("l: {any}, r: {any}, t: {any}, b: {any}", .{ self.left, self.right, self.top, self.bottom }),
            }
            try writer.print("}}", .{});
        }
    };
}

test "Rect.from" {
    const b = Rect(?f32){ .left = null, .right = 1.0, .top = 2.0, .bottom = 2.0 };
    _ = b; // autofix
}
