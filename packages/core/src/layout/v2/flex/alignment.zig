const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");
const computeAlignmentOffset = @import("computeAlignmentOffset.zig").computeAlignmentOffset;

/// Distribute any remaining free space.
///
/// # [9.5. Main-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#main-alignment)
///
/// - [**Distribute any remaining free space**](https://www.w3.org/TR/css-flexbox-1/#algo-main-align). For each flex line:
///
///     1. If the remaining free space is positive and at least one main-axis margin on this line is `auto`, distribute the free space equally among these margins.
///        Otherwise, set all `auto` margins to zero.
///
///     2. Align the items along the main-axis per `justify-content`.
pub fn distributeRemainingFreeSpace(
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !void {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    for (lines.items) |*line| {
        const total_main_axis_gap = types.FlexLine.sumAxisGaps(
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
            if (dir.getMainStart(bool, child.margin_is_auto)) {
                num_auto_margins += 1;
            }

            if (dir.getMainEnd(bool, child.margin_is_auto)) {
                num_auto_margins += 1;
            }
        }

        if (free_space > 0.0 and num_auto_margins > 0) {
            const margin = free_space / @as(f32, @floatFromInt(num_auto_margins));

            for (line.items) |*child| {
                if (dir.getMainStart(bool, child.margin_is_auto)) {
                    if (constants.is_row) {
                        child.margin.left = margin;
                    } else {
                        child.margin.top = margin;
                    }
                }

                if (dir.getMainEnd(bool, child.margin_is_auto)) {
                    if (constants.is_row) {
                        child.margin.right = margin;
                    } else {
                        child.margin.bottom = margin;
                    }
                }
            }
        } else {
            const num_items = line.items.len;
            const layout_reverse = constants.dir.isReverse();
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
pub fn resolveCrossAxisAutoMargins(
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !void {
    // const dir = constants.dir;
    const dir = flexItems.DirectionHelper.init(constants.dir);
    for (lines.items) |*line| {
        const line_cross_size = line.cross_size;
        var max_baseline: f32 = 0.0;
        for (line.items) |child| {
            max_baseline = @max(max_baseline, child.baseline);
        }

        for (line.items) |*child| {
            const free_space = line_cross_size - dir.getCross(child.outer_target_size);
            if (dir.getCrossStart(bool, child.margin_is_auto) and dir.getCrossEnd(bool, child.margin_is_auto)) {
                if (constants.is_row) {
                    child.margin.top = free_space / 2.0;
                    child.margin.bottom = free_space / 2.0;
                } else {
                    child.margin.left = free_space / 2.0;
                    child.margin.right = free_space / 2.0;
                }
            } else if (dir.getCrossStart(bool, child.margin_is_auto)) {
                if (constants.is_row) {
                    child.margin.top = free_space;
                } else {
                    child.margin.left = free_space;
                }
            } else if (dir.getCrossEnd(bool, child.margin_is_auto)) {
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
    // const dir = flexItems.DirectionHelper.init(constants.dir);

    // for (lines.items) |*line| {
    //     for (line.items) |*item| {
    //         const cross_size = dir.getCross(item.target_size);
    //         const line_cross_size = line.cross_size;
    //         const non_auto_cross_margin = if (dir.is_row)
    //             item.margin.sumVertical()
    //         else
    //             item.margin.sumHorizontal();

    //         const free_space = line_cross_size - cross_size - non_auto_cross_margin;

    //         // Count auto margins in cross axis
    //         const auto_margin_count = if (dir.is_row)
    //             @as(f32, @floatFromInt(@intFromBool(item.margin_is_auto.top == 1.0) + @intFromBool(item.margin_is_auto.bottom == 1.0)))
    //         else
    //             @as(f32, @floatFromInt(@intFromBool(item.margin_is_auto.left == 1.0) + @intFromBool(item.margin_is_auto.right == 1.0)));

    //         if (auto_margin_count > 0 and free_space > 0) {
    //             const auto_margin_size = free_space / auto_margin_count;

    //             if (dir.is_row) {
    //                 if (item.margin_is_auto.top == 1.0) item.margin.top = auto_margin_size;
    //                 if (item.margin_is_auto.bottom == 1.0) item.margin.bottom = auto_margin_size;
    //             } else {
    //                 if (item.margin_is_auto.left == 1.0) item.margin.left = auto_margin_size;
    //                 if (item.margin_is_auto.right == 1.0) item.margin.right = auto_margin_size;
    //             }
    //         }
    //     }
    // }
}

/// Align all flex items along the cross-axis.
///
/// # [9.6. Cross-Axis Alignment](https://www.w3.org/TR/css-flexbox-1/#cross-alignment)
///
/// - [**Align all flex items along the cross-axis**](https://www.w3.org/TR/css-flexbox-1/#algo-cross-align) per `align-self`,
///     if neither of the item's cross-axis margins are `auto`.
// #[inline]
pub fn alignFlexItemsAlongCrossAxis(
    child: *types.FlexItem,
    free_space: f32,
    max_baseline: f32,
    constants: *types.AlgoConstants,
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
    lines: *std.ArrayList(types.FlexLine),
    node_size: mod.CSSMaybePoint,
    constants: *types.AlgoConstants,
) f32 {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    const total_cross_axis_gap = types.FlexLine.sumAxisGaps(
        lines.items.len,
        dir.getCross(constants.gap),
    );
    var total_line_cross_size: f32 = 0.0;
    for (lines.items) |line| {
        total_line_cross_size += line.cross_size;
    }

    const padding_border_sum: f32 = dir.sumCrossAxis(constants.content_box_inset);
    const cross_scrollbar_gutter: f32 = dir.getCross(constants.scrollbar_gutter);
    const min_cross_size: ?f32 = dir.getCrossOptional(constants.min_size);
    const max_cross_size: ?f32 = dir.getCrossOptional(constants.max_size);
    const outer_container_size: f32 = blk: {
        const cross_from_node = dir.getCrossOptional(node_size);
        var out: f32 = cross_from_node orelse total_line_cross_size + total_cross_axis_gap + padding_border_sum;
        out = mod.math.maybeClamp(out, min_cross_size, max_cross_size).?;
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
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
    total_line_cross_size: f32,
) void {
    // [https://www.w3.org/TR/css-flexbox-1/#align-content-property]
    // "Note, this property has no effect on a single-line flex container"
    if (!constants.is_wrap) {
        return;
    }
    const num_lines = lines.items.len;
    const dir = flexItems.DirectionHelper.init(constants.dir);
    const gap = dir.getCross(constants.gap);
    const align_content_mode: css_types.AlignContent = constants.align_content;
    const total_cross_axis_gap: f32 = types.FlexLine.sumAxisGaps(num_lines, gap);
    const free_space: f32 = dir.getCross(constants.inner_container_size) - total_line_cross_size - total_cross_axis_gap;

    for (lines.items, 0..) |*line, i| {
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
