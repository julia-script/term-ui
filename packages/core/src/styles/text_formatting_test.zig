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
const computeLayout = @import("../layout/compute/compute_layout.zig").computeLayout;

const testing = std.testing;

test "text decoration parsing" {
    const allocator = testing.allocator;

    // Basic decoration types
    {
        const result = try text_decoration.parse(allocator, "underline", 0);
        try testing.expectEqual(result.value.line, .underline);
        try testing.expect(result.value.color == null);
        try testing.expectEqual(result.value.thickness, 1.0);
    }

    {
        const result = try text_decoration.parse(allocator, "line_through", 0);
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

    // Explicit inheritance
    {
        const result = try text_decoration.parse(allocator, "inherit", 0);
        try testing.expectEqual(result.value.line, .inherit);
    }

    // None value
    {
        const result = try text_decoration.parse(allocator, "none", 0);
        try testing.expectEqual(result.value.line, .none);
    }

    // Double underline
    {
        const result = try text_decoration.parse(allocator, "double", 0);
        try testing.expectEqual(result.value.line, .double);
    }

    // Dashed underline
    {
        const result = try text_decoration.parse(allocator, "dashed", 0);
        try testing.expectEqual(result.value.line, .dashed);
    }
}

test "font weight parsing" {
    const allocator = testing.allocator;

    {
        const result = try font_style.parseFontWeight(allocator, "normal", 0);
        try testing.expectEqual(result.value, .normal);
    }

    {
        const result = try font_style.parseFontWeight(allocator, "bold", 0);
        try testing.expectEqual(result.value, .bold);
    }

    {
        const result = try font_style.parseFontWeight(allocator, "dim", 0);
        try testing.expectEqual(result.value, .dim);
    }

    {
        const result = try font_style.parseFontWeight(allocator, "inherit", 0);
        try testing.expectEqual(result.value, .inherit);
    }

    // Test error case
    {
        const parse_result = font_style.parseFontWeight(allocator, "invalid", 0);
        try testing.expectError(error.InvalidSyntax, parse_result);
    }
}

test "font style parsing" {
    const allocator = testing.allocator;

    {
        const result = try font_style.parseFontStyle(allocator, "normal", 0);
        try testing.expectEqual(result.value, .normal);
    }

    {
        const result = try font_style.parseFontStyle(allocator, "italic", 0);
        try testing.expectEqual(result.value, .italic);
    }

    {
        const result = try font_style.parseFontStyle(allocator, "inherit", 0);
        try testing.expectEqual(result.value, .inherit);
    }

    // Test error case
    {
        const parse_result = font_style.parseFontStyle(allocator, "invalid", 0);
        try testing.expectError(error.InvalidSyntax, parse_result);
    }
}

test "text formatting inheritance" {
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

    // Test invalidation
    {
        // Change parent style
        var parent_style = tree.getStyle(parent_id);
        parent_style.font_weight = .normal;

        // Invalidate cache
        style_cache.invalidateTree(&tree, parent_id);

        // Check that changes propagated
        const grandchild_computed = style_cache.getComputedStyle(&tree, grandchild_id);
        try testing.expectEqual(grandchild_computed.font_weight, .normal); // Should get updated value
    }
}

test "TextFormat conversion" {
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

    // Test with decoration and color
    const color_value = color.Color{ .r = 0, .g = 1, .b = 0, .a = 1 };
    const colored_underline = text_decoration.TextDecoration{
        .line = .underline,
        .color = color_value,
        .thickness = 2.0,
    };
    const colored_format = Canvas.TextFormat.fromStyle(.normal, .normal, colored_underline);
    try testing.expectEqual(colored_format.decoration_line, .underline);
    try testing.expect(colored_format.decoration_color != null);
    if (colored_format.decoration_color) |c| {
        try testing.expectEqual(c.g, 1.0);
    }
    try testing.expectEqual(colored_format.decoration_thickness, 2.0);

    // Combined styles
    const combined_format = Canvas.TextFormat.fromStyle(.bold, .italic, colored_underline);
    try testing.expect(combined_format.is_bold);
    try testing.expect(combined_format.is_italic);
    try testing.expectEqual(combined_format.decoration_line, .underline);
}

test "renderer with text formatting" {
    const allocator = testing.allocator;

    // Create a simple tree with formatted text
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create renderer
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();

    // Create root node
    const root_id = try tree.createNode();

    // Create text nodes with different formatting
    const bold_id = try tree.createNode();
    const italic_id = try tree.createNode();
    const underline_id = try tree.createNode();
    const colored_id = try tree.createNode();

    // Set up the tree
    try tree.appendChild(root_id, bold_id);
    try tree.appendChild(root_id, italic_id);
    try tree.appendChild(root_id, underline_id);
    try tree.appendChild(root_id, colored_id);

    // Set text content
    try tree.setText(bold_id, "Bold text");
    try tree.setText(italic_id, "Italic text");
    try tree.setText(underline_id, "Underlined text");
    try tree.setText(colored_id, "Colored underline");

    // Apply styling
    {
        var bold_style = tree.getStyle(bold_id);
        bold_style.font_weight = .bold;

        var italic_style = tree.getStyle(italic_id);
        italic_style.font_style = .italic;

        var underline_style = tree.getStyle(underline_id);
        underline_style.text_decoration = text_decoration.TextDecoration.underline();

        var colored_style = tree.getStyle(colored_id);
        colored_style.text_decoration = text_decoration.TextDecoration{
            .line = .wavy,
            .color = color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 }, // Red
            .thickness = 2.0,
        };
    }

    // Compute styles and layout using the new API
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{
        .x = .{ .definite = 100 },
        .y = .{ .definite = 50 },
    });

    // Paint using the new API
    const null_writer = std.io.null_writer.any();
    try tree.paint(&renderer, null_writer, .simple);

    // Additional tests that can help catch WASM issues:

    // 1. Test accessing computed style properties
    var style_cache = try ComputedStyleCache.init(allocator);
    defer style_cache.deinit();

    // Check that computed styles are correct
    const bold_computed = style_cache.getComputedStyle(&tree, bold_id);
    try testing.expectEqual(bold_computed.font_weight, .bold);

    const italic_computed = style_cache.getComputedStyle(&tree, italic_id);
    try testing.expectEqual(italic_computed.font_style, .italic);

    const underline_computed = style_cache.getComputedStyle(&tree, underline_id);
    try testing.expectEqual(underline_computed.text_decoration.line, .underline);

    const colored_computed = style_cache.getComputedStyle(&tree, colored_id);
    try testing.expectEqual(colored_computed.text_decoration.line, .wavy);
    try testing.expect(colored_computed.text_decoration.color != null);

    // 2. Test direct Canvas rendering with text formatting
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

    // Test combined formatting
    try canvas.drawStringFormatted(.{ .x = 5, .y = 20 }, "Combined formatting", color.Color.tw.white, .{
        .is_bold = true,
        .is_italic = true,
        .decoration_line = .underline,
    });

    // Render to null writer to test rendering path
    try canvas.render(null_writer, false);

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

    {
        const combined_cell = canvas.fetchCell(.{ .x = 5, .y = 20 });
        try testing.expect(combined_cell.format.is_bold);
        try testing.expect(combined_cell.format.is_italic);
        try testing.expectEqual(combined_cell.format.decoration_line, .underline);
    }
}

