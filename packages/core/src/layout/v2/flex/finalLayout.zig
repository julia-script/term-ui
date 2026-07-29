const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");
const computeContentSizeContribution = @import("computeContentSizeContribution.zig").computeContentSizeContribution;

/// Do a final layout pass and gather the resulting layouts
pub fn finalLayoutPass(
    context: *mod.LayoutContext,
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !mod.CSSPoint {
    const dir = flexItems.DirectionHelper.init(constants.dir);
    var total_offset_cross: f32 = dir.getCrossStart(f32, constants.content_box_inset);
    var content_size: mod.CSSPoint = .{ .x = 0.0, .y = 0.0 };
    if (constants.is_wrap_reverse) {
        // var iter = mod.Iter.sliceReverse(lines.items);
        var i: usize = lines.items.len - 1;
        while (i > 0) : (i -= 1) {
            const line = &lines.items[i];
            try calculateLayoutLine(
                context,
                line,
                &total_offset_cross,
                &content_size,
                constants.container_size,
                constants.node_inner_size,
                constants.content_box_inset,
                constants.dir,
            );
        }
    } else {
        var i: usize = 0;
        while (i < lines.items.len) : (i += 1) {
            const line = &lines.items[i];
            try calculateLayoutLine(
                context,
                line,
                &total_offset_cross,
                &content_size,
                constants.container_size,
                constants.node_inner_size,
                constants.content_box_inset,
                constants.dir,
            );
        }
    }

    return content_size;
}
/// Calculates the layout line
pub fn calculateLayoutLine(
    context: *mod.LayoutContext,
    line: *types.FlexLine,
    total_offset_cross: *f32,
    content_size: *mod.CSSPoint,
    container_size: mod.CSSPoint,
    node_inner_size: mod.CSSMaybePoint,
    padding_border: mod.CSSRect,
    direction: css_types.FlexDirection,
) !void {
    const dir = direction;
    var total_offset_main: f32 = dir.getMainStart(padding_border);
    const line_offset_cross: f32 = line.offset_cross;

    if (dir.isReverse()) {
        var i: usize = line.items.len - 1;
        while (i > 0) : (i -= 1) {
            const item = &line.items[i];
            try calculateFlexItem(
                context,
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
        var i: usize = 0;
        while (i < line.items.len) : (i += 1) {
            const item = &line.items[i];
            try calculateFlexItem(
                context,
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
    context: *mod.LayoutContext,
    item: *types.FlexItem,
    total_offset_main: *f32,
    total_offset_cross: f32,
    line_offset_cross: f32,
    total_content_size: *mod.CSSPoint,
    container_size: mod.CSSPoint,
    node_inner_size: mod.CSSMaybePoint,
    css_dir: css_types.FlexDirection,
) !void {
    const dir = flexItems.DirectionHelper.init(css_dir);
    var layout_output: mod.LayoutResult = try mod.performChildLayout(
        context,
        item.node_id,
        item.target_size.intoOptional(),
        node_inner_size,
        .{
            .x = .{ .definite = container_size.x },
            .y = .{ .definite = container_size.y },
        },
        .content_size,
        .{ .start = false, .end = false },
    );
    defer layout_output.deinit();

    const size = layout_output.size;
    const content_size = layout_output.content_size;

    const offset_main = total_offset_main.* +
        item.offset_main +
        dir.getMainStart(f32, item.margin) + blk: {
        if (dir.getMainStart(?f32, item.inset)) |pos| {
            break :blk pos;
        } else if (dir.getMainEnd(?f32, item.inset)) |pos| {
            break :blk -pos;
        } else {
            break :blk 0.0;
        }
    };

    const offset_cross = total_offset_cross +
        item.offset_cross +
        line_offset_cross +
        dir.getCrossStart(f32, item.margin) + blk: {
        if (dir.getCrossStart(?f32, item.inset)) |pos| {
            break :blk pos;
        } else if (dir.getCrossEnd(?f32, item.inset)) |pos| {
            break :blk -pos;
        } else {
            break :blk 0.0;
        }
    };

    if (css_dir.isRow()) {
        const baseline_offset_cross = total_offset_cross + item.offset_cross + dir.getCrossStart(f32, item.margin);
        const inner_baseline = layout_output.first_baselines.y orelse size.y;
        item.baseline = baseline_offset_cross + inner_baseline;
    } else {
        const baseline_offset_main = total_offset_main.* + item.offset_main + dir.getMainStart(f32, item.margin);
        const inner_baseline = layout_output.first_baselines.y orelse size.y;
        item.baseline = baseline_offset_main + inner_baseline;
    }

    const location: mod.CSSPoint = if (css_dir.isRow())
        .{ .x = offset_main, .y = offset_cross }
    else
        .{ .x = offset_cross, .y = offset_main };

    const scrollbar_size: mod.CSSPoint = .{
        .x = if (item.overflow.y == .scroll) item.scrollbar_width else 0.0,
        .y = if (item.overflow.x == .scroll) item.scrollbar_width else 0.0,
    };

    try context.setBox(item.node_id, .{
        .content_size = content_size,
        .size = size,
        .scrollbar_size = scrollbar_size,
        .location = location,
        .padding = item.padding,
        .border = item.border,
        .margin = item.margin,
    }, layout_output.line_boxes);

    total_offset_main.* += item.offset_main + dir.sumMainAxis(item.margin) + dir.getMain(size);
    total_content_size.* = total_content_size.max(
        computeContentSizeContribution(location, size, content_size, item.overflow),
    );
}

/// Calculate baselines for flex items (simplified version)
pub fn calculateChildrenBaselines(
    context: *mod.LayoutContext,
    node_size: mod.CSSMaybePoint,
    available_space: mod.constants.AvailableSpacePoint,
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !void {
    // Only compute baselines for flex rows because we only support baseline alignment in the cross axis
    // where that axis is also the inline axis
    // TODO: this may need revisiting if/when we support vertical writing modes

    if (!constants.is_row) {
        return;
    }

    for (lines.items) |*line| {
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

            var measured_size_and_baselines = try mod.performChildLayout(
                context,
                child.node_id,
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
                .{ .start = false, .end = false },
            );
            defer measured_size_and_baselines.deinit();

            const baseline = measured_size_and_baselines.first_baselines.y;
            const height = measured_size_and_baselines.size.y;
            child.baseline = (baseline orelse height) + child.margin.top;
        }
    }
}

/// Perform absolute layout on absolutely positioned children
pub fn performAbsoluteLayoutOnAbsoluteChildren(
    context: *mod.LayoutContext,
    l_node_id: mod.LayoutNode.Id,
    constants: *types.AlgoConstants,
) !mod.CSSPoint {
    const container_width: f32 = constants.container_size.x;
    const container_height = constants.container_size.y;
    const inset_relative_size = constants.container_size.sub(constants.border.sumAxes()).sub(constants.scrollbar_gutter);
    context.info(l_node_id, "inset_relative_size: {}", .{inset_relative_size});

    var content_size: mod.CSSPoint = .{ .x = 0.0, .y = 0.0 };

    for (context.getChildren(l_node_id)) |child_id| {
        const child_css_display = context.getStyleValue(css_types.Display, child_id, .display);
        const child_css_position = context.getStyleValue(css_types.Position, child_id, .position);

        context.info(child_id, "child_css_display: {any}", .{child_css_display});
        context.info(child_id, "child_css_position: {any}", .{child_css_position});
        if (child_css_display.outside == .none or child_css_position != .absolute) {
            continue;
        }
        const overflow = context.getStyleValue(css_types.OverflowPoint, child_id, .overflow);
        const scrollbar_width = context.getStyleValue(f32, child_id, .scrollbar_width);
        const aspect_ratio = context.getStyleValue(?f32, child_id, .aspect_ratio);
        const align_self = context.getStyleValue(?css_types.AlignSelf, child_id, .align_self) orelse constants.align_items;
        const css_margin = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .margin);
        const css_padding = context.getStyleValue(css_types.LengthPercentageRect, child_id, .padding);
        const css_border = context.getStyleValue(css_types.LengthPercentageRect, child_id, .border_width);
        const css_inset = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .inset);
        const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .size);
        const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .min_size);
        const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .max_size);

        // const overflow = child_style.overflow;
        // const scrollbar_width = child_style.scrollbar_width;
        // const aspect_ratio = child_style.aspect_ratio;
        // const align_self = child_style.align_self orelse constants.align_items;
        const margin = (mod.math.maybeResolveRect(css_margin, container_width));
        const padding = mod.math.unwrapRect(mod.math.maybeResolveRect(css_padding, container_width));
        const border = mod.math.unwrapRect(mod.math.maybeResolveRect(css_border, container_width));
        const padding_border_sum: mod.CSSPoint = padding.sumAxes().add(border.sumAxes());

        // Resolve inset
        const left = mod.math.maybeResolve(css_inset.left, inset_relative_size.x);
        const right = mod.math.maybeAdd(mod.math.maybeResolve(css_inset.right, inset_relative_size.x), constants.scrollbar_gutter.x);
        const top = mod.math.maybeResolve(css_inset.top, inset_relative_size.y);

        const bottom = mod.math.maybeAdd(mod.math.maybeResolve(css_inset.bottom, inset_relative_size.y), constants.scrollbar_gutter.y);

        // Compute known dimensions from min/max/inherent size styles
        var style_size = mod.math.maybeResolveOnPoint(css_size, constants.container_size.intoOptional());
        style_size = mod.math.maybeApplyAspectRatio(style_size, aspect_ratio);

        const min_size: mod.CSSPoint = blk: {
            var maybe_min_size = mod.math.maybeResolveOnPoint(css_min_size, constants.container_size.intoOptional());
            maybe_min_size = mod.math.maybeApplyAspectRatio(maybe_min_size, aspect_ratio);
            var concrete_min_size = mod.math.orElse(maybe_min_size, padding_border_sum);
            concrete_min_size = concrete_min_size.max(padding_border_sum);
            break :blk concrete_min_size;
        };

        var max_size = mod.math.maybeResolveOnPoint(css_max_size, constants.container_size.intoOptional());
        max_size = mod.math.maybeApplyAspectRatio(max_size, aspect_ratio);

        var known_dimensions = style_size.maybeClamp(min_size, max_size);

        // Fill in width from left/right and reapply aspect ratio if:
        //  - Width is not already known
        //  - Item has both left and right inset properties set
        if (known_dimensions.x == null and left != null and right != null) {
            const new_width_raw = mod.math.maybeSub(container_width, margin.left).? - left.? - right.?;
            known_dimensions.x = @max(new_width_raw, 0.0);
            known_dimensions = known_dimensions.maybeApplyAspectRatio(aspect_ratio).maybeClamp(min_size, max_size);
        }

        // Fill in height from top/bottom and reapply aspect ratio if:
        // - Height is not already known
        // - Item has both top and bottom inset properties set
        if (known_dimensions.y == null and top != null and bottom != null) {
            const new_height_raw = mod.math.maybeSub(container_height, margin.top).? - top.? - bottom.?;
            known_dimensions.y = @max(new_height_raw, 0.0);
            known_dimensions = known_dimensions.maybeApplyAspectRatio(aspect_ratio).maybeClamp(min_size, max_size);
        }
        context.info(child_id, "known_dimensions: {any}", .{known_dimensions});
        context.info(child_id, "min_size: {any}", .{min_size});
        context.info(child_id, "max_size: {any}", .{max_size});
        context.info(child_id, "container_width: {any}", .{container_width});

        var layout_output = try mod.performChildLayout(
            context,
            child_id,
            known_dimensions,
            constants.node_inner_size,
            .{
                .x = .{
                    .definite = mod.math.maybeClamp(container_width, min_size.x, max_size.x).?,
                },
                .y = .{
                    .definite = mod.math.maybeClamp(container_height, min_size.y, max_size.y).?,
                },
            },
            .content_size,
            .{
                .start = false,
                .end = false,
            },
        );
        defer layout_output.deinit();

        const measured_size = layout_output.size;
        const final_size = known_dimensions.orElse(measured_size).maybeClamp(min_size, max_size);

        const non_auto_margin = margin.orZero();

        const free_space: mod.CSSPoint = .{
            .x = @max(container_width - final_size.x - non_auto_margin.sumHorizontal(), 0),
            .y = @max(container_height - final_size.y - non_auto_margin.sumVertical(), 0),
        };

        // Expand auto margins to fill available space
        const resolved_margin: mod.CSSRect = resolved_margin: {
            const auto_margin_size: mod.CSSPoint = .{
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
                break :offset_cross start + dir.getCrossStart(f32, constants.border) + dir.getCrossStart(f32, resolved_margin);
            }
            if (end_cross) |end| {
                break :offset_cross dir.getCross(constants.container_size) -
                    dir.getCrossEnd(f32, constants.border) -
                    dir.getCross(final_size) -
                    end -
                    dir.getCrossEnd(f32, resolved_margin);
            }

            // stretch alignment does not apply to absolutely positioned items
            // See "Example 3" at https://www.w3.org/TR/css-flexbox-1/#abspos-items
            // Note: stretch should be flex_start not start when we support both
            if (align_self == .start or
                (!constants.is_wrap_reverse and (align_self == .baseline or align_self == .stretch or align_self == .flex_start)) or
                (constants.is_wrap_reverse and align_self == .flex_end))
            {
                break :offset_cross dir.getCrossStart(f32, constants.content_box_inset) + dir.getCrossStart(f32, resolved_margin);
            }

            if (align_self == .end or
                (constants.is_wrap_reverse and (align_self == .baseline or align_self == .stretch or align_self == .flex_start)) or
                (!constants.is_wrap_reverse and align_self == .flex_end))
            {
                break :offset_cross dir.getCross(constants.container_size) -
                    dir.getCrossEnd(f32, constants.content_box_inset) -
                    dir.getCross(final_size) -
                    dir.getCrossEnd(f32, resolved_margin);
            }

            if (align_self == .center) {
                break :offset_cross (dir.getCross(constants.container_size) +
                    dir.getCrossStart(f32, constants.content_box_inset) -
                    dir.getCrossEnd(f32, constants.content_box_inset) -
                    dir.getCross(final_size) +
                    dir.getCrossStart(f32, resolved_margin) -
                    dir.getCrossEnd(f32, resolved_margin)) / 2.0;
            }
            unreachable;
        };

        const location: mod.CSSPoint = if (constants.is_row)
            .{ .x = offset_main, .y = offset_cross }
        else
            .{ .x = offset_cross, .y = offset_main };

        const scrollbar_size: mod.CSSPoint = .{
            .x = if (overflow.y == .scroll) scrollbar_width else 0.0,
            .y = if (overflow.x == .scroll) scrollbar_width else 0.0,
        };

        try context.setBox(child_id, .{
            .size = final_size,
            .content_size = layout_output.content_size,
            .scrollbar_size = scrollbar_size,
            .location = location,
            .padding = padding,
            .border = border,
            .margin = resolved_margin,
        }, layout_output.line_boxes);

        const size_content_size_contribution = .{
            .x = if (overflow.x == .visible) @max(final_size.x, layout_output.content_size.x) else final_size.x,
            .y = if (overflow.y == .visible) @max(final_size.y, layout_output.content_size.y) else final_size.y,
        };

        if (size_content_size_contribution.x > 0.0 and size_content_size_contribution.y > 0.0) {
            const content_size_contribution: mod.CSSPoint = .{
                .x = location.x + size_content_size_contribution.x,
                .y = location.y + size_content_size_contribution.y,
            };

            content_size = content_size.max(content_size_contribution);
        }
    }
    return content_size;
}
