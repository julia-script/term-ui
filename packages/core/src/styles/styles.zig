pub const utils = @import("utils.zig");
pub const display = @import("display.zig");
pub const color = @import("color.zig");
pub const length = @import("length.zig");
pub const length_percentage = @import("length-percentage.zig");
pub const length_percentage_auto = @import("length-percentage-auto.zig");
pub const position = @import("position.zig");
pub const overflow = @import("overflow.zig");
pub const flex_direction = @import("flex-direction.zig");
pub const flex_wrap = @import("flex-wrap.zig");
pub const align_items = @import("align-items.zig");
pub const align_content = @import("align-content.zig");
pub const number = @import("number.zig");
pub const angle = @import("angle.zig");
pub const color_stop = @import("color-stop.zig");
pub const linear_gradient = @import("linear-gradient.zig");
pub const radial_gradient = @import("radial-gradient.zig");
pub const background = @import("background.zig");
pub const text_align = @import("text-align.zig");
pub const white_space = @import("white-space.zig");
pub const text_decoration = @import("text-decoration.zig");
pub const font_style = @import("font-style.zig");
pub const font_weight = @import("font-weight.zig");
pub const border = @import("border.zig");
pub const cursor = @import("cursor.zig");
pub const pointer_events = @import("pointer-events.zig");
pub const z_index = @import("z-index.zig");

// CSSOM Implementation modules
pub const style_manager = @import("StyleManager.zig");
pub const cascade_types = @import("CascadeTypes.zig");
pub const selector = @import("Selector.zig");
pub const style_sheet = @import("StyleSheet.zig");
pub const computed_style = @import("ComputedStyle.zig");
pub const border_style = @import("border.zig");
pub const parseStyleString = @import("parse-styles.zig").parseStyleString;
pub const parseStyleProperty = @import("parse-styles.zig").parseStyleProperty;

pub const isEop = utils.isEop;

test "parsers" {
    // @import("std").testing.refAllDeclsRecursive(@This());
    _ = color;
    _ = display;
    _ = length;
    _ = length_percentage;
    _ = number;
    _ = angle;
    _ = color_stop;
    _ = linear_gradient;
    _ = radial_gradient;
    _ = background;
    _ = isEop;
}
