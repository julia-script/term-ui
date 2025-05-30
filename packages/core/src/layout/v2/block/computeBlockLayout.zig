const std = @import("std");
const mod = @import("../mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutTree = mod.LayoutTree;
const LayoutNode = mod.LayoutNode;
const ContainerContext = mod.ContainerContext;

const CSSPoint = mod.CSSPoint;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");

pub fn computeBlockLayout(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) mod.ComputeLayoutError!mod.LayoutResult {
    context.info(l_node_id, "computeBlockLayout", .{});
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
    const css_scrollbar_width = context.getStyleValue(f32, l_node_id, .scrollbar_width);

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
        // For compute_size mode, we still need to provide basic box model data
        const compute_size_margin = mod.CSSRect{
            .top = mod.math.maybeResolve(css_margins.top, parent_size.x) orelse 0,
            .right = mod.math.maybeResolve(css_margins.right, parent_size.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_margins.bottom, parent_size.x) orelse 0,
            .left = mod.math.maybeResolve(css_margins.left, parent_size.x) orelse 0,
        };

        return .{
            .size = .{
                .x = styled_based_known_dimensions.x.?,
                .y = styled_based_known_dimensions.y.?,
            },
            .resolved_margin = compute_size_margin,
            .resolved_padding = padding,
            .resolved_border = border,
            .scrollbar_size = .{
                .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
                .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
            },
        };
    }

    return try computeInner(context, .{
        .known_dimensions = styled_based_known_dimensions,

        // unchanged
        .run_mode = inputs.run_mode,
        .sizing_mode = inputs.sizing_mode,
        .axis = inputs.axis,
        .parent_size = inputs.parent_size,
        .available_space = inputs.available_space,
        .vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible,
    }, l_node_id);
}

const BlockItem = struct {
    node_id: LayoutNode.Id,
    /// The "source order" of the item. This is the index of the item within the children iterator,
    /// and controls the order in which the nodes are placed
    order: u32,
    /// The base size of this item
    size: mod.CSSMaybePoint,
    /// The minimum allowable size of this item
    min_size: mod.CSSMaybePoint,
    /// The maximum allowable size of this item
    max_size: mod.CSSMaybePoint,
    /// The overflow style of the item
    overflow: css_types.OverflowPoint,
    /// The width of the item's scrollbars (if it has scrollbars)
    scrollbar_width: f32,
    /// The position style of the item
    position: css_types.Position,
    /// The final offset of this item
    inset: css_types.LengthPercentageAutoRect,
    /// The margin of this item
    margin: css_types.LengthPercentageAutoRect,
    /// The margin of this item
    padding: mod.CSSRect,
    /// The margin of this item
    border: mod.CSSRect,
    /// The sum of padding and border for this item
    padding_border_sum: mod.CSSPoint,
    /// The computed border box size of this item
    computed_size: mod.CSSPoint,
    /// The computed "static position" of this item. The static position is the position
    /// taking into account padding, border, margins, and scrollbar_gutters but not inset
    static_position: mod.CSSPoint,
    /// Whether margins can be collapsed through this item
    can_be_collapsed_through: bool,
};

