const std = @import("std");
const mod = @import("../mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutTree = mod.LayoutTree;
const LayoutNode = mod.LayoutNode;
const ContainerContext = mod.ContainerContext;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");

pub fn computeInlineContextLayout(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) mod.ComputeLayoutError!mod.LayoutResult {
    context.info(l_node_id, "computeInlineContextLayout", .{});
    const l_node = context.layout_tree.getNodePtr(l_node_id);
    _ = l_node; // autofix
    const available_space = inputs.available_space;
    const parent_size = inputs.parent_size;

    const maybe_container_size = CSSMaybePoint{
        .x = switch (available_space.x) {
            .definite => available_space.x.definite,
            else => null,
        },
        .y = switch (available_space.y) {
            .definite => available_space.y.definite,
            else => null,
        },
    };
    _ = maybe_container_size; // autofix
    // Get style values
    const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .size);
    const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .min_size);
    const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .max_size);
    const css_margins = context.getStyleValue(css_types.LengthPercentageAutoRect, l_node_id, .margin);
    const css_padding = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .padding);
    const css_border = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .border_width);
    const css_display = context.getStyleValue(css_types.Display, l_node_id, .display);
    const css_overflow = context.getStyleValue(css_types.OverflowPoint, l_node_id, .overflow);
    const css_aspect_ratio = context.getStyleValue(?f32, l_node_id, .aspect_ratio);

    // Resolve margins
    const margin = mod.CSSRect{
        .top = mod.math.maybeResolve(css_margins.top, parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_margins.right, parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_margins.bottom, parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_margins.left, parent_size.x) orelse 0,
    };
    const padding = mod.CSSRect{
        .top = mod.math.maybeResolve(css_padding.top, parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_padding.right, parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_padding.bottom, parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_padding.left, parent_size.x) orelse 0,
    };
    const border = mod.CSSRect{
        .top = mod.math.maybeResolve(css_border.top, parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_border.right, parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_border.bottom, parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_border.left, parent_size.x) orelse 0,
    };
    const maybe_min_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
        .x = mod.math.maybeResolve(css_min_size.x, parent_size.x),
        .y = mod.math.maybeResolve(css_min_size.y, parent_size.y),
    }, css_aspect_ratio);

    const maybe_max_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
        .x = mod.math.maybeResolve(css_max_size.x, parent_size.x),
        .y = mod.math.maybeResolve(css_max_size.y, parent_size.y),
    }, css_aspect_ratio);

    const clamped_style_size = switch (inputs.sizing_mode) {
        .inherent_size => mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_size.x, parent_size.x),
            .y = mod.math.maybeResolve(css_size.y, parent_size.y),
        }, css_aspect_ratio),
        else => mod.CSSMaybePoint.NULL,
    };
    const padding_border_size = mod.CSSPoint{
        .x = padding.sumHorizontal() + border.sumHorizontal(),
        .y = padding.sumVertical() + border.sumVertical(),
    };

    // If both min and max in a given axis are set and max <= min then this determines the size in that axis
    var min_max_definite_size = mod.CSSMaybePoint.NULL;
    if (maybe_min_size.x) |min| if (maybe_max_size.x) |max| if (max <= min) {
        min_max_definite_size.x = min;
    };

    if (maybe_min_size.y) |min| if (maybe_max_size.y) |max| if (max <= min) {
        min_max_definite_size.y = min;
    };

    // Block nodes automatically stretch fit their width to fit available space if available space is definite
    const available_space_based_size = mod.CSSMaybePoint{
        .x = if (css_display.outside != .@"inline") mod.math.maybeSub(switch (available_space.x) {
            .definite => available_space.x.definite,
            else => null,
        }, margin.sumHorizontal()) else null,
        .y = null,
    };

    const styled_based_known_dimensions = mod.CSSMaybePoint{
        .x = mod.math.maybeMax(inputs.known_dimensions.x orelse min_max_definite_size.x orelse clamped_style_size.x orelse available_space_based_size.x, padding_border_size.x),
        .y = mod.math.maybeMax(inputs.known_dimensions.y orelse min_max_definite_size.y orelse clamped_style_size.y orelse available_space_based_size.y, padding_border_size.y),
    };
    if (inputs.run_mode == .compute_size and styled_based_known_dimensions.x != null and styled_based_known_dimensions.y != null) {
        return .{
            .size = .{
                .x = styled_based_known_dimensions.x.?,
                .y = styled_based_known_dimensions.y.?,
            },
            .resolved_margin = margin,
            .resolved_padding = padding,
            .resolved_border = border,
            .scrollbar_size = .{
                .x = if (css_overflow.y == .scroll) context.getStyleValue(f32, l_node_id, .scrollbar_width) else 0,
                .y = if (css_overflow.x == .scroll) context.getStyleValue(f32, l_node_id, .scrollbar_width) else 0,
            },
        };
    }

    // Get style values for text layout
    const white_space_collapse = context.getStyleValue(css_types.WhiteSpaceCollapse, l_node_id, .white_space_collapse);
    const text_wrap_mode = context.getStyleValue(css_types.TextWrapMode, l_node_id, .text_wrap_mode);
    const text_align = context.getStyleValue(css_types.TextAlign, l_node_id, .text_align);
    const css_scrollbar_width = context.getStyleValue(f32, l_node_id, .scrollbar_width);

    // Calculate scrollbar gutters
    const scrollbar_gutter = mod.CSSRect{
        .top = 0,
        .left = 0,
        .right = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
        .bottom = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
    };

    // Calculate content box inset
    const content_box_inset = mod.CSSRect{
        .left = padding.left + border.left + scrollbar_gutter.left,
        .right = padding.right + border.right + scrollbar_gutter.right,
        .top = padding.top + border.top + scrollbar_gutter.top,
        .bottom = padding.bottom + border.bottom + scrollbar_gutter.bottom,
    };

    // Adjust available space for content box
    const content_box_available_space = mod.constants.AvailableSpacePoint{
        .x = if (styled_based_known_dimensions.x) |width|
            mod.constants.AvailableSpace{ .definite = @max(0, width - content_box_inset.sumHorizontal()) }
        else
            inputs.available_space.x.maybeSubtractIfDefinite(content_box_inset.sumHorizontal()),
        .y = if (styled_based_known_dimensions.y) |height|
            mod.constants.AvailableSpace{ .definite = @max(0, height - content_box_inset.sumVertical()) }
        else
            inputs.available_space.y.maybeSubtractIfDefinite(content_box_inset.sumVertical()),
    };

    const known_dimensions = mod.CSSMaybePoint{
        .x = mod.math.maybeSub(styled_based_known_dimensions.x, content_box_inset.sumHorizontal()),
        .y = mod.math.maybeSub(styled_based_known_dimensions.y, content_box_inset.sumVertical()),
    };
    _ = known_dimensions; // autofix
    // Create adjusted inputs for line building
    const content_inputs = ContainerContext{
        .known_dimensions = mod.CSSMaybePoint{
            .x = mod.math.maybeSub(styled_based_known_dimensions.x, content_box_inset.sumHorizontal()),
            .y = mod.math.maybeSub(styled_based_known_dimensions.y, content_box_inset.sumVertical()),
        },
        .available_space = content_box_available_space,
        .parent_size = inputs.parent_size,
        .run_mode = inputs.run_mode,
        .sizing_mode = inputs.sizing_mode,
        .axis = inputs.axis,
        .vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible,
    };

    // Process all text through the line-builder pipeline with content box dimensions
    const line_boxes = mod.compute(
        context,
        context.allocator,
        content_inputs,
        l_node_id,
        white_space_collapse,
        text_wrap_mode,
        text_align,
    ) catch |err| switch (err) {
        error.InvalidUtf8 => {
            // Handle invalid UTF-8 by returning empty content
            return .{
                .size = mod.CSSPoint{
                    .x = styled_based_known_dimensions.x orelse 0,
                    .y = styled_based_known_dimensions.y orelse 0,
                },
                .content_size = .{ .x = 0, .y = 0 },
                .resolved_margin = margin,
                .resolved_padding = padding,
                .resolved_border = border,
                .scrollbar_size = .{
                    .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
                    .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
                },
            };
        },
        else => |e| return e,
    };

    // Calculate content size from line boxes
    var content_width: f32 = 0;
    var content_height: f32 = 0;

    for (line_boxes.list.items) |*line| {
        // Track the maximum width across all lines
        content_width = @max(content_width, line.size.x);
        line.location.y = content_height + content_box_inset.top;
        line.location.x = content_box_inset.left;

        // Position fragments within this line using alignment-adjusted positions
        for (line.fragments.items) |fragment| {
            // Update the corresponding layout node's box with position and size
            const fragment_node = context.layout_tree.getNodePtr(fragment.l_node_id);
            fragment_node.box.location = .{ .x = fragment.position.x, .y = line.size.y - fragment.size.y };
            fragment_node.box.size = fragment.size;
            fragment_node.box.content_size = fragment.size;
        }

        // Accumulate total height from all lines
        content_height += line.size.y;
    }

    // Use known dimensions if available, otherwise use content dimensions
    const final_size = mod.CSSPoint{
        .x = styled_based_known_dimensions.x orelse (content_width + content_box_inset.sumHorizontal()),
        .y = styled_based_known_dimensions.y orelse (content_height + content_box_inset.sumVertical()),
    };

    const scrollbar_size = mod.CSSPoint{
        .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
        .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
    };

    return .{
        .size = final_size,
        .content_size = .{ .x = content_width, .y = content_height },
        .line_boxes = line_boxes,
        .resolved_margin = margin,
        .resolved_padding = padding,
        .resolved_border = border,
        .scrollbar_size = scrollbar_size,
    };
}

test "computeInlineContextLayout" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="display: flex; width: 30px;">
        \\  <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        \\  <p>Hello, world!</p>
        \\</div> 
        \\
    ;
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .{ .definite = 100 }, .y = .max_content });
}

test "computeInlineContextLayout with forced breaks" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="padding:1;width:30">
        \\  <p>Line 1
        \\Line 2
        \\Line 3</p>
        \\</div> 
        \\
    ;
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .min_content, .y = .max_content });
}

test "computeInlineContextLayout single line" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="padding:1;width:100">
        \\  <p>Short text</p>
        \\</div> 
        \\
    ;
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .{ .definite = 100 }, .y = .max_content });
}

test "computeInlineContextLayout multiple fragments one line" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="padding:1;width:100">
        \\  <p>Hello world test</p>
        \\</div> 
        \\
    ;
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .{ .definite = 100 }, .y = .max_content });
}

test "computeInlineContextLayout long text wrapping" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="padding:1;width:20">
        \\  <p>This is a very long text that should definitely wrap across multiple lines when the available width is constrained</p>
        \\</div> 
        \\
    ;
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .{ .definite = 20 }, .y = .max_content });
}

test "computeInlineContextLayout real forced breaks" {
    const allocator = std.testing.allocator;
    const doc_xml = "<div style=\"padding:1;width:30\"><p>Line 1\nLine 2\nLine 3</p></div>";
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .min_content, .y = .max_content });
}

