const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const measureChildSize = @import("measureChildSize.zig").measureChildSize;

/// Generate anonymous flex items.
///
/// # [9.1. Initial Setup](https://www.w3.org/TR/css-flexbox-1/#box-manip)
///
/// - [**Generate anonymous flex items**](https://www.w3.org/TR/css-flexbox-1/#algo-anon-box) as described in [§4 Flex Items](https://www.w3.org/TR/css-flexbox-1/#flex-items).
pub fn generateAnonymousFlexItems(
    context: *mod.LayoutContext,
    l_node_id: mod.LayoutNode.Id,
    constants: *types.AlgoConstants,
) !std.ArrayList(types.FlexItem) {
    var flex_items = std.ArrayList(types.FlexItem).init(context.allocator);
    const children = context.layout_tree.getChildren(l_node_id);

    for (children, 0..) |child_id, index| {
        // Get style values for this child
        const css_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .size);
        const css_min_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .min_size);
        const css_max_size = context.getStyleValue(css_types.LengthPercentageAutoPoint, child_id, .max_size);
        const css_margin = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .margin);
        const css_padding = context.getStyleValue(css_types.LengthPercentageRect, child_id, .padding);
        const css_border = context.getStyleValue(css_types.LengthPercentageRect, child_id, .border_width);
        const css_inset = context.getStyleValue(css_types.LengthPercentageAutoRect, child_id, .inset);
        const css_position = context.getStyleValue(css_types.Position, child_id, .position);
        const css_display = context.getStyleValue(css_types.Display, child_id, .display);
        const css_overflow = context.getStyleValue(css_types.OverflowPoint, child_id, .overflow);
        const css_aspect_ratio = context.getStyleValue(?f32, child_id, .aspect_ratio);
        const css_flex_grow = context.getStyleValue(f32, child_id, .flex_grow);
        const css_flex_shrink = context.getStyleValue(f32, child_id, .flex_shrink);
        _ = context.getStyleValue(css_types.LengthPercentageAuto, child_id, .flex_basis);
        const css_align_self = context.getStyleValue(?css_types.AlignSelf, child_id, .align_self);
        const css_scrollbar_width = context.getStyleValue(f32, child_id, .scrollbar_width);

        if (css_position == .absolute or css_display.outside == .none) {
            continue;
        }

        // Resolve size values with aspect ratio
        const size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_size.x, constants.node_inner_size.x),
            .y = mod.math.maybeResolve(css_size.y, constants.node_inner_size.y),
        }, css_aspect_ratio);

        const min_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_min_size.x, constants.node_inner_size.x),
            .y = mod.math.maybeResolve(css_min_size.y, constants.node_inner_size.y),
        }, css_aspect_ratio);

        const max_size = mod.math.maybeApplyAspectRatio(mod.CSSMaybePoint{
            .x = mod.math.maybeResolve(css_max_size.x, constants.node_inner_size.x),
            .y = mod.math.maybeResolve(css_max_size.y, constants.node_inner_size.y),
        }, css_aspect_ratio);

        // Resolve padding and border (margin handling below)
        const padding = mod.CSSRect{
            .top = mod.math.maybeResolve(css_padding.top, constants.node_inner_size.x) orelse 0,
            .right = mod.math.maybeResolve(css_padding.right, constants.node_inner_size.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_padding.bottom, constants.node_inner_size.x) orelse 0,
            .left = mod.math.maybeResolve(css_padding.left, constants.node_inner_size.x) orelse 0,
        };

        const border = mod.CSSRect{
            .top = mod.math.maybeResolve(css_border.top, constants.node_inner_size.x) orelse 0,
            .right = mod.math.maybeResolve(css_border.right, constants.node_inner_size.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_border.bottom, constants.node_inner_size.x) orelse 0,
            .left = mod.math.maybeResolve(css_border.left, constants.node_inner_size.x) orelse 0,
        };

        // Resolve margins - but also track whether they're auto
        const margin = mod.CSSRect{
            .top = mod.math.maybeResolve(css_margin.top, constants.node_inner_size.y) orelse 0,
            .right = mod.math.maybeResolve(css_margin.right, constants.node_inner_size.x) orelse 0,
            .bottom = mod.math.maybeResolve(css_margin.bottom, constants.node_inner_size.y) orelse 0,
            .left = mod.math.maybeResolve(css_margin.left, constants.node_inner_size.x) orelse 0,
        };

        const margin_is_auto = mod.RectOf(bool){
            .top = (css_margin.top == .auto),
            .right = (css_margin.right == .auto),
            .bottom = (css_margin.bottom == .auto),
            .left = (css_margin.left == .auto),
        };

        try flex_items.append(.{
            .node_id = child_id,
            .order = @intCast(index),
            .size = size,
            .min_size = min_size,
            .max_size = max_size,
            .inset = .{
                .top = mod.math.maybeResolve(css_inset.top, constants.node_inner_size.y),
                .bottom = mod.math.maybeResolve(css_inset.bottom, constants.node_inner_size.y),
                .left = mod.math.maybeResolve(css_inset.left, constants.node_inner_size.x),
                .right = mod.math.maybeResolve(css_inset.right, constants.node_inner_size.x),
            },
            .margin = margin,
            .margin_is_auto = margin_is_auto,
            .padding = padding,
            .border = border,
            .align_self = css_align_self orelse constants.align_items,
            .overflow = css_overflow,
            .scrollbar_width = css_scrollbar_width,
            .flex_grow = css_flex_grow,
            .flex_shrink = css_flex_shrink,
            .flex_basis = 0, // Will be computed in determineFlexBaseSize
            .inner_flex_basis = 0,
            .violation = 0,
            .frozen = false,

            .resolved_minimum_main_size = 0,
            .hypothetical_inner_size = mod.CSSPoint{ .x = 0, .y = 0 },
            .hypothetical_outer_size = mod.CSSPoint{ .x = 0, .y = 0 },
            .target_size = mod.CSSPoint{ .x = 0, .y = 0 },
            .outer_target_size = mod.CSSPoint{ .x = 0, .y = 0 },
            .content_flex_fraction = 0,
            .baseline = 0,
            .offset_main = 0,
            .offset_cross = 0,
        });
    }

    return flex_items;
}