/// Computes the layout of [`LayoutPartialTree`] according to the block layout algorithm
fn computeInner(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) mod.ComputeLayoutError!mod.LayoutResult {
    // Get style values
    const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .size);
    const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .min_size);
    const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .max_size);
    const css_margins = context.getStyleValue(css_types.LengthPercentageAutoRect, l_node_id, .margin);
    const css_padding = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .padding);
    const css_border = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .border_width);
    const css_position = context.getStyleValue(css_types.Position, l_node_id, .position);
    const css_display = context.getStyleValue(css_types.Display, l_node_id, .display);
    const css_overflow = context.getStyleValue(css_types.OverflowPoint, l_node_id, .overflow);
    const css_aspect_ratio = context.getStyleValue(?f32, l_node_id, .aspect_ratio);
    const css_scrollbar_width = context.getStyleValue(f32, l_node_id, .scrollbar_width);

    const parent_size = inputs.parent_size;

    // Resolve values
    const size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
        .x = mod.math.maybeResolve(css_size.x, parent_size.x),
        .y = mod.math.maybeResolve(css_size.y, parent_size.y),
    }, css_aspect_ratio);

    const min_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
        .x = mod.math.maybeResolve(css_min_size.x, parent_size.x),
        .y = mod.math.maybeResolve(css_min_size.y, parent_size.y),
    }, css_aspect_ratio);

    const max_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
        .x = mod.math.maybeResolve(css_max_size.x, parent_size.x),
        .y = mod.math.maybeResolve(css_max_size.y, parent_size.y),
    }, css_aspect_ratio);

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

    // Scrollbar gutters are reserved when the `overflow` property is set to `Overflow::Scroll`.
    // However, the axis are switched (transposed) because a node that scrolls vertically needs
    // *horizontal* space to be reserved for a scrollbar
    const scrollbar_gutter = mod.CSSRect{
        // TODO: make side configurable based on the `direction` property
        .top = 0,
        .left = 0,
        .right = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
        .bottom = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
    };

    const padding_border_x = padding.sumHorizontal() + border.sumHorizontal();
    const padding_border_y = padding.sumVertical() + border.sumVertical();
    const padding_border_size = mod.CSSPoint{ .x = padding_border_x, .y = padding_border_y };

    const content_box_inset = mod.CSSRect{
        .left = padding.left + border.left + scrollbar_gutter.left,
        .right = padding.right + border.right + scrollbar_gutter.right,
        .top = padding.top + border.top + scrollbar_gutter.top,
        .bottom = padding.bottom + border.bottom + scrollbar_gutter.bottom,
    };

    const container_content_box_size = mod.CSSMaybePoint{
        .x = mod.math.maybeSub(inputs.known_dimensions.x, content_box_inset.sumHorizontal()),
        .y = mod.math.maybeSub(inputs.known_dimensions.y, content_box_inset.sumVertical()),
    };

    // Determine margin collapsing behaviour
    const own_margins_collapse_with_children = mod.Line(bool){
        .start = inputs.vertical_margins_are_collapsible.start and
            !css_overflow.x.isScrollContainer() and
            !css_overflow.y.isScrollContainer() and
            css_position == .relative and
            padding.top == 0 and
            border.top == 0,
        .end = inputs.vertical_margins_are_collapsible.end and
            !css_overflow.x.isScrollContainer() and
            !css_overflow.y.isScrollContainer() and
            css_position == .relative and
            padding.bottom == 0 and
            border.bottom == 0 and
            size.y == null,
    };

    const has_styles_preventing_being_collapsed_through = css_display.outside != .block or
        css_overflow.x.isScrollContainer() or
        css_overflow.y.isScrollContainer() or
        css_position == .absolute or
        padding.top > 0 or
        padding.bottom > 0 or
        border.top > 0 or border.bottom > 0;

    // 1. Generate items
    var items = try generateItemList(context, l_node_id, container_content_box_size);
    defer items.deinit();

    // 2. Compute container width
    const container_outer_width: f32 = inputs.known_dimensions.x orelse blk: {
        const available_width = switch (inputs.available_space.x) {
            .definite => |w| mod.constants.AvailableSpace{ .definite = @max(0, w - content_box_inset.sumHorizontal()) },
            else => inputs.available_space.x,
        };
        const intrinsic_width = (try determineContentBasedContainerWidth(context, l_node_id, &items, available_width)) + content_box_inset.sumHorizontal();
        break :blk @max(mod.math.maybeClamp(intrinsic_width, min_size.x, max_size.x) orelse intrinsic_width, padding_border_size.x);
    };

    // Short-circuit if computing size and both dimensions known
    if (inputs.run_mode == .compute_size) if (inputs.known_dimensions.y) |container_outer_height| {
        // Resolve basic margins for compute_size mode
        const compute_size_margin = mod.CSSRect{
            .top = mod.math.maybeResolve(css_margins.top, inputs.parent_size.x) orelse 0,
            .right = mod.math.maybeResolve(css_margins.right, inputs.parent_size.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_margins.bottom, inputs.parent_size.x) orelse 0,
            .left = mod.math.maybeResolve(css_margins.left, inputs.parent_size.x) orelse 0,
        };

        return .{
            .size = mod.CSSPoint{
                .x = container_outer_width,
                .y = container_outer_height,
            },
            .resolved_margin = compute_size_margin,
            .resolved_padding = padding,
            .resolved_border = border,
            .scrollbar_size = .{
                .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
                .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
            },
        };
    };

    // 3. Perform final item layout and return content height
    const resolved_padding = mod.CSSRect{
        .top = mod.math.maybeResolve(css_padding.top, container_outer_width) orelse 0,
        .right = mod.math.maybeResolve(css_padding.right, container_outer_width) orelse 0,
        .bottom = mod.math.maybeResolve(css_padding.bottom, container_outer_width) orelse 0,
        .left = mod.math.maybeResolve(css_padding.left, container_outer_width) orelse 0,
    };

    const resolved_border = mod.CSSRect{
        .top = mod.math.maybeResolve(css_border.top, container_outer_width) orelse 0,
        .right = mod.math.maybeResolve(css_border.right, container_outer_width) orelse 0,
        .bottom = mod.math.maybeResolve(css_border.bottom, container_outer_width) orelse 0,
        .left = mod.math.maybeResolve(css_border.left, container_outer_width) orelse 0,
    };

    const resolved_content_box_inset = mod.CSSRect{
        .left = resolved_padding.left + resolved_border.left + scrollbar_gutter.left,
        .right = resolved_padding.right + resolved_border.right + scrollbar_gutter.right,
        .top = resolved_padding.top + resolved_border.top + scrollbar_gutter.top,
        .bottom = resolved_padding.bottom + resolved_border.bottom + scrollbar_gutter.bottom,
    };

    const inflow_content_size, const intrinsic_outer_height, const first_child_top_margin_set, const last_child_bottom_margin_set = try performFinalLayoutOnInFlowChildren(
        context,
        l_node_id,
        &items,
        container_outer_width,
        content_box_inset,
        resolved_content_box_inset,
        own_margins_collapse_with_children,
    );

    const container_outer_height = inputs.known_dimensions.y orelse blk: {
        const clamped = mod.math.maybeClamp(intrinsic_outer_height, min_size.y, max_size.y) orelse intrinsic_outer_height;
        break :blk @max(clamped, padding_border_size.y);
    };

    const final_outer_size = mod.CSSPoint{
        .x = container_outer_width,
        .y = container_outer_height,
    };

    if (inputs.run_mode == .compute_size) {
        // Resolve basic margins for compute_size mode
        const compute_size_margin = mod.CSSRect{
            .top = mod.math.maybeResolve(css_margins.top, inputs.parent_size.x) orelse 0,
            .right = mod.math.maybeResolve(css_margins.right, inputs.parent_size.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_margins.bottom, inputs.parent_size.x) orelse 0,
            .left = mod.math.maybeResolve(css_margins.left, inputs.parent_size.x) orelse 0,
        };

        return .{
            .size = final_outer_size,
            .resolved_margin = compute_size_margin,
            .resolved_padding = resolved_padding,
            .resolved_border = resolved_border,
            .scrollbar_size = .{
                .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
                .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
            },
        };
    }

    // 4. Layout absolutely positioned children
    const absolute_position_inset = mod.CSSRect{
        .left = resolved_border.left + scrollbar_gutter.left,
        .right = resolved_border.right + scrollbar_gutter.right,
        .top = resolved_border.top + scrollbar_gutter.top,
        .bottom = resolved_border.bottom + scrollbar_gutter.bottom,
    };

    const absolute_position_area = mod.CSSPoint{
        .x = final_outer_size.x - absolute_position_inset.sumHorizontal(),
        .y = final_outer_size.y - absolute_position_inset.sumVertical(),
    };

    const absolute_position_offset = mod.CSSPoint{
        .x = absolute_position_inset.left,
        .y = absolute_position_inset.top,
    };

    const absolute_content_size = try performAbsoluteLayoutOnAbsoluteChildren(context, items, absolute_position_area, absolute_position_offset);

    // 5. Perform hidden layout on hidden children
    const children = context.layout_tree.getChildren(l_node_id);
    for (children) |child_id| {
        const child_css_display = context.getStyleValue(css_types.Display, child_id, .display);
        if (child_css_display.outside == .none) {
            context.setBox(child_id, .{
                .size = mod.CSSPoint{ .x = 0, .y = 0 },
                .location = mod.CSSPoint{ .x = 0, .y = 0 },
                .margin = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .padding = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .border = mod.CSSRect{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .content_size = mod.CSSPoint{ .x = 0, .y = 0 },
                .scrollbar_size = mod.CSSPoint{ .x = 0, .y = 0 },
            }, null);
            _ = try mod.performChildLayout(
                context,
                child_id,
                mod.CSSMaybePoint.NULL,
                mod.CSSMaybePoint.NULL,
                mod.constants.AvailableSpace.MAX_CONTENT,
                .inherent_size,
                .{ .start = false, .end = false },
            );
        }
    }

    // 7. Determine whether this node can be collapsed through
    var all_in_flow_children_can_be_collapsed_through = true;
    for (items.items) |item| {
        all_in_flow_children_can_be_collapsed_through = item.position == .absolute or item.can_be_collapsed_through;
        if (!all_in_flow_children_can_be_collapsed_through) {
            break;
        }
    }
    const can_be_collapsed_through = !has_styles_preventing_being_collapsed_through and all_in_flow_children_can_be_collapsed_through;

    const content_size = mod.CSSPoint{
        .x = @max(inflow_content_size.x, absolute_content_size.x),
        .y = @max(inflow_content_size.y, absolute_content_size.y),
    };

    // Resolve margins for the container itself
    const container_resolved_margin = mod.CSSRect{
        .top = mod.math.maybeResolve(css_margins.top, inputs.parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_margins.right, inputs.parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_margins.bottom, inputs.parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_margins.left, inputs.parent_size.x) orelse 0,
    };

    // Compute scrollbar size
    const container_scrollbar_size = mod.CSSPoint{
        .x = if (css_overflow.y == .scroll) css_scrollbar_width else 0,
        .y = if (css_overflow.x == .scroll) css_scrollbar_width else 0,
    };

    return .{
        .size = final_outer_size,
        .content_size = content_size,
        .first_baselines = mod.CSSMaybePoint.NULL,
        .top_margin = if (own_margins_collapse_with_children.start)
            first_child_top_margin_set
        else
            mod.CollapsibleMarginSet.fromMargin(container_resolved_margin.top),

        .bottom_margin = if (own_margins_collapse_with_children.end)
            last_child_bottom_margin_set
        else
            mod.CollapsibleMarginSet.fromMargin(container_resolved_margin.bottom),

        .margins_can_collapse_through = can_be_collapsed_through,

        // Box model fields
        .resolved_margin = container_resolved_margin,
        .resolved_padding = resolved_padding,
        .resolved_border = resolved_border,
        .scrollbar_size = container_scrollbar_size,
    };
}

