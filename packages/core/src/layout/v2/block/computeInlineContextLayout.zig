const std = @import("std");
const mod = @import("../mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutTree = mod.LayoutTree;
const LayoutNode = mod.LayoutNode;
const ContainerContext = mod.ContainerContext;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");

/// Recursively process a node and its children to add text content to LineBuilder
fn processNodeRecursively(context: *LayoutContext, lines_builder: *mod.LineBuilder, node_id: LayoutNode.Id, white_space: css_types.WhiteSpace) !void {
    const node = context.layout_tree.getNodePtr(node_id);

    switch (node.data) {
        .inline_container_node => |*container| {
            // root
            for (container.children.items) |child_id| {
                try processNodeRecursively(context, lines_builder, child_id, white_space);
            }
        },
        .text_node => |*text_node| {
            // Convert text content to slice
            const text_content = text_node.contents.items;

            // Add this text node's content to the lines builder
            try lines_builder.appendNodeSlice(text_content, node_id);
        },

        .inline_node => |*inline_node| {
            if (inline_node.is_atomic) return;
            // Recursively process all children
            for (inline_node.children.items) |child_id| {
                try processNodeRecursively(context, lines_builder, child_id, white_space);
            }
        },
        .block_container_node => {
            unreachable;
        },
    }
}

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
    const css_inset = context.getStyleValue(css_types.LengthPercentageAutoRect, l_node_id, .inset);
    _ = css_inset; // autofix
    const css_position = context.getStyleValue(css_types.Position, l_node_id, .position);
    _ = css_position; // autofix
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

    return computeInner(context, .{
        .known_dimensions = styled_based_known_dimensions,

        // unchanged
        .run_mode = inputs.run_mode,
        .sizing_mode = inputs.sizing_mode,
        .axis = inputs.axis,
        .parent_size = inputs.parent_size,
        .available_space = inputs.available_space,
        .vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible,
    }, l_node_id) catch |err| switch (err) {
        error.InvalidUtf8 => {
            // Handle invalid UTF-8 by returning empty content
            return .{
                .size = .{ .x = 0, .y = 0 },
                .resolved_margin = margin,
                .resolved_padding = padding,
                .resolved_border = border,
            };
        },
        else => |e| return e,
    };
}

fn computeInner(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) (mod.ComputeLayoutError || error{InvalidUtf8})!mod.LayoutResult {
    const allocator = context.layout_tree.allocator;

    // Initialize LineBuilder with available space from layout constraints
    const whitespace = switch (context.getStyleValue(css_types.WhiteSpace, l_node_id, .white_space)) {
        .inherit => css_types.WhiteSpace.normal, // TODO: should be resolved by this point
        else => context.getStyleValue(css_types.WhiteSpace, l_node_id, .white_space),
    };
    const whitespace_longhand = whitespace.toLonghand(); // TODO: should be resolved by this point

    const available_width = inputs.available_space.x;
    var lines_builder = mod.LineBuilder.init(
        allocator,
        available_width,
        context,
        whitespace_longhand.wrap_mode,
        whitespace_longhand.collapse,
    );
    defer lines_builder.deinit();

    // The style system should resolve shorthands and inherit values during cascade/computation.
    // Recursively process all child nodes to collect text content
    // try processNodeRecursively(context, &lines_builder, l_node_id, whitespace);
    try mod.compute(
        context,
        allocator,
        inputs,
        l_node_id,
        whitespace_longhand.collapse,
        whitespace_longhand.wrap_mode,
    );

    // Build lines using the multi-pass system
    // try lines_builder.runPhase1CollapseAndTransformation();
    // try lines_builder.runLineWrapping();

    // // Apply text alignment if container has definite width
    // const text_align = context.getStyleValue(css_types.TextAlign, l_node_id, .text_align);
    // if (text_align != .inherit) {
    //     switch (available_width) {
    //         .definite => |width| {
    //             lines_builder.applyTextAlignment(text_align, width);
    //         },
    //         .min_content, .max_content => {
    //             // No alignment for content-based sizing
    //         },
    //     }
    // }

    // Calculate content size from LineBuilder's measured line dimensions
    var content_width: f32 = 0;
    var content_height: f32 = 0;

    // Position text nodes based on LineBox/LineBoxFragment layout

    for (lines_builder.lines.items()) |*line| {
        // Track the maximum width across all lines
        content_width = @max(content_width, line.size.x);
        line.location.y = content_height;

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

    // Get style values for box model
    const css_margins = context.getStyleValue(css_types.LengthPercentageAutoRect, l_node_id, .margin);
    const css_padding = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .padding);
    const css_border = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .border_width);
    const css_overflow = context.getStyleValue(css_types.OverflowPoint, l_node_id, .overflow);
    const css_scrollbar_width = context.getStyleValue(f32, l_node_id, .scrollbar_width);

    // Resolve box model values
    const resolved_margin = mod.CSSRect{
        .top = mod.math.maybeResolve(css_margins.top, inputs.parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_margins.right, inputs.parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_margins.bottom, inputs.parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_margins.left, inputs.parent_size.x) orelse 0,
    };
    const resolved_padding = mod.CSSRect{
        .top = mod.math.maybeResolve(css_padding.top, inputs.parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_padding.right, inputs.parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_padding.bottom, inputs.parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_padding.left, inputs.parent_size.x) orelse 0,
    };
    const resolved_border = mod.CSSRect{
        .top = mod.math.maybeResolve(css_border.top, inputs.parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_border.right, inputs.parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_border.bottom, inputs.parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_border.left, inputs.parent_size.x) orelse 0,
    };
    const scrollbar_size = mod.CSSPoint{
        .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
        .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
    };

    // Use known dimensions if available, otherwise use content dimensions
    const final_size = mod.CSSPoint{
        .x = inputs.known_dimensions.x orelse content_width,
        .y = inputs.known_dimensions.y orelse content_height,
    };

    return .{
        .size = final_size,
        .content_size = .{ .x = content_width, .y = content_height },
        .line_boxes = try lines_builder.toOwnedLineBoxes(context.allocator),
        .resolved_margin = resolved_margin,
        .resolved_padding = resolved_padding,
        .resolved_border = resolved_border,
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

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();
    var context = LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };
    try mod.computeLayout(
        &context,
        .{ .x = .{ .definite = 100 }, .y = .max_content },
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
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

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();
    var context = LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };
    std.debug.print("\n=== Testing with forced breaks ===\n", .{});
    try mod.computeLayout(
        &context,
        .{ .x = .min_content, .y = .max_content },
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
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

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();
    var context = LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };
    std.debug.print("\n=== Testing single line text ===\n", .{});
    try mod.computeLayout(
        &context,
        .{ .x = .{ .definite = 100 }, .y = .max_content },
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
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

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();
    var context = LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };
    std.debug.print("\n=== Testing multiple nodes on single line ===\n", .{});
    try mod.computeLayout(
        &context,
        .{ .x = .{ .definite = 100 }, .y = .max_content },
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
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

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();
    var context = LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };
    std.debug.print("\n=== Testing long text wrapping ===\n", .{});
    try mod.computeLayout(
        &context,
        .{ .x = .{ .definite = 20 }, .y = .max_content },
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
}

