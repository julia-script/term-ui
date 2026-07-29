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
    const parent_size = inputs.parent_size;

    const vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible;
    _ = vertical_margins_are_collapsible; // autofix

    // Get style values
    const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .size);
    const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .min_size);
    const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .max_size);
    const css_padding = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .padding);
    const css_border = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .border_width);
    const css_aspect_ratio = context.getStyleValue(?f32, l_node_id, .aspect_ratio);

    const min_size = css_min_size.maybeResolve(parent_size).maybeApplyAspectRatio(css_aspect_ratio);
    const max_size = css_max_size.maybeResolve(parent_size).maybeApplyAspectRatio(css_aspect_ratio);
    const clamped_style_size = blk: {
        if (inputs.sizing_mode != .inherent_size) {
            break :blk mod.CSSMaybePoint.NULL;
        }
        var out = css_size.maybeResolve(parent_size);
        out = out.maybeApplyAspectRatio(css_aspect_ratio);
        out = out.maybeClamp(min_size, max_size);
        break :blk out;
    };

    var min_max_definite_size = mod.CSSMaybePoint.NULL;
    if (min_size.x) |min| if (max_size.x) |max| if (max <= min) {
        min_max_definite_size.x = min;
    };

    if (min_size.y) |min| if (max_size.y) |max| if (max <= min) {
        min_max_definite_size.y = min;
    };
    const padding = (mod.CSSRect{
        .top = (mod.math.maybeResolve(css_padding.top, parent_size.x) orelse 0),
        .right = (mod.math.maybeResolve(css_padding.right, parent_size.x) orelse 0),
        .bottom = (mod.math.maybeResolve(css_padding.bottom, parent_size.x) orelse 0),
        .left = (mod.math.maybeResolve(css_padding.left, parent_size.x) orelse 0),
    }).sumAxes();
    const border = (mod.CSSRect{
        .top = (mod.math.maybeResolve(css_border.top, parent_size.x) orelse 0),
        .right = (mod.math.maybeResolve(css_border.right, parent_size.x) orelse 0),
        .bottom = (mod.math.maybeResolve(css_border.bottom, parent_size.x) orelse 0),
        .left = (mod.math.maybeResolve(css_border.left, parent_size.x) orelse 0),
    }).sumAxes();

    const padding_and_border = padding.add(border);
    const known_dimensions = inputs.known_dimensions;
    // Block nodes automatically stretch fit their width to fit available space if available space is definite
    var styled_based_known_dimensions = known_dimensions
        .orElse(min_max_definite_size)
        .orElse(clamped_style_size)
        .maybeMax(padding_and_border);
    if (inputs.run_mode == .compute_size) {
        if (styled_based_known_dimensions.nullable()) |size| {
            return .{ .size = size };
        }
    }
    return try computeInner(context, .{
        .known_dimensions = styled_based_known_dimensions,
        .run_mode = inputs.run_mode,
        .sizing_mode = inputs.sizing_mode,
        .axis = inputs.axis,
        .parent_size = inputs.parent_size,
        .available_space = inputs.available_space,
        .vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible,
    }, l_node_id);
}

