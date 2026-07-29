const std = @import("std");
const Point = @import("../layout/point.zig").Point;
const Rect = @import("../layout/rect.zig").Rect;
const utils = @import("../layout/utils/comptime.zig");
const isOptional = utils.isOptional;
const MemberType = utils.MemberType;
const Color = @import("../colors/Color.zig");
const expect = std.testing.expect;
const Styles = @This();
const Node = @import("Node.zig");
pub const styles = @import("../styles/styles.zig");

// pub fn init(allocator: std.mem.Allocator) Styles {
//     return .{
//         .allocator = allocator,
//         .arena = std.heap.ArenaAllocator.init(allocator),
//     };
// }

// pub fn deinit(self: *Styles) void {
//     self.arena.deinit();
// }

// allocator: std.mem.Allocator,
// arena: std.heap.ArenaAllocator,
// Style Properties
display: styles.display.Display = styles.display.Display.BLOCK,
@"inline": bool = false,

overflow: Point(styles.overflow.Overflow) = .{
    .x = .visible,
    .y = .visible,
},
scrollbar_width: f32 = 0,
position: styles.position.Position = .relative,
inset: Rect(styles.length_percentage_auto.LengthPercentageAuto) = .{
    .top = .auto,
    .right = .auto,
    .bottom = .auto,
    .left = .auto,
},
size: Point(styles.length_percentage_auto.LengthPercentageAuto) = .{
    .x = .auto,
    .y = .auto,
},
min_size: Point(styles.length_percentage_auto.LengthPercentageAuto) = .{
    .x = .auto,
    .y = .auto,
},
max_size: Point(styles.length_percentage_auto.LengthPercentageAuto) = .{
    .x = .auto,
    .y = .auto,
},
aspect_ratio: ?f32 = null,
margin: Rect(styles.length_percentage_auto.LengthPercentageAuto) = .{
    .top = styles.length_percentage_auto.LengthPercentageAuto.ZERO,
    .right = styles.length_percentage_auto.LengthPercentageAuto.ZERO,
    .bottom = styles.length_percentage_auto.LengthPercentageAuto.ZERO,
    .left = styles.length_percentage_auto.LengthPercentageAuto.ZERO,
},
padding: Rect(styles.length_percentage.LengthPercentage) = .{
    .top = styles.length_percentage.LengthPercentage.ZERO,
    .right = styles.length_percentage.LengthPercentage.ZERO,
    .bottom = styles.length_percentage.LengthPercentage.ZERO,
    .left = styles.length_percentage.LengthPercentage.ZERO,
},
border: Rect(styles.length_percentage.LengthPercentage) = .{
    .top = styles.length_percentage.LengthPercentage.ZERO,
    .right = styles.length_percentage.LengthPercentage.ZERO,
    .bottom = styles.length_percentage.LengthPercentage.ZERO,
    .left = styles.length_percentage.LengthPercentage.ZERO,
},
align_items: ?AlignItems = null,
align_self: ?AlignSelf = null,
justify_items: ?AlignItems = null,
justify_self: ?AlignSelf = null,
align_content: ?AlignContent = null,
justify_content: ?JustifyContent = null,
gap: Point(styles.length_percentage.LengthPercentage) = .{
    .x = styles.length_percentage.LengthPercentage.ZERO,
    .y = styles.length_percentage.LengthPercentage.ZERO,
},

flex_direction: styles.flex_direction.FlexDirection = .row,
flex_wrap: styles.flex_wrap.FlexWrap = .no_wrap,
flex_basis: styles.length_percentage_auto.LengthPercentageAuto = .auto,
flex_grow: f32 = 0,
flex_shrink: f32 = 1,

//TODO: Move styles below to another struct
background_color: ?styles.background.Background = null,
foreground_color: ?styles.color.Color = null,
text_align: styles.text_align.TextAlign = .inherit,
// White space properties (longhand only)
white_space_collapse: styles.white_space.WhiteSpaceCollapse = .inherit,
text_wrap_mode: styles.white_space.TextWrapMode = .inherit,
white_space_trim: styles.white_space.Trim = .none,
tab_size: styles.white_space.TabSize = styles.white_space.TabSize.DEFAULT,

