const styles = @import("../styles/styles.zig");
const Rect = @import("../layout/rect.zig").Rect;
const Point = @import("../layout/point.zig").Point;

pub const parseStyleString = styles.parseStyleString;
pub const parseStyleProperty = styles.parseStyleProperty;

// Basic property types
pub const Display = styles.display.Display;
pub const Length = styles.length.Length;
pub const LengthPercentage = styles.length_percentage.LengthPercentage;
pub const LengthPercentageAuto = styles.length_percentage_auto.LengthPercentageAuto;
pub const Position = styles.position.Position;
pub const Overflow = styles.overflow.Overflow;

pub const FlexDirection = styles.flex_direction.FlexDirection;
pub const FlexWrap = styles.flex_wrap.FlexWrap;
pub const AlignItems = styles.align_items.AlignItems;
pub const AlignContent = styles.align_content.AlignContent;
pub const AlignSelf = styles.align_items.AlignItems;
pub const JustifyContent = styles.align_content.AlignContent;
pub const Number = styles.number.Number;
pub const Angle = styles.angle.Angle;

// Color related types
pub const Color = styles.color.Color;
pub const NamedColor = styles.color.NamedColor;
pub const ColorStop = styles.color_stop.ColorStop;
pub const ColorStopList = styles.color_stop.ColorStopList;
pub const LinearGradient = styles.linear_gradient.LinearGradient;
pub const RadialShape = styles.radial_gradient.RadialShape;
pub const RadialExtent = styles.radial_gradient.RadialExtent;
pub const RadialGradientPosition = styles.radial_gradient.Position;
pub const RadialSize = styles.radial_gradient.RadialSize;
pub const RadialGradient = styles.radial_gradient.RadialGradient;
pub const BackgroundType = styles.background.BackgroundType;
pub const Background = styles.background.Background;

// Text formatting
pub const TextAlign = styles.text_align.TextAlign;
pub const WhiteSpace = styles.white_space.WhiteSpace;
pub const WhiteSpaceCollapse = styles.white_space.WhiteSpaceCollapse;
pub const TextWrapMode = styles.white_space.TextWrapMode;
pub const TextDecorationLine = styles.text_decoration.TextDecorationLine;
pub const TextDecoration = styles.text_decoration.TextDecoration;

// Font and border utilities
pub const FontStyle = styles.font_style.FontStyle;
pub const FontWeight = styles.font_weight.FontWeight;
pub const BoxChar = styles.border.BoxChar;
pub const Border = styles.border.Border;
pub const Cursor = styles.cursor.Cursor;
pub const PointerEvents = styles.pointer_events.PointerEvents;

// Convenience point/rect aliases
pub const LengthPercentageAutoPoint = Point(LengthPercentageAuto);
pub const LengthPercentageAutoRect = Rect(LengthPercentageAuto);
pub const LengthPercentagePoint = Point(LengthPercentage);
pub const LengthPercentageRect = Rect(LengthPercentage);
pub const LengthPoint = Point(Length);
pub const LengthRect = Rect(Length);
pub const OverflowPoint = Point(Overflow);
