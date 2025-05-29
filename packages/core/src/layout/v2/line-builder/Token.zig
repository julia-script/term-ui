const std = @import("std");
const mod = @import("../mod.zig");

pub const Kind = enum {
    text, // Regular text content
    whitespace, // Spaces, tabs (not segment breaks)
    segment_break, // Newlines
    atomic, // Inline-blocks, images, etc.
};

pub const BreakType = enum {
    mandatory, // Must break here (after newlines)
    allowed, // Can break here (after spaces)
    prohibited, // Cannot break here (middle of words)
};

// Original location - never lost!
l_node_id: mod.LayoutNode.Id,
dom_range: struct { start: u32, end: u32 },

// Content (already transformed based on collapse mode)
text: []const u8,
kind: Kind,

// Line breaking information
break_after: BreakType,

// Size (known immediately for atomic nodes, computed later for text)
size: mod.CSSPoint = .{ .x = 0, .y = 0 },

// Layout info (filled during line breaking phase)
line_index: usize = 0,
position_in_line: f32 = 0,
is_hanging: bool = false, // Set during Phase II if this token hangs
