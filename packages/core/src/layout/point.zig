const std = @import("std");
const ConcreteTypeOf = @import("utils/comptime.zig").ConcreteTypeOf;
const MemberType = @import("utils/comptime.zig").MemberType;
const Maybe = @import("utils/Maybe.zig");
const Rect = @import("rect.zig").Rect;
const Style = @import("../tree/Style.zig");
const styles = @import("../styles/styles.zig");
const expect = std.testing.expect;

pub const CSSPoint = Point(f32);
pub const CSSMaybePoint = Point(?f32);

pub const Of = Point;

pub fn Point(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        const Self = @This();
        const ConcreteT = ConcreteTypeOf(T);
        const OptionalT = ?ConcreteT;
        // A function to create a new Point
        pub fn new(x: T, y: T) Self {
            return .{ .x = x, .y = y };
        }

        pub fn width(self: Self) T {
            return self.x;
        }
        pub fn height(self: Self) T {
            return self.y;
        }
        pub fn isZero(self: Self) bool {
            return self.x == 0 and self.y == 0;
        }

        pub fn swap(self: Self) Self {
            return .{
                .x = self.y,
                .y = self.x,
            };
        }
        pub fn orElse(self: Self, other: anytype) @TypeOf(other) {
            return .{
                .x = self.x orelse other.x,
                .y = self.y orelse other.y,
            };
        }
        pub fn resolveOrZero(self: Self, other: anytype) Point(ConcreteT) {
            return self.orElse(other).orElse(Point(ConcreteT).ZERO);
        }
        pub fn orZero(self: Self) Point(ConcreteT) {
            return self.orElse(Point(ConcreteT).ZERO);
        }
        pub fn toRect(self: Self) Rect(T) {
            return Rect(T){
                .top = self.y,
                .bottom = self.y,
                .left = self.x,
                .right = self.x,
            };
        }

        pub fn MaybeResolve(self: type, other: type) type {
            return switch (self) {
                Point(styles.length_percentage.LengthPercentage) => switch (other) {
                    Point(f32), f32 => Point(f32),
                    Point(?f32), ?f32 => Point(?f32),
                    else => @compileError("Unsupported type: " ++ @typeName(other)),
                },
                Point(styles.length_percentage_auto.LengthPercentageAuto) => Point(?f32),
                else => @compileError("Unsupported type: " ++ @typeName(self)),
            };
        }
        pub fn maybeResolve(self: Self, other: anytype) MaybeResolve(@TypeOf(self), @TypeOf(other)) {
            switch (@TypeOf(other)) {
                Point(f32) => {
                    return .{
                        .x = self.x.maybeResolve(@as(f32, other.x)),
                        .y = self.y.maybeResolve(@as(f32, other.y)),
                    };
                },
                Point(?f32) => {
                    return .{
                        .x = self.x.maybeResolve(@as(?f32, other.x)),
                        .y = self.y.maybeResolve(@as(?f32, other.y)),
                    };
                },
                f32 => {
                    return .{
                        .x = self.x.maybeResolve(@as(f32, other)),
                        .y = self.y.maybeResolve(@as(f32, other)),
                    };
                },
                ?f32 => {
                    return .{
                        .x = self.x.maybeResolve(@as(?f32, other)),
                        .y = self.y.maybeResolve(@as(?f32, other)),
                    };
                },
                else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(other))),
            }
        }

        pub fn maybeClamp(self: Self, min: anytype, max_: anytype) Self {
            return Maybe.clampMembers(self, min, max_);
        }
        /// Applies aspect_ratio (if one is supplied) to the Size:
        ///   - If width is `Some` but height is `None`, then height is computed from width and aspect_ratio
        ///   - If height is `Some` but width is `None`, then width is computed from height and aspect_ratio
        ///
        /// If aspect_ratio is `None` then this function simply returns self.
        pub fn maybeApplyAspectRatio(self: Self, aspect_ratio: ?f32) Self {
            if (aspect_ratio) |ratio| {
                if (self.x == null and self.y == null) {
                    return self;
                }
                if (self.x) |w| {
                    return Self{ .x = w, .y = w / ratio };
                } else if (self.y) |h| {
                    return Self{ .x = h * ratio, .y = h };
                }
            }
            return self;
        }
        pub fn maybeAdd(self: Self, other: anytype) Self {
            return Maybe.addMembers(self, other);
        }

        pub fn maybeSub(self: Self, other: anytype) Self {
            return Maybe.subMembers(self, other);
        }

        pub fn maybeMin(self: Self, other: anytype) Self {
            return Maybe.minMembers(self, other);
        }
        pub fn maybeMax(self: Self, other: anytype) Self {
            return Maybe.maxMembers(self, other);
        }

        pub fn add(self: Self, other: Self) Self {
            return .{
                .x = self.x + other.x,
                .y = self.y + other.y,
            };
        }

        pub fn sub(self: Self, other: Self) Self {
            return .{
                .x = self.x - other.x,
                .y = self.y - other.y,
            };
        }
        pub fn round(self: Self) Self {
            return .{
                .x = @round(self.x),
                .y = @round(self.y),
            };
        }
        pub fn max(self: Self, other: Self) Self {
            return .{
                .x = @max(self.x, other.x),
                .y = @max(self.y, other.y),
            };
        }
        pub fn nullable(self: Self) ?Point(ConcreteT) {
            if (self.x == null or self.y == null) {
                return null;
            }
            return .{
                .x = self.x.?,
                .y = self.y.?,
            };
        }
        pub fn intoOptional(self: Self) Point(?ConcreteT) {
            return .{
                .x = self.x,
                .y = self.y,
            };
        }

        pub fn intoConcrete(self: Self) ?Point(ConcreteT) {
            if (self.x == null or self.y == null) {
                return null;
            }
            return .{
                .x = self.x.?,
                .y = self.y.?,
            };
        }
        pub fn diagonalLength(self: Self) ConcreteT {
            return std.math.hypot(self.x, self.y);
        }
        pub const DEFAULT = Self{ .x = 0, .y = 0 };
        pub const ZERO = Self{ .x = 0, .y = 0 };
        pub const NULL = Self{ .x = null, .y = null };
        pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            switch (@typeInfo(ConcreteT)) {
                .int, .float, .comptime_int, .comptime_float => try writer.print("({?d:.2}, {?d:.2})", .{ self.x, self.y }),
                else => try writer.print("(x: {any}, y: {any})", .{ self.x, self.y }),
            }
        }
    };
}
test "Point orElse with optional and concrete" {
    const optional_a: Point(?f32) = .{
        .x = null,
        .y = 1,
    };

    const concrete: Point(f32) = .{
        .x = 2,
        .y = 2,
    };

    const result = optional_a.orElse(concrete);

    try expect(result.x == 2.0);
    try expect(result.y == 1.0);
    try expect(@TypeOf(result) == Point(f32));
}