pub fn generateItemList(context: *LayoutContext, l_node_id: LayoutNode.Id, nodeInnerSize: mod.CSSMaybePoint) !std.ArrayList(BlockItem) {
    var items = std.ArrayList(BlockItem).init(context.allocator);
    const children = context.layout_tree.getChildren(l_node_id);

    for (children, 0..) |child_id, order| {
        // Get style values for this child
        const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .size);
        const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .min_size);
        const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .max_size);
        const css_padding = context.getStyleValue(css_types.LengthPercentageRect, child_id, .padding);
        const css_border = context.getStyleValue(css_types.LengthPercentageRect, child_id, .border_width);
        const css_margin = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .margin);
        const css_inset = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .inset);
        const css_position = context.getStyleValue(css_types.Position, child_id, .position);
        const css_overflow = context.getStyleValue(css_types.OverflowPoint, child_id, .overflow);
        const css_aspect_ratio = context.getStyleValue(?f32, child_id, .aspect_ratio);
        const css_scrollbar_width = context.getStyleValue(f32, child_id, .scrollbar_width);

        // Resolve size values with aspect ratio
        const size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_size.x, nodeInnerSize.x),
            .y = mod.math.maybeResolve(css_size.y, nodeInnerSize.y),
        }, css_aspect_ratio);

        const min_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_min_size.x, nodeInnerSize.x),
            .y = mod.math.maybeResolve(css_min_size.y, nodeInnerSize.y),
        }, css_aspect_ratio);

        const max_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_max_size.x, nodeInnerSize.x),
            .y = mod.math.maybeResolve(css_max_size.y, nodeInnerSize.y),
        }, css_aspect_ratio);

        // Resolve padding and border
        const padding = mod.CSSRect{
            .top = mod.math.maybeResolve(css_padding.top, nodeInnerSize.x) orelse 0,
            .right = mod.math.maybeResolve(css_padding.right, nodeInnerSize.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_padding.bottom, nodeInnerSize.x) orelse 0,
            .left = mod.math.maybeResolve(css_padding.left, nodeInnerSize.x) orelse 0,
        };

        const border = mod.CSSRect{
            .top = mod.math.maybeResolve(css_border.top, nodeInnerSize.x) orelse 0,
            .right = mod.math.maybeResolve(css_border.right, nodeInnerSize.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_border.bottom, nodeInnerSize.x) orelse 0,
            .left = mod.math.maybeResolve(css_border.left, nodeInnerSize.x) orelse 0,
        };

        const padding_border_sum = mod.CSSPoint{
            .x = padding.sumHorizontal() + border.sumHorizontal(),
            .y = padding.sumVertical() + border.sumVertical(),
        };

        try items.append(.{
            .node_id = child_id,
            .order = @intCast(order),
            .size = size,
            .min_size = min_size,
            .max_size = max_size,
            .overflow = css_overflow,
            .scrollbar_width = css_scrollbar_width,
            .position = css_position,
            .inset = css_inset,
            .margin = css_margin,
            .padding = padding,
            .border = border,
            .padding_border_sum = padding_border_sum,

            // Fields to be computed later (for now we initialise with dummy values)
            .computed_size = .{ .x = 0, .y = 0 },
            .static_position = .{ .x = 0, .y = 0 },
            .can_be_collapsed_through = false,
        });
    }
    return items;
}

