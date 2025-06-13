const std = @import("std");
const lookups = @import("lookups.zig");
pub const EastAsianWidth = lookups.EastAsianWidth;
pub const LineBreak = lookups.LineBreak;
pub const GeneralCategory = lookups.GeneralCategory;
pub const GraphemeBreak = lookups.GraphemeBreak;
pub const CoreProperty = lookups.CoreProperty;
pub const WordBreak = lookups.WordBreak;
pub fn getHandle(comptime T: type) usize {
    inline for (std.meta.fields(lookups.Columns), 0..) |field, index| {
        if (field.type == T) {
            return index;
        }
    }
    unreachable;
}

pub fn getValue(comptime T: type, key: usize) T {
    const handle = comptime getHandle(T);
    const index: usize = lookups.index1[key >> lookups.shift];
    const ivalue: usize = lookups.index2[(index << lookups.shift) + (key & ((1 << lookups.shift) - 1))];
    return lookups.values[ivalue][handle];
}
pub fn getBoolValue(comptime column: usize, key: usize) bool {
    const index: usize = lookups.index1[key >> lookups.shift];
    const ivalue: usize = lookups.index2[(index << lookups.shift) + (key & ((1 << lookups.shift) - 1))];
    return lookups.values[ivalue][column];
}

pub fn getLineBreak(c: u21) lookups.LineBreak {
    return getValue(lookups.LineBreak, c);
}
pub fn getCategory(c: u21) lookups.GeneralCategory {
    return getValue(lookups.GeneralCategory, c);
}
pub fn getEastAsianWidth(c: u21) EastAsianWidth {
    return getValue(EastAsianWidth, c);
}
pub fn isEmoji(c: u21) bool {
    return getBoolValue(lookups.EmojiIndex, c);
}
pub fn isEmojiPresentation(c: u21) bool {
    return getBoolValue(lookups.EmojiPresentationIndex, c);
}
pub fn isEmojiModifier(c: u21) bool {
    return getBoolValue(lookups.EmojiModifierIndex, c);
}
pub fn isEmojiModifierBase(c: u21) bool {
    return getBoolValue(lookups.EmojiModifierBaseIndex, c);
}
pub fn isEmojiComponent(c: u21) bool {
    return getBoolValue(lookups.EmojiComponentIndex, c);
}
pub fn isExtendedPictographic(c: u21) bool {
    return getBoolValue(lookups.ExtendedPictographicIndex, c);
}
pub fn getGraphemeBreak(c: u21) GraphemeBreak {
    return getValue(GraphemeBreak, c);
}
pub fn getCoreProperty(c: u21) CoreProperty {
    return getValue(CoreProperty, c);
}
pub fn getWordBreak(c: u21) WordBreak {
    return getValue(WordBreak, c);
}
