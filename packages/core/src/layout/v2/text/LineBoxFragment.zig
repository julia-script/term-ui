const mod = @import("../mod.zig");
const LayoutNode = mod.LayoutNode;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");
const white_space_types = @import("../../../styles/white-space.zig");
const std = @import("std");

l_node_id: LayoutNode.Id,
start: u32,
length: u32,
size: mod.CSSPoint,
is_atomic: bool,
white_space_info: WhiteSpaceInfo,
/// The processed text content of this fragment (owned by the fragment)
text: []const u8,
/// Allocator used for text memory management
allocator: std.mem.Allocator,
/// Position of this fragment within its line (set by text alignment)
position: mod.CSSPoint = .{ .x = 0, .y = 0 },

const WhiteSpaceInfo = struct {
    has_preserved_spaces: bool,
    has_preserved_tabs: bool,
    has_collapsible_spaces: bool,
    original_white_space_mode: white_space_types.WhiteSpace,
    tab_size: white_space_types.TabSize,
};
pub fn dupe(self: *@This(), allocator: std.mem.Allocator) !@This() {
    return .{
        .l_node_id = self.l_node_id,
        .start = self.start,
        .length = self.length,
        .size = self.size,
        .is_atomic = self.is_atomic,
        .white_space_info = self.white_space_info,
        .text = try allocator.dupe(u8, self.text),
        .allocator = allocator,
        .position = self.position,
    };
}
pub fn endsWithWhitespace(self: *@This()) bool {
    return self.text.len > 0 and std.ascii.isWhitespace(self.text[self.text.len - 1]);
}

/// Free the fragment's owned text memory
pub fn deinit(self: *@This()) void {
    self.allocator.free(self.text);
}
