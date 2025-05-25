const std = @import("std");
const styles = @import("styles.zig");
const Tree = @import("../tree/Tree.zig");
const Style = @import("../tree/Style.zig");
const text_decoration = styles.text_decoration;
const font_style = styles.font_style;
const color = styles.color;
const ComputedStyleCache = styles.computed_style.ComputedStyleCache;
const Renderer = @import("../renderer/Renderer.zig");
const Canvas = @import("../renderer/Canvas.zig");
const utils = @import("utils.zig");
const font_weight = styles.font_weight;

const testing = std.testing;

test "text_decoration_parsing" {
    const allocator = testing.allocator;

    // Basic decoration types
    {
        const result = try text_decoration.parse(allocator, "underline", 0);
        try testing.expectEqual(result.value.line, .underline);
        try testing.expect(result.value.color == null);
        try testing.expectEqual(result.value.thickness, 1.0);
    }

    // Check for the line-through decoration
    {
        const result = try text_decoration.parse(allocator, "line-through", 0);
        try testing.expectEqual(result.value.line, .line_through);
    }

    {
        const result = try text_decoration.parse(allocator, "wavy", 0);
        try testing.expectEqual(result.value.line, .wavy);
    }

    // With color
    {
        const result = try text_decoration.parse(allocator, "underline red", 0);
        try testing.expectEqual(result.value.line, .underline);
        try testing.expect(result.value.color != null);
        if (result.value.color) |c| {
            try testing.expectEqual(c.r, 1.0);
            try testing.expectEqual(c.g, 0.0);
            try testing.expectEqual(c.b, 0.0);
        }
    }

    // With thickness
    {
        const result = try text_decoration.parse(allocator, "underline 2.5", 0);
        try testing.expectEqual(result.value.line, .underline);
        try testing.expectEqual(result.value.thickness, 2.5);
    }

    // With color and thickness
    {
        const result = try text_decoration.parse(allocator, "wavy #00ff00 3.0", 0);
        try testing.expectEqual(result.value.line, .wavy);
        try testing.expect(result.value.color != null);
        if (result.value.color) |c| {
            try testing.expectApproxEqAbs(c.g, 1.0, 0.001);
        }
        try testing.expectEqual(result.value.thickness, 3.0);
    }
}

test "font_weight_parsing" {
    const allocator = testing.allocator;

    {
        const result = try font_weight.parse(allocator, "normal", 0);
        try testing.expectEqual(result.value, .normal);
    }

    {
        const result = try font_weight.parse(allocator, "bold", 0);
        try testing.expectEqual(result.value, .bold);
    }

    {
        const result = try font_weight.parse(allocator, "dim", 0);
        try testing.expectEqual(result.value, .dim);
    }

    {
        const result = try font_weight.parse(allocator, "inherit", 0);
        try testing.expectEqual(result.value, .inherit);
    }
}

test "font_style_parsing" {
    const allocator = testing.allocator;

    {
        const result = try font_style.parse(allocator, "normal", 0);
        try testing.expectEqual(result.value, .normal);
    }

    {
        const result = try font_style.parse(allocator, "italic", 0);
        try testing.expectEqual(result.value, .italic);
    }

    {
        const result = try font_style.parse(allocator, "inherit", 0);
        try testing.expectEqual(result.value, .inherit);
    }
}

test "basic_style_inheritance" {
    const allocator = testing.allocator;

    // Create a tree with parent-child structure
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create nodes with styles
    const parent_id = try tree.createNode();
    const child_id = try tree.createNode();
    const grandchild_id = try tree.createNode();

    try tree.appendChild(parent_id, child_id);
    try tree.appendChild(child_id, grandchild_id);

    // Set styles on parent
    {
        var parent_style = tree.getStyle(parent_id);
        parent_style.font_weight = .bold;
        parent_style.font_style = .italic;
        parent_style.text_decoration = text_decoration.TextDecoration.underline();
        parent_style.foreground_color = color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 }; // Red
    }

    // Set text_align on child (explicit, not inherit)
    {
        var child_style = tree.getStyle(child_id);
        child_style.font_weight = .inherit; // Should inherit bold
        child_style.text_decoration.line = .line_through; // Override parent
    }

    // Set all properties to inherit on grandchild
    {
        var grandchild_style = tree.getStyle(grandchild_id);
        grandchild_style.font_weight = .inherit;
        grandchild_style.font_style = .inherit;
        grandchild_style.text_decoration.line = .inherit;
    }

    // Test computed styles
    var style_cache = try ComputedStyleCache.init(allocator);
    defer style_cache.deinit();

    // Check parent computed style
    {
        const parent_computed = style_cache.getComputedStyle(&tree, parent_id);
        try testing.expectEqual(parent_computed.font_weight, .bold);
        try testing.expectEqual(parent_computed.font_style, .italic);
        try testing.expectEqual(parent_computed.text_decoration.line, .underline);
    }

    // Check child computed style (should inherit some, override others)
    {
        const child_computed = style_cache.getComputedStyle(&tree, child_id);
        try testing.expectEqual(child_computed.font_weight, .bold); // Inherited
        try testing.expectEqual(child_computed.font_style, .italic); // Inherited
        try testing.expectEqual(child_computed.text_decoration.line, .line_through); // Overridden
    }

    // Check grandchild computed style (should inherit all)
    {
        const grandchild_computed = style_cache.getComputedStyle(&tree, grandchild_id);
        try testing.expectEqual(grandchild_computed.font_weight, .bold); // Inherited from parent
        try testing.expectEqual(grandchild_computed.font_style, .italic); // Inherited from parent
        try testing.expectEqual(grandchild_computed.text_decoration.line, .line_through); // Inherited from child
        try testing.expect(grandchild_computed.foreground_color != null); // Should inherit red color
    }
}

