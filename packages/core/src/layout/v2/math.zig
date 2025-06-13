const css_types = @import("../../css/types.zig");
const std = @import("std");
const mod = @import("mod.zig");

pub fn maybeResolve(value: anytype, maybe_container_size: ?f32) ?f32 {
    return switch (@TypeOf(value)) {
        css_types.LengthPercentage => switch (value) {
            .length => |length| length,
            .percentage => |percentage| if (maybe_container_size) |container_size| container_size * percentage else null,
        },
        css_types.LengthPercentageAuto => switch (value) {
            .length => |length| length,
            .percentage => |percentage| if (maybe_container_size) |container_size| container_size * percentage else null,
            .auto => null,
        },
        f32 => if (maybe_container_size) |container_size| container_size * value else null,

        else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(value))),
    };
}
pub fn maybeResolveOnPoint(value: anytype, maybe_container_size: mod.CSSMaybePoint) mod.CSSMaybePoint {
    return .{
        .x = maybeResolve(value.x, maybe_container_size.x),
        .y = maybeResolve(value.y, maybe_container_size.y),
    };
}
pub fn maybeResolveRect(value: anytype, maybe_container_size: ?f32) mod.CSSMaybeRect {
    return .{
        .top = maybeResolve(value.top, maybe_container_size),
        .right = maybeResolve(value.right, maybe_container_size),
        .bottom = maybeResolve(value.bottom, maybe_container_size),
        .left = maybeResolve(value.left, maybe_container_size),
    };
}
pub fn unwrapRect(maybe_rect: mod.CSSMaybeRect) mod.CSSRect {
    return .{
        .top = maybe_rect.top.?,
        .right = maybe_rect.right.?,
        .bottom = maybe_rect.bottom.?,
        .left = maybe_rect.left.?,
    };
}

pub fn maybeResolveRectOnPoint(value: anytype, maybe_container_size: mod.CSSMaybePoint) mod.CSSMaybeRect {
    return .{
        .top = maybeResolve(value.top, maybe_container_size.y),
        .right = maybeResolve(value.right, maybe_container_size.x),
        .bottom = maybeResolve(value.bottom, maybe_container_size.y),
        .left = maybeResolve(value.left, maybe_container_size.x),
    };
}
pub fn clamp(value: f32, min: f32, max: f32) f32 {
    return @max(@min(value, max), min);
}
pub fn maybeClamp(maybe_value: ?f32, maybe_min: ?f32, maybe_max: ?f32) ?f32 {
    var value = maybe_value orelse return maybe_value;
    if (maybe_min) |min| value = @max(value, min);
    if (maybe_max) |max| value = @min(value, max);
    return value;
}
pub fn maybeMax(maybe_value: ?f32, maybe_other: ?f32) ?f32 {
    const value = maybe_value orelse return maybe_value;
    const other = maybe_other orelse return maybe_value;
    return @max(value, other);
}
pub fn maybeOrElse(maybe_value: mod.CSSMaybePoint, maybe_other: mod.CSSMaybePoint) mod.CSSMaybePoint {
    return .{
        .x = maybe_value.x orelse maybe_other.x,
        .y = maybe_value.y orelse maybe_other.y,
    };
}
pub fn orElse(maybe_value: mod.CSSMaybePoint, maybe_other: mod.CSSPoint) mod.CSSPoint {
    return .{
        .x = maybe_value.x orelse maybe_other.x,
        .y = maybe_value.y orelse maybe_other.y,
    };
}
pub fn maybeMin(maybe_value: ?f32, maybe_other: ?f32) ?f32 {
    const value = maybe_value orelse return maybe_value;
    const other = maybe_other orelse return maybe_value;
    return @min(value, other);
}
pub fn maybeMul(maybe_value: ?f32, maybe_other: ?f32) ?f32 {
    const value = maybe_value orelse return maybe_value;
    const other = maybe_other orelse return maybe_value;
    return value * other;
}

pub fn maybeDiv(maybe_value: ?f32, maybe_other: ?f32) ?f32 {
    const value = maybe_value orelse return maybe_value;
    const other = maybe_other orelse return maybe_value;
    return value / other;
}

pub fn maybeSub(maybe_value: ?f32, maybe_other: ?f32) ?f32 {
    const value = maybe_value orelse return maybe_value;
    const other = maybe_other orelse return maybe_value;
    return value - other;
}
pub fn maybeAdd(maybe_value: ?f32, maybe_other: ?f32) ?f32 {
    const value = maybe_value orelse return maybe_value;
    const other = maybe_other orelse return maybe_value;
    return value + other;
}
pub fn orZero(maybe_value: ?f32) f32 {
    return maybe_value orelse 0;
}

pub fn maybeApplyAspectRatio(self: mod.CSSMaybePoint, aspect_ratio: ?f32) mod.CSSMaybePoint {
    if (aspect_ratio) |ratio| {
        if (self.x == null and self.y == null) {
            return self;
        }
        if (self.x) |w| {
            return .{ .x = w, .y = w / ratio };
        } else if (self.y) |h| {
            return .{ .x = h * ratio, .y = h };
        }
    }
    return self;
}