/// Inner flexbox computation function that implements the full flexbox algorithm
fn computeInner(context: *LayoutContext, inputs: ContainerContext, l_node_id: LayoutNode.Id) mod.ComputeLayoutError!mod.LayoutResult {

    // Compute algorithm constants
    var constants = computeConstants(
        context,
        l_node_id,
        inputs.known_dimensions,
        inputs.parent_size,
    );

    // 1. Generate anonymous flex items
    var flex_items = try flexItems.generateAnonymousFlexItems(context, l_node_id, &constants);
    defer flex_items.deinit();
    // 2. Determine the available main and cross space for the flex items
    const available_space = determineAvailableSpace(
        inputs.known_dimensions,
        inputs.available_space,
        &constants,
    );

    // 2. Determine flex base size
    try flexItems.determineFlexBaseSize(context, &constants, available_space, &flex_items);

    // 3. Collect flex items into flex lines
    var flex_lines = try flexLines.collectFlexLines(context.allocator, &constants, inputs.available_space, &flex_items);
    defer flex_lines.deinit(context.allocator);

    // If container size is undefined, determine the container's main size
    // and then re-resolve gaps based on newly determined size
    // const original_gap = constants.gap;

    const dir = flexItems.DirectionHelper.init(constants.dir);
    // const inner_main_size = inner_main_size: {
    if (dir.getMainOptional(constants.node_inner_size)) |inner_main_size| {
        const outer_main_size = inner_main_size +
            dir.getMain(constants.content_box_inset.sumAxes());
        constants.inner_container_size = dir.setMain(constants.inner_container_size, inner_main_size);
        constants.container_size = dir.setMain(constants.container_size, outer_main_size);
    } else {
        // const style = tree.getComputedStyle(node_id);
        // Sets constants.container_size and constants.outer_container_size
        try mainSize.determineContainerMainSize(context, available_space, &flex_lines, &constants);
        constants.node_inner_size = dir.setMainOptional(constants.node_inner_size, dir.getMain(constants.inner_container_size));
        constants.node_outer_size = dir.setMainOptional(constants.node_outer_size, dir.getMain(constants.container_size));

        // Re-resolve percentage gaps
        const inner_container_size = dir.getMain(constants.inner_container_size);
        const css_gap = context.getStyleValue(css_types.LengthPercentagePoint, l_node_id, .gap);
        const new_gap = dir.getMainByType(css_types.LengthPercentage, css_gap).maybeResolve(inner_container_size);
        constants.gap = dir.setMain(constants.gap, new_gap);
    }

    // 6. Resolve the flexible lengths of all flex items to find their target main sizes.
    for (flex_lines.items) |*line| {
        try mainSize.resolveFlexibleLengths(context, line, &constants, constants.gap);
    }

    // 6. Determine hypothetical cross sizes
    for (flex_lines.items) |*line| {
        try crossSize.determineHypotheticalCrossSize(context, line, &constants, available_space);
    }
    // Calculate child baselines. This function is internally smart and only computes child baselines
    // if they are necessary.
    try finalLayout.calculateChildrenBaselines(
        context,
        inputs.known_dimensions,
        available_space,
        &flex_lines,
        &constants,
    );

    // 8. Calculate the cross size of each flex line.
    try crossSize.calculateCrossSize(&flex_lines, inputs.known_dimensions, &constants);

    // 9. Handle 'align-content: stretch'.
    // handleAlignContentStretch(&mut flex_lines, known_dimensions, &constants);
    try crossSize.handleAlignContentStretch(&flex_lines, inputs.known_dimensions, &constants);
    // 10. Collapse visibility:collapse items. If any flex items have visibility: collapse,
    //     note the cross size of the line they're in as the item's strut size, and restart
    //     layout from the beginning.
    //
    //     In this second layout round, when collecting items into lines, treat the collapsed
    //     items as having zero main size. For the rest of the algorithm following that step,
    //     ignore the collapsed items entirely (as if they were display:none) except that after
    //     calculating the cross size of the lines, if any line's cross size is less than the
    //     largest strut size among all the collapsed items in the line, set its cross size to
    //     that strut size.
    //
    //     Skip this step in the second layout round.

    // TODO implement once (if ever) we support visibility:collapse

    // 11. Determine the used cross size of each flex item.
    try crossSize.determineUsedCrossSize(context, &flex_lines, &constants);

    // 11. Distribute any remaining free space (handles main axis auto margins)
    try alignment.distributeRemainingFreeSpace(&flex_lines, &constants);

    // 12. Resolve cross-axis auto margins
    try alignment.resolveCrossAxisAutoMargins(&flex_lines, &constants);
    // 15. Determine the flex container's used cross size.
    const total_line_cross_size = alignment.determineContainerCrossSize(&flex_lines, inputs.known_dimensions, &constants);

    // We have the container size.
    // If our caller does not care about performing layout we are done now.
    if (inputs.run_mode == .compute_size) {
        return .{
            .size = constants.container_size,
            .resolved_margin = constants.margin,
            .resolved_padding = constants.content_box_inset,
            .resolved_border = constants.border,
            .scrollbar_size = constants.scrollbar_gutter,
        };
    }

    // 16. Align all flex lines per align-content.
    alignment.alignFlexLinesPerAlignContent(&flex_lines, &constants, total_line_cross_size);
    // Do a final layout pass and gather the resulting layouts
    const inflow_content_size = try finalLayout.finalLayoutPass(context, &flex_lines, &constants);
    // Before returning we perform absolute layout on all absolutely positioned children
    // debug_log!("performAbsoluteLayoutOnAbsoluteChildren");
    // let absolute_content_size = performAbsoluteLayoutOnAbsoluteChildren(tree, node, &constants);
    const absolute_content_size = try finalLayout.performAbsoluteLayoutOnAbsoluteChildren(context, l_node_id, &constants);

    for (context.getChildren(l_node_id), 0..) |child_id, order| {
        _ = order; // autofix
        // const child_style = .getComputedStyle(child_id);
        const child_css_display = context.getStyleValue(css_types.Display, child_id, .display);
        if (child_css_display.outside == .none) {
            try context.setBox(child_id, .{
                .margin = .{
                    .top = 0,
                    .right = 0,
                    .bottom = 0,
                    .left = 0,
                },
                .size = .{ .x = 0, .y = 0 },
                .content_size = .{ .x = 0, .y = 0 },
                .scrollbar_size = .{ .x = 0, .y = 0 },
                .location = .{ .x = 0, .y = 0 },
                .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
                .border = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
            }, null);
            // FIXME: do we need to perform child layout for display none children?
            var layout = try mod.performChildLayout(
                context,
                child_id,
                .{ .x = null, .y = null },
                .{ .x = null, .y = null },
                .{ .x = .max_content, .y = .max_content },
                .inherent_size,
                .{ .start = false, .end = false },
            );
            defer layout.deinit();
        }
    }
    // 8.5. Flex Container Baselines: calculate the flex container's first baseline
    // See https://www.w3.org/TR/css-flexbox-1/#flex-baselines

    const first_vertical_baseline = blk: {
        if (flex_lines.items.len == 0) {
            break :blk null;
        }
        const first_line: types.FlexLine = flex_lines.items[0];
        if (first_line.items.len == 0) {
            break :blk null;
        }
        var child: types.FlexItem = first_line.items[0];

        for (flex_lines.items[0].items) |item| {
            if (constants.is_column or item.align_self == .baseline) {
                child = item;
                break;
            }
        }

        const offset_vertical = if (constants.is_row) child.offset_cross else child.offset_main;
        break :blk offset_vertical + child.baseline;
    };
    return .{
        .size = constants.container_size,
        .content_size = inflow_content_size.max(absolute_content_size),
        .first_baselines = .{ .x = null, .y = first_vertical_baseline },
        .top_margin = mod.CollapsibleMarginSet.ZERO,
        .bottom_margin = mod.CollapsibleMarginSet.ZERO,
        .margins_can_collapse_through = false,
        .resolved_margin = constants.margin,
        .resolved_padding = constants.content_box_inset,
        .resolved_border = constants.border,
        .scrollbar_size = constants.scrollbar_gutter,
    };
}