test "textformat_conversion" {
    // Create various style combinations
    const normal_format = Canvas.TextFormat.fromStyle(.normal, .normal, .{});
    try testing.expect(!normal_format.is_bold);
    try testing.expect(!normal_format.is_italic);
    try testing.expect(!normal_format.is_dim);
    try testing.expectEqual(normal_format.decoration_line, .none);

    const bold_format = Canvas.TextFormat.fromStyle(.bold, .normal, .{});
    try testing.expect(bold_format.is_bold);
    try testing.expect(!bold_format.is_italic);

    const italic_format = Canvas.TextFormat.fromStyle(.normal, .italic, .{});
    try testing.expect(!italic_format.is_bold);
    try testing.expect(italic_format.is_italic);

    const dim_format = Canvas.TextFormat.fromStyle(.dim, .normal, .{});
    try testing.expect(!dim_format.is_bold);
    try testing.expect(dim_format.is_dim);

    // Test with decoration
    const underline_decoration = text_decoration.TextDecoration.underline();
    const underline_format = Canvas.TextFormat.fromStyle(.normal, .normal, underline_decoration);
    try testing.expectEqual(underline_format.decoration_line, .underline);
    try testing.expect(underline_format.decoration_color == null);
    try testing.expectEqual(underline_format.decoration_thickness, 1.0);
}

test "canvas_formatting" {
    const allocator = testing.allocator;

    // Create a Canvas with specific dimensions
    var canvas = try Canvas.init(allocator, .{ .x = 100, .y = 50 }, color.Color.tw.black, color.Color.tw.white);
    defer canvas.deinit();

    // Test basic formatting
    try canvas.drawStringFormatted(.{ .x = 5, .y = 5 }, "Bold text", color.Color.tw.white, .{ .is_bold = true });

    // Test underline
    try canvas.drawStringFormatted(.{ .x = 5, .y = 10 }, "Underlined text", color.Color.tw.white, .{ .decoration_line = .underline });

    // Test colored underline
    try canvas.drawStringFormatted(.{ .x = 5, .y = 15 }, "Colored underline", color.Color.tw.white, .{
        .decoration_line = .wavy,
        .decoration_color = color.Color.tw.red_500,
    });

    // Verify cell format information
    {
        const bold_cell = canvas.fetchCell(.{ .x = 5, .y = 5 });
        try testing.expect(bold_cell.format.is_bold);
        try testing.expect(!bold_cell.format.is_italic);
        try testing.expectEqual(bold_cell.format.decoration_line, .none);
    }

    {
        const underline_cell = canvas.fetchCell(.{ .x = 5, .y = 10 });
        try testing.expect(!underline_cell.format.is_bold);
        try testing.expectEqual(underline_cell.format.decoration_line, .underline);
    }

    {
        const colored_cell = canvas.fetchCell(.{ .x = 5, .y = 15 });
        try testing.expectEqual(colored_cell.format.decoration_line, .wavy);
        try testing.expect(colored_cell.format.decoration_color != null);
    }
}

test "style_copying" {
    const allocator = testing.allocator;

    // Create source style with formatting
    var source = Style.init(allocator);
    defer source.deinit();

    // Set source formatting
    source.font_weight = .bold;
    source.font_style = .italic;
    source.text_decoration = text_decoration.TextDecoration.underlineWithColor(color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 });

    // Create destination style
    var dest = Style.init(allocator);
    defer dest.deinit();

    // Copy styles
    dest.copyFrom(&source);

    // Verify all formatting was copied correctly
    try testing.expectEqual(dest.font_weight, .bold);
    try testing.expectEqual(dest.font_style, .italic);
    try testing.expectEqual(dest.text_decoration.line, .underline);
    try testing.expect(dest.text_decoration.color != null);
    if (dest.text_decoration.color) |c| {
        try testing.expectEqual(c.r, 1.0);
    }
}

test "float_conversions" {
    const allocator = testing.allocator;

    // Create a Canvas with specific dimensions
    var canvas = try Canvas.init(allocator, .{ .x = 100, .y = 50 }, color.Color.tw.black, color.Color.tw.white);
    defer canvas.deinit();

    // Create text_decoration with floating point thickness
    const decoration = text_decoration.TextDecoration{
        .line = .underline,
        .thickness = 2.5,
    };

    // Test drawing formatted text with float values
    const pos_x = 10.25;
    const pos_y = 15.75;
    try canvas.drawStringFormatted(.{ .x = pos_x, .y = pos_y }, "Float test", color.Color.tw.white, .{
        .decoration_line = decoration.line,
        .decoration_thickness = decoration.thickness,
    });

    // Verify cell position and format
    const cell_x: u32 = @intFromFloat(@round(pos_x));
    const cell_y: u32 = @intFromFloat(@round(pos_y));

    const cell = canvas.fetchCell(.{ .x = cell_x, .y = cell_y });
    try testing.expectEqual(cell.format.decoration_line, .underline);
    try testing.expectEqual(cell.format.decoration_thickness, 2.5);

    // Test float-to-int conversions that might cause issues in WASM
    const rect_width: u32 = 80;
    const rect_height: u32 = 40;

    const float_width: f32 = @floatFromInt(rect_width);
    const float_height: f32 = @floatFromInt(rect_height);

    const back_to_u32_width: u32 = @intFromFloat(float_width);
    const back_to_u32_height: u32 = @intFromFloat(float_height);

    try testing.expectEqual(back_to_u32_width, rect_width);
    try testing.expectEqual(back_to_u32_height, rect_height);

    // Check roundtrip with non-integer values
    const non_integer: f32 = 12.75;
    const rounded: u32 = @intFromFloat(@round(non_integer));
    try testing.expectEqual(rounded, 13);
}