test "text decoration utilities" {
    // Test the creation helper functions
    const underline = text_decoration.TextDecoration.underline();
    try testing.expectEqual(underline.line, .underline);
    try testing.expect(underline.color == null);
    try testing.expectEqual(underline.thickness, 1.0);

    const line_through = text_decoration.TextDecoration.lineThrough();
    try testing.expectEqual(line_through.line, .line_through);

    const wavy = text_decoration.TextDecoration.wavy();
    try testing.expectEqual(wavy.line, .wavy);

    // Test colored decoration helpers
    const color_value = color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 };

    const colored_underline = text_decoration.TextDecoration.underlineWithColor(color_value);
    try testing.expectEqual(colored_underline.line, .underline);
    try testing.expect(colored_underline.color != null);
    if (colored_underline.color) |c| {
        try testing.expectEqual(c.r, 1.0);
    }

    const colored_wavy = text_decoration.TextDecoration.wavyWithColor(color_value);
    try testing.expectEqual(colored_wavy.line, .wavy);
    try testing.expect(colored_wavy.color != null);
}

test "style copying with text formatting" {
    const allocator = testing.allocator;

    // Create source style with formatting
    var source = try Style.init(allocator);
    defer source.deinit();

    // Set source formatting
    source.font_weight = .bold;
    source.font_style = .italic;
    source.text_decoration = text_decoration.TextDecoration.underlineWithColor(color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 });

    // Create destination style
    var dest = try Style.init(allocator);
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