fn computeConstants(
    context: *LayoutContext,
    l_node_id: LayoutNode.Id,
    known_dimensions: mod.CSSMaybePoint,
    parent_size: mod.CSSMaybePoint,
) types.AlgoConstants {
    const css_flex_direction = context.getStyleValue(css_types.FlexDirection, l_node_id, .flex_direction);
    const css_flex_wrap = context.getStyleValue(css_types.FlexWrap, l_node_id, .flex_wrap);
    const css_align_items = context.getStyleValue(?css_types.AlignItems, l_node_id, .align_items);
    const css_align_content = context.getStyleValue(?css_types.AlignContent, l_node_id, .align_content);
    const css_justify_content = context.getStyleValue(?css_types.JustifyContent, l_node_id, .justify_content);
    const css_gap = context.getStyleValue(css_types.LengthPercentagePoint, l_node_id, .gap);
    const css_padding = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .padding);
    const css_border = context.getStyleValue(css_types.LengthPercentageRect, l_node_id, .border_width);
    const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .min_size);
    const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, l_node_id, .max_size);
    const css_overflow = context.getStyleValue(css_types.OverflowPoint, l_node_id, .overflow);
    const css_scrollbar_width = context.getStyleValue(f32, l_node_id, .scrollbar_width);
    const css_aspect_ratio = context.getStyleValue(?f32, l_node_id, .aspect_ratio);
    const css_margin = context.getStyleValue(css_types.LengthPercentageAutoRect, l_node_id, .margin);

    const dir = flexItems.DirectionHelper.init(css_flex_direction);
    const is_row = dir.is_row;
    const is_column = dir.is_column;
    const is_wrap = css_flex_wrap.isWrap();
    const is_wrap_reverse = css_flex_wrap == .wrap_reverse;

    const aspect_ratio = css_aspect_ratio;
    const parent_width = parent_size.x;
    _ = parent_width; // autofix
    const margin = mod.CSSRect{
        .top = mod.math.maybeResolve(css_margin.top, parent_size.x) orelse 0,
        .right = mod.math.maybeResolve(css_margin.right, parent_size.x) orelse 0,
        .bottom = mod.math.maybeResolve(css_margin.bottom, parent_size.x) orelse 0,
        .left = mod.math.maybeResolve(css_margin.left, parent_size.x) orelse 0,
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
    const align_items = css_align_items orelse .stretch;
    const align_content = css_align_content orelse .stretch;
    const justify_content = css_justify_content;

    // Scrollbar gutters are reserved when the `overflow` property is set to `Overflow::Scroll`.
    // However, the axis are switched (transposed) because a node that scrolls vertically needs
    // *horizontal* space to be reserved for a scrollbar
    const scrollbar_width = css_scrollbar_width;
    const overflow = css_overflow;
    const scrollbar_gutter: mod.CSSPoint = .{
        .x = if (overflow.y == .scroll) scrollbar_width else 0,
        .y = if (overflow.x == .scroll) scrollbar_width else 0,
    };

    var content_box_inset = padding.add(border);
    content_box_inset.right += scrollbar_gutter.x;
    content_box_inset.bottom += scrollbar_gutter.y;

    const node_outer_size = known_dimensions;
    const node_inner_size = node_outer_size.maybeSub(content_box_inset.sumAxes());

    const gap = css_gap.maybeResolve(node_inner_size.orZero());

    const container_size = mod.CSSPoint.ZERO;
    const inner_container_size = mod.CSSPoint.ZERO;

    return .{
        .dir = css_flex_direction,
        .is_row = is_row,
        .is_column = is_column,
        .is_wrap = is_wrap,
        .is_wrap_reverse = is_wrap_reverse,
        .min_size = css_min_size.maybeResolve(parent_size).maybeApplyAspectRatio(aspect_ratio),
        .max_size = css_max_size.maybeResolve(parent_size).maybeApplyAspectRatio(aspect_ratio),
        .margin = margin,
        .border = border,
        .gap = gap,
        .content_box_inset = content_box_inset,
        .scrollbar_gutter = scrollbar_gutter,
        .align_items = align_items,
        .align_content = align_content,
        .justify_content = justify_content,
        .node_outer_size = node_outer_size,
        .node_inner_size = node_inner_size,
        .container_size = container_size,
        .inner_container_size = inner_container_size,
    };
}

