const std = @import("std");
const mod = @import("../mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutTree = mod.LayoutTree;
const LayoutNode = mod.LayoutNode;
const ContainerContext = mod.ContainerContext;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");

/// Recursively process a node and its children to add text content to LinesBuilder
fn processNodeRecursively(context: *LayoutContext, lines_builder: *mod.LinesBuilder, node_id: LayoutNode.Id) !void {
    const node = context.layout_tree.getNodePtr(node_id);
    
    switch (node.data) {
        .text_node => |*text_node| {
            // Convert text content to slice
            const text_content = text_node.contents.items;
            
            // Check if this text contains newlines - if so, preserve them
            const white_space = if (std.mem.indexOf(u8, text_content, "\n") != null) 
                @import("../../../styles/white-space.zig").WhiteSpace.pre 
            else 
                @import("../../../styles/white-space.zig").WhiteSpace.normal;
            
            // Add this text node's content to the lines builder
            try lines_builder.addTextWithNode(text_content, white_space, node_id);
        },
        .inline_container_node => |*container| {
            // Check if we have multiple text children - if so, we need to preserve line breaks between them
            var has_multiple_text_nodes = false;
            var text_count: u32 = 0;
            for (container.children.items) |child_id| {
                const child = context.layout_tree.getNodePtr(child_id);
                if (child.data == .text_node) {
                    text_count += 1;
                    if (text_count > 1) {
                        has_multiple_text_nodes = true;
                        break;
                    }
                }
            }
            
            // Recursively process all children, adding newlines between text nodes if needed
            var prev_was_text = false;
            for (container.children.items) |child_id| {
                const child = context.layout_tree.getNodePtr(child_id);
                if (child.data == .text_node) {
                    // If the previous node was also text and we have multiple text nodes, add a newline
                    if (prev_was_text and has_multiple_text_nodes) {
                        try lines_builder.addTextWithNode("\n", @import("../../../styles/white-space.zig").WhiteSpace.pre, child_id);
                    }
                    prev_was_text = true;
                } else {
                    prev_was_text = false;
                }
                try processNodeRecursively(context, lines_builder, child_id);
            }
        },
        .block_container_node => |*container| {
            // Recursively process all children  
            for (container.children.items) |child_id| {
                try processNodeRecursively(context, lines_builder, child_id);
            }
        },
        .inline_node => |*inline_node| {
            // Recursively process all children
            for (inline_node.children.items) |child_id| {
                try processNodeRecursively(context, lines_builder, child_id);
            }
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
    _ = css_overflow; // autofix
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
            return .{ .size = .{ .x = 0, .y = 0 } };
        },
        else => |e| return e,
    };
}

fn computeInner(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) (mod.ComputeLayoutError || error{InvalidUtf8})!mod.LayoutResult {
    const allocator = context.layout_tree.allocator;
    const l_node = context.layout_tree.getNodePtr(l_node_id);

    // Initialize LinesBuilder with available space from layout constraints
    const available_width = inputs.available_space.x;
    std.debug.print("available_width: {}\n", .{available_width});
    var lines_builder = mod.LinesBuilder.init(allocator, available_width);
    defer lines_builder.deinit();

    // Recursively process all child nodes to collect text content
    try processNodeRecursively(context, &lines_builder, l_node_id);
    
    // Debug: print what's in the buffer
    if (std.mem.indexOf(u8, lines_builder.segmenter.buffer.items, "\n") != null) {
        std.debug.print("Buffer contains newlines: '{s}'\n", .{lines_builder.segmenter.buffer.items});
    } else {
        std.debug.print("Buffer has no newlines: '{s}'\n", .{lines_builder.segmenter.buffer.items});
    }

    // Generate line layout based on white-space mode
    // Use normal wrap mode as default - in a real implementation, 
    // this could be inherited from the container or determined from CSS
    const wrap_mode = @import("../../../styles/white-space.zig").TextWrapMode.wrap;

    try lines_builder.buildLinesWithWrapMode(wrap_mode);

    // Calculate content size from LinesBuilder's measured line dimensions
    var content_width: f32 = 0;
    var content_height: f32 = 0;

    // Position text nodes based on LineBox/LineBoxFragment layout
    var current_y: f32 = 0;

    for (lines_builder.lines.items) |line| {
        // Track the maximum width across all lines
        content_width = @max(content_width, line.size.x);

        // Position fragments within this line
        var current_x: f32 = 0;

        for (line.fragments.items) |fragment| {
            // Update the corresponding layout node's box with position and size
            const fragment_node = context.layout_tree.getNodePtr(fragment.l_node_id);
            fragment_node.box.location = .{ .x = current_x, .y = current_y };
            fragment_node.box.size = fragment.size;
            fragment_node.box.content_size = fragment.size;

            current_x += fragment.size.x;
        }

        // Accumulate total height from all lines
        content_height += line.size.y;
        current_y += line.size.y;
    }

    // If no lines were created, ensure minimum height
    if (lines_builder.lines.items.len == 0) {
        content_height = 16.0; // Default line height
    }

    // Transfer ownership of line boxes to the InlineContainerNode
    // This prevents deallocation when LinesBuilder is destroyed
    if (l_node.data == .inline_container_node) {
        const text_line_boxes = lines_builder.toOwnedLineBoxes();

        // Convert from text.LineBox format to LayoutTree.LineBox format
        var layout_line_boxes = std.ArrayListUnmanaged(LayoutTree.LineBox){};

        for (text_line_boxes.items) |text_line| {
            var layout_line = LayoutTree.LineBox{};

            // Convert fragments from text.LineBoxFragment to LayoutTree.LineBox.Fragment
            for (text_line.fragments.items) |text_fragment| {
                const layout_fragment = LayoutTree.LineBox.Fragment{
                    .node = text_fragment.l_node_id,
                    .start = text_fragment.start,
                    .end = text_fragment.start + text_fragment.length,
                };
                try layout_line.fragments.append(allocator, layout_fragment);
            }

            try layout_line_boxes.append(allocator, layout_line);
        }

        // Clean up the text line boxes
        for (text_line_boxes.items) |*text_line| {
            text_line.fragments.deinit();
        }
        text_line_boxes.deinit();

        l_node.data.inline_container_node.line_boxes = layout_line_boxes;
    }

    return .{
        .size = .{ .x = content_width, .y = content_height },
        .content_size = .{ .x = content_width, .y = content_height },
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
        0,
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
}

test "computeInlineContextLayout with forced breaks" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="display: flex;">
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
    std.debug.print("\n=== Testing with forced breaks and min_content ===\n", .{});
    try mod.computeLayout(
        &context,
        .{ .x = .min_content, .y = .max_content },
        0,
    );
    try context.layout_tree.printRoot(std.io.getStdErr().writer().any());
}