test "style to terminal escapes conversion" {
    // Create a canvas to test escape sequence generation
    const allocator = testing.allocator;
    var canvas = try Canvas.init(allocator, .{ .x = 40, .y = 10 }, color.Color.tw.black, color.Color.tw.white);
    defer canvas.deinit();

    // Set up styles for different test cases
    const bold_format = Canvas.TextFormat{ .is_bold = true };
    const italic_format = Canvas.TextFormat{ .is_italic = true };
    const underline_format = Canvas.TextFormat{ .decoration_line = .underline };
    const strikethrough_format = Canvas.TextFormat{ .decoration_line = .line_through };

    // Add text with different formats
    try canvas.drawStringFormatted(.{ .x = 0, .y = 0 }, "Bold", null, bold_format);
    try canvas.drawStringFormatted(.{ .x = 0, .y = 1 }, "Italic", null, italic_format);
    try canvas.drawStringFormatted(.{ .x = 0, .y = 2 }, "Underline", null, underline_format);
    try canvas.drawStringFormatted(.{ .x = 0, .y = 3 }, "Strike", null, strikethrough_format);

    // Render to capture escape sequences
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    try canvas.render(buffer.writer().any(), false);

    // Check that buffer contains expected escape sequences
    const buffer_str = buffer.items;

    // Check for bold escape sequence: \x1b[1m
    try testing.expect(std.mem.indexOf(u8, buffer_str, "\x1b[1m") != null);

    // Check for italic escape sequence: \x1b[3m
    try testing.expect(std.mem.indexOf(u8, buffer_str, "\x1b[3m") != null);

    // Check for underline escape sequence: \x1b[4m
    try testing.expect(std.mem.indexOf(u8, buffer_str, "\x1b[4m") != null);

    // Check for strikethrough escape sequence: \x1b[9m
    try testing.expect(std.mem.indexOf(u8, buffer_str, "\x1b[9m") != null);

    // Check for reset sequence: \x1b[0m
    try testing.expect(std.mem.indexOf(u8, buffer_str, "\x1b[0m") != null);
}

test "parse CSS style text decoration" {
    const allocator = testing.allocator;

    // Parse from CSS-like strings
    {
        const result = try text_decoration.parse(allocator, "underline", 0);
        try testing.expectEqual(result.value.line, .underline);
    }

    // Parse with hex color
    {
        const result = try text_decoration.parse(allocator, "underline #ff0000", 0);
        try testing.expectEqual(result.value.line, .underline);
        try testing.expect(result.value.color != null);
        if (result.value.color) |c| {
            try testing.expectEqual(c.r, 1.0);
            try testing.expectEqual(c.g, 0.0);
            try testing.expectEqual(c.b, 0.0);
        }
    }

    // Parse with named color and thickness
    {
        const result = try text_decoration.parse(allocator, "wavy green 2.5", 0);
        try testing.expectEqual(result.value.line, .wavy);
        try testing.expect(result.value.color != null);
        try testing.expectEqual(result.value.thickness, 2.5);
    }

    // Edge cases - just thickness
    {
        const result = try text_decoration.parse(allocator, "underline 3.0", 0);
        try testing.expectEqual(result.value.line, .underline);
        try testing.expect(result.value.color == null);
        try testing.expectEqual(result.value.thickness, 3.0);
    }
}