pub fn determineContentBasedContainerWidth(
    context: *LayoutContext,
    l_node_id: LayoutNode.Id,
    items: *std.ArrayList(BlockItem),
    available_width: mod.constants.AvailableSpace,
) !f32 {
    _ = l_node_id; // autofix
    var max_child_width: f32 = 0;
    const available_space = mod.constants.AvailableSpacePoint{
        .x = available_width,
        .y = .min_content,
    };
    const available_space_width = switch (available_width) {
        .definite => available_width.definite,
        else => null,
    };

    for (items.items) |*item| {
        if (item.position == .absolute) {
            continue;
        }

        const known_dimensions = mod.CSSMaybePoint{
            .x = mod.math.maybeClamp(item.size.x, item.min_size.x, item.max_size.x),
            .y = mod.math.maybeClamp(item.size.y, item.min_size.y, item.max_size.y),
        };

        var width = known_dimensions.x orelse blk: {
            // Resolve margins for this item
            const item_margin = mod.CSSRect{
                .top = mod.math.maybeResolve(item.margin.top, available_space_width) orelse 0,
                .right = mod.math.maybeResolve(item.margin.right, available_space_width) orelse 0,
                .bottom = mod.math.maybeResolve(item.margin.bottom, available_space_width) orelse 0,
                .left = mod.math.maybeResolve(item.margin.left, available_space_width) orelse 0,
            };
            const item_x_margin_sum = item_margin.sumHorizontal();

            const size_and_baselines = try mod.performChildLayout(
                context,
                item.node_id,

                known_dimensions,
                .{ .x = null, .y = null },
                .{
                    .x = available_space.x.maybeSubtractIfDefinite(item_x_margin_sum),
                    .y = .min_content,
                },
                .inherent_size,
                .{ .start = true, .end = true },
            );
            //     .parent_size = mod.CSSMaybePoint{ .x = null, .y = null },
            //     .available_space = item_available_space,
            //     .sizing_mode = .inherent_size,
            //     .vertical_margins_are_collapsible = .{ .start = true, .end = true },
            //     .run_mode = .perform_layout,
            //     .axis = .both,
            //     .compute_mode = .layout,
            // },
            //     item.node_id,
            // );
            break :blk size_and_baselines.size.x + item_x_margin_sum;
        };
        width = @max(width, item.padding_border_sum.x);
        max_child_width = @max(max_child_width, width);
    }
    return max_child_width;
}

