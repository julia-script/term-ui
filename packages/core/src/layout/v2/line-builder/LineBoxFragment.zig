const std = @import("std");
const LineBox = @import("./LineBox.zig");
const mod = @import("../mod.zig");

/// Layout node ID this fragment belongs to
l_node_id: mod.LayoutNode.Id,
/// The start index of the fragment in the original text node
start: u32,
/// Length of the fragment text
length: u32,
/// Size of the fragment (width, height)
size: mod.CSSPoint,
/// Whether this is an atomic inline element
is_atomic: bool,
/// The processed text content of this fragment (owned by the fragment)
text: []const u8,
/// Allocator used for text memory management
allocator: std.mem.Allocator,
/// Position of this fragment within its line (set by text alignment)
position: mod.CSSPoint = .{ .x = 0, .y = 0 },
/// Range in the original DOM text node (for selection mapping)
dom_range: @import("../RenderList.zig").DomRange = .{ .start = 0, .end = 0 },

const Self = @This();

pub fn dupe(self: *Self, allocator: std.mem.Allocator) !Self {
    return .{
        .l_node_id = self.l_node_id,
        .start = self.start,
        .length = self.length,
        .size = self.size,
        .is_atomic = self.is_atomic,
        .text = try allocator.dupe(u8, self.text),
        .allocator = allocator,
        .position = self.position,
        .dom_range = self.dom_range,
    };
}

pub fn endsWithWhitespace(self: *Self) bool {
    return self.text.len > 0 and std.ascii.isWhitespace(self.text[self.text.len - 1]);
}

/// Free the fragment's owned text memory
pub fn deinit(self: *Self) void {
    self.allocator.free(self.text);
}