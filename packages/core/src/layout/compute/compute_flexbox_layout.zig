const Tree = @import("../../tree/Tree.zig");
const std = @import("std");
const with = @import("../utils/comptime.zig").with;
pub const Style = @import("../../tree/Style.zig");
const styles = @import("../../styles/styles.zig");
const Node = @import("../../tree/Node.zig");
const Maybe = @import("../utils/Maybe.zig");
const ComputeConstants = @import("compute_constants.zig");
const Iter = @import("../utils/Iter.zig");
const AvailableSpace = ComputeConstants.AvailableSpace;
const AbsoluteAxis = ComputeConstants.AbsoluteAxis;
const LayoutInput = @import("compute_constants.zig").LayoutInput;
const LayoutOutput = @import("compute_constants.zig").LayoutOutput;
const Point = @import("../point.zig").Point;
const Rect = @import("../rect.zig").Rect;

const Line = @import("../line.zig");
const measureChildSize = @import("measure_child_size.zig").measureChildSize;
const computeChildLayout = @import("compute_child_layout.zig").computeChildLayout;
const performChildLayout = @import("perform_child_layout.zig").performChildLayout;
const computeAlignmentOffset = @import("compute_alignment_offset.zig").computeAlignmentOffset;
const computeContentSizeContribution = @import("compute_content_size_contribution.zig").computeContentSizeContribution;

const AlgoConstants = struct {
    /// The direction of the current segment being laid out
    dir: styles.flex_direction.FlexDirection,
    /// Is this segment a row
    is_row: bool,
    /// Is this segment a column
    is_column: bool,
    /// Is wrapping enabled (in either direction)
    is_wrap: bool,
    /// Is the wrap direction inverted
    is_wrap_reverse: bool,

    /// The item's min_size style
    min_size: Point(?f32),
    /// The item's max_size style
    max_size: Point(?f32),
    /// The margin of this section
    margin: Rect(f32),
    /// The border of this section
    border: Rect(f32),
    /// The space between the content box and the border box.
    /// This consists of padding + border + scrollbar_gutter.
    content_box_inset: Rect(f32),
    /// The size reserved for scrollbar gutters in each axis
    scrollbar_gutter: Point(f32),
    /// The gap of this section
    gap: Point(f32),
    /// The align_items property of this node
    align_items: Style.AlignItems,
    /// The align_content property of this node
    align_content: Style.AlignContent,
    /// The justify_content property of this node
    justify_content: ?Style.JustifyContent,

    /// The border-box size of the node being laid out (if known)
    node_outer_size: Point(?f32),
    /// The content-box size of the node being laid out (if known)
    node_inner_size: Point(?f32),

    /// The size of the virtual container containing the flex items.
    container_size: Point(f32),
    /// The size of the internal container
    inner_container_size: Point(f32),
};