fn performFinalLayoutOnInFlowChildren(
    context: *LayoutContext,
    l_node_id: LayoutNode.Id,
    items: *std.ArrayList(BlockItem),
    container_outer_width: f32,
    content_box_inset: mod.CSSRect,
    resolved_content_box_inset: mod.CSSRect,
    own_margins_collapse_with_children: mod.Line(bool),
) !struct { mod.CSSPoint, f32, mod.CollapsibleMarginSet, mod.CollapsibleMarginSet } {
    _ = l_node_id; // autofix

    // Resolve container_inner_width for sizing child nodes using initial content_box_inset
    const container_inner_width: f32 = container_outer_width - content_box_inset.sumHorizontal();
    const parent_size = mod.CSSMaybePoint{
        .x = container_outer_width,
        .y = null,
    };
    const available_space = mod.constants.AvailableSpacePoint{
        .x = .{ .definite = container_inner_width },
        .y = .min_content,
    };
    var inflow_content_size = mod.CSSPoint{
        .x = 0,
        .y = 0,
    };
    var committed_offset = mod.CSSPoint{
        .x = resolved_content_box_inset.left,
        .y = resolved_content_box_inset.top,
    };
    var first_child_top_margin_set = mod.CollapsibleMarginSet.ZERO;
    var active_collapsible_margin_set = mod.CollapsibleMarginSet.ZERO;
    var is_collapsing_with_first_margin_set = true;

    for (items.items) |*item| {
        if (item.position == .absolute) {
            item.static_position = committed_offset;
            continue;
        }

        // Resolve margins for this item
        const item_margin = mod.CSSMaybeRect{
            .top = mod.math.maybeResolve(item.margin.top, container_outer_width),
            .right = mod.math.maybeResolve(item.margin.right, container_outer_width),
            .bottom = mod.math.maybeResolve(item.margin.bottom, container_outer_width),
            .left = mod.math.maybeResolve(item.margin.left, container_outer_width),
        };

        const item_non_auto_margin = mod.CSSRect{
            .top = item_margin.top orelse 0,
            .right = item_margin.right orelse 0,
            .bottom = item_margin.bottom orelse 0,
            .left = item_margin.left orelse 0,
        };
        const item_non_auto_x_margin_sum = item_non_auto_margin.sumHorizontal();

        const known_dimensions = mod.CSSMaybePoint{
            .x = mod.math.maybeClamp(
                item.size.x orelse (container_inner_width - item_non_auto_x_margin_sum),
                item.min_size.x,
                item.max_size.x,
            ),
            .y = mod.math.maybeClamp(item.size.y, item.min_size.y, item.max_size.y),
        };

        const item_available_space = mod.constants.AvailableSpacePoint{
            .x = switch (available_space.x) {
                .definite => |w| mod.constants.AvailableSpace{ .definite = @max(0, w - item_non_auto_x_margin_sum) },
                else => available_space.x,
            },
            .y = available_space.y,
        };

        const item_layout = try mod.performChildLayout(
            context,
            item.node_id,
            known_dimensions,
            parent_size,
            item_available_space,
            .inherent_size,
            .{ .start = true, .end = true },
        );

        const final_size = item_layout.size;
        const top_margin_value = item_margin.top orelse 0;
        const bottom_margin_value = item_margin.bottom orelse 0;
        const top_margin_set = item_layout.top_margin.collapseWithMargin(top_margin_value);
        const bottom_margin_set = item_layout.bottom_margin.collapseWithMargin(bottom_margin_value);

        // Expand auto margins to fill available space
        // Note: Vertical auto-margins for relatively positioned block items simply resolve to 0.
        // See: https://www.w3.org/TR/CSS21/visudet.html#abs-non-replaced-width
        const free_x_space = @max(0, container_inner_width - final_size.x - item_non_auto_x_margin_sum);
        const x_axis_auto_margin_size = blk: {
            const auto_margin_count: f32 = @floatFromInt(@as(u8, @intFromBool(item_margin.left == null)) + @as(u8, @intFromBool(item_margin.right == null)));
            if (auto_margin_count > 0) {
                break :blk free_x_space / auto_margin_count;
            } else {
                break :blk 0;
            }
        };

        const resolved_margin = mod.CSSRect{
            .left = item_margin.left orelse x_axis_auto_margin_size,
            .right = item_margin.right orelse x_axis_auto_margin_size,
            .top = top_margin_set.resolve(),
            .bottom = bottom_margin_set.resolve(),
        };

        // Resolve item inset
        const inset_top = mod.math.maybeResolve(item.inset.top, 0.0);
        const inset_bottom = mod.math.maybeResolve(item.inset.bottom, 0.0);
        const inset_left = mod.math.maybeResolve(item.inset.left, container_inner_width);
        const inset_right = mod.math.maybeResolve(item.inset.right, container_inner_width);

        const inset_offset = mod.CSSPoint{
            .x = inset_left orelse -(inset_right orelse 0),
            .y = inset_top orelse -(inset_bottom orelse 0),
        };

        const y_margin_offset = if (is_collapsing_with_first_margin_set and own_margins_collapse_with_children.start)
            0
        else
            active_collapsible_margin_set.collapseWithMargin(resolved_margin.top).resolve();

        item.computed_size = item_layout.size;
        item.can_be_collapsed_through = item_layout.margins_can_collapse_through;
        item.static_position = mod.CSSPoint{
            .x = resolved_content_box_inset.left,
            .y = committed_offset.y + active_collapsible_margin_set.resolve(),
        };

        const location = mod.CSSPoint{
            .x = resolved_content_box_inset.left + inset_offset.x + resolved_margin.left,
            .y = committed_offset.y + inset_offset.y + y_margin_offset,
        };

        const content_size = mod.CSSPoint{
            .x = container_inner_width,
            .y = item_layout.content_size.y,
        };

        context.setBox(item.node_id, .{
            .size = item_layout.size,
            .scrollbar_size = item_layout.scrollbar_size,
            .location = location,
            .padding = item_layout.resolved_padding,
            .border = item_layout.resolved_border,
            .content_size = content_size,
            .margin = resolved_margin,
        }, item_layout.line_boxes);

        inflow_content_size = mod.CSSPoint{
            .x = @max(inflow_content_size.x, mod.computeContentSizeContribution(
                location,
                final_size,
                item_layout.content_size,
                item.overflow,
            ).x),
            .y = @max(inflow_content_size.y, mod.computeContentSizeContribution(
                location,
                final_size,
                item_layout.content_size,
                item.overflow,
            ).y),
        };

        // Update first_child_top_margin_set
        if (is_collapsing_with_first_margin_set) {
            if (item.can_be_collapsed_through) {
                first_child_top_margin_set = first_child_top_margin_set
                    .collapseWithSet(top_margin_set)
                    .collapseWithSet(bottom_margin_set);
            } else {
                first_child_top_margin_set = first_child_top_margin_set.collapseWithSet(top_margin_set);
                is_collapsing_with_first_margin_set = false;
            }
        }

        // Update active_collapsible_margin_set
        if (item.can_be_collapsed_through) {
            active_collapsible_margin_set = active_collapsible_margin_set
                .collapseWithSet(top_margin_set)
                .collapseWithSet(bottom_margin_set);
        } else {
            committed_offset.y += item_layout.size.y + y_margin_offset;
            active_collapsible_margin_set = bottom_margin_set;
        }
    }

    const last_child_bottom_margin_set = active_collapsible_margin_set;
    const bottom_y_margin_offset = if (own_margins_collapse_with_children.end) 0 else last_child_bottom_margin_set.resolve();

    committed_offset.y += resolved_content_box_inset.bottom + bottom_y_margin_offset;

    const content_height = @max(0, committed_offset.y);
    return .{ inflow_content_size, content_height, first_child_top_margin_set, last_child_bottom_margin_set };
}