test "computeInlineContextLayout text alignment" {
    const allocator = std.testing.allocator;

    // Test left alignment (default)
    {
        const doc_xml = "<div style=\"width:50; text-align:left\"><p>Short text</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        // Use the new pipeline approach
        try tree.computeStyles();
        try tree.buildLayoutTree();
        try tree.computeLayout(allocator, .{ .x = .{ .definite = 50 }, .y = .max_content });
    }

    // Test center alignment
    {
        const doc_xml = "<div style=\"width:50; text-align:center\"><p>Short text</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        // Use the new pipeline approach
        try tree.computeStyles();
        try tree.buildLayoutTree();
        try tree.computeLayout(allocator, .{ .x = .{ .definite = 50 }, .y = .max_content });
    }

    // Test right alignment
    {
        const doc_xml = "<div style=\"width:50; text-align:right\"><p>Short text</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        // Use the new pipeline approach
        try tree.computeStyles();
        try tree.buildLayoutTree();
        try tree.computeLayout(allocator, .{ .x = .{ .definite = 50 }, .y = .max_content });
    }

    // Test alignment with multiple lines
    {
        const doc_xml = "<div style=\"width:20; text-align:center\"><p>This is longer text that will wrap</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        // Use the new pipeline approach
        try tree.computeStyles();
        try tree.buildLayoutTree();
        try tree.computeLayout(allocator, .{ .x = .{ .definite = 20 }, .y = .max_content });
    }
}
