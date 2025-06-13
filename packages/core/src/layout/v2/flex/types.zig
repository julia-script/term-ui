const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");

// Core algorithm constants structure
pub const AlgoConstants = struct {
    /// The direction of the current segment being laid out
    dir: css_types.FlexDirection,
    /// Is this segment a row
    is_row: bool,
    /// Is this segment a column
    is_column: bool,
    /// Is wrapping enabled (in either direction)
    is_wrap: bool,
    /// Is the wrap direction inverted
    is_wrap_reverse: bool,

    /// The item's min_size style
    min_size: mod.CSSMaybePoint,
    /// The item's max_size style
    max_size: mod.CSSMaybePoint,
    /// The margin of this section
    margin: mod.CSSRect,
    /// The border of this section
    border: mod.CSSRect,
    /// The space between the content box and the border box.
    /// This consists of padding + border + scrollbar_gutter.
    content_box_inset: mod.CSSRect,
    /// The size reserved for scrollbar gutters in each axis
    scrollbar_gutter: mod.CSSPoint,
    /// The gap of this section
    gap: mod.CSSPoint,
    /// The align_items property of this node
    align_items: css_types.AlignItems,
    /// The align_content property of this node
    align_content: css_types.AlignContent,
    /// The justify_content property of this node
    justify_content: ?css_types.JustifyContent,

    /// The border-box size of the node being laid out (if known)
    node_outer_size: mod.CSSMaybePoint,
    /// The content-box size of the node being laid out (if known)
    node_inner_size: mod.CSSMaybePoint,

    /// The size of the virtual container containing the flex items.
    container_size: mod.CSSPoint,
    /// The size of the internal container
    inner_container_size: mod.CSSPoint,
};

pub const FlexItem = struct {
    /// The identifier for the associated node
    node_id: mod.LayoutNode.Id,

    /// The order of the node relative to its siblings
    order: u32,

    /// The base size of this item
    size: mod.CSSMaybePoint,
    /// The minimum allowable size of this item
    min_size: mod.CSSMaybePoint,
    /// The maximum allowable size of this item
    max_size: mod.CSSMaybePoint,
    /// The cross-alignment of this item
    align_self: css_types.AlignSelf,

    /// The overflow style of the item
    overflow: css_types.OverflowPoint,
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
    inset: mod.RectOf(?f32),
    /// The margin of this item
    margin: mod.CSSRect,
    /// Whether each margin is an auto margin or not
    margin_is_auto: mod.RectOf(bool),
    /// The padding of this item
    padding: mod.CSSRect,
    /// The border of this item
    border: mod.CSSRect,

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
    hypothetical_inner_size: mod.CSSPoint,
    /// The proposed outer size of this item
    hypothetical_outer_size: mod.CSSPoint,
    /// The size that this item wants to be
    target_size: mod.CSSPoint,
    /// The size that this item wants to be, plus any padding and border
    outer_target_size: mod.CSSPoint,

    /// The position of the bottom edge of this item
    baseline: f32,

    /// A temporary value for the main offset
    offset_main: f32,
    /// A temporary value for the cross offset
    offset_cross: f32,

    pub fn marginIsAuto(self: *const FlexItem) mod.CSSRectBool {
        return mod.CSSRectBool{
            .top = switch (self.inset.top) {
                .auto => true,
                else => false,
            },
            .right = switch (self.inset.right) {
                .auto => true,
                else => false,
            },
            .bottom = switch (self.inset.bottom) {
                .auto => true,
                else => false,
            },
            .left = switch (self.inset.left) {
                .auto => true,
                else => false,
            },
        };
    }
};

pub const FlexLine = struct {
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