pub fn performAbsoluteLayoutOnAbsoluteChildren(
    context: *LayoutContext,
    items: std.ArrayList(BlockItem),
    area_size: mod.CSSPoint,
    area_offset: mod.CSSPoint,
) !mod.CSSPoint {
    const area_width = area_size.x;
    const area_height = area_size.y;
    var absolute_content_size = mod.CSSPoint{
        .x = 0,
        .y = 0,
    };

    for (items.items) |*item| {
        const child_id = item.node_id;

        // Get style values for this child
        const css_display = context.getStyleValue(css_types.Display, child_id, .display);
        const css_position = context.getStyleValue(css_types.Position, child_id, .position);
        if (css_display.outside == .none or css_position != .absolute) {
            continue;
        }

        const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .size);
        const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .min_size);
        const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .max_size);
        const css_margin = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .margin);
        const css_padding = context.getStyleValue(css_types.LengthPercentageRect, child_id, .padding);
        const css_border = context.getStyleValue(css_types.LengthPercentageRect, child_id, .border_width);
        const css_inset = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .inset);
        const css_aspect_ratio = context.getStyleValue(?f32, child_id, .aspect_ratio);

        // Resolve margin, padding, border
        const margin = mod.CSSMaybeRect{
            .top = mod.math.maybeResolve(css_margin.top, area_width),
            .right = mod.math.maybeResolve(css_margin.right, area_width),
            .bottom = mod.math.maybeResolve(css_margin.bottom, area_width),
            .left = mod.math.maybeResolve(css_margin.left, area_width),
        };

        const padding = mod.CSSRect{
            .top = mod.math.maybeResolve(css_padding.top, area_width) orelse 0,
            .right = mod.math.maybeResolve(css_padding.right, area_width) orelse 0,
            .bottom = mod.math.maybeResolve(css_padding.bottom, area_width) orelse 0,
            .left = mod.math.maybeResolve(css_padding.left, area_width) orelse 0,
        };

        const border = mod.CSSRect{
            .top = mod.math.maybeResolve(css_border.top, area_width) orelse 0,
            .right = mod.math.maybeResolve(css_border.right, area_width) orelse 0,
            .bottom = mod.math.maybeResolve(css_border.bottom, area_width) orelse 0,
            .left = mod.math.maybeResolve(css_border.left, area_width) orelse 0,
        };

        const padding_border_sum = mod.CSSPoint{
            .x = padding.sumHorizontal() + border.sumHorizontal(),
            .y = padding.sumVertical() + border.sumVertical(),
        };

        // Resolve inset
        const left = mod.math.maybeResolve(css_inset.left, area_width);
        const right = mod.math.maybeResolve(css_inset.right, area_width);
        const top = mod.math.maybeResolve(css_inset.top, area_height);
        const bottom = mod.math.maybeResolve(css_inset.bottom, area_height);

        // Compute known dimensions from min/max/inherent size styles
        const style_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_size.x, area_size.x),
            .y = mod.math.maybeResolve(css_size.y, area_size.y),
        }, css_aspect_ratio);

        var min_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_min_size.x, area_size.x),
            .y = mod.math.maybeResolve(css_min_size.y, area_size.y),
        }, css_aspect_ratio);

        // Ensure min_size is at least padding_border_sum
        min_size.x = @max(min_size.x orelse padding_border_sum.x, padding_border_sum.x);
        min_size.y = @max(min_size.y orelse padding_border_sum.y, padding_border_sum.y);

        const max_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_max_size.x, area_size.x),
            .y = mod.math.maybeResolve(css_max_size.y, area_size.y),
        }, css_aspect_ratio);

        var known_dimensions = mod.CSSMaybePoint{
            .x = mod.math.maybeClamp(style_size.x, min_size.x, max_size.x),
            .y = mod.math.maybeClamp(style_size.y, min_size.y, max_size.y),
        };

        // Fill in width from left/right and reapply aspect ratio if:
        //  - Width is not already known
        //  - Item has both left and right inset properties set
        if (known_dimensions.x == null) if (left) |_left| if (right) |_right| {
            var new_width_raw = area_width - _left - _right;
            if (margin.left) |ml| new_width_raw -= ml;
            if (margin.right) |mr| new_width_raw -= mr;
            known_dimensions.x = @max(new_width_raw, 0);
            known_dimensions = mod.math.maybeApplyAspectRatio(known_dimensions, css_aspect_ratio);
            known_dimensions.x = mod.math.maybeClamp(known_dimensions.x, min_size.x, max_size.x);
            known_dimensions.y = mod.math.maybeClamp(known_dimensions.y, min_size.y, max_size.y);
        };

        // Fill in height from top/bottom and reapply aspect ratio if:
        // - Height is not already known
        // - Item has both top and bottom inset properties set
        if (known_dimensions.y == null) if (top) |_top| if (bottom) |_bottom| {
            var new_height_raw = area_height - _top - _bottom;
            if (margin.top) |mt| new_height_raw -= mt;
            if (margin.bottom) |mb| new_height_raw -= mb;
            known_dimensions.y = @max(new_height_raw, 0);
            known_dimensions = mod.math.maybeApplyAspectRatio(known_dimensions, css_aspect_ratio);
            known_dimensions.x = mod.math.maybeClamp(known_dimensions.x, min_size.x, max_size.x);
            known_dimensions.y = mod.math.maybeClamp(known_dimensions.y, min_size.y, max_size.y);
        };

        const layout_output = try mod.performChildLayout(
            context,
            child_id,
            known_dimensions,
            area_size.intoOptional(),
            .{
                .x = .{ .definite = mod.math.maybeClamp(area_width, min_size.x, max_size.x) orelse area_width },
                .y = .{ .definite = mod.math.maybeClamp(area_height, min_size.y, max_size.y) orelse area_height },
            },
            .content_size,
            .{ .start = false, .end = false },
        );
        const measured_size = layout_output.size;

        const final_size = mod.CSSPoint{
            .x = mod.math.maybeClamp(known_dimensions.x orelse measured_size.x, min_size.x, max_size.x) orelse measured_size.x,
            .y = mod.math.maybeClamp(known_dimensions.y orelse measured_size.y, min_size.y, max_size.y) orelse measured_size.y,
        };

        const non_auto_margin = mod.CSSRect{
            .left = if (left != null) margin.left orelse 0 else 0,
            .right = if (right != null) margin.right orelse 0 else 0,
            .top = if (top != null) margin.top orelse 0 else 0,
            .bottom = if (bottom != null) margin.bottom orelse 0 else 0,
        };

        // Expand auto margins to fill available space
        // https://www.w3.org/TR/CSS21/visudet.html#abs-non-replaced-width

        const auto_margin = blk: {
            // Auto margins for absolutely positioned elements in block containers only resolve
            // if inset is set. Otherwise they resolve to 0.
            const absolute_auto_margin_space = mod.CSSPoint{
                .x = if (right) |r| area_size.x - r - (left orelse 0) else final_size.x,
                .y = if (bottom) |b| area_size.y - b - (top orelse 0) else final_size.y,
            };

            const free_space = mod.CSSPoint{
                .x = absolute_auto_margin_space.x - final_size.x - non_auto_margin.sumHorizontal(),
                .y = absolute_auto_margin_space.y - final_size.y - non_auto_margin.sumVertical(),
            };
            const auto_margin_size = mod.CSSPoint{

                // If all three of 'left', 'width', and 'right' are 'auto': First set any 'auto' values for 'margin-left' and 'margin-right' to 0.
                // Then, if the 'direction' property of the element establishing the static-position containing block is 'ltr' set 'left' to the
                // static position and apply rule number three below; otherwise, set 'right' to the static position and apply rule number one below.
                //
                // If none of the three is 'auto': If both 'margin-left' and 'margin-right' are 'auto', solve the equation under the extra constraint
                // that the two margins get equal values, unless this would make them negative, in which case when direction of the containing block is
                // 'ltr' ('rtl'), set 'margin-left' ('margin-right') to zero and solve for 'margin-right' ('margin-left'). If one of 'margin-left' or
                // 'margin-right' is 'auto', solve the equation for that value. If the values are over-constrained, ignore the value for 'left' (in case
                // the 'direction' property of the containing block is 'rtl') or 'right' (in case 'direction' is 'ltr') and solve for that value.
                .x = width: {
                    const auto_margin_count: f32 = @floatFromInt(@as(u8, @intFromBool(left == null)) + @as(u8, @intFromBool(right == null)));

                    if (auto_margin_count == 2 and (style_size.x == null or style_size.x.? >= free_space.x)) {
                        break :width 0;
                    } else if (auto_margin_count > 0) {
                        break :width free_space.x / auto_margin_count;
                    } else {
                        break :width 0;
                    }
                },

                .y = height: {
                    const auto_margin_count: f32 = @floatFromInt(@as(u8, @intFromBool(top == null)) + @as(u8, @intFromBool(bottom == null)));

                    if (auto_margin_count == 2 and (style_size.y == null or style_size.y.? >= free_space.y)) {
                        break :height 0;
                    } else if (auto_margin_count > 0) {
                        break :height free_space.y / auto_margin_count;
                    } else {
                        break :height 0;
                    }
                },
            };

            break :blk mod.CSSRect{
                .left = if (margin.left != null) 0 else auto_margin_size.x,
                .right = if (margin.right != null) 0 else auto_margin_size.x,
                .top = if (margin.top != null) 0 else auto_margin_size.y,
                .bottom = if (margin.bottom != null) 0 else auto_margin_size.y,
            };
        };

        const resolved_margin = mod.CSSRect{
            .left = margin.left orelse auto_margin.left,
            .right = margin.right orelse auto_margin.right,
            .top = margin.top orelse auto_margin.top,
            .bottom = margin.bottom orelse auto_margin.bottom,
        };

        const location = mod.CSSPoint{
            .x = width: {
                var width: ?f32 = if (left) |_left| _left + resolved_margin.left else null;
                width = if (right) |_right| area_size.x - final_size.x - _right - resolved_margin.right else width;
                break :width (if (width) |w| w + area_offset.x else null) orelse (item.static_position.x + resolved_margin.left);
            },
            .y = height: {
                var height: ?f32 = if (top) |_top| _top + resolved_margin.top else null;
                height = if (bottom) |_bottom| area_size.y - final_size.y - _bottom - resolved_margin.bottom else height;
                break :height (if (height) |h| h + area_offset.y else null) orelse (item.static_position.y + resolved_margin.top);
            },
        };

        context.setBox(child_id, .{
            .size = final_size,
            .content_size = layout_output.content_size,
            .scrollbar_size = layout_output.scrollbar_size,
            .location = location,
            .padding = layout_output.resolved_padding,
            .border = layout_output.resolved_border,
            .margin = resolved_margin,
        }, layout_output.line_boxes);

        const contribution = mod.computeContentSizeContribution(
            location,
            final_size,
            layout_output.content_size,
            item.overflow,
        );
        absolute_content_size = mod.CSSPoint{
            .x = @max(absolute_content_size.x, contribution.x),
            .y = @max(absolute_content_size.y, contribution.y),
        };
    }

    return absolute_content_size;
}

