const styles = @import("styles.zig");
const std = @import("std");
const utils = styles.utils;
const fmt = @import("../fmt.zig");

pub const BackgroundType = enum {
    solid,
    linear_gradient,
    radial_gradient,
};

pub const Background = union(BackgroundType) {
    solid: styles.color.Color,
    linear_gradient: styles.linear_gradient.LinearGradient,
    radial_gradient: styles.radial_gradient.RadialGradient,
};

/// Parses a background value, which can be a solid color, linear gradient, or radial gradient
pub fn parse(src: []const u8, pos: usize) utils.ParseError!utils.Result(Background) {
    const cursor = utils.eatWhitespace(src, pos);

    // Try parsing as a gradient first
    const linear_gradient = utils.consumeFnCall(src, cursor);
    if (linear_gradient.match("linear-gradient(")) {
        // It's a linear gradient
        const gradient_result = try styles.linear_gradient.parse(src, cursor);
        return .{
            .value = .{ .linear_gradient = gradient_result.value },
            .start = gradient_result.start,
            .end = gradient_result.end,
        };
    }

    const radial_gradient = utils.consumeFnCall(src, cursor);
    if (radial_gradient.match("radial-gradient(")) {
        // It's a radial gradient
        const gradient_result = try styles.radial_gradient.parse(src, cursor);
        return .{
            .value = .{ .radial_gradient = gradient_result.value },
            .start = gradient_result.start,
            .end = gradient_result.end,
        };
    }

    // Try parsing as a solid color
    const color_result = try styles.color.parse(src, cursor);
    return .{
        .value = .{ .solid = color_result.value },
        .start = color_result.start,
        .end = color_result.end,
    };
}

test "background-parse" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    // Test solid color
    {
        const src = "red";
        const result = try parse(src, 0);
        try std.testing.expectEqual(BackgroundType.solid, @as(BackgroundType, result.value));
        try std.testing.expectEqual(1.0, result.value.solid.r);
        try std.testing.expectEqual(0.0, result.value.solid.g);
        try std.testing.expectEqual(0.0, result.value.solid.b);
    }

    // Test RGB color
    {
        const src = "rgb(0, 128, 255)";
        const result = try parse(src, 0);
        try std.testing.expectEqual(BackgroundType.solid, @as(BackgroundType, result.value));
        try std.testing.expectEqual(0.0, result.value.solid.r);
        try std.testing.expectApproxEqAbs(@as(f64, 0.5019607843137255), result.value.solid.g, 0.001);
        try std.testing.expectEqual(1.0, result.value.solid.b);
    }

    // Test linear gradient
    {
        const src = "linear-gradient(to right, red, blue)";
        const result = try parse(src, 0);
        try std.testing.expectEqual(BackgroundType.linear_gradient, @as(BackgroundType, result.value));
        try std.testing.expectEqual(90, result.value.linear_gradient.angle);
        try std.testing.expectEqual(2, result.value.linear_gradient.color_stops.items().len);
    }

    // Test radial gradient
    {
        const src = "radial-gradient(circle, red, blue)";
        const result = try parse(src, 0);
        try std.testing.expectEqual(BackgroundType.radial_gradient, @as(BackgroundType, result.value));
        try std.testing.expectEqual(styles.radial_gradient.RadialShape.circle, result.value.radial_gradient.shape);
        try std.testing.expectEqual(2, result.value.radial_gradient.color_stops.items().len);
        try std.testing.expectEqualStrings(src[result.start..result.end], src);
    }
}