test "text formatting style binding" {
    const allocator = testing.allocator;

    // Create a tree
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a node
    const node_id = try tree.createNode();

    // Get the style
    var style = tree.getStyle(node_id);

    // Set font-weight through parser
    style.font_weight = (try font_style.parseFontWeight(allocator, "bold", 0)).value;
    try testing.expectEqual(style.font_weight, .bold);

    // Set font-style through parser
    style.font_style = (try font_style.parseFontStyle(allocator, "italic", 0)).value;
    try testing.expectEqual(style.font_style, .italic);

    // Set text-decoration through parser
    style.text_decoration = (try text_decoration.parse(allocator, "underline red 2.0", 0)).value;
    try testing.expectEqual(style.text_decoration.line, .underline);
    try testing.expect(style.text_decoration.color != null);
    try testing.expectEqual(style.text_decoration.thickness, 2.0);

    // Create a temporary string similar to what WASM would parse
    const temp_styles = "font-weight: bold; font-style: italic; text-decoration: underline";

    // Simulate a parseStyles similar to wasm.zig
    var iter_properties = std.mem.splitSequence(u8, temp_styles, ";");
    var source_style = try Style.init(allocator);
    defer source_style.deinit();

    while (iter_properties.next()) |_property| {
        const property = std.mem.trim(u8, _property, " \t\n\r");
        if (property.len == 0) continue;

        var iter_property = std.mem.splitSequence(u8, property, ":");
        const key = std.mem.trim(u8, iter_property.next() orelse continue, " \t\n\r");
        const value = std.mem.trim(u8, iter_property.next() orelse continue, " \t\n\r");

        if (std.mem.eql(u8, key, "font-weight")) {
            source_style.font_weight = (try font_style.parseFontWeight(allocator, value, 0)).value;
        } else if (std.mem.eql(u8, key, "font-style")) {
            source_style.font_style = (try font_style.parseFontStyle(allocator, value, 0)).value;
        } else if (std.mem.eql(u8, key, "text-decoration")) {
            source_style.text_decoration = (try text_decoration.parse(allocator, value, 0)).value;
        }
    }

    // Verify the style was set correctly
    try testing.expectEqual(source_style.font_weight, .bold);
    try testing.expectEqual(source_style.font_style, .italic);
    try testing.expectEqual(source_style.text_decoration.line, .underline);
}

test "text formatting float conversions" {
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
    const pos = .{ .x = 10.25, .y = 15.75 }; // Non-integer position
    try canvas.drawStringFormatted(pos, "Float test", color.Color.tw.white, .{
        .decoration_line = decoration.line,
        .decoration_thickness = decoration.thickness,
    });

    // Verify cell position and format
    const cell_x: u32 = @intFromFloat(@round(pos.x));
    const cell_y: u32 = @intFromFloat(@round(pos.y));

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

    // Test with canvas mask functions that use float-to-int conversion
    canvas.setMask(.{
        .pos = .{ .x = 5.5, .y = 6.5 },
        .size = .{ .x = 20.25, .y = 15.75 },
    });

    try testing.expectEqual(canvas.getMinX(), 5);
    try testing.expectEqual(canvas.getMinY(), 6);
    try testing.expectEqual(canvas.getMaxX(), 25); // 5 + 20
    try testing.expectEqual(canvas.getMaxY(), 22); // 6 + 16
}