/// Determine the available main and cross space for the flex items.
///
/// # [9.2. Line Length Determination](https://www.w3.org/TR/css-flexbox-1/#line-sizing)
///
/// - [**Determine the available main and cross space for the flex items**](https://www.w3.org/TR/css-flexbox-1/#algo-available).
/// For each dimension, if that dimension of the flex container's content box is a definite size, use that;
/// if that dimension of the flex container is being sized under a min or max-content constraint, the available space in that dimension is that constraint;
/// otherwise, subtract the flex container's margin, border, and padding from the space available to the flex container in that dimension and use that value.
/// **This might result in an infinite value**.
pub fn determineAvailableSpace(
    known_dimensions: mod.CSSMaybePoint,
    outer_available_space: mod.constants.AvailableSpacePoint,
    constants: *types.AlgoConstants,
) mod.constants.AvailableSpacePoint {
    const width: mod.constants.AvailableSpace = blk: {
        if (known_dimensions.x) |node_width| {
            break :blk .{ .definite = node_width - constants.content_box_inset.sumHorizontal() };
        }
        if (outer_available_space.x.intoOption()) |available_space| {
            break :blk .{
                .definite = available_space -
                    constants.margin.sumHorizontal() -
                    constants.content_box_inset.sumHorizontal(),
            };
        }
        break :blk outer_available_space.x;
    };

    const height: mod.constants.AvailableSpace = blk: {
        if (known_dimensions.y) |node_height| {
            break :blk .{ .definite = node_height - constants.content_box_inset.sumVertical() };
        }
        if (outer_available_space.y.intoOption()) |available_space| {
            break :blk .{
                .definite = available_space -
                    constants.margin.sumVertical() -
                    constants.content_box_inset.sumVertical(),
            };
        }
        break :blk outer_available_space.y;
    };
    return .{ .x = width, .y = height };
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

    // Use the new pipeline approach
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .{ .definite = 100 }, .y = .max_content });
}