pub fn computeFlexboxLayout(allocator: std.mem.Allocator, node_id: Node.NodeId, tree: *Tree, inputs: LayoutInput) !LayoutOutput {
    const style = tree.getComputedStyle(node_id);
    const parent_size = inputs.parent_size;
    const sizing_mode = inputs.sizing_mode;
    _ = sizing_mode; // autofix
    const run_mode = inputs.run_mode;
    const known_dimensions = inputs.known_dimensions;
    const available_space = inputs.available_space;
    _ = available_space; // autofix
    const vertical_margins_are_collapsible = inputs.vertical_margins_are_collapsible;
    _ = vertical_margins_are_collapsible; // autofix

    const aspect_ratio = style.aspect_ratio;
    const min_size = style.min_size.maybeResolve(parent_size).maybeApplyAspectRatio(aspect_ratio);
    const max_size = style.max_size.maybeResolve(parent_size).maybeApplyAspectRatio(aspect_ratio);
    const clamped_style_size = blk: {
        if (inputs.sizing_mode != .inherent_size) {
            break :blk Point(?f32).NULL;
        }
        var out = style.size.maybeResolve(parent_size);
        out = out.maybeApplyAspectRatio(aspect_ratio);
        out = out.maybeClamp(min_size, max_size);
        break :blk out;
    };

    // If both min and max in a given axis are set and max <= min then this determines the size in that axis
    // const min_max_definite_size = Point(?f32){
    //     .x = blk: {
    //         const min = min_size.x orelse break :blk null;
    //         const max = max_size.x orelse break :blk null;
    //         if (max <= min) {
    //             break :blk min;
    //         }
    //         break :blk null;
    //     },
    //     .y = blk: {
    //         const min = min_size.y orelse break :blk null;
    //         const max = max_size.y orelse break :blk null;
    //         if (max <= min) {
    //             break :blk min;
    //         }
    //         break :blk null;
    //     },
    // };
    //
    var min_max_definite_size = Point(?f32).NULL;
    if (min_size.x) |min| if (max_size.x) |max| if (max <= min) {
        min_max_definite_size.x = min;
    };

    if (min_size.y) |min| if (max_size.y) |max| if (max <= min) {
        min_max_definite_size.y = min;
    };

    const padding = style.padding.maybeResolve(parent_size.x).orZero().sumAxes();
    const border = style.border.maybeResolve(parent_size.x).orZero().sumAxes();
    const padding_and_border = padding.add(border);

    // Block nodes automatically stretch fit their width to fit available space if available space is definite
    var styled_based_known_dimensions = known_dimensions
        .orElse(min_max_definite_size)
        .orElse(clamped_style_size)
        .maybeMax(padding_and_border);

    if (run_mode == .compute_size) {
        if (styled_based_known_dimensions.nullable()) |size| {
            return .{ .size = size };
        }
    }

    return computePreliminary(
        allocator,
        tree,
        node_id,
        with(inputs, .{
            .known_dimensions = styled_based_known_dimensions,
        }),
    );
}
pub fn computePreliminary(allocator: std.mem.Allocator, tree: *Tree, node_id: Node.NodeId, inputs: LayoutInput) !LayoutOutput {
    const known_dimensions = inputs.known_dimensions;
    // Define some general constants we will need for the remainder of the algorithm.
    var constants = computeConstants(tree, node_id, known_dimensions, inputs.parent_size);
    // 9. Flex Layout Algorithm
    // 9.1. Initial Setup

    // 1. Generate anonymous flex items as described in §4 Flex Items.
    // let mut flex_items = generateAnonymousFlexItems(tree, node, &constants);
    var flex_items = try generateAnonymousFlexItems(allocator, tree, node_id, &constants);
    defer flex_items.deinit();

    // 9.2. Line Length Determination

    // 2. Determine the available main and cross space for the flex items
    // debug_log!("determineAvailableSpace");
    const available_space = determineAvailableSpace(
        inputs.known_dimensions,
        inputs.available_space,
        &constants,
    );
    // 3. Determine the flex base size and hypothetical main size of each item.

    try determineFlexBaseSize(allocator, tree, &constants, available_space, &flex_items);

    // 4. Determine the main size of the flex container
    // This has already been done as part of computeConstants. The inner size is exposed as constants.node_inner_size.

    // 9.3. Main Size Determination

    // 5. Collect flex items into flex lines.

    // let mut flex_lines = collectFlexLines(&constants, available_space, &mut flex_items);
    var flex_lines = try collectFlexLines(allocator, &constants, available_space, &flex_items);
    defer flex_lines.deinit();

    // If container size is undefined, determine the container's main size
    // and then re-resolve gaps based on newly determined size
    const original_gap = constants.gap;

    const dir = constants.dir;
    // const inner_main_size = inner_main_size: {
    if (dir.getMain(constants.node_inner_size)) |inner_main_size| {
        const outer_main_size = inner_main_size +
            dir.getMain(constants.content_box_inset.sumAxes());
        constants.inner_container_size = dir.setMain(constants.inner_container_size, inner_main_size);
        constants.container_size = dir.setMain(constants.container_size, outer_main_size);
    } else {
        const style = tree.getComputedStyle(node_id);
        // Sets constants.container_size and constants.outer_container_size
        try determineContainerMainSize(allocator, tree, available_space, &flex_lines, &constants);
        constants.node_inner_size = dir.setMain(constants.node_inner_size, dir.getMain(constants.inner_container_size));
        constants.node_outer_size = dir.setMain(constants.node_outer_size, dir.getMain(constants.container_size));

        // Re-resolve percentage gaps
        const inner_container_size = dir.getMain(constants.inner_container_size);
        const new_gap = dir.getMain(style.gap).maybeResolve(inner_container_size);
        constants.gap = dir.setMain(constants.gap, new_gap);
    }
    // 6. Resolve the flexible lengths of all flex items to find their target main sizes.
    for (flex_lines.items) |*line| {
        try resolveFlexibleLengths(allocator, line, &constants, original_gap);
    }

    // 9.4. Cross Size Determination

    // 7. Determine the hypothetical cross size of each item.
    for (flex_lines.items) |*line| {
        try determineHypotheticalCrossSize(allocator, tree, line, &constants, available_space);
    }

    // Calculate child baselines. This function is internally smart and only computes child baselines
    // if they are necessary.
    try calculateChildrenBaseLines(
        allocator,
        tree,
        known_dimensions,
        available_space,
        &flex_lines,
        &constants,
    );

    // 8. Calculate the cross size of each flex line.
    try calculateCrossSize(&flex_lines, known_dimensions, &constants);
    //
    // 9. Handle 'align-content: stretch'.
    // handleAlignContentStretch(&mut flex_lines, known_dimensions, &constants);
    try handleAlignContentStretch(&flex_lines, known_dimensions, &constants);
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
    try determineUsedCrossSize(tree, &flex_lines, &constants);
    // 9.5. Main-Axis Alignment

    // 12. Distribute any remaining free space.
    try distributeRemainingFreeSpace(&flex_lines, &constants);

    // 9.6. Cross-Axis Alignment

    // 13. Resolve cross-axis auto margins (also includes 14).
    try resolveCrossAxisAutoMargis(&flex_lines, &constants);
    // 15. Determine the flex container's used cross size.
    const total_line_cross_size = determineContainerCrossSize(&flex_lines, known_dimensions, &constants);
    // We have the container size.
    // If our caller does not care about performing layout we are done now.
    if (inputs.run_mode == .compute_size) {
        //     return LayoutOutput::from_outer_size(constants.container_size);
        return .{ .size = constants.container_size };
    }
    // 16. Align all flex lines per align-content.
    alignFlexLinesPerAlignContent(&flex_lines, &constants, total_line_cross_size);
    // Do a final layout pass and gather the resulting layouts
    const inflow_content_size = try finalLayoutPass(allocator, tree, &flex_lines, &constants);
    // Before returning we perform absolute layout on all absolutely positioned children
    // debug_log!("performAbsoluteLayoutOnAbsoluteChildren");
    // let absolute_content_size = performAbsoluteLayoutOnAbsoluteChildren(tree, node, &constants);
    const absolute_content_size = try performAbsoluteLayoutOnAbsoluteChildren(allocator, tree, node_id, &constants);

    for (tree.getChildren(node_id).items, 0..) |child_id, order| {
        const child_style = tree.getComputedStyle(child_id);
        if (child_style.display.outside == .none) {
            tree.setUnroundedLayout(child_id, .{ .order = @as(u32, @intCast(order)), .margin = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 } });
            _ = try performChildLayout(
                allocator,
                child_id,
                tree,
                .{ .x = null, .y = null },
                .{ .x = null, .y = null },
                .{ .x = .max_content, .y = .max_content },
                .inherent_size,
                Line.FALSE,
            );
        }
    }
    // 8.5. Flex Container Baselines: calculate the flex container's first baseline
    // See https://www.w3.org/TR/css-flexbox-1/#flex-baselines

    const first_vertical_baseline = blk: {
        if (flex_lines.items.len == 0) {
            break :blk null;
        }
        const first_line: FlexLine = flex_lines.items[0];
        if (first_line.items.len == 0) {
            break :blk null;
        }
        var child: FlexItem = first_line.items[0];

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
    known_dimensions: Point(?f32),
    outer_available_space: Point(AvailableSpace),
    constants: *AlgoConstants,
) Point(AvailableSpace) {
    const width: AvailableSpace = blk: {
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

    const height: AvailableSpace = blk: {
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

pub const FlexItem = struct {
    /// The identifier for the associated node
    node_id: Node.NodeId,

    /// The order of the node relative to its siblings
    order: u32,

    /// The base size of this item
    size: Point(?f32),
    /// The minimum allowable size of this item
    min_size: Point(?f32),
    /// The maximum allowable size of this item
    max_size: Point(?f32),
    /// The cross-alignment of this item
    align_self: Style.AlignSelf,

    /// The overflow style of the item
    overflow: Point(styles.overflow.Overflow),
    /// The width of the scrollbars (if it has any)
    scrollbar_width: f32,
    /// The flex shrink style of the item
    flex_shrink: f32,
    /// The flex grow style of the item
    flex_grow: f32,

    /// The minimum size of the item. This differs from min_size above because it also
    /// takes into account content based automatic minimum sizes
    resolved_minimum_main_size: f32,

    /// The final offset of this item
    inset: Rect(?f32),
    /// The margin of this item
    margin: Rect(f32),
    /// Whether each margin is an auto margin or not
    margin_is_auto: Rect(bool),
    /// The padding of this item
    padding: Rect(f32),
    /// The border of this item
    border: Rect(f32),

    /// The default size of this item
    flex_basis: f32,
    /// The default size of this item, minus padding and border
    inner_flex_basis: f32,
    /// The amount by which this item has deviated from its target size
    violation: f32,
    /// Is the size of this item locked
    frozen: bool,

    /// Either the max- or min- content flex fraction
    content_flex_fraction: f32,

    /// The proposed inner size of this item
    hypothetical_inner_size: Point(f32),
    /// The proposed outer size of this item
    hypothetical_outer_size: Point(f32),
    /// The size that this item wants to be
    target_size: Point(f32),
    /// The size that this item wants to be, plus any padding and border
    outer_target_size: Point(f32),

    /// The position of the bottom edge of this item
    baseline: f32,

    /// A temporary value for the main offset
    offset_main: f32,
    /// A temporary value for the cross offset
    offset_cross: f32,
};

/// Generate anonymous flex items.
///
/// # [9.1. Initial Setup](https://www.w3.org/TR/css-flexbox-1/#box-manip)
///
/// - [**Generate anonymous flex items**](https://www.w3.org/TR/css-flexbox-1/#algo-anon-box) as described in [§4 Flex Items](https://www.w3.org/TR/css-flexbox-1/#flex-items).
pub fn generateAnonymousFlexItems(gpa: std.mem.Allocator, tree: *Tree, node_id: Node.NodeId, constants: *AlgoConstants) !std.ArrayList(FlexItem) {
    var flex_items = std.ArrayList(FlexItem).init(gpa);
    for (tree.getChildren(node_id).items, 0..) |child_id, index| {
        const style = tree.getComputedStyle(child_id);
        const display = style.display;
        if (style.position == .absolute or display.outside == .none) {
            continue;
        }
        const aspect_ratio = style.aspect_ratio;

        try flex_items.append(.{
            .node_id = child_id,
            .order = @intCast(index),
            .size = style
                .size
                .maybeResolve(constants.node_inner_size)
                .maybeApplyAspectRatio(aspect_ratio),
            .min_size = style
                .min_size
                .maybeResolve(constants.node_inner_size)
                .maybeApplyAspectRatio(aspect_ratio),
            .max_size = style
                .max_size
                .maybeResolve(constants.node_inner_size)
                .maybeApplyAspectRatio(aspect_ratio),
            .inset = .{
                .top = style.margin.top.maybeResolve(constants.node_inner_size.y),
                .bottom = style.margin.bottom.maybeResolve(constants.node_inner_size.y),
                .left = style.margin.left.maybeResolve(constants.node_inner_size.x),
                .right = style.margin.right.maybeResolve(constants.node_inner_size.x),
            },
            .margin = style.margin.maybeResolve(constants.node_inner_size.width()).orZero(),
            .margin_is_auto = .{
                .top = style.margin.top == .auto,
                .bottom = style.margin.bottom == .auto,
                .left = style.margin.left == .auto,
                .right = style.margin.right == .auto,
            },
            .padding = style.padding.maybeResolve(constants.node_inner_size.width()).orZero(),
            .border = style.border.maybeResolve(constants.node_inner_size.width()).orZero(),
            .align_self = style.align_self orelse constants.align_items,
            .overflow = style.overflow,
            .scrollbar_width = style.scrollbar_width,
            .flex_grow = style.flex_grow,
            .flex_shrink = style.flex_shrink,
            .flex_basis = 0,
            .inner_flex_basis = 0,
            .violation = 0,
            .frozen = false,

            .resolved_minimum_main_size = 0,
            .hypothetical_inner_size = Point(f32).ZERO,
            .hypothetical_outer_size = Point(f32).ZERO,
            .target_size = Point(f32).ZERO,
            .outer_target_size = Point(f32).ZERO,
            .content_flex_fraction = 0,
            .baseline = 0,
            .offset_main = 0,
            .offset_cross = 0,
        });
    }

    return flex_items;
}

/// Determine the flex base size and hypothetical main size of each item.
///
/// # [9.2. Line Length Determination](https://www.w3.org/TR/css-flexbox-1/#line-sizing)
///
/// - [**Determine the flex base size and hypothetical main size of each item:**](https://www.w3.org/TR/css-flexbox-1/#algo-main-item)
///
///     - A. If the item has a definite used flex basis, that's the flex base size.
///
///     - B. If the flex item has ...
///
///         - an intrinsic aspect ratio,
///         - a used flex basis of content, and
///         - a definite cross size,
///
///     then the flex base size is calculated from its inner cross size and the flex item's intrinsic aspect ratio.
///
///     - C. If the used flex basis is content or depends on its available space, and the flex container is being sized under a min-content
///         or max-content constraint (e.g. when performing automatic table layout \[CSS21\]), size the item under that constraint.
///         The flex base size is the item's resulting main size.
///
///     - E. Otherwise, size the item into the available space using its used flex basis in place of its main size, treating a value of content as max-content.
///         If a cross size is needed to determine the main size (e.g. when the flex item's main size is in its block axis) and the flex item's cross size is auto and not definite,
///         in this calculation use fit-content as the flex item's cross size. The flex base size is the item's resulting main size.
///
///     When determining the flex base size, the item's min and max main sizes are ignored (no clamping occurs).
///     Furthermore, the sizing calculations that floor the content box size at zero when applying box-sizing are also ignored.
///     (For example, an item with a specified size of zero, positive padding, and box-sizing: border-box will have an outer flex base size of zero—and hence a negative inner flex base size.)
pub fn determineFlexBaseSize(
    allocator: std.mem.Allocator,
    tree: *Tree,
    constants: *AlgoConstants,
    available_space: Point(AvailableSpace),
    flex_items: *std.ArrayList(FlexItem),
) !void {
    const dir = constants.dir;

    for (flex_items.items) |*child| {
        const child_style = tree.getComputedStyle(child.node_id);
        // Parent size for child sizing
        const cross_axis_parent_size: ?f32 = dir.getCross(constants.node_inner_size);
        const child_parent_size: Point(?f32) = dir.pointFromCross(cross_axis_parent_size);

        // Available space for child sizing
        const cross_axis_margin_sum: f32 = dir.sumCrossAxis(constants.margin);
        const child_min_cross: ?f32 = blk: {
            if (dir.getCross(child.min_size)) |a| {
                break :blk a + cross_axis_margin_sum;
            }
            break :blk null;
        };
        const child_max_cross: ?f32 = blk: {
            if (dir.getCross(child.max_size)) |a| {
                break :blk a + cross_axis_margin_sum;
            }
            break :blk null;
        };
        const cross_axis_available_space: AvailableSpace = blk: {
            const v: AvailableSpace = dir.getCross(available_space);
            switch (v) {
                .definite => |d| break :blk .{
                    .definite = Maybe.clamp(
                        cross_axis_parent_size orelse d,
                        child_min_cross,
                        child_max_cross,
                    ),
                },
                else => break :blk v,
            }
        };
        // Known dimensions for child sizing
        const child_known_dimensions: Point(?f32) = blk: {
            const ckd = dir.setMain(child.size, null);
            if (child.align_self == .stretch and dir.getCross(child.size) == null) {
                break :blk dir.setCross(
                    ckd,
                    Maybe.sub(
                        cross_axis_available_space.intoOption(),
                        dir.sumCrossAxis(constants.margin),
                    ),
                );
            }

            break :blk ckd;
        };
        child.flex_basis = flex_basis: {
            // A. If the item has a definite used flex basis, that's the flex base size.

            // B. If the flex item has an intrinsic aspect ratio,
            //    a used flex basis of content, and a definite cross size,
            //    then the flex base size is calculated from its inner
            //    cross size and the flex item's intrinsic aspect ratio.

            // Note: `child.size` has already been resolved against aspect_ratio in generateAnonymousFlexItems
            // So B will just work here by using main_size without special handling for aspect_ratio

            const flex_basis: ?f32 = child_style.flex_basis.maybeResolve(dir.getMain(constants.node_inner_size));
            const main_size: ?f32 = dir.getMain(child.size);
            if (flex_basis orelse main_size) |value| {
                break :flex_basis value;
            }

            // C. If the used flex basis is content or depends on its available space,
            //    and the flex container is being sized under a min-content or max-content
            //    constraint (e.g. when performing automatic table layout [CSS21]),
            //    size the item under that constraint. The flex base size is the item's
            //    resulting main size.

            // This is covered by the implementation of E below, which passes the available_space constraint
            // through to the child size computation. It may need a separate implementation if/when D is implemented.

            // D. Otherwise, if the used flex basis is content or depends on its
            //    available space, the available main size is infinite, and the flex item's
            //    inline axis is parallel to the main axis, lay the item out using the rules
            //    for a box in an orthogonal flow [CSS3-WRITING-MODES]. The flex base size
            //    is the item's max-content main size.

            // TODO if/when vertical writing modes are supported

            // E. Otherwise, size the item into the available space using its used flex basis
            //    in place of its main size, treating a value of content as max-content.
            //    If a cross size is needed to determine the main size (e.g. when the
            //    flex item's main size is in its block axis) and the flex item's cross size
            //    is auto and not definite, in this calculation use fit-content as the
            //    flex item's cross size. The flex base size is the item's resulting main size.

            const child_available_space = blk: {
                var space = AvailableSpace.MAX_CONTENT;
                if (dir.getMain(available_space) == .min_content) {
                    space = dir.setMain(space, .min_content);
                }
                break :blk dir.setCross(space, cross_axis_available_space);
            };

            break :flex_basis try measureChildSize(
                allocator,
                child.node_id,
                tree,
                child_known_dimensions,
                child_parent_size,
                child_available_space,
                .content_size,
                AbsoluteAxis.fromFlexDirection(dir),
                Line.FALSE,
            );
        };

        // Floor flex-basis by the padding_border_sum (floors inner_flex_basis at zero)
        // This seems to be in violation of the spec which explicitly states that the content box should not be floored at zero
        // (like it usually is) when calculating the flex-basis. But including this matches both Chrome and Firefox's behaviour.
        //
        // TODO: resolve spec violation
        // Spec: https://www.w3.org/TR/css-flexbox-1/#intrinsic-item-contributions
        // Spec: https://www.w3.org/TR/css-flexbox-1/#change-2016-max-contribution
        const padding_border_sum: f32 = dir.sumMainAxis(child.padding) + dir.sumMainAxis(child.border);
        child.flex_basis = @max(child.flex_basis, padding_border_sum);

        // The hypothetical main size is the item's flex base size clamped according to its
        // used min and max main sizes (and flooring the content box size at zero).

        child.inner_flex_basis = child.flex_basis - dir.sumMainAxis(child.padding) - dir.sumMainAxis(child.border);

        const padding_border_axes_sums = (child.padding.add(child.border)).sumAxes();
        const hypothetical_inner_min_main: ?f32 = Maybe.max(dir.getMain(child.min_size), dir.getMain(padding_border_axes_sums));
        const hypothetical_inner_size: f32 = Maybe.clamp(child.flex_basis, hypothetical_inner_min_main, dir.getMain(child.max_size));
        const hypothetical_outer_size: f32 = hypothetical_inner_size + dir.sumMainAxis(child.margin);

        child.hypothetical_inner_size = dir.setMain(child.hypothetical_inner_size, hypothetical_inner_size);
        child.hypothetical_outer_size = dir.setMain(child.hypothetical_outer_size, hypothetical_outer_size);

        // Note that it is important that the `parent_size` parameter in the main axis is not set for this
        // function call as it used for resolving percentages, and percentage size in an axis should not contribute
        // to a min-content contribution in that same axis. However the `parent_size` and `available_space` *should*
        // be set to their usual values in the cross axis so that wrapping content can wrap correctly.
        //
        // See https://drafts.csswg.org/css-sizing-3/#min-percentage-contribution
        const style_min_main_size: ?f32 = dir.getMain(child.min_size) orelse dir.getMain(.{
            .x = child.overflow.x.maybeIntoAutomaticMinSize(),
            .y = child.overflow.y.maybeIntoAutomaticMinSize(),
        });

        child.resolved_minimum_main_size = style_min_main_size orelse resolved: {
            const min_content_main_size: f32 = blk: {
                const child_available_space = dir.setCross(
                    AvailableSpace.MIN_CONTENT,
                    cross_axis_available_space,
                );

                break :blk try measureChildSize(
                    allocator,
                    child.node_id,
                    tree,
                    child_known_dimensions,
                    child_parent_size,
                    child_available_space,
                    .content_size,
                    AbsoluteAxis.fromFlexDirection(dir),
                    Line.FALSE,
                );
            };

            // 4.5. Automatic Minimum Size of Flex Items
            // https://www.w3.org/TR/css-flexbox-1/#min-size-auto
            var clamped_min_content_size: f32 = Maybe.min(
                min_content_main_size,
                dir.getMain(child.size),
            );

            clamped_min_content_size = Maybe.min(
                clamped_min_content_size,
                dir.getMain(child.max_size),
            );

            break :resolved Maybe.max(
                clamped_min_content_size,
                dir.getMain(padding_border_axes_sums),
            );
        };
    }
}

pub fn computeConstants(tree: *Tree, node_id: Node.NodeId, known_dimensions: Point(?f32), parent_size: Point(?f32)) AlgoConstants {
    const style = tree.getComputedStyle(node_id);
    const dir = style.flex_direction;
    const is_row = dir.isRow();
    const is_column = dir.isColumn();
    const is_wrap = style.flex_wrap.isWrap();
    const is_wrap_reverse = style.flex_wrap == .wrap_reverse;

    const aspect_ratio = style.aspect_ratio;
    const parent_width = parent_size.width();
    const margin = style.margin.maybeResolve(parent_width).orZero();
    const padding = style.padding.maybeResolve(parent_width).orZero();
    const border = style.border.maybeResolve(parent_width).orZero();
    const align_items = style.align_items orelse .stretch;
    const align_content = style.align_content orelse .stretch;
    const justify_content = style.justify_content;

    // Scrollbar gutters are reserved when the `overflow` property is set to `Overflow::Scroll`.
    // However, the axis are switched (transposed) because a node that scrolls vertically needs
    // *horizontal* space to be reserved for a scrollbar
    const scrollbar_width = style.scrollbar_width;
    const overflow = style.overflow;
    const scrollbar_gutter: Point(f32) = .{
        .x = if (overflow.y == .scroll) scrollbar_width else 0,
        .y = if (overflow.x == .scroll) scrollbar_width else 0,
    };

    var content_box_inset = padding.add(border);
    content_box_inset.right += scrollbar_gutter.x;
    content_box_inset.bottom += scrollbar_gutter.y;

    const node_outer_size = known_dimensions;
    const node_inner_size = node_outer_size.maybeSub(content_box_inset.sumAxes());
    const gap = style.gap.maybeResolve(node_inner_size.orZero());

    const container_size = Point(f32).ZERO;
    const inner_container_size = Point(f32).ZERO;

    return .{
        .dir = dir,
        .is_row = is_row,
        .is_column = is_column,
        .is_wrap = is_wrap,
        .is_wrap_reverse = is_wrap_reverse,
        .min_size = style.min_size.maybeResolve(parent_size).maybeApplyAspectRatio(aspect_ratio),
        .max_size = style.max_size.maybeResolve(parent_size).maybeApplyAspectRatio(aspect_ratio),
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

/// Collect flex items into flex lines.
///
/// # [9.3. Main Size Determination](https://www.w3.org/TR/css-flexbox-1/#main-sizing)
///
/// - [**Collect flex items into flex lines**](https://www.w3.org/TR/css-flexbox-1/#algo-line-break):
///
///     - If the flex container is single-line, collect all the flex items into a single flex line.
///
///     - Otherwise, starting from the first uncollected item, collect consecutive items one by one until the first time that the next collected item would not fit into the flex container's inner main size
///         (or until a forced break is encountered, see [§10 Fragmenting Flex Layout](https://www.w3.org/TR/css-flexbox-1/#pagination)).
///         If the very first uncollected item wouldn't fit, collect just it into the line.
///
///         For this step, the size of a flex item is its outer hypothetical main size. (**Note: This can be negative**.)
///
///         Repeat until all flex items have been collected into flex lines.
///
///         **Note that the "collect as many" line will collect zero-sized flex items onto the end of the previous line even if the last non-zero item exactly "filled up" the line**.
// #[inline]
const FlexLine = struct {
    items: []FlexItem,
    cross_size: f32,
    offset_cross: f32,

    pub fn sumAxisGaps(self_or_count: anytype, gap_size: f32) f32 {
        const count: usize = if (@TypeOf(self_or_count) == *FlexLine) self_or_count.items.len else self_or_count;
        if (count <= 1) {
            return 0.0;
        }
        return gap_size * @as(f32, @floatFromInt(count - 1));
    }
};
pub fn collectFlexLines(
    allocator: std.mem.Allocator,
    constants: *AlgoConstants,
    available_space: Point(AvailableSpace),
    flex_items: *std.ArrayList(FlexItem),
) !std.ArrayList(FlexLine) {
    if (!constants.is_wrap) {
        var lines = try std.ArrayList(FlexLine).initCapacity(allocator, 1);
        lines.appendAssumeCapacity(.{ .items = flex_items.items.ptr[0..flex_items.items.len], .cross_size = 0.0, .offset_cross = 0.0 });
        return lines;
    }

    switch (constants.dir.getMain(available_space)) {
        // If we're sizing under a max-content constraint then the flex items will never wrap
        // (at least for now - future extensions to the CSS spec may add provisions for forced wrap points)
        .max_content => {
            var lines = try std.ArrayList(FlexLine).initCapacity(allocator, 1);
            lines.appendAssumeCapacity(.{ .items = flex_items.items.ptr[0..flex_items.items.len], .cross_size = 0.0, .offset_cross = 0.0 });
            return lines;
        },

        // If flex-wrap is wrap and we're sizing under a min-content constraint, then we take every possible wrapping opportunity
        // and place each item in it's own line
        .min_content => {
            var lines = try std.ArrayList(FlexLine).initCapacity(allocator, flex_items.items.len);
            for (0..flex_items.items.len) |index| {
                lines.appendAssumeCapacity(.{ .items = flex_items.items.ptr[index .. index + 1], .cross_size = 0.0, .offset_cross = 0.0 });
            }
            return lines;
        },

        .definite => |definite| {
            var lines = std.ArrayList(FlexLine).init(allocator);
            var start_range_index: usize = 0;
            //
            var line_length: f32 = 0.0;
            const main_axis_gap = constants.dir.getMain(constants.gap);
            var is_new_row = true;
            var index: usize = 0;
            while (index < flex_items.items.len) {
                const current_item = flex_items.items.ptr[index];
                // Find index of the first item in the next line
                // (or the last item if all remaining items are in the current line)
                const gap_contribution = if (is_new_row) 0.0 else main_axis_gap;
                line_length += constants.dir.getMain(current_item.hypothetical_outer_size) + gap_contribution;
                if (line_length > definite and !is_new_row) {
                    try lines.append(.{ .items = flex_items.items.ptr[start_range_index..index], .cross_size = 0.0, .offset_cross = 0.0 });
                    start_range_index = index;
                    is_new_row = true;
                    line_length = 0;
                } else {
                    is_new_row = false;
                    index += 1;
                }
            }

            if (start_range_index < flex_items.items.len) {
                try lines.append(.{ .items = flex_items.items.ptr[start_range_index..flex_items.items.len], .cross_size = 0.0, .offset_cross = 0.0 });
            }

            return lines;
        },
    }
    return std.ArrayList(FlexLine).init(allocator);
}

/// Determine the container's main size (if not already known)
pub fn determineContainerMainSize(
    allocator: std.mem.Allocator,
    tree: *Tree,
    available_space: Point(AvailableSpace),
    lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
) !void {
    const dir = constants.dir;

    const main_content_box_inset: f32 = dir.getMain(constants.content_box_inset.sumAxes());

    var outer_main_size: f32 = dir.getMain(constants.node_outer_size) orelse blk: {
        const main_axis_available_space = dir.getMain(available_space);
        if (main_axis_available_space == .definite) {
            var longest_line_length: f32 = 0.0;
            for (lines.items) |*line| {
                var line_size: f32 = line.sumAxisGaps(dir.getMain(constants.gap));

                for (line.items) |*child| {
                    const padding_border_sum = dir.sumMainAxis(child.padding.add(child.border));
                    line_size += @max(child.flex_basis + dir.sumMainAxis(child.margin), padding_border_sum);
                }

                longest_line_length = @max(longest_line_length, line_size);
            }

            const size = longest_line_length + main_content_box_inset;

            if (lines.items.len > 1) {
                break :blk @max(size, main_axis_available_space.definite);
            }
            break :blk size;
        }
        if (main_axis_available_space == .min_content and constants.is_wrap) {
            var longest_line_length: f32 = 0.0;
            for (lines.items) |*line| {
                var line_size = line.sumAxisGaps(dir.getMain(constants.gap));

                for (line.items) |*child| {
                    const padding_border_sum = dir.sumMainAxis(child.padding.add(child.border));
                    line_size += @max(child.flex_basis + dir.sumMainAxis(child.margin), padding_border_sum);
                }

                longest_line_length = @max(longest_line_length, line_size);
            }

            break :blk longest_line_length + main_content_box_inset;
        }
        // Define a base main_size variable. This is mutated once for iteration over the outer
        // loop over the flex lines as:
        //   "The flex container's max-content size is the largest sum of the afore-calculated sizes of all items within a single line."
        var main_size: f32 = 0.0;
        for (lines.items) |*line| {
            for (line.items) |*item| {
                const style_min: ?f32 = dir.getMain(item.min_size);
                const style_preferred: ?f32 = dir.getMain(item.size);
                const style_max: ?f32 = dir.getMain(item.max_size);

                // The spec seems a bit unclear on this point (my initial reading was that the `.maybe_max(style_preferred)` should
                // not be included here), however this matches both Chrome and Firefox as of 9th March 2023.
                //
                // Spec: https://www.w3.org/TR/css-flexbox-1/#intrinsic-item-contributions
                // Spec modification: https://www.w3.org/TR/css-flexbox-1/#change-2016-max-contribution
                // Issue: https://github.com/w3c/csswg-drafts/issues/1435
                // Gentest: padding_border_overrides_size_flex_basis_0.html

                const clamping_basis = Maybe.max(item.flex_basis, style_preferred);
                const flex_basis_min: ?f32 = if (item.flex_shrink == 0.0) clamping_basis else null;
                const flex_basis_max: ?f32 = if (item.flex_grow == 0.0) clamping_basis else null;

                const min_main_size = @max(
                    Maybe.max(
                        style_min,
                        flex_basis_min,
                    ) orelse
                        item.resolved_minimum_main_size,
                    item.resolved_minimum_main_size,
                );

                const max_main_size = Maybe.min(
                    style_max,
                    flex_basis_max,
                ) orelse std.math.inf(f32);

                const content_contribution = content_distribution: {
                    // If the clamping values are such that max <= min, then we can avoid the expensive step of computing the content size
                    // as we know that the clamping values will override it anyway
                    if (style_preferred) |pref| {
                        if (max_main_size <= min_main_size or max_main_size <= pref) {
                            break :content_distribution std.math.clamp(pref, min_main_size, max_main_size) + dir.sumMainAxis(item.margin);
                        }
                    }

                    if (max_main_size <= min_main_size) {
                        break :content_distribution min_main_size + dir.sumMainAxis(item.margin);
                    }
                    // Else compute the min- or -max content size and apply the full formula for computing the
                    // min- or max- content contributuon

                    // parent size for child sizing
                    const cross_axis_parent_size: ?f32 = dir.getCross(constants.node_inner_size);

                    // Available space for child sizing
                    const cross_axis_margin_sum: f32 = dir.sumCrossAxis(constants.margin);
                    const child_min_cross: ?f32 = Maybe.add(dir.getCross(item.min_size), cross_axis_margin_sum);
                    const child_max_cross: ?f32 = Maybe.add(dir.getCross(item.max_size), cross_axis_margin_sum);

                    const cross_axis_available_space: AvailableSpace = available_space: {
                        const v: AvailableSpace = dir.getCross(available_space);
                        switch (v) {
                            .definite => |d| break :available_space .{
                                .definite = Maybe.clamp(
                                    cross_axis_parent_size orelse d,
                                    child_min_cross,
                                    child_max_cross,
                                ),
                            },
                            else => break :available_space v,
                        }
                    };
                    const child_available_space = dir.setCross(available_space, cross_axis_available_space);

                    // Either the min- or max- content size depending on which constraint we are sizing under.
                    // TODO: Optimise by using already computed values where available

                    const content_main_size = try measureChildSize(
                        allocator,
                        item.node_id,
                        tree,
                        .{
                            .x = null,
                            .y = null,
                        },
                        constants.node_inner_size,
                        child_available_space,
                        .inherent_size,
                        AbsoluteAxis.fromFlexDirection(dir),
                        Line.FALSE,
                    ) + dir.sumMainAxis(item.margin);

                    // This is somewhat bizarre in that it's asymmetrical depending whether the flex container is a column or a row.
                    //
                    // I *think* this might relate to https://drafts.csswg.org/css-flexbox-1/#algo-main-container:
                    //
                    //    "The automatic block size of a block-level flex container is its max-content size."
                    //
                    // Which could suggest that flex-basis defining a vertical size does not shrink because it is in the block axis, and the automatic size
                    // in the block axis is a MAX content size. Whereas a flex-basis defining a horizontal size does shrink because the automatic size in
                    // inline axis is MIN content size (although I don't have a reference for that).
                    //
                    // Ultimately, this was not found by reading the spec, but by trial and error fixing tests to align with Webkit/Firefox output.
                    // (see the `flex_basis_unconstraint_row` and `flex_basis_uncontraint_column` generated tests which demonstrate this)

                    if (dir.isRow()) {
                        break :content_distribution Maybe.clamp(content_main_size, min_main_size, max_main_size);
                    }

                    break :content_distribution @max(Maybe.clamp(
                        @max(content_main_size, item.flex_basis),
                        style_min,
                        style_max,
                    ), main_content_box_inset);
                };
                item.content_flex_fraction = flex_fraction: {
                    const diff = content_contribution - item.flex_basis;
                    if (diff > 0.0) {
                        break :flex_fraction diff / @max(1.0, item.flex_grow);
                    }
                    if (diff < 0.0) {
                        const scaled_shrink_factor = @max(1.0, item.flex_shrink * item.inner_flex_basis);
                        break :flex_fraction diff / scaled_shrink_factor;
                    }

                    break :flex_fraction 0.0;
                };
            }

            // TODO Spec says to scale everything by the line's max flex fraction. But neither Chrome nor firefox implement this
            // so we don't either. But if we did want to, we'd need this computation here (and to use it below):
            //
            // Within each line, find the largest max-content flex fraction among all the flex items.
            // let line_flex_fraction = line
            //     .items
            //     .iter()
            //     .map(|item| item.content_flex_fraction)
            //     .max_by(|a, b| a.total_cmp(b))
            //     .unwrap_or(0.0); // Unwrap case never gets hit because there is always at least one item a line

            // Add each item's flex base size to the product of:
            //   - its flex grow factor (or scaled flex shrink factor,if the chosen max-content flex fraction was negative)
            //   - the chosen max-content flex fraction
            // then clamp that result by the max main size floored by the min main size.
            //
            // The flex container's max-content size is the largest sum of the afore-calculated sizes of all items within a single line.

            var item_main_size_sum: f32 = 0.0;
            for (line.items) |*item| {
                const flex_fraction = item.content_flex_fraction;

                const flex_contribution = contribution: {
                    if (item.content_flex_fraction > 0.0) {
                        break :contribution @max(1.0, item.flex_grow) * flex_fraction;
                    }
                    if (item.content_flex_fraction < 0.0) {
                        const scaled_shrink_factor = @max(1.0, item.flex_shrink) * item.inner_flex_basis;
                        break :contribution scaled_shrink_factor * flex_fraction;
                    }
                    break :contribution 0.0;
                };

                const size = item.flex_basis + flex_contribution;

                item.outer_target_size = dir.setMain(item.outer_target_size, size);
                item.target_size = dir.setMain(item.target_size, size);

                item_main_size_sum += size;
            }

            const gap_sum = line.sumAxisGaps(dir.getMain(constants.gap));
            main_size = @max(main_size, item_main_size_sum + gap_sum);
        }

        break :blk main_size + main_content_box_inset;
    };

    outer_main_size = Maybe.clamp(
        outer_main_size,
        dir.getMain(constants.min_size),
        dir.getMain(constants.max_size),
    );
    outer_main_size = @max(
        outer_main_size,
        main_content_box_inset - dir.getMain(constants.scrollbar_gutter),
    );

    const inner_main_size = @max(0.0, outer_main_size - main_content_box_inset);
    constants.container_size = dir.setMain(constants.container_size, outer_main_size);
    constants.inner_container_size = dir.setMain(constants.inner_container_size, inner_main_size);
    constants.node_inner_size = dir.setMain(constants.node_inner_size, inner_main_size);
}

/// Resolve the flexible lengths of the items within a flex line.
/// Sets the `main` component of each item's `target_size` and `outer_target_size`
///
/// # [9.7. Resolving Flexible Lengths](https://www.w3.org/TR/css-flexbox-1/#resolve-flexible-lengths)
pub fn resolveFlexibleLengths(
    allocator: std.mem.Allocator,
    line: *FlexLine,
    constants: *AlgoConstants,
    original_gap: Point(f32),
) !void {
    const dir = constants.dir;
    const total_original_main_axis_gap = line.sumAxisGaps(dir.getMain(original_gap));
    const total_main_axis_gap = line.sumAxisGaps(dir.getMain(constants.gap));

    // 1. Determine the used flex factor. Sum the outer hypothetical main sizes of all
    //    items on the line. If the sum is less than the flex container's inner main size,
    //    use the flex grow factor for the rest of this algorithm; otherwise, use the
    //    flex shrink factor.

    const total_hypothetical_outer_main_size = blk: {
        var sum: f32 = 0.0;
        for (line.items) |*child| {
            sum += dir.getMain(child.hypothetical_outer_size);
        }
        break :blk sum;
    };
    const used_flex_factor = total_original_main_axis_gap + total_hypothetical_outer_main_size;
    const growing = used_flex_factor < dir.getMain(constants.node_inner_size) orelse 0.0;
    const shrinking = !growing;

    // 2. Size inflexible items. Freeze, setting its target main size to its hypothetical main size
    //    - Any item that has a flex factor of zero
    //    - If using the flex grow factor: any item that has a flex base size
    //      greater than its hypothetical main size
    //    - If using the flex shrink factor: any item that has a flex base size
    //      smaller than its hypothetical main size

    for (line.items) |*child| {
        const inner_target_size = dir.getMain(child.hypothetical_inner_size);
        child.target_size = dir.setMain(child.target_size, inner_target_size);

        if ((child.flex_grow == 0.0 and child.flex_shrink == 0.0) or (growing and child.flex_basis > dir.getMain(child.hypothetical_inner_size)) or (shrinking and child.flex_basis < dir.getMain(child.hypothetical_inner_size))) {
            child.frozen = true;
            const outer_target_size = inner_target_size + dir.sumMainAxis(child.margin);
            child.outer_target_size = dir.setMain(child.outer_target_size, outer_target_size);
        }
    }

    // 3. calculate initial free space. sum the outer sizes of all items on the line,
    //    and subtract this from the flex container's inner main size. for frozen items,
    //    use their outer target main size; for other items, use their outer flex base size.

    const initial_used_space = blk: {
        var sum: f32 = 0.0;
        for (line.items) |child| {
            sum += dir.sumMainAxis(child.margin) + if (child.frozen) dir.getMain(child.outer_target_size) else child.flex_basis;
        }
        break :blk sum + total_main_axis_gap;
    };
    const initial_free_space = Maybe.sub(dir.getMain(constants.node_inner_size), initial_used_space) orelse 0.0;

    // 4. Loop
    var unfrozen = try std.ArrayList(*FlexItem).initCapacity(allocator, line.items.len);
    defer unfrozen.deinit();
    while (true) {
        // a. Check for flexible items. If all the flex items on the line are frozen,
        //    free space has been distributed; exit this loop.

        const all_frozen = for (line.items) |child| {
            if (child.frozen == false) {
                break false;
            }
        } else true;

        if (all_frozen) {
            break;
        }

        // b. Calculate the remaining free space as for initial free space, above.
        //    If the sum of the unfrozen flex items' flex factors is less than one,
        //    multiply the initial free space by this sum. If the magnitude of this
        //    value is less than the magnitude of the remaining free space, use this
        //    as the remaining free space.

        var used_space = total_main_axis_gap;
        for (line.items) |child| {
            used_space += dir.sumMainAxis(child.margin) + if (child.frozen) dir.getMain(child.outer_target_size) else child.flex_basis;
        }

        var sum_flex_grow: f32 = 0.0;
        var sum_flex_shrink: f32 = 0.0;
        // iter unfrozen
        unfrozen.clearRetainingCapacity();
        for (line.items) |*child| {
            if (!child.frozen) {
                unfrozen.appendAssumeCapacity(child);
                sum_flex_grow += child.flex_grow;
                sum_flex_shrink += child.flex_shrink;
            }
        }

        const free_space = blk: {
            if (growing and sum_flex_grow < 1.0) {
                const a: f32 = initial_free_space * sum_flex_grow - total_main_axis_gap;
                const b: ?f32 = Maybe.sub(dir.getMain(constants.node_inner_size), used_space);
                break :blk Maybe.min(a, b);
            }
            if (shrinking and sum_flex_shrink < 1.0) {
                const a: f32 = initial_free_space * sum_flex_grow - total_main_axis_gap;
                const b: ?f32 = Maybe.sub(dir.getMain(constants.node_inner_size), used_space);
                break :blk Maybe.max(a, b);
            }

            break :blk Maybe.sub(dir.getMain(constants.node_inner_size), used_space) orelse used_flex_factor - used_space;
        };

        // c. Distribute free space proportional to the flex factors.
        //    - If the remaining free space is zero
        //        Do Nothing
        //    - If using the flex grow factor
        //        Find the ratio of the item's flex grow factor to the sum of the
        //        flex grow factors of all unfrozen items on the line. Set the item's
        //        target main size to its flex base size plus a fraction of the remaining
        //        free space proportional to the ratio.
        //    - If using the flex shrink factor
        //        For every unfrozen item on the line, multiply its flex shrink factor by
        //        its inner flex base size, and note this as its scaled flex shrink factor.
        //        Find the ratio of the item's scaled flex shrink factor to the sum of the
        //        scaled flex shrink factors of all unfrozen items on the line. Set the item's
        //        target main size to its flex base size minus a fraction of the absolute value
        //        of the remaining free space proportional to the ratio. Note this may result
        //        in a negative inner main size; it will be corrected in the next step.
        //    - Otherwise
        //        Do Nothing
        if (std.math.isNormal(free_space)) {
            if (growing and sum_flex_grow > 0) {
                for (unfrozen.items) |child| {
                    const ratio = child.flex_grow / sum_flex_grow;
                    const target_size = child.flex_basis + free_space * ratio;
                    child.target_size = dir.setMain(child.target_size, target_size);
                }
            } else if (shrinking and sum_flex_shrink > 0) {
                var sum_scaled_shrink_factor: f32 = 0.0;
                for (unfrozen.items) |child| {
                    sum_scaled_shrink_factor += child.inner_flex_basis * child.flex_shrink;
                }

                if (sum_scaled_shrink_factor > 0) {
                    for (unfrozen.items) |child| {
                        const scaled_shrink_factor = child.inner_flex_basis * child.flex_shrink;
                        const ratio = scaled_shrink_factor / sum_scaled_shrink_factor;
                        const target_size = child.flex_basis + free_space * ratio;
                        child.target_size = dir.setMain(child.target_size, target_size);
                    }
                }
            }
        }

        // d. Fix min/max violations. Clamp each non-frozen item's target main size by its
        //    used min and max main sizes and floor its content-box size at zero. If the
        //    item's target main size was made smaller by this, it's a max violation.
        //    If the item's target main size was made larger by this, it's a min violation.

        var total_violation: f32 = 0.0;
        for (unfrozen.items) |child| {
            const resolved_min_main: ?f32 = child.resolved_minimum_main_size;
            const max_main = dir.getMain(child.max_size);
            const clamped = @max(Maybe.clamp(dir.getMain(child.target_size), resolved_min_main, max_main), 0);
            child.violation = clamped - dir.getMain(child.target_size);
            child.target_size = dir.setMain(child.target_size, clamped);
            child.outer_target_size = dir.setMain(
                child.outer_target_size,
                clamped + dir.sumMainAxis(child.margin),
            );

            total_violation += child.violation;
        }

        // e. Freeze over-flexed items. The total violation is the sum of the adjustments
        //    from the previous step ∑(clamped size - unclamped size). If the total violation is:
        //    - Zero
        //        Freeze all items.
        //    - Positive
        //        Freeze all the items with min violations.
        //    - Negative
        //        Freeze all the items with max violations.

        for (unfrozen.items) |child| {
            if (total_violation > 0.0) {
                child.frozen = child.violation > 0.0;
                continue;
            }
            if (total_violation < 0.0) {
                child.frozen = child.violation < 0.0;
                continue;
            }
            child.frozen = true;
        }
    }
}

/// Determine the hypothetical cross size of each item.
///
/// # [9.4. Cross Size Determination](https://www.w3.org/TR/css-flexbox-1/#cross-sizing)
///
/// - [**Determine the hypothetical cross size of each item**](https://www.w3.org/TR/css-flexbox-1/#algo-cross-item)
///     by performing layout with the used main size and the available space, treating auto as fit-content.
pub fn determineHypotheticalCrossSize(
    allocator: std.mem.Allocator,
    tree: *Tree,
    line: *FlexLine,
    constants: *AlgoConstants,
    available_space: Point(AvailableSpace),
) !void {
    const dir = constants.dir;

    for (line.items) |*child| {
        const padding_border_sum: f32 = dir.sumCrossAxis(child.padding.add(child.border));

        const child_known_main: AvailableSpace = .{ .definite = dir.getMain(constants.container_size) };
        const child_cross: ?f32 = Maybe.max(
            Maybe.clamp(
                dir.getCross(child.size),
                dir.getCross(child.min_size),
                dir.getCross(child.max_size),
            ),
            padding_border_sum,
        );
        const child_available_cross: AvailableSpace = dir.getCross(available_space).maybeClamp(
            dir.getCross(child.min_size),
            dir.getCross(child.max_size),
        ).maybeMax(padding_border_sum);
        const child_inner_cross: f32 = child_cross orelse blk: {
            const size = try measureChildSize(
                allocator,
                child.node_id,
                tree,
                .{
                    .x = if (constants.is_row) child.target_size.x else null,
                    .y = if (constants.is_row) null else child.target_size.y,
                },
                constants.node_inner_size,
                .{
                    .x = if (constants.is_row) child_known_main else child_available_cross,
                    .y = if (constants.is_row) child_available_cross else child_known_main,
                },
                .content_size,
                AbsoluteAxis.fromFlexDirection(dir).otherAxis(),
                Line.FALSE,
            );
            break :blk @max(
                Maybe.clamp(
                    size,
                    dir.getCross(child.min_size),
                    dir.getCross(child.max_size),
                ),
                padding_border_sum,
            );
        };
        const child_outer_cross = child_inner_cross + dir.sumCrossAxis(child.margin);

        child.hypothetical_inner_size = dir.setCross(child.hypothetical_inner_size, child_inner_cross);
        child.hypothetical_outer_size = dir.setCross(child.hypothetical_outer_size, child_outer_cross);
    }
}

/// Calculate the base lines of the children.
pub fn calculateChildrenBaseLines(
    allocator: std.mem.Allocator,
    tree: *Tree,
    node_size: Point(?f32),
    available_space: Point(AvailableSpace),
    flex_lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
) !void {
    // Only compute baselines for flex rows because we only support baseline alignment in the cross axis
    // where that axis is also the inline axis
    // TODO: this may need revisiting if/when we support vertical writing modes

    if (!constants.is_row) {
        return;
    }

    for (flex_lines.items) |*line| {
        // If a flex line has one or zero items participating in baseline alignment then baseline alignment is a no-op so we skip
        var line_baseline_child_count: usize = 0;
        for (line.items) |child| {
            if (child.align_self == .baseline) {
                line_baseline_child_count += 1;
            }
        }

        if (line_baseline_child_count <= 1) {
            continue;
        }

        for (line.items) |*child| {
            // Only calculate baselines for children participating in baseline alignment
            if (child.align_self != .baseline) {
                continue;
            }

            const measured_size_and_baselines = try performChildLayout(
                allocator,
                child.node_id,
                tree,
                if (constants.is_row)
                    .{
                        .x = child.target_size.x,
                        .y = child.hypothetical_inner_size.y,
                    }
                else
                    .{
                        .x = child.hypothetical_inner_size.x,
                        .y = child.target_size.y,
                    },
                constants.node_inner_size,
                if (constants.is_row)
                    .{
                        .x = .{ .definite = constants.container_size.x },
                        .y = available_space.y.maybeSet(node_size.y),
                    }
                else
                    .{
                        .x = available_space.x.maybeSet(node_size.x),
                        .y = .{ .definite = constants.container_size.y },
                    },
                .content_size,
                Line.FALSE,
            );

            const baseline = measured_size_and_baselines.first_baselines.y;
            const height = measured_size_and_baselines.size.y;
            child.baseline = (baseline orelse height) + child.margin.top;
        }
    }
}

/// Calculate the cross size of each flex line.
///
/// # [9.4. Cross Size Determination](https://www.w3.org/TR/css-flexbox-1/#cross-sizing)
///
/// - [**Calculate the cross size of each flex line**](https://www.w3.org/TR/css-flexbox-1/#algo-cross-line).
///
///     If the flex container is single-line and has a definite cross size, the cross size of the flex line is the flex container's inner cross size.
///
///     Otherwise, for each flex line:
///
///     1. Collect all the flex items whose inline-axis is parallel to the main-axis, whose align-self is baseline, and whose cross-axis margins are both non-auto.
///         Find the largest of the distances between each item's baseline and its hypothetical outer cross-start edge,
///         and the largest of the distances between each item's baseline and its hypothetical outer cross-end edge, and sum these two values.
///
///     2. Among all the items not collected by the previous step, find the largest outer hypothetical cross size.
///
///     3. The used cross-size of the flex line is the largest of the numbers found in the previous two steps and zero.
///
///         If the flex container is single-line, then clamp the line's cross-size to be within the container's computed min and max cross sizes.
///         **Note that if CSS 2.1's definition of min/max-width/height applied more generally, this behavior would fall out automatically**.
pub fn calculateCrossSize(
    flex_lines: *std.ArrayList(FlexLine),
    node_size: Point(?f32),
    constants: *AlgoConstants,
) !void {
    // Note: AlignContent::space_evenly and AlignContent::space_around behave like AlignContent::stretch when there is only
    // a single flex line in the container. See: https://www.w3.org/TR/css-flexbox-1/#align-content-property
    // Also: align_content is ignored entirely (and thus behaves like stretch) when `flex_wrap` is set to `nowrap`.
    const dir = constants.dir;

    if (flex_lines.items.len == 1 and
        dir.getCross(node_size) != null and
        (!constants.is_wrap or
            constants.align_content == .stretch or
            constants.align_content == .space_evenly or
            constants.align_content == .space_around))
    {
        const cross_axis_padding_border = dir.sumCrossAxis(constants.content_box_inset);
        const cross_min_size = dir.getCross(constants.min_size);
        const cross_max_size = dir.getCross(constants.max_size);

        var line = flex_lines.items[0];
        var cross_size = dir.getCross(node_size);

        cross_size = Maybe.clamp(cross_size, cross_min_size, cross_max_size);
        cross_size = Maybe.sub(cross_size, cross_axis_padding_border);
        cross_size = Maybe.max(cross_size, 0.0);
        line.cross_size = cross_size orelse 0.0;
    } else {
        for (flex_lines.items) |*line| {
            //    1. Collect all the flex items whose inline-axis is parallel to the main-axis, whose
            //       align-self is baseline, and whose cross-axis margins are both non-auto. Find the
            //       largest of the distances between each item's baseline and its hypothetical outer
            //       cross-start edge, and the largest of the distances between each item's baseline
            //       and its hypothetical outer cross-end edge, and sum these two values.

            //    2. Among all the items not collected by the previous step, find the largest
            //       outer hypothetical cross size.

            //    3. The used cross-size of the flex line is the largest of the numbers found in the
            //       previous two steps and zero.

            var max_baseline: f32 = 0.0;
            for (line.items) |child| {
                max_baseline = @max(max_baseline, child.baseline);
            }

            var cross_size: f32 = 0.0;
            for (line.items) |*child| {
                if (child.align_self == .baseline and
                    !dir.getCrossStart(child.margin_is_auto) and
                    !dir.getCrossEnd(child.margin_is_auto))
                {
                    cross_size = @max(cross_size, max_baseline - child.baseline + dir.getCross(child.hypothetical_outer_size));
                } else {
                    cross_size = @max(cross_size, dir.getCross(child.hypothetical_outer_size));
                }
            }
            line.cross_size = cross_size;
        }
        //  If the flex container is single-line, then clamp the line's cross-size to be within the container's computed min and max cross sizes.
        if (!constants.is_wrap) {
            const cross_axis_padding_border = dir.sumCrossAxis(constants.content_box_inset);
            const cross_min_size = dir.getCross(constants.min_size);
            const cross_max_size = dir.getCross(constants.max_size);
            var line = flex_lines.items[0];
            line.cross_size = Maybe.clamp(
                line.cross_size,
                Maybe.sub(cross_min_size, cross_axis_padding_border),
                Maybe.sub(cross_max_size, cross_axis_padding_border),
            );
        }
    }
}

/// Handle 'align-content: stretch'.
///
/// # [9.4. Cross Size Determination](https://www.w3.org/TR/css-flexbox-1/#cross-sizing)
///
/// - [**Handle 'align-content: stretch'**](https://www.w3.org/TR/css-flexbox-1/#algo-line-stretch). If the flex container has a definite cross size, align-content is stretch,
///     and the sum of the flex lines' cross sizes is less than the flex container's inner cross size,
///     increase the cross size of each flex line by equal amounts such that the sum of their cross sizes exactly equals the flex container's inner cross size.
pub fn handleAlignContentStretch(
    flex_lines: *std.ArrayList(FlexLine),
    node_size: Point(?f32),
    constants: *AlgoConstants,
) !void {
    // [https://www.w3.org/TR/css-flexbox-1/#align-content-property]
    // "Note, this property has no effect on a single-line flex container"
    // if (!constants.is_wrap) {
    //     return;
    // }
    //
    if (constants.align_content == .stretch) {
        const dir = constants.dir;
        const cross_axis_padding_border = dir.sumCrossAxis(constants.content_box_inset);
        const cross_min_size = dir.getCross(constants.min_size);
        const cross_max_size = dir.getCross(constants.max_size);
        const container_min_inner_cross: f32 = blk: {
            var out: ?f32 = dir.getCross(node_size) orelse cross_min_size;
            out = Maybe.clamp(out, cross_min_size, cross_max_size);
            out = Maybe.sub(out, cross_axis_padding_border);
            break :blk Maybe.max(out, 0.0) orelse 0.0;
        };

        const total_cross_axis_gap = FlexLine.sumAxisGaps(
            flex_lines.items.len,
            dir.getCross(constants.gap),
        );

        var lines_total_cross: f32 = total_cross_axis_gap;
        for (flex_lines.items) |line| {
            lines_total_cross += line.cross_size;
        }

        if (lines_total_cross < container_min_inner_cross) {
            const remaining = container_min_inner_cross - lines_total_cross;
            const addition = remaining / @as(f32, @floatFromInt(flex_lines.items.len));
            for (flex_lines.items) |*line| {
                line.cross_size += addition;
            }
        }
    }
}

/// Determine the used cross size of each flex item.
///
/// # [9.4. Cross Size Determination](https://www.w3.org/TR/css-flexbox-1/#cross-sizing)
///
/// - [**Determine the used cross size of each flex item**](https://www.w3.org/TR/css-flexbox-1/#algo-stretch). If a flex item has align-self: stretch, its computed cross size property is auto,
///     and neither of its cross-axis margins are auto, the used outer cross size is the used cross size of its flex line, clamped according to the item's used min and max cross sizes.
///     Otherwise, the used cross size is the item's hypothetical cross size.
///
///     If the flex item has align-self: stretch, redo layout for its contents, treating this used size as its definite cross size so that percentage-sized children can be resolved.
///
///     **Note that this step does not affect the main size of the flex item, even if it has an intrinsic aspect ratio**.
pub fn determineUsedCrossSize(
    tree: *Tree,
    flex_lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
) !void {
    const dir = constants.dir;

    for (flex_lines.items) |*line| {
        const line_cross_size: f32 = line.cross_size;

        for (line.items) |*child| {
            const child_style = tree.getComputedStyle(child.node_id);
            if (child.align_self == .stretch and
                !dir.getCrossStart(child.margin_is_auto) and
                !dir.getCrossEnd(child.margin_is_auto) and
                dir.getCross(child_style.size) == .auto)
            {
                // for some reason this particular usage of max_width is an exception to the rule that max_width's transfer
                // using the aspect_ratio (if set). both chrome and firefox agree on this. and reading the spec, it seems like
                // a reasonable interpretation. although it seems to me that the spec *should* apply aspect_ratio here.
                const max_size_ignoring_aspect_ratio = child_style.max_size.maybeResolve(constants.node_inner_size);
                const cross = Maybe.clamp(
                    line_cross_size - dir.sumCrossAxis(child.margin),
                    dir.getCross(child.min_size),
                    dir.getCross(max_size_ignoring_aspect_ratio),
                );
                child.target_size = dir.setCross(child.target_size, cross);
            } else {
                child.target_size = dir.setCross(child.target_size, dir.getCross(child.hypothetical_inner_size));
            }

            child.outer_target_size = dir.setCross(
                child.outer_target_size,
                dir.getCross(child.target_size) + dir.sumCrossAxis(child.margin),
            );
        }
    }
}

/// Distribute any remaining free space.
///
/// # [9.5. Main-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#main-alignment)
///
/// - [**Distribute any remaining free space**](https://www.w3.org/TR/css-flexbox-1/#algo-main-align). For each flex line:
///
///     1. If the remaining free space is positive and at least one main-axis margin on this line is `auto`, distribute the free space equally among these margins.
///         Otherwise, set all `auto` margins to zero.
///
///     2. Align the items along the main-axis per `justify-content`.
pub fn distributeRemainingFreeSpace(
    flex_lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
) !void {
    const dir = constants.dir;

    for (flex_lines.items) |*line| {
        const total_main_axis_gap = FlexLine.sumAxisGaps(
            line.items.len,
            dir.getMain(constants.gap),
        );
        var used_space: f32 = total_main_axis_gap;
        for (line.items) |child| {
            used_space += dir.getMain(child.outer_target_size);
        }
        const free_space = dir.getMain(constants.inner_container_size) - used_space;

        var num_auto_margins: usize = 0;

        for (line.items) |*child| {
            if (dir.getMainStart(child.margin_is_auto)) {
                num_auto_margins += 1;
            }

            if (dir.getMainEnd(child.margin_is_auto)) {
                num_auto_margins += 1;
            }
        }

        if (free_space > 0.0 and num_auto_margins > 0) {
            const margin = free_space / @as(f32, @floatFromInt(num_auto_margins));

            for (line.items) |*child| {
                if (dir.getMainStart(child.margin_is_auto)) {
                    if (constants.is_row) {
                        child.margin.left = margin;
                    } else {
                        child.margin.top = margin;
                    }
                }

                if (dir.getMainEnd(child.margin_is_auto)) {
                    if (constants.is_row) {
                        child.margin.right = margin;
                    } else {
                        child.margin.bottom = margin;
                    }
                }
            }
        } else {
            const num_items = line.items.len;
            const layout_reverse = dir.isReverse();
            const gap = dir.getMain(constants.gap);
            const justify_content_mode = constants.justify_content orelse .flex_start;

            for (line.items, 0..) |*child, i| {
                child.offset_main = computeAlignmentOffset(
                    free_space,
                    num_items,
                    gap,
                    justify_content_mode,
                    layout_reverse,
                    if (layout_reverse) i == num_items - 1 else i == 0,
                );
            }
        }
    }
}

/// Resolve cross-axis `auto` margins.
///
/// # [9.6. Cross-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#cross-alignment)
///
/// - [**Resolve cross-axis `auto` margins**](https://www.w3.org/TR/css-flexbox-1/#algo-cross-margins).
///     If a flex item has auto cross-axis margins:
///
///     - If its outer cross size (treating those auto margins as zero) is less than the cross size of its flex line,
///         distribute the difference in those sizes equally to the auto margins.
///
///     - Otherwise, if the block-start or inline-start margin (whichever is in the cross axis) is auto, set it to zero.
///         Set the opposite margin so that the outer cross size of the item equals the cross size of its flex line.
pub fn resolveCrossAxisAutoMargis(
    flex_lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
) !void {
    const dir = constants.dir;
    for (flex_lines.items) |*line| {
        const line_cross_size = line.cross_size;
        var max_baseline: f32 = 0.0;
        for (line.items) |child| {
            max_baseline = @max(max_baseline, child.baseline);
        }

        for (line.items) |*child| {
            const free_space = line_cross_size - dir.getCross(child.outer_target_size);
            if (dir.getCrossStart(child.margin_is_auto) and dir.getCrossEnd(child.margin_is_auto)) {
                if (constants.is_row) {
                    child.margin.top = free_space / 2.0;
                    child.margin.bottom = free_space / 2.0;
                } else {
                    child.margin.left = free_space / 2.0;
                    child.margin.right = free_space / 2.0;
                }
            } else if (dir.getCrossStart(child.margin_is_auto)) {
                if (constants.is_row) {
                    child.margin.top = free_space;
                } else {
                    child.margin.left = free_space;
                }
            } else if (dir.getCrossEnd(child.margin_is_auto)) {
                if (constants.is_row) {
                    child.margin.bottom = free_space;
                } else {
                    child.margin.right = free_space;
                }
            } else {
                child.offset_cross = alignFlexItemsAlongCrossAxis(child, free_space, max_baseline, constants);
            }
        }
    }
}
/// Align all flex items along the cross-axis.
///
/// # [9.6. Cross-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#cross-alignment)
///
/// - [**Align all flex items along the cross-axis**](https://www.w3.org/TR/css-flexbox-1/#algo-cross-align) per `align-self`,
///     if neither of the item's cross-axis margins are `auto`.
// #[inline]
pub fn alignFlexItemsAlongCrossAxis(
    child: *FlexItem,
    free_space: f32,
    max_baseline: f32,
    constants: *AlgoConstants,
) f32 {
    switch (child.align_self) {
        .start => return 0.0,
        .flex_start => {
            if (constants.is_wrap_reverse) {
                return free_space;
            } else {
                return 0.0;
            }
        },
        .end => return free_space,
        .flex_end => {
            if (constants.is_wrap_reverse) {
                return 0.0;
            } else {
                return free_space;
            }
        },
        .center => return free_space / 2.0,
        .baseline => {
            if (constants.is_row) {
                return max_baseline - child.baseline;
            } else {
                // Until we support vertical writing modes, baseline alignment only makes sense if
                // the constants.direction is row, so we treat it as flex-start alignment in columns.
                if (constants.is_wrap_reverse) {
                    return free_space;
                } else {
                    return 0.0;
                }
            }
        },
        .stretch => {
            if (constants.is_wrap_reverse) {
                return free_space;
            } else {
                return 0.0;
            }
        },
    }
}
/// Determine the flex container's used cross size.
///
/// # [9.6. Cross-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#cross-alignment)
///
/// - [**Determine the flex container's used cross size**](https://www.w3.org/TR/css-flexbox-1/#algo-cross-container):
///
///     - If the cross size property is a definite size, use that, clamped by the used min and max cross sizes of the flex container.
///
///     - Otherwise, use the sum of the flex lines' cross sizes, clamped by the used min and max cross sizes of the flex container.
pub fn determineContainerCrossSize(
    flex_lines: *std.ArrayList(FlexLine),
    node_size: Point(?f32),
    constants: *AlgoConstants,
) f32 {
    const dir = constants.dir;
    const total_cross_axis_gap = FlexLine.sumAxisGaps(
        flex_lines.items.len,
        dir.getCross(constants.gap),
    );
    var total_line_cross_size: f32 = 0.0;
    for (flex_lines.items) |line| {
        total_line_cross_size += line.cross_size;
    }

    const padding_border_sum: f32 = dir.sumCrossAxis(constants.content_box_inset);
    const cross_scrollbar_gutter: f32 = dir.getCross(constants.scrollbar_gutter);
    const min_cross_size: ?f32 = dir.getCross(constants.min_size);
    const max_cross_size: ?f32 = dir.getCross(constants.max_size);
    const outer_container_size: f32 = blk: {
        var out: f32 = dir.getCross(node_size) orelse total_line_cross_size + total_cross_axis_gap + padding_border_sum;
        out = Maybe.clamp(out, min_cross_size, max_cross_size);
        break :blk @max(out, padding_border_sum - cross_scrollbar_gutter);
    };
    const inner_container_size: f32 = @max(outer_container_size - padding_border_sum, 0.0);

    constants.container_size = dir.setCross(constants.container_size, outer_container_size);
    constants.inner_container_size = dir.setCross(constants.inner_container_size, inner_container_size);

    return total_line_cross_size;
}
/// Align all flex lines per `align-content`.
///
/// # [9.6. Cross-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#cross-alignment)
///
/// - [**Align all flex lines**](https://www.w3.org/TR/css-flexbox-1/#algo-line-align) per `align-content`.
pub fn alignFlexLinesPerAlignContent(
    flex_lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
    total_cross_size: f32,
) void {
    // [https://www.w3.org/TR/css-flexbox-1/#align-content-property]
    // "Note, this property has no effect on a single-line flex container"
    if (!constants.is_wrap) {
        return;
    }
    const num_lines = flex_lines.items.len;
    const dir = constants.dir;
    const gap = dir.getCross(constants.gap);
    const align_content_mode: Style.AlignContent = constants.align_content;
    const total_cross_axis_gap: f32 = FlexLine.sumAxisGaps(num_lines, gap);
    const free_space: f32 = dir.getCross(constants.inner_container_size) - total_cross_size - total_cross_axis_gap;

    for (flex_lines.items, 0..) |*line, i| {
        line.offset_cross = computeAlignmentOffset(
            free_space,
            num_lines,
            gap,
            align_content_mode,
            constants.is_wrap_reverse,
            if (constants.is_wrap_reverse) i == num_lines - 1 else i == 0,
        );
    }
}

/// Do a final layout pass and collect the resulting layouts.
pub fn finalLayoutPass(
    allocator: std.mem.Allocator,
    tree: *Tree,
    flex_lines: *std.ArrayList(FlexLine),
    constants: *AlgoConstants,
) !Point(f32) {
    const dir = constants.dir;
    var total_offset_cross: f32 = dir.getCrossStart(constants.content_box_inset);
    var content_size: Point(f32) = .{ .x = 0.0, .y = 0.0 };
    if (constants.is_wrap_reverse) {
        var iter = Iter.sliceReverse(flex_lines.items);
        while (iter.next()) |line| {
            try calculateLayoutLine(
                allocator,
                tree,
                line,
                &total_offset_cross,
                &content_size,
                constants.container_size,
                constants.node_inner_size,
                constants.content_box_inset,
                dir,
            );
        }
    } else {
        var iter = Iter.slice(flex_lines.items);
        while (iter.next()) |line| {
            try calculateLayoutLine(
                allocator,
                tree,
                line,
                &total_offset_cross,
                &content_size,
                constants.container_size,
                constants.node_inner_size,
                constants.content_box_inset,
                dir,
            );
        }
    }

    return content_size;
}

/// Calculates the layout line
pub fn calculateLayoutLine(
    allocator: std.mem.Allocator,
    tree: *Tree,
    line: *FlexLine,
    total_offset_cross: *f32,
    content_size: *Point(f32),
    container_size: Point(f32),
    node_inner_size: Point(?f32),
    padding_border: Rect(f32),
    direction: styles.flex_direction.FlexDirection,
) !void {
    const dir = direction;
    var total_offset_main: f32 = dir.getMainStart(padding_border);
    const line_offset_cross: f32 = line.offset_cross;

    if (dir.isReverse()) {
        var iter = Iter.sliceReverse(line.items);
        while (iter.next()) |item| {
            try calculateFlexItem(
                allocator,
                tree,
                item,
                &total_offset_main,
                total_offset_cross.*,
                line_offset_cross,
                content_size,
                container_size,
                node_inner_size,
                direction,
            );
        }
    } else {
        var iter = Iter.slice(line.items);
        while (iter.next()) |item| {
            try calculateFlexItem(
                allocator,
                tree,
                item,
                &total_offset_main,
                total_offset_cross.*,
                line_offset_cross,
                content_size,
                container_size,
                node_inner_size,
                direction,
            );
        }
    }

    total_offset_cross.* += line_offset_cross + line.cross_size;
}
/// Calculates the layout for a flex-item
pub fn calculateFlexItem(
    allocator: std.mem.Allocator,
    tree: *Tree,
    item: *FlexItem,
    total_offset_main: *f32,
    total_offset_cross: f32,
    line_offset_cross: f32,
    total_content_size: *Point(f32),
    container_size: Point(f32),
    node_inner_size: Point(?f32),
    dir: styles.flex_direction.FlexDirection,
) !void {
    const layout_output: LayoutOutput = try performChildLayout(
        allocator,
        item.node_id,
        tree,
        item.target_size.intoOptional(),
        node_inner_size,
        AvailableSpace.fromPoint(container_size),
        .content_size,
        Line.FALSE,
    );

    const size = layout_output.size;
    const content_size = layout_output.content_size;

    const offset_main = total_offset_main.* +
        item.offset_main +
        dir.getMainStart(item.margin) + blk: {
        if (dir.getMainStart(item.inset)) |pos| {
            break :blk pos;
        } else if (dir.getMainEnd(item.inset)) |pos| {
            break :blk -pos;
        } else {
            break :blk 0.0;
        }
    };

    const offset_cross = total_offset_cross +
        item.offset_cross +
        line_offset_cross +
        dir.getCrossStart(item.margin) + blk: {
        if (dir.getCrossStart(item.inset)) |pos| {
            break :blk pos;
        } else if (dir.getCrossEnd(item.inset)) |pos| {
            break :blk -pos;
        } else {
            break :blk 0.0;
        }
    };

    if (dir.isRow()) {
        const baseline_offset_cross = total_offset_cross + item.offset_cross + dir.getCrossStart(item.margin);
        const inner_baseline = layout_output.first_baselines.y orelse size.y;
        item.baseline = baseline_offset_cross + inner_baseline;
    } else {
        const baseline_offset_main = total_offset_main.* + item.offset_main + dir.getMainStart(item.margin);
        const inner_baseline = layout_output.first_baselines.y orelse size.y;
        item.baseline = baseline_offset_main + inner_baseline;
    }

    const location: Point(f32) = if (dir.isRow())
        .{ .x = offset_main, .y = offset_cross }
    else
        .{ .x = offset_cross, .y = offset_main };

    const scrollbar_size: Point(f32) = .{
        .x = if (item.overflow.y == .scroll) item.scrollbar_width else 0.0,
        .y = if (item.overflow.x == .scroll) item.scrollbar_width else 0.0,
    };

    tree.setUnroundedLayout(item.node_id, .{
        .order = item.order,
        .content_size = content_size,
        .size = size,
        .scrollbar_size = scrollbar_size,
        .location = location,
        .padding = item.padding,
        .border = item.border,
        .margin = item.margin,
    });

    total_offset_main.* += item.offset_main + dir.sumMainAxis(item.margin) + dir.getMain(size);
    total_content_size.* = total_content_size.max(
        computeContentSizeContribution(location, size, content_size, item.overflow),
    );
}

/// Perform absolute layout on all absolutely positioned children.
pub fn performAbsoluteLayoutOnAbsoluteChildren(
    allocator: std.mem.Allocator,
    tree: *Tree,
    node_id: Node.NodeId,
    constants: *AlgoConstants,
) !Point(f32) {
    const container_width: f32 = constants.container_size.x;
    const container_height = constants.container_size.y;
    const inset_relative_size = constants.container_size.sub(constants.border.sumAxes()).sub(constants.scrollbar_gutter);

    var content_size: Point(f32) = Point(f32).ZERO;

    for (tree.getChildren(node_id).items, 0..) |child_id, order| {
        const child_style = tree.getComputedStyle(child_id);

        if (child_style.display.outside == .none or child_style.position != .absolute) {
            continue;
        }

        const overflow = child_style.overflow;
        const scrollbar_width = child_style.scrollbar_width;
        const aspect_ratio = child_style.aspect_ratio;
        const align_self = child_style.align_self orelse constants.align_items;
        const margin = child_style.margin.maybeResolve(container_width);
        const padding = child_style.padding.maybeResolve(container_width);
        const border = child_style.border.maybeResolve(container_width);
        const padding_border_sum = padding.sumAxes().add(border.sumAxes());

        // Resolve inset
        const left = child_style.inset.left.maybeResolve(inset_relative_size.x);
        const right = Maybe.add(child_style.inset.right.maybeResolve(inset_relative_size.x), constants.scrollbar_gutter.x);
        const top = child_style.inset.top.maybeResolve(inset_relative_size.y);

        const bottom = Maybe.add(child_style.inset.bottom.maybeResolve(inset_relative_size.y), constants.scrollbar_gutter.y);

        // Compute known dimensions from min/max/inherent size styles
        const style_size = child_style.size.maybeResolve(constants.container_size.intoOptional()).maybeApplyAspectRatio(aspect_ratio);
        const min_size = child_style.min_size
            .maybeResolve(constants.container_size.intoOptional())
            .maybeApplyAspectRatio(aspect_ratio)
            .orElse(padding_border_sum)
            .maybeMax(padding_border_sum);
        const max_size = child_style.max_size.maybeResolve(constants.container_size.intoOptional()).maybeApplyAspectRatio(aspect_ratio);

        var known_dimensions = style_size.maybeClamp(min_size, max_size);

        // Fill in width from left/right and reapply aspect ratio if:
        //  - Width is not already known
        //  - Item has both left and right inset properties set
        if (known_dimensions.x == null and left != null and right != null) {
            const new_width_raw = Maybe.sub(container_width, margin.left) - left.? - right.?;
            known_dimensions.x = @max(new_width_raw, 0.0);
            known_dimensions = known_dimensions.maybeApplyAspectRatio(aspect_ratio).maybeClamp(min_size, max_size);
        }

        // Fill in height from top/bottom and reapply aspect ratio if:
        // - Height is not already known
        // - Item has both top and bottom inset properties set
        if (known_dimensions.y == null and top != null and bottom != null) {
            const new_height_raw = Maybe.sub(container_height, margin.top) - top.? - bottom.?;
            known_dimensions.y = @max(new_height_raw, 0.0);
            known_dimensions = known_dimensions.maybeApplyAspectRatio(aspect_ratio).maybeClamp(min_size, max_size);
        }

        const layout_output = try performChildLayout(
            allocator,
            child_id,
            tree,
            known_dimensions,
            constants.node_inner_size,
            .{
                .x = .{
                    .definite = Maybe.clamp(container_width, min_size.x, max_size.x),
                },
                .y = .{
                    .definite = Maybe.clamp(container_height, min_size.y, max_size.y),
                },
            },
            .content_size,
            Line.FALSE,
        );

        const measured_size = layout_output.size;
        const final_size = known_dimensions.orElse(measured_size).maybeClamp(min_size, max_size);

        const non_auto_margin = margin.orZero();

        const free_space: Point(f32) = .{
            .x = @max(container_width - final_size.x - non_auto_margin.sumHorizontal(), 0),
            .y = @max(container_height - final_size.y - non_auto_margin.sumVertical(), 0),
        };

        // Expand auto margins to fill available space
        const resolved_margin: Rect(f32) = resolved_margin: {
            const auto_margin_size: Point(f32) = .{
                .x = blk: {
                    var auto_margin_count: f32 = 0;
                    if (margin.left == null) {
                        auto_margin_count += 1;
                    }
                    if (margin.right == null) {
                        auto_margin_count += 1;
                    }
                    if (auto_margin_count == 0) {
                        break :blk 0;
                    }
                    break :blk free_space.x / auto_margin_count;
                },
                .y = blk: {
                    var auto_margin_count: f32 = 0;
                    if (margin.top == null) {
                        auto_margin_count += 1;
                    }
                    if (margin.bottom == null) {
                        auto_margin_count += 1;
                    }
                    if (auto_margin_count == 0) {
                        break :blk 0;
                    }
                    break :blk free_space.y / auto_margin_count;
                },
            };

            break :resolved_margin .{
                .left = margin.left orelse auto_margin_size.x,
                .right = margin.right orelse auto_margin_size.x,
                .top = margin.top orelse auto_margin_size.y,
                .bottom = margin.bottom orelse auto_margin_size.y,
            };
        };

        // Determine flex-relative insets
        var start_main: ?f32 = left;
        var end_main: ?f32 = right;
        var start_cross: ?f32 = top;
        var end_cross: ?f32 = bottom;
        if (constants.is_column) {
            start_main = top;
            end_main = bottom;
            start_cross = left;
            end_cross = right;
        }

        const dir = constants.dir;
        // Apply main-axis alignment
        const offset_main = offset_main: {
            if (start_main) |start| {
                break :offset_main start + dir.getMainStart(constants.border) + dir.getMainStart(resolved_margin);
            }
            if (end_main) |end| {
                break :offset_main dir.getMain(constants.container_size) -
                    dir.getMainEnd(constants.border) -
                    dir.getMain(final_size) -
                    end -
                    dir.getMainEnd(resolved_margin);
            }
            // stretch is an invalid value for justify_content in the flexbox algorithm, so we
            // treat it as if it wasn't set (and thus we default to flex_start behaviour)

            const justify_content = constants.justify_content orelse .start;
            if (justify_content == .space_between or
                justify_content == .start or
                (justify_content == .stretch and !constants.is_wrap_reverse) or
                (justify_content == .flex_start and !constants.is_wrap_reverse) or
                (justify_content == .flex_end and constants.is_wrap_reverse))
            {
                break :offset_main dir.getMainStart(constants.content_box_inset) + dir.getMainStart(resolved_margin);
            }

            if (justify_content == .end or
                (justify_content == .flex_end and !constants.is_wrap_reverse) or
                (justify_content == .flex_start and constants.is_wrap_reverse) or
                (justify_content == .stretch and constants.is_wrap_reverse))
            {
                break :offset_main dir.getMain(constants.container_size) -
                    dir.getMainEnd(constants.content_box_inset) -
                    dir.getMain(final_size) -
                    dir.getMainEnd(resolved_margin);
            }

            if (justify_content == .space_evenly or justify_content == .space_around or justify_content == .center) {
                break :offset_main (dir.getMain(constants.container_size) +
                    dir.getMainStart(constants.content_box_inset) -
                    dir.getMainEnd(constants.content_box_inset) -
                    dir.getMain(final_size) +
                    dir.getMainStart(resolved_margin) -
                    dir.getMainEnd(resolved_margin)) / 2.0;
            }
            unreachable;
        };

        // Apply cross-axis alignment
        const offset_cross = offset_cross: {
            if (start_cross) |start| {
                break :offset_cross start + dir.getCrossStart(constants.border) + dir.getCrossStart(resolved_margin);
            }
            if (end_cross) |end| {
                break :offset_cross dir.getCross(constants.container_size) -
                    dir.getCrossEnd(constants.border) -
                    dir.getCross(final_size) -
                    end -
                    dir.getCrossEnd(resolved_margin);
            }

            // stretch alignment does not apply to absolutely positioned items
            // See "Example 3" at https://www.w3.org/TR/css-flexbox-1/#abspos-items
            // Note: stretch should be flex_start not start when we support both
            if (align_self == .start or
                (!constants.is_wrap_reverse and (align_self == .baseline or align_self == .stretch or align_self == .flex_start)) or
                (constants.is_wrap_reverse and align_self == .flex_end))
            {
                break :offset_cross dir.getCrossStart(constants.content_box_inset) + dir.getCrossStart(resolved_margin);
            }

            if (align_self == .end or
                (constants.is_wrap_reverse and (align_self == .baseline or align_self == .stretch or align_self == .flex_start)) or
                (!constants.is_wrap_reverse and align_self == .flex_end))
            {
                break :offset_cross dir.getCross(constants.container_size) -
                    dir.getCrossEnd(constants.content_box_inset) -
                    dir.getCross(final_size) -
                    dir.getCrossEnd(resolved_margin);
            }

            if (align_self == .center) {
                break :offset_cross (dir.getCross(constants.container_size) +
                    dir.getCrossStart(constants.content_box_inset) -
                    dir.getCrossEnd(constants.content_box_inset) -
                    dir.getCross(final_size) +
                    dir.getCrossStart(resolved_margin) -
                    dir.getCrossEnd(resolved_margin)) / 2.0;
            }
            unreachable;
        };

        const location: Point(f32) = if (constants.is_row)
            .{ .x = offset_main, .y = offset_cross }
        else
            .{ .x = offset_cross, .y = offset_main };

        const scrollbar_size: Point(f32) = .{
            .x = if (overflow.y == .scroll) scrollbar_width else 0.0,
            .y = if (overflow.x == .scroll) scrollbar_width else 0.0,
        };

        tree.setUnroundedLayout(child_id, .{
            .order = @as(u32, @intCast(order)),
            .size = final_size,
            .content_size = layout_output.content_size,
            .scrollbar_size = scrollbar_size,
            .location = location,
            .padding = padding,
            .border = border,
            .margin = resolved_margin,
        });

        const size_content_size_contribution = .{
            .x = if (overflow.x == .visible) @max(final_size.x, layout_output.content_size.x) else final_size.x,
            .y = if (overflow.y == .visible) @max(final_size.y, layout_output.content_size.y) else final_size.y,
        };

        if (size_content_size_contribution.x > 0.0 and size_content_size_contribution.y > 0.0) {
            const content_size_contribution: Point(f32) = .{
                .x = location.x + size_content_size_contribution.x,
                .y = location.y + size_content_size_contribution.y,
            };

            content_size = content_size.max(content_size_contribution);
        }
    }
    return content_size;
}