/// Direction helper struct to handle main/cross axis operations
pub const DirectionHelper = struct {
    direction: css_types.FlexDirection,
    is_row: bool,
    is_column: bool,

    pub fn init(direction: css_types.FlexDirection) DirectionHelper {
        return DirectionHelper{
            .direction = direction,
            .is_row = direction == .row or direction == .row_reverse,
            .is_column = direction == .column or direction == .column_reverse,
        };
    }

    pub fn getMain(self: DirectionHelper, point: mod.CSSPoint) f32 {
        return if (self.is_row) point.x else point.y;
    }

    pub fn getMainOptional(self: DirectionHelper, point: mod.CSSMaybePoint) ?f32 {
        return if (self.is_row) point.x else point.y;
    }
    pub fn getCross(self: DirectionHelper, point: mod.CSSPoint) f32 {
        return if (self.is_row) point.y else point.x;
    }

    pub fn getCrossOptional(self: DirectionHelper, point: mod.CSSMaybePoint) ?f32 {
        return if (self.is_row) point.y else point.x;
    }

    // pub fn getCross(self: DirectionHelper, point: mod.CSSMaybePoint) ?f32 {
    //     return if (self.is_row) point.y else point.x;
    // }

    // pub fn getCrossPoint(self: DirectionHelper, point: mod.CSSPoint) f32 {
    //     return if (self.is_row) point.y else point.x;
    // }

    pub fn getCrossAvailableSpace(self: DirectionHelper, point: mod.constants.AvailableSpacePoint) mod.constants.AvailableSpace {
        return if (self.is_row) point.y else point.x;
    }

    pub fn getMainAvailableSpace(self: DirectionHelper, point: mod.constants.AvailableSpacePoint) mod.constants.AvailableSpace {
        return if (self.is_row) point.y else point.x;
    }

    pub fn setMain(self: DirectionHelper, point: mod.CSSPoint, value: f32) mod.CSSPoint {
        if (self.is_row) {
            return .{ .x = value, .y = point.y };
        } else {
            return .{ .x = point.x, .y = value };
        }
    }
    pub fn setMainOptional(self: DirectionHelper, point: mod.CSSMaybePoint, value: ?f32) mod.CSSMaybePoint {
        if (self.is_row) {
            return mod.CSSMaybePoint{ .x = value, .y = point.y };
        } else {
            return mod.CSSMaybePoint{ .x = point.x, .y = value };
        }
    }
    pub fn setCrossOptional(self: DirectionHelper, point: mod.CSSMaybePoint, value: ?f32) mod.CSSMaybePoint {
        if (self.is_row) {
            return mod.CSSMaybePoint{ .x = point.x, .y = value };
        } else {
            return mod.CSSMaybePoint{ .x = value, .y = point.y };
        }
    }
    pub fn getMainByType(self: DirectionHelper, T: type, point: mod.PointOf(T)) T {
        return if (self.is_row) point.x else point.y;
    }
    pub fn getCrossByType(self: DirectionHelper, T: type, point: mod.PointOf(T)) T {
        return if (self.is_row) point.y else point.x;
    }

    pub fn setMainAvailableSpace(self: DirectionHelper, point: mod.constants.AvailableSpacePoint, value: mod.constants.AvailableSpace) mod.constants.AvailableSpacePoint {
        return if (self.is_row) .{ .x = point.x, .y = value } else .{ .x = value, .y = point.y };
    }

    pub fn setCrossAvailableSpace(self: DirectionHelper, point: mod.constants.AvailableSpacePoint, value: mod.constants.AvailableSpace) mod.constants.AvailableSpacePoint {
        return if (self.is_row) .{ .x = point.x, .y = value } else .{ .x = value, .y = point.y };
    }

    pub fn setCross(self: DirectionHelper, point: mod.CSSPoint, value: f32) mod.CSSPoint {
        if (self.is_row) {
            return .{ .x = point.x, .y = value };
        } else {
            return .{ .x = value, .y = point.y };
        }
    }

    pub fn sumMainAxis(self: DirectionHelper, rect: mod.CSSRect) f32 {
        return if (self.is_row) rect.sumHorizontal() else rect.sumVertical();
    }

    pub fn sumCrossAxis(self: DirectionHelper, rect: mod.CSSRect) f32 {
        return if (self.is_row) rect.sumVertical() else rect.sumHorizontal();
    }

    pub fn getCrossStart(self: DirectionHelper, T: type, rect: mod.RectOf(T)) T {
        return if (self.is_row) rect.top else rect.left;
    }
    pub fn getCrossEnd(self: DirectionHelper, T: type, rect: mod.RectOf(T)) T {
        return if (self.is_row) rect.bottom else rect.right;
    }
    pub fn getMainStart(self: DirectionHelper, T: type, rect: mod.RectOf(T)) T {
        return if (self.is_row) rect.left else rect.top;
    }
    pub fn getMainEnd(self: DirectionHelper, T: type, rect: mod.RectOf(T)) T {
        return if (self.is_row) rect.right else rect.bottom;
    }
};

