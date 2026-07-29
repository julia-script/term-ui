const std = @import("std");
const utils = @import("utils.zig");

/// z-index controls the stacking order of positioned elements
/// https://developer.mozilla.org/en-US/docs/Web/CSS/z-index
pub const ZIndex = union(enum) {
    /// Automatically determined by paint order
    auto,
    /// Integer value for stacking order
    integer: i32,

    pub const DEFAULT = ZIndex{ .auto = {} };
};

pub fn parse(src: []const u8, pos: usize) !utils.Result(ZIndex) {
    // Skip whitespace
    const start = utils.eatWhitespace(src, pos);

    // Check for "auto"
    if (utils.matchIdentifier(src, "auto", start)) |auto_range| {
        return utils.Result(ZIndex){
            .value = ZIndex{ .auto = {} },
            .start = auto_range.start,
            .end = auto_range.end,
        };
    }

    // Try to parse as integer
    const number_range = utils.parseNumber(src, start) catch return error.InvalidSyntax;

    // Parse as integer
    const int_value = std.fmt.parseInt(i32, number_range.value, 10) catch return error.InvalidSyntax;

    return utils.Result(ZIndex){
        .value = ZIndex{ .integer = int_value },
        .start = number_range.start,
        .end = number_range.end,
    };
}

test "parse z-index" {
    const expectEqual = std.testing.expectEqual;

    // Test auto
    {
        const result = try parse("auto", 0);
        try expectEqual(ZIndex{ .auto = {} }, result.value);
        try expectEqual(@as(usize, 4), result.end);
    }

    // Test positive integer
    {
        const result = try parse("10", 0);
        try expectEqual(ZIndex{ .integer = 10 }, result.value);
        try expectEqual(@as(usize, 2), result.end);
    }

    // Test negative integer
    {
        const result = try parse("-5", 0);
        try expectEqual(ZIndex{ .integer = -5 }, result.value);
        try expectEqual(@as(usize, 2), result.end);
    }

    // Test zero
    {
        const result = try parse("0", 0);
        try expectEqual(ZIndex{ .integer = 0 }, result.value);
        try expectEqual(@as(usize, 1), result.end);
    }
}