test "Point orElse with optional and optional" {
    const optional_a: Point(?f32) = .{
        .x = null,
        .y = 1,
    };

    const optional_b: Point(?f32) = .{
        .x = 2,
        .y = null,
    };

    const result = optional_a.orElse(optional_b);

    try expect(result.x == 2.0);
    try expect(result.y == 1.0);
    try expect(@TypeOf(result) == Point(?f32));
}

test "ResolveOrZero" {
    const optional_a: Point(?f32) = .{
        .x = null,
        .y = 1,
    };

    const optional_b: Point(?f32) = .{
        .x = null,
        .y = 2,
    };

    const result = optional_a.resolveOrZero(optional_b);
    try expect(result.x == 0);
    try expect(result.y == 1.0);
    try expect(@TypeOf(result) == Point(f32));
}
test "Point.orZero" {
    const optional_a: Point(?f32) = .{
        .x = null,
        .y = 1,
    };

    const a = Maybe.hasOptional(1, 2);
    _ = a; // autofix

    const result = optional_a.orZero();
    try expect(result.x == 0);
    try expect(result.y == 1.0);
    try expect(@TypeOf(result) == Point(f32));
}
const expectEqual = std.testing.expectEqual;
test "Point.maybeResolve" {
    const optional_a: Point(styles.length_percentage_auto.LengthPercentageAuto) = .{
        .x = .{ .length = 10 },
        .y = .{ .length = 10 },
    };

    const optional_b: Point(?f32) = .{
        .x = null,
        .y = null,
    };

    const concrete = Point(f32){
        .x = 10,
        .y = 10,
    };

    try expectEqual(optional_a.maybeResolve(optional_b), Point(?f32){
        .x = 10,
        .y = 10,
    });

    try expectEqual(optional_a.maybeResolve(concrete), Point(?f32){
        .x = 10,
        .y = 10,
    });
    // const result = optional_a.maybeResolve(concrete);
    // std.debug.print("result: {}\n", .{result});
}