/// Determine the flex base size and hypothetical main size of each item.
///
/// # [9.2. Line Length Determination](https://www.w3.org/TR/css-flexbox-1/#line-sizing)
///
/// - [**Determine the flex base size and hypothetical main size of each item:**](https://www.w3.org/TR/css-flexbox-1/#algo-main-item)
pub fn determineFlexBaseSize(
    context: *mod.LayoutContext,
    constants: *types.AlgoConstants,
    available_space: mod.constants.AvailableSpacePoint,
    flex_items: *std.ArrayList(types.FlexItem),
) !void {
    const dir = DirectionHelper.init(constants.dir);

    for (flex_items.items) |*child| {
        const css_flex_basis = context.getStyleValue(css_types.LengthPercentageAuto, child.node_id, .flex_basis);
        // Parent size for child sizing
        const cross_axis_parent_size: ?f32 = dir.getCrossOptional(constants.node_inner_size);
        const child_parent_size: mod.CSSMaybePoint = constants.dir.pointFromCross(cross_axis_parent_size);

        // Available space for child sizing
        const cross_axis_margin_sum: f32 = dir.sumCrossAxis(constants.margin);
        const child_min_cross: ?f32 = blk: {
            if (dir.getCrossOptional(child.min_size)) |a| {
                break :blk a + cross_axis_margin_sum;
            }
            break :blk null;
        };
        const child_max_cross: ?f32 = blk: {
            if (dir.getCrossOptional(child.max_size)) |a| {
                break :blk a + cross_axis_margin_sum;
            }
            break :blk null;
        };
        const cross_axis_available_space: mod.constants.AvailableSpace = blk: {
            const v: mod.constants.AvailableSpace = dir.getCrossAvailableSpace(available_space);
            switch (v) {
                .definite => |d| break :blk .{
                    .definite = mod.math.maybeClamp(
                        cross_axis_parent_size orelse d,
                        child_min_cross,
                        child_max_cross,
                    ).?,
                },
                else => break :blk v,
            }
        };
        // Known dimensions for child sizing
        const child_known_dimensions: mod.CSSMaybePoint = blk: {
            const ckd = dir.setMainOptional(child.size, null);
            if (child.align_self == .stretch and dir.getCrossOptional(child.size) == null) {
                break :blk dir.setCrossOptional(
                    ckd,
                    mod.math.maybeSub(
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

            const flex_basis: ?f32 = css_flex_basis.maybeResolve(dir.getMainOptional(constants.node_inner_size));
            const main_size: ?f32 = dir.getMainOptional(child.size);
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
                var space = mod.constants.AvailableSpace.MAX_CONTENT;
                if (dir.getMainAvailableSpace(available_space) == .min_content) {
                    space = dir.setMainAvailableSpace(space, .min_content);
                }
                break :blk dir.setCrossAvailableSpace(space, cross_axis_available_space);
            };

            break :flex_basis try measureChildSize(
                context,
                child.node_id,
                child_known_dimensions,
                child_parent_size,
                child_available_space,
                .content_size,
                mod.constants.AbsoluteAxis.fromFlexDirection(constants.dir),
                .{
                    .start = false,
                    .end = false,
                },
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
        const hypothetical_inner_min_main: ?f32 = mod.math.maybeMax(
            dir.getMainOptional(child.min_size),
            dir.getMain(padding_border_axes_sums),
        );
        const hypothetical_inner_size: f32 = mod.math.maybeClamp(
            child.flex_basis,
            hypothetical_inner_min_main,
            dir.getMainOptional(child.max_size),
        ).?;
        const hypothetical_outer_size: f32 = hypothetical_inner_size + dir.sumMainAxis(child.margin);

        child.hypothetical_inner_size = dir.setMain(child.hypothetical_inner_size, hypothetical_inner_size);
        child.hypothetical_outer_size = dir.setMain(child.hypothetical_outer_size, hypothetical_outer_size);

        // Note that it is important that the `parent_size` parameter in the main axis is not set for this
        // function call as it used for resolving percentages, and percentage size in an axis should not contribute
        // to a min-content contribution in that same axis. However the `parent_size` and `available_space` *should*
        // be set to their usual values in the cross axis so that wrapping content can wrap correctly.
        //
        // See https://drafts.csswg.org/css-sizing-3/#min-percentage-contribution
        const style_min_main_size: ?f32 = dir.getMainOptional(child.min_size) orelse dir.getMainOptional(.{
            .x = child.overflow.x.maybeIntoAutomaticMinSize(),
            .y = child.overflow.y.maybeIntoAutomaticMinSize(),
        });

        child.resolved_minimum_main_size = style_min_main_size orelse resolved: {
            const min_content_main_size: f32 = blk: {
                const child_available_space = dir.setCrossAvailableSpace(
                    mod.constants.AvailableSpace.MIN_CONTENT,
                    cross_axis_available_space,
                );

                break :blk try measureChildSize(
                    context,
                    child.node_id,
                    child_known_dimensions,
                    child_parent_size,
                    child_available_space,
                    .content_size,
                    mod.constants.AbsoluteAxis.fromFlexDirection(constants.dir),
                    .{
                        .start = false,
                        .end = false,
                    },
                );
            };

            // 4.5. Automatic Minimum Size of Flex Items
            // https://www.w3.org/TR/css-flexbox-1/#min-size-auto
            var clamped_min_content_size: f32 = mod.math.maybeMin(
                min_content_main_size,
                dir.getMainOptional(child.size),
            ).?;

            clamped_min_content_size = mod.math.maybeMin(
                clamped_min_content_size,
                dir.getMainOptional(child.max_size),
            ).?;

            break :resolved mod.math.maybeMax(
                clamped_min_content_size,
                dir.getMain(padding_border_axes_sums),
            ).?;
        };
    }
}