// Text formatting styles
font_weight: styles.font_weight.FontWeight = .inherit,
font_style: styles.font_style.FontStyle = .inherit,
text_decoration: styles.text_decoration.TextDecoration = .{},

line_height: f32 = 1,
border_style: Rect(styles.border_style.BoxChar.Cell) = .{
    .top = .{},
    .right = .{},
    .bottom = .{},
    .left = .{},
},
border_color: Rect(styles.background.Background) = .{
    .top = .{
        .solid = Color.tw.white,
    },
    .right = .{
        .solid = Color.tw.white,
    },
    .bottom = .{
        .solid = Color.tw.white,
    },
    .left = .{
        .solid = Color.tw.white,
    },
},
cursor: styles.cursor.Cursor = .default,
pointer_events: styles.pointer_events.PointerEvents = .auto,
z_index: styles.z_index.ZIndex = styles.z_index.ZIndex.DEFAULT,
/// Copy all style properties from another style object
pub fn copyFrom(self: *Styles, source: *const Styles) void {
    inline for (comptime std.meta.fieldNames(Styles)) |field_name| {
        @field(self, field_name) = @field(source, field_name);
    }
    // Layout properties
    // self.display = source.display;
    // self.@"inline" = source.@"inline";
    // self.overflow = source.overflow;
    // self.scrollbar_width = source.scrollbar_width;
    // self.position = source.position;
    // self.inset = source.inset;
    // self.size = source.size;
    // self.min_size = source.min_size;
    // self.max_size = source.max_size;
    // self.aspect_ratio = source.aspect_ratio;
    // self.margin = source.margin;
    // self.padding = source.padding;
    // self.border = source.border;

    // // Alignment properties
    // self.align_items = source.align_items;
    // self.align_self = source.align_self;
    // self.justify_items = source.justify_items;
    // self.justify_self = source.justify_self;
    // self.align_content = source.align_content;
    // self.justify_content = source.justify_content;
    // self.gap = source.gap;

    // // Flex properties
    // self.flex_direction = source.flex_direction;
    // self.flex_wrap = source.flex_wrap;
    // self.flex_basis = source.flex_basis;
    // self.flex_grow = source.flex_grow;
    // self.flex_shrink = source.flex_shrink;

    // // Visual properties
    // self.background_color = source.background_color;
    // self.foreground_color = source.foreground_color;
    // self.text_align = source.text_align;
    // self.text_wrap = source.text_wrap;
    // self.line_height = source.line_height;

    // // Text formatting properties
    // self.font_weight = source.font_weight;
    // self.font_style = source.font_style;
    // self.text_decoration = source.text_decoration;
}

pub const AlignItems = styles.align_items.AlignItems;
/// Used to control how child nodes are aligned.
/// Does not apply to Flexbox, and will be ignored if specified on a flex container
/// For Grid it controls alignment in the inline axis
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-items)
pub const JustifyItems = styles.align_items.AlignItems;

/// Used to control how the specified nodes is aligned.
/// Overrides the parent Node's `AlignItems` property.
/// For Flexbox it controls alignment in the cross axis
/// For Grid it controls alignment in the block axis
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/align-self)
pub const AlignSelf = styles.align_items.AlignItems;

/// Used to control how the specified nodes is aligned.
/// Overrides the parent Node's `JustifyItems` property.
/// Does not apply to Flexbox, and will be ignored if specified on a flex child
/// For Grid it controls alignment in the inline axis
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-self)
pub const JustifySelf = styles.align_items.AlignItems;

pub const AlignContent = styles.align_content.AlignContent;
/// Sets the distribution of space between and around content items
/// For Flexbox it controls alignment in the main axis
/// For Grid it controls alignment in the inline axis
///
/// [MDN](https://developer.mozilla.org/en-US/docs/Web/CSS/justify-content)
pub const JustifyContent = styles.align_content.AlignContent;
