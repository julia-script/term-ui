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
text: []u8,
/// Allocator used for text memory management
allocator: std.mem.Allocator,

const WhiteSpaceInfo = struct {
    has_preserved_spaces: bool,
    has_preserved_tabs: bool,
    has_collapsible_spaces: bool,
    original_white_space_mode: white_space_types.WhiteSpace,
    tab_size: white_space_types.TabSize,
};

/// Free the fragment's owned text memory
pub fn deinit(self: *@This()) void {
    self.allocator.free(self.text);
}
