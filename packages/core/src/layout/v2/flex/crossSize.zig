const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");
const measureChildSize = @import("measureChildSize.zig").measureChildSize;

/// Determine the hypothetical cross size of each item.
pub fn determineHypotheticalCrossSize(
    context: *mod.LayoutContext,
    line: *types.FlexLine,
    constants: *types.AlgoConstants,
    available_space: mod.constants.AvailableSpacePoint,
) !void {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    for (line.items) |*child| {
        const padding_border_sum: f32 = dir.sumCrossAxis(child.padding.add(child.border));

        const child_known_main: mod.constants.AvailableSpace = .{ .definite = dir.getMain(constants.container_size) };
        const child_cross: ?f32 = mod.math.maybeMax(
            mod.math.maybeClamp(
                dir.getCrossOptional(child.size),
                dir.getCrossOptional(child.min_size),
                dir.getCrossOptional(child.max_size),
            ),
            padding_border_sum,
        );
        const child_available_cross: mod.constants.AvailableSpace = dir.getCrossAvailableSpace(available_space).maybeClamp(
            dir.getCrossOptional(child.min_size),
            dir.getCrossOptional(child.max_size),
        ).maybeMax(padding_border_sum);
        const child_inner_cross: f32 = child_cross orelse blk: {
            const size = try measureChildSize(
                context,
                child.node_id,
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
                mod.constants.AbsoluteAxis.fromFlexDirection(constants.dir).otherAxis(),
                .{ .start = false, .end = false },
            );
            break :blk @max(
                mod.math.maybeClamp(
                    size,
                    dir.getCrossOptional(child.min_size),
                    dir.getCrossOptional(child.max_size),
                ).?,
                padding_border_sum,
            );
        };
        const child_outer_cross = child_inner_cross + dir.sumCrossAxis(child.margin);

        child.hypothetical_inner_size = dir.setCross(child.hypothetical_inner_size, child_inner_cross);
        child.hypothetical_outer_size = dir.setCross(child.hypothetical_outer_size, child_outer_cross);
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
///         **Note that if CSS 2.1's definition of min/max-width/height applied more generally, this behavior would fall out automatically**.pub fn calculateCrossSize(
pub fn calculateCrossSize(
    lines: *std.ArrayList(types.FlexLine),
    node_size: mod.CSSMaybePoint,
    constants: *types.AlgoConstants,
) !void {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    // Note: AlignContent::space_evenly and AlignContent::space_around behave like AlignContent::stretch when there is only
    // a single flex line in the container. See: https://www.w3.org/TR/css-flexbox-1/#align-content-property
    // Also: align_content is ignored entirely (and thus behaves like stretch) when `flex_wrap` is set to `nowrap`.

    if (lines.items.len == 1 and
        dir.getCrossOptional(node_size) != null and
        (!constants.is_wrap or
            constants.align_content == .stretch or
            constants.align_content == .space_evenly or
            constants.align_content == .space_around))
    {
        const cross_axis_padding_border = dir.sumCrossAxis(constants.content_box_inset);
        const cross_min_size = dir.getCrossOptional(constants.min_size);
        const cross_max_size = dir.getCrossOptional(constants.max_size);

        var line = lines.items[0];
        var cross_size = dir.getCrossOptional(node_size);

        cross_size = mod.math.maybeClamp(cross_size, cross_min_size, cross_max_size);
        cross_size = mod.math.maybeSub(cross_size, cross_axis_padding_border);
        cross_size = mod.math.maybeMax(cross_size, 0.0);
        line.cross_size = cross_size orelse 0.0;
    } else {
        for (lines.items) |*line| {
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
                    !dir.getCrossStart(bool, child.margin_is_auto) and
                    !dir.getCrossEnd(bool, child.margin_is_auto))
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
            const cross_min_size = dir.getCrossOptional(constants.min_size);
            const cross_max_size = dir.getCrossOptional(constants.max_size);
            var line = lines.items[0];
            line.cross_size = mod.math.maybeClamp(
                line.cross_size,
                mod.math.maybeSub(cross_min_size, cross_axis_padding_border),
                mod.math.maybeSub(cross_max_size, cross_axis_padding_border),
            ).?;
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
    lines: *std.ArrayList(types.FlexLine),
    node_size: mod.CSSMaybePoint,
    constants: *types.AlgoConstants,
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
            out = mod.math.maybeClamp(out, cross_min_size, cross_max_size);
            out = mod.math.maybeSub(out, cross_axis_padding_border);
            break :blk mod.math.maybeMax(out, 0.0) orelse 0.0;
        };

        const total_cross_axis_gap = types.FlexLine.sumAxisGaps(
            lines.items.len,
            dir.getCross(constants.gap),
        );

        var lines_total_cross: f32 = total_cross_axis_gap;
        for (lines.items) |line| {
            lines_total_cross += line.cross_size;
        }

        if (lines_total_cross < container_min_inner_cross) {
            const remaining = container_min_inner_cross - lines_total_cross;
            const addition = remaining / @as(f32, @floatFromInt(lines.items.len));
            for (lines.items) |*line| {
                line.cross_size += addition;
            }
        }
    }
}

/// Determine the used cross size of each flex item.
pub fn determineUsedCrossSize(
    context: *mod.LayoutContext,
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !void {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    for (lines.items) |*line| {
        const line_cross_size: f32 = line.cross_size;

        for (line.items) |*child| {
            const size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child.node_id, .size);
            const max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child.node_id, .max_size);
            if (child.align_self == .stretch and
                !dir.getCrossStart(bool, child.margin_is_auto) and
                !dir.getCrossEnd(bool, child.margin_is_auto) and
                dir.getCrossByType(css_types.LengthPercentageAuto, size) == .auto)
            {
                // for some reason this particular usage of max_width is an exception to the rule that max_width's transfer
                // using the aspect_ratio (if set). both chrome and firefox agree on this. and reading the spec, it seems like
                // a reasonable interpretation. although it seems to me that the spec *should* apply aspect_ratio here.
                const max_size_ignoring_aspect_ratio = max_size.maybeResolve(constants.node_inner_size);
                const cross = mod.math.maybeClamp(
                    line_cross_size - dir.sumCrossAxis(child.margin),
                    dir.getCrossOptional(child.min_size),
                    dir.getCrossOptional(max_size_ignoring_aspect_ratio),
                ).?;
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
