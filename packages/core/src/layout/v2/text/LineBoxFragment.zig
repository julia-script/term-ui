const mod = @import("../mod.zig");
const LayoutNode = mod.LayoutNode;
const CSSMaybePoint = mod.CSSMaybePoint;
const css_types = @import("../../../css/types.zig");
const white_space_types = @import("../../../styles/white-space.zig");

l_node_id: LayoutNode.Id,
start: u32,
length: u32,
size: mod.CSSPoint,
is_atomic: bool,
white_space_info: WhiteSpaceInfo,

const WhiteSpaceInfo = struct {
    has_preserved_spaces: bool,
    has_preserved_tabs: bool,
    has_collapsible_spaces: bool,
    original_white_space_mode: white_space_types.WhiteSpace,
    tab_size: white_space_types.TabSize,
};
