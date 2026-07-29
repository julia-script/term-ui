const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");
const measureChildSize = @import("measureChildSize.zig").measureChildSize;

/// Determine the container's main size (if not already known)
pub fn determineContainerMainSize(
    context: *mod.LayoutContext,
    available_space: mod.constants.AvailableSpacePoint,
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !void {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    const main_content_box_inset: f32 = dir.sumMainAxis(constants.content_box_inset);
    const main_available_space = if (dir.is_row) available_space.x else available_space.y;

    const outer_main_size: f32 = dir.getMainOptional(constants.node_outer_size) orelse blk: {
        switch (main_available_space) {
            .definite => |definite| {
                var longest_line_length: f32 = 0.0;
                for (lines.items) |*line| {
                    var line_size: f32 = line.sumAxisGaps(dir.getMain(constants.gap));

                    for (line.items) |*child| {
                        const padding_border_sum = dir.sumMainAxis(child.padding) + dir.sumMainAxis(child.border);
                        line_size += @max(child.flex_basis + dir.sumMainAxis(child.margin), padding_border_sum);
                    }

                    longest_line_length = @max(longest_line_length, line_size);
                }

                const size = longest_line_length + main_content_box_inset;

                if (lines.items.len > 1) {
                    break :blk @max(size, definite);
                }
                break :blk size;
            },
            .min_content => {
                if (constants.is_wrap) {
                    var longest_line_length: f32 = 0.0;
                    for (lines.items) |*line| {
                        var line_size = line.sumAxisGaps(dir.getMain(constants.gap));

                        for (line.items) |*child| {
                            const padding_border_sum = dir.sumMainAxis(child.padding) + dir.sumMainAxis(child.border);
                            line_size += @max(child.flex_basis + dir.sumMainAxis(child.margin), padding_border_sum);
                        }

                        longest_line_length = @max(longest_line_length, line_size);
                    }

                    break :blk longest_line_length + main_content_box_inset;
                }

                // Fall through to max_content calculation
                var main_size: f32 = 0.0;
                for (lines.items) |*line| {
                    var item_main_size_sum: f32 = 0.0;
                    for (line.items) |*item| {
                        item_main_size_sum += try computeContentContribution(context, item, constants, available_space, &dir);
                    }
                    main_size = @max(main_size, item_main_size_sum + line.sumAxisGaps(dir.getMain(constants.gap)));
                }
                break :blk main_size + main_content_box_inset;
            },
            .max_content => {
                var main_size: f32 = 0.0;
                for (lines.items) |*line| {
                    var item_main_size_sum: f32 = 0.0;
                    for (line.items) |*item| {
                        item_main_size_sum += try computeContentContribution(context, item, constants, available_space, &dir);
                    }
                    main_size = @max(main_size, item_main_size_sum + line.sumAxisGaps(dir.getMain(constants.gap)));
                }
                break :blk main_size + main_content_box_inset;
            },
        }
    };

    const inner_main_size = outer_main_size - main_content_box_inset;
    constants.inner_container_size = if (dir.is_row)
        mod.CSSPoint{ .x = inner_main_size, .y = constants.inner_container_size.y }
    else
        mod.CSSPoint{ .x = constants.inner_container_size.x, .y = inner_main_size };

    constants.container_size = if (dir.is_row)
        mod.CSSPoint{ .x = outer_main_size, .y = constants.container_size.y }
    else
        mod.CSSPoint{ .x = constants.container_size.x, .y = outer_main_size };

    constants.node_inner_size = if (dir.is_row)
        mod.CSSMaybePoint{ .x = inner_main_size, .y = constants.node_inner_size.y }
    else
        mod.CSSMaybePoint{ .x = constants.node_inner_size.x, .y = inner_main_size };

    constants.node_outer_size = if (dir.is_row)
        mod.CSSMaybePoint{ .x = outer_main_size, .y = constants.node_outer_size.y }
    else
        mod.CSSMaybePoint{ .x = constants.node_outer_size.x, .y = outer_main_size };
}

fn computeContentContribution(
    context: *mod.LayoutContext,
    item: *types.FlexItem,
    constants: *types.AlgoConstants,
    available_space: mod.constants.AvailableSpacePoint,
    dir: *const flexItems.DirectionHelper,
) !f32 {
    const style_min: ?f32 = dir.getMainOptional(item.min_size);
    const style_preferred: ?f32 = dir.getMainOptional(item.size);
    const style_max: ?f32 = dir.getMainOptional(item.max_size);

    const clamping_basis = mod.math.maybeMax(item.flex_basis, style_preferred) orelse item.flex_basis;
    const flex_basis_min: ?f32 = if (item.flex_shrink == 0.0) clamping_basis else null;
    const flex_basis_max: ?f32 = if (item.flex_grow == 0.0) clamping_basis else null;

    const min_main_size = @max(
        mod.math.maybeMax(style_min, flex_basis_min) orelse item.resolved_minimum_main_size,
        item.resolved_minimum_main_size,
    );

    const max_main_size = mod.math.maybeMin(style_max, flex_basis_max) orelse std.math.inf(f32);

    // If the clamping values are such that max <= min, then we can avoid expensive computation
    if (style_preferred) |pref| {
        if (max_main_size <= min_main_size or max_main_size <= pref) {
            return std.math.clamp(pref, min_main_size, max_main_size) + dir.sumMainAxis(item.margin);
        }
    }

    if (max_main_size <= min_main_size) {
        return min_main_size + dir.sumMainAxis(item.margin);
    }

    // Compute the min- or max-content size
    const cross_axis_parent_size: ?f32 = dir.getCrossOptional(constants.node_inner_size);
    const cross_axis_margin_sum: f32 = dir.sumCrossAxis(constants.margin);
    const child_min_cross: ?f32 = if (dir.getCrossOptional(item.min_size)) |min| min + cross_axis_margin_sum else null;
    const child_max_cross: ?f32 = if (dir.getCrossOptional(item.max_size)) |max| max + cross_axis_margin_sum else null;

    const cross_axis_available_space: mod.constants.AvailableSpace = blk: {
        const cross_available = if (dir.is_row) available_space.y else available_space.x;
        switch (cross_available) {
            .definite => |d| break :blk .{
                .definite = mod.math.maybeClamp(
                    cross_axis_parent_size orelse d,
                    child_min_cross,
                    child_max_cross,
                ) orelse d,
            },
            .min_content => break :blk .min_content,
            .max_content => break :blk .max_content,
        }
    };

    const child_available_space = mod.constants.AvailableSpacePoint{
        .x = if (dir.is_row)
            (if (available_space.x == .min_content) .min_content else .max_content)
        else
            cross_axis_available_space,
        .y = if (dir.is_row)
            cross_axis_available_space
        else
            (if (available_space.y == .min_content) .min_content else .max_content),
    };

    const child_parent_size = mod.CSSMaybePoint{
        .x = if (dir.is_row) null else cross_axis_parent_size,
        .y = if (dir.is_row) cross_axis_parent_size else null,
    };

    var child_layout = try mod.performChildLayout(
        context,
        item.node_id,
        mod.CSSMaybePoint.NULL,
        child_parent_size,
        child_available_space,
        .inherent_size,
        .{ .start = false, .end = false },
    );
    defer child_layout.deinit();

    const content_main_size = (dir.getMainOptional(mod.CSSMaybePoint{
        .x = child_layout.size.x,
        .y = child_layout.size.y,
    }) orelse 0) + dir.sumMainAxis(item.margin);

    // Asymmetrical behavior for row vs column containers
    if (dir.is_row) {
        return mod.math.maybeClamp(content_main_size, min_main_size, max_main_size) orelse content_main_size;
    }

    const main_content_box_inset = dir.sumMainAxis(constants.content_box_inset);
    return @max(
        mod.math.maybeClamp(
            @max(content_main_size, item.flex_basis),
            style_min,
            style_max,
        ) orelse @max(content_main_size, item.flex_basis),
        main_content_box_inset,
    );
}

/// Resolve the flexible lengths of all flex items to find their target main sizes.
pub fn resolveFlexibleLengths(
    context: *mod.LayoutContext,
    line: *types.FlexLine,
    constants: *types.AlgoConstants,
    original_gap: mod.CSSPoint,
) !void {
    const dir = flexItems.DirectionHelper.init(constants.dir);
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
    const growing = used_flex_factor < dir.getMainOptional(constants.node_inner_size) orelse 0.0;
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
    const initial_free_space = mod.math.maybeSub(dir.getMainOptional(constants.node_inner_size), initial_used_space) orelse 0.0;

    // 4. Loop
    var unfrozen: std.ArrayList(*types.FlexItem) = .empty;
    try unfrozen.ensureTotalCapacity(context.allocator, line.items.len);
    defer unfrozen.deinit(context.allocator);
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

        const free_space: f32 = blk: {
            if (growing and sum_flex_grow < 1.0) {
                const a: f32 = initial_free_space * sum_flex_grow - total_main_axis_gap;
                const b: ?f32 = mod.math.maybeSub(dir.getMainOptional(constants.node_inner_size), used_space);
                break :blk mod.math.maybeMin(a, b).?;
            }
            if (shrinking and sum_flex_shrink < 1.0) {
                const a: f32 = initial_free_space * sum_flex_grow - total_main_axis_gap;
                const b: ?f32 = mod.math.maybeSub(dir.getMainOptional(constants.node_inner_size), used_space);
                break :blk mod.math.maybeMax(a, b).?;
            }

            break :blk mod.math.maybeSub(dir.getMainOptional(constants.node_inner_size), used_space) orelse used_flex_factor - used_space;
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
            const resolved_min_main: f32 = child.resolved_minimum_main_size;
            const max_main = dir.getMainOptional(child.max_size);
            const clamped = @max(mod.math.maybeClamp(dir.getMain(child.target_size), resolved_min_main, max_main).?, 0);
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