test "computeBlockLayout" {
    const allocator = std.testing.allocator;
    const doc_xml =
        \\<div>
        \\  <p>Hello, world!</p>
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
}

// test "margin auto centering" {
//     const allocator = std.testing.allocator;

//     // Test case: child with margin auto should be centered
//     const doc_xml = "<div style=\"width: 100px;\"><div style=\"width: 50px; margin-left: auto; margin-right: auto;\">Centered</div></div>";

//     var tree = try mod.docFromXml(allocator, doc_xml, .{});
//     defer tree.deinit();

//     var lt = try mod.LayoutTree.fromTree(allocator, &tree);
//     defer lt.deinit();

//     var context = LayoutContext{
//         .layout_tree = &lt,
//         .doc_tree = &tree,
//         .allocator = allocator,
//     };

//     try mod.computeLayout(
//         &context,
//         .{ .x = .{ .definite = 200 }, .y = .max_content },
//     );

//     // Print the layout to see the results

//     // Check the tree structure first
//     std.debug.print("\nAnalyzing tree structure:\n", .{});
//     for (0..context.layout_tree.node_count) |i| {
//         const node_id = @as(u32, @intCast(i));
//         const node = context.layout_tree.getNodePtr(node_id);
//         std.debug.print("Node #{d}: {s}, box: {any}\n", .{ node_id, @tagName(node.data), node.box });

