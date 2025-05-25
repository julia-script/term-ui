const std = @import("std");
const mod = @import("../mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutTree = mod.LayoutTree;
const LayoutNode = mod.LayoutNode;
const ContainerContext = mod.ContainerContext;

const CSSPoint = mod.CSSPoint;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");

// Import all our modular components
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");
const flexLines = @import("flexLines.zig");
const mainSize = @import("mainSize.zig");
const crossSize = @import("crossSize.zig");
const alignment = @import("alignment.zig");
const finalLayout = @import("finalLayout.zig");

const measureChildSize = @import("measureChildSize.zig").measureChildSize;
const computeAlignmentOffset = @import("computeAlignmentOffset.zig").computeAlignmentOffset;
const computeContentSizeContribution = @import("computeContentSizeContribution.zig").computeContentSizeContribution;

pub fn computeFlexboxLayout(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) mod.ComputeLayoutError!mod.LayoutResult {
    context.info(l_node_id, "computeFlexboxLayout", .{});
    const l_node = context.layout_tree.getNodePtr(l_node_id);
    _ = l_node; // autofix
    const available_space = inputs.available_space;
    const parent_size = inputs.parent_size;

    // Get style values
    const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .size);
    const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .min_size);
    const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .max_size);
    const css_margins = context.getStyleValue(css_types.LengthPercentageAutoRect, l_node_id, .margin);
    const css_padding = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .padding);
    const css_border = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .border_width);
    const css_overflow = context.getStyleValue(css_types.OverflowPoint, l_node_id, .overflow);
    const css_aspect_ratio = context.getStyleValue(?f32, l_node_id, .aspect_ratio);
    const css_flex_direction = context.getStyleValue(css_types.FlexDirection, l_node_id, .flex_direction);
    const css_flex_wrap = context.getStyleValue(css_types.FlexWrap, l_node_id, .flex_wrap);
    const css_align_items = context.getStyleValue(css_types.AlignItems, l_node_id, .align_items);
    const css_align_content = context.getStyleValue(css_types.AlignContent, l_node_id, .align_content);
    const css_justify_content = context.getStyleValue(css_types.JustifyContent, l_node_id, .justify_content);
    const css_gap = context.getStyleValue(css_types.LengthPercentagePoint, l_node_id, .gap);
    const css_scrollbar_width = context.getStyleValue(f32, l_node_id, .scrollbar_width);

    // Resolve basic values
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
    const gap = mod.CSSPoint{
        .x = mod.math.maybeResolve(css_gap.x, parent_size.x) orelse 0,
        .y = mod.math.maybeResolve(css_gap.y, parent_size.y) orelse 0,
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

    const available_space_based_size = mod.CSSMaybePoint{
        .x = mod.math.maybeSub(switch (available_space.x) {
            .definite => available_space.x.definite,
            else => null,
        }, margin.sumHorizontal()),
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

    return try computeInner(context, .{
        .known_dimensions = styled_based_known_dimensions,
        .run_mode = inputs.run_mode,
        .sizing_mode = inputs.sizing_mode,
        .axis = inputs.axis,
        .parent_size = inputs.parent_size,
        .available_space = inputs.available_space,
        .vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible,
    }, l_node_id, css_flex_direction, css_flex_wrap, css_align_items, css_align_content, css_justify_content, gap, padding, border, maybe_min_size, maybe_max_size, css_overflow, css_scrollbar_width);
}

/// Inner flexbox computation function that implements the full flexbox algorithm
fn computeInner(
    context: *LayoutContext,
    inputs: ContainerContext,
    l_node_id: LayoutNode.Id,
    css_flex_direction: css_types.FlexDirection,
    css_flex_wrap: css_types.FlexWrap,
    css_align_items: css_types.AlignItems,
    css_align_content: css_types.AlignContent,
    css_justify_content: css_types.JustifyContent,
    gap: mod.CSSPoint,
    padding: mod.CSSRect,
    border: mod.CSSRect,
    min_size: mod.CSSMaybePoint,
    max_size: mod.CSSMaybePoint,
    css_overflow: css_types.OverflowPoint,
    css_scrollbar_width: f32,
) mod.ComputeLayoutError!mod.LayoutResult {

    // Compute algorithm constants
    _ = computeConstants(context, l_node_id, inputs.known_dimensions, inputs.parent_size, css_flex_direction, css_flex_wrap, css_align_items, css_align_content, css_justify_content, gap, padding, border, min_size, max_size, css_overflow, css_scrollbar_width);

    // Simplified flexbox algorithm for now
    const children = context.layout_tree.getChildren(l_node_id);
    var content_size = mod.CSSPoint{ .x = 0, .y = 0 };

    // Simple layout - lay out children in a row
    var offset_x: f32 = padding.left + border.left;
    var max_height: f32 = 0;

    for (children) |child_id| {
        const child_layout = try mod.performChildLayout(
            context,
            child_id,
            mod.CSSMaybePoint.NULL,
            inputs.parent_size,
            .{
                .x = .min_content,
                .y = .min_content,
            },
            .inherent_size,
            .{ .start = false, .end = false },
        );

        context.setBox(child_id, .{
            .size = child_layout.size,
            .location = .{ .x = offset_x, .y = padding.top + border.top },
            .margin = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            .padding = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            .border = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            .content_size = child_layout.content_size,
            .scrollbar_size = mod.CSSPoint{ .x = 0, .y = 0 },
        }, child_layout.line_boxes);

        offset_x += child_layout.size.x;
        max_height = @max(max_height, child_layout.size.y);
        content_size.x = @max(content_size.x, offset_x);
        content_size.y = @max(content_size.y, max_height);
    }

    const container_size = mod.CSSPoint{
        .x = inputs.known_dimensions.x orelse (content_size.x + padding.sumHorizontal() + border.sumHorizontal()),
        .y = inputs.known_dimensions.y orelse (content_size.y + padding.sumVertical() + border.sumVertical()),
    };

    if (inputs.run_mode == .compute_size) {
        return .{
            .size = container_size,
        };
    }

    return .{
        .size = container_size,
        .content_size = content_size,
        .first_baselines = mod.CSSMaybePoint.NULL,
        .top_margin = mod.CollapsibleMarginSet.ZERO,
        .bottom_margin = mod.CollapsibleMarginSet.ZERO,
        .margins_can_collapse_through = false,
    };
}

fn computeConstants(
    context: *LayoutContext,
    l_node_id: LayoutNode.Id,
    known_dimensions: mod.CSSMaybePoint,
    parent_size: mod.CSSMaybePoint,
    css_flex_direction: css_types.FlexDirection,
    css_flex_wrap: css_types.FlexWrap,
    css_align_items: css_types.AlignItems,
    css_align_content: css_types.AlignContent,
    css_justify_content: css_types.JustifyContent,
    gap: mod.CSSPoint,
    padding: mod.CSSRect,
    border: mod.CSSRect,
    min_size: mod.CSSMaybePoint,
    max_size: mod.CSSMaybePoint,
    css_overflow: css_types.OverflowPoint,
    css_scrollbar_width: f32,
) types.AlgoConstants {
    _ = context;
    _ = l_node_id;
    _ = parent_size;

    const is_row = css_flex_direction == .row or css_flex_direction == .row_reverse;
    const is_wrap = css_flex_wrap == .wrap or css_flex_wrap == .wrap_reverse;

    const scrollbar_gutter = mod.CSSPoint{
        .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
        .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
    };

    const content_box_inset = mod.CSSRect{
        .left = padding.left + border.left + scrollbar_gutter.x,
        .right = padding.right + border.right + scrollbar_gutter.x,
        .top = padding.top + border.top + scrollbar_gutter.y,
        .bottom = padding.bottom + border.bottom + scrollbar_gutter.y,
    };

    return types.AlgoConstants{
        .dir = css_flex_direction,
        .is_row = is_row,
        .is_column = !is_row,
        .is_wrap = is_wrap,
        .is_wrap_reverse = css_flex_wrap == .wrap_reverse,
        .min_size = min_size,
        .max_size = max_size,
        .margin = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
        .border = border,
        .content_box_inset = content_box_inset,
        .scrollbar_gutter = scrollbar_gutter,
        .gap = gap,
        .align_items = css_align_items,
        .align_content = css_align_content,
        .justify_content = css_justify_content,
        .node_outer_size = known_dimensions,
        .node_inner_size = mod.CSSMaybePoint{
            .x = mod.math.maybeSub(known_dimensions.x, content_box_inset.sumHorizontal()),
            .y = mod.math.maybeSub(known_dimensions.y, content_box_inset.sumVertical()),
        },
        .container_size = mod.CSSPoint{
            .x = known_dimensions.x orelse 0,
            .y = known_dimensions.y orelse 0,
        },
        .inner_container_size = mod.CSSPoint{
            .x = (known_dimensions.x orelse 0) - content_box_inset.sumHorizontal(),
            .y = (known_dimensions.y orelse 0) - content_box_inset.sumVertical(),
        },
    };
}

test "computeFlexLayout" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div style="width: 30px;">
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
