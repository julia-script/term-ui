const std = @import("std");
const utils = @import("utils.zig");
const Color = @import("../colors/Color.zig");
const color_module = @import("color.zig");

/// The type of line decoration
pub const TextDecorationLine = enum {
    /// No decoration
    none,

    /// Single underline
    underline,

    /// Double underline
    double,

    /// Dashed underline
    dashed,

    /// Strikethrough (line through the middle of text)
    line_through,

    /// Wave/squiggly underline (typically used for spelling/grammar errors)
    wavy,

    /// Inherit from parent (default)
    inherit,
};

/// Text decoration style options
pub const TextDecoration = struct {
    /// The type of line decoration
    line: TextDecorationLine = .inherit,

    /// The color for the decoration line (null means use the text color)
    color: ?Color = null,

    /// Thickness multiplier for the decoration line (1.0 = normal)
    thickness: f32 = 1.0,

    /// Creates a default text decoration (inherit)
    pub fn init() TextDecoration {
        return .{};
    }

    /// Creates underline with the current text color
    pub fn underline() TextDecoration {
        return .{ .line = .underline };
    }

    /// Creates strikethrough with the current text color
    pub fn lineThrough() TextDecoration {
        return .{ .line = .line_through };
    }

    /// Creates wavy/squiggly underline with the current text color
    pub fn wavy() TextDecoration {
        return .{ .line = .wavy };
    }

    /// Creates an underline with a custom color
    pub fn underlineWithColor(color_val: Color) TextDecoration {
        return .{
            .line = .underline,
            .color = color_val,
        };
    }

    /// Creates a wavy underline with a custom color
    pub fn wavyWithColor(color_val: Color) TextDecoration {
        return .{
            .line = .wavy,
            .color = color_val,
        };
    }
};

/// Parse text decoration from a string
pub fn parseTextDecorationLine(src: []const u8, pos: usize) utils.ParseError!utils.Result(TextDecorationLine) {
    if (utils.parseEnum(TextDecorationLine, src, pos)) |result| {
        return result;
    } else {
        return error.InvalidSyntax;
    }
}

/// Parses a full text decoration from a string like "underline red 2.0"
pub fn parse(src: []const u8, pos: usize) utils.ParseError!utils.Result(TextDecoration) {
    var cursor = utils.eatWhitespace(src, pos);

    // Try to parse the line type first
    const line_result = try parseTextDecorationLine(src, cursor);
    if (line_result.start == line_result.end) {
        return error.InvalidSyntax;
    }

    var result = TextDecoration{
        .line = line_result.value,
    };

    cursor = utils.eatWhitespace(src, line_result.end);
    if (cursor >= src.len) {
        return .{
            .value = result,
            .start = pos,
            .end = cursor,
        };
    }

    // Try to parse a color
    if (color_module.parse(src, cursor)) |color_result| {
        result.color = color_result.value;
        cursor = utils.eatWhitespace(src, color_result.end);

        // Check for thickness
        if (cursor < src.len) {
            if (utils.parseNumber(src, cursor)) |thickness_result| {
                result.thickness = std.fmt.parseFloat(f32, thickness_result.value) catch 1.0;
                cursor = thickness_result.end;
            } else |_| {}
        }
    } else |_| {
        // Try to parse thickness directly
        if (utils.parseNumber(src, cursor)) |thickness_result| {
            result.thickness = std.fmt.parseFloat(f32, thickness_result.value) catch 1.0;
            cursor = thickness_result.end;
        } else |_| {}
    }

    return .{
        .value = result,
        .start = pos,
        .end = cursor,
    };
}

test "parse text decoration line" {
    const none_result = try parseTextDecorationLine("none", 0);
    try std.testing.expectEqual(none_result.value, .none);

    const underline_result = try parseTextDecorationLine("underline", 0);
    try std.testing.expectEqual(underline_result.value, .underline);

    const line_through_result = try parseTextDecorationLine("line-through", 0);
    try std.testing.expectEqual(line_through_result.value, .line_through);

    const inherit_result = try parseTextDecorationLine("inherit", 0);
    try std.testing.expectEqual(inherit_result.value, .inherit);
}

test "parse text decoration" {
    const allocator = std.testing.allocator;
    _ = allocator; // autofix

    const simple_result = try parse("underline", 0);
    try std.testing.expectEqual(simple_result.value.line, .underline);
    try std.testing.expect(simple_result.value.color == null);
    try std.testing.expectEqual(simple_result.value.thickness, 1.0);

    const with_color_result = try parse("wavy red", 0);
    try std.testing.expectEqual(with_color_result.value.line, .wavy);
    try std.testing.expect(with_color_result.value.color != null);
    if (with_color_result.value.color) |color| {
        try std.testing.expectEqual(color.r, 1.0);
        try std.testing.expectEqual(color.g, 0.0);
        try std.testing.expectEqual(color.b, 0.0);
    }

    const full_result = try parse("underline #00ff00 2.5", 0);
    try std.testing.expectEqual(full_result.value.line, .underline);
    try std.testing.expect(full_result.value.color != null);
    if (full_result.value.color) |color| {
        try std.testing.expectEqual(color.g, 1.0);
    }
    try std.testing.expectEqual(full_result.value.thickness, 2.5);
}