//         // Check if this node has margin auto by looking at CSS
//         if (node.ref == .doc_node) {
//             const style = context.doc_tree.getStyle(node.ref.doc_node);
//             std.debug.print("  CSS margin: {any}\n", .{style.margin});
//         }
//     }

//     // Look for the node that should have margin auto
//     // This should be the block container with width 50px
//     var margin_auto_node_id: ?u32 = null;
//     for (0..context.layout_tree.node_count) |i| {
//         const node_id = @as(u32, @intCast(i));
//         const node = context.layout_tree.getNodePtr(node_id);
//         if (node.ref == .doc_node) {
//             const style = context.doc_tree.getStyle(node.ref.doc_node);
//             // Check if this has margin auto
//             if (style.margin.left == .auto and style.margin.right == .auto) {
//                 margin_auto_node_id = node_id;
//                 break;
//             }
//         }
//     }

//     if (margin_auto_node_id) |node_id| {
//         const margin_auto_box = context.layout_tree.getNodePtr(node_id).box;
//         std.debug.print("\nFound margin auto node #{d}: {any}\n", .{ node_id, margin_auto_box });
//         std.debug.print("Expected: margin left=25, margin right=25\n", .{});
//         std.debug.print("Actual: margin left={d}, margin right={d}\n", .{ margin_auto_box.margin.left, margin_auto_box.margin.right });

//         // Test the margin auto centering
//         try std.testing.expect(margin_auto_box.margin.left == 25.0);
//         try std.testing.expect(margin_auto_box.margin.right == 25.0);
//     } else {
//         std.debug.print("\nERROR: Could not find node with margin auto!\n", .{});
//         return error.TestFailed;
//     }
// }