test "computeInlineContextLayout real forced breaks" {
    const allocator = std.testing.allocator;
    const doc_xml = "<div style=\"padding:1;width:30\"><p>Line 1\nLine 2\nLine 3</p></div>";
    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();
    var context = LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };
    std.debug.print("\n=== Testing real embedded newlines ===\n", .{});
    try mod.computeLayout(
        &context,
        .{ .x = .min_content, .y = .max_content },
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
}

test "computeInlineContextLayout text alignment" {
    const allocator = std.testing.allocator;

    // Test left alignment (default)
    {
        const doc_xml = "<div style=\"width:50; text-align:left\"><p>Short text</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        var lt = try mod.LayoutTree.fromTree(allocator, &tree);
        defer lt.deinit();
        var context = LayoutContext{
            .layout_tree = &lt,
            .doc_tree = &tree,
            .allocator = allocator,
        };
        std.debug.print("\n=== Testing left text alignment ===\n", .{});
        try mod.computeLayout(
            &context,
            .{ .x = .{ .definite = 50 }, .y = .max_content },
        );
        try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
    }

    // Test center alignment
    {
        const doc_xml = "<div style=\"width:50; text-align:center\"><p>Short text</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        var lt = try mod.LayoutTree.fromTree(allocator, &tree);
        defer lt.deinit();
        var context = LayoutContext{
            .layout_tree = &lt,
            .doc_tree = &tree,
            .allocator = allocator,
        };
        std.debug.print("\n=== Testing center text alignment ===\n", .{});
        try mod.computeLayout(
            &context,
            .{ .x = .{ .definite = 50 }, .y = .max_content },
        );
        try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
    }

    // Test right alignment
    {
        const doc_xml = "<div style=\"width:50; text-align:right\"><p>Short text</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        var lt = try mod.LayoutTree.fromTree(allocator, &tree);
        defer lt.deinit();
        var context = LayoutContext{
            .layout_tree = &lt,
            .doc_tree = &tree,
            .allocator = allocator,
        };
        std.debug.print("\n=== Testing right text alignment ===\n", .{});
        try mod.computeLayout(
            &context,
            .{ .x = .{ .definite = 50 }, .y = .max_content },
        );
        try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
    }

    // Test alignment with multiple lines
    {
        const doc_xml = "<div style=\"width:20; text-align:center\"><p>This is longer text that will wrap</p></div>";
        var tree = try mod.docFromXml(allocator, doc_xml, .{});
        defer tree.deinit();

        var lt = try mod.LayoutTree.fromTree(allocator, &tree);
        defer lt.deinit();
        var context = LayoutContext{
            .layout_tree = &lt,
            .doc_tree = &tree,
            .allocator = allocator,
        };
        std.debug.print("\n=== Testing center alignment with wrapping ===\n", .{});
        try mod.computeLayout(
            &context,
            .{ .x = .{ .definite = 20 }, .y = .max_content },
        );
        try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
    }
}
