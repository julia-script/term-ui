const std = @import("std");
const Style = @import("Style.zig");
const ArrayList = std.ArrayListUnmanaged;
const Layout = @import("Layout.zig");
const Point = @import("../layout/point.zig").Point;
const AvailableSpace = @import("../layout/compute/compute_constants.zig").AvailableSpace;
const build_options = @import("build_options");
const Node = @This();
const Cache = @import("Cache.zig");
const Tree = @import("Tree.zig");
const ComputedText = @import("../layout/compute/text/ComputedText.zig");
const String = @import("String.zig");
const Attributes = @import("Attributes.zig");
const RenderList = @import("../layout/v2/RenderList.zig");
const LayoutTree = @import("../layout/v2/LayoutTree.zig");
pub const NodeKind = enum(u8) {
    node = 1,
    text = 2,
};

id: NodeId,
kind: NodeKind = .node,
parent: ?NodeId = null,
children: ArrayList(NodeId) = .{},
styles: Style,
attributes: Attributes,

text: String = .{},

scroll_offset: Point(f32) = .{
    .x = 0,
    .y = 0,
},
text_root_id: ?NodeId = null,
tabindex: i32 = -1,

regenerate_level: RegenerateLevel = .regenerate,
// Invalidation tracking
// needs_repaint: bool = false,
// needs_recompute: bool = false,
// needs_regenerate: bool = false,
pub const RegenerateLevel = enum(u8) {
    regenerate = 0,
    recompute = 1,
    repaint = 2,

    pub fn max(a: RegenerateLevel, b: RegenerateLevel) RegenerateLevel {
        return @enumFromInt(@max(a.toInt(), b.toInt()));
    }
    pub fn min(a: RegenerateLevel, b: RegenerateLevel) RegenerateLevel {
        return @enumFromInt(@min(a.toInt(), b.toInt()));
    }
    pub fn toInt(self: RegenerateLevel) u8 {
        return @intFromEnum(self);
    }
};
pub fn needsRegenerate(self: *Self) bool {
    return self.regenerate_level.toInt() <= RegenerateLevel.regenerate.toInt();
}
pub fn needsRepaint(self: *Self) bool {
    return self.regenerate_level.toInt() <= RegenerateLevel.repaint.toInt();
}
pub fn needsRecompute(self: *Self) bool {
    return self.regenerate_level.toInt() <= RegenerateLevel.recompute.toInt();
}
pub fn markRegenerateCompleted(self: *Self, level: RegenerateLevel) void {
    if (level == .repaint) {
        self.regenerate_level = .repaint;
        return;
    }
    const next = level.toInt() + 1;
    self.regenerate_level = @enumFromInt(next);
}
pub fn requestRecompute(self: *Self) void {
    self.regenerate_level = .recompute;
}
pub fn requestRegenerate(self: *Self) void {
    self.regenerate_level = .regenerate;
}
pub fn requestRepaint(self: *Self) void {
    self.regenerate_level = .repaint;
}

pub fn setRegenerateLevel(self: *Self, level: RegenerateLevel) void {
    self.regenerate_level = RegenerateLevel.min(self.regenerate_level, level);
}

const Self = @This();
pub const NodeId = usize;
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.children.deinit(allocator);
    self.text.deinit(allocator);
    self.attributes.deinit();
}
pub fn length(self: *Self) usize {
    switch (self.kind) {
        .text => {
            return self.text.length();
        },
        .node => {
            return self.children.items.len;
        },
    }
}

pub fn isCharacterData(self: *Self) bool {
    return self.kind == .text;
}
pub fn replaceData(self: *Self, tree: *Tree, offset: u32, count: u32, data: []const u8) !void {
    if (self.kind != .text) {
        return error.NotCharacterData;
    }

    // Step 1: Get node's length
    const len = self.text.length();

    // Step 2: Check if offset is valid
    if (offset > len) {
        return error.IndexSizeError;
    }

    // Step 3: Adjust count if needed
    var adjusted_count = count;
    if (offset + count > len) {
        adjusted_count = @intCast(len - offset);
    }

    // Steps 5-7: Perform the text replacement
    try self.text.replace(tree.allocator, offset, adjusted_count, data);

    // Update all ranges that might be affected
    self.updateRangesAfterReplace(tree, offset, adjusted_count, data.len);
}

// The appendData(data) method steps are to replace data with node this, offset this’s length, count 0, and data data.
pub fn appendData(self: *Self, tree: *Tree, data: []const u8) !void {
    try self.replaceData(tree, @intCast(self.text.length()), 0, data);
}

// The insertData(offset, data) method steps are to replace data with node this, offset offset, count 0, and data data.
pub fn insertData(self: *Self, tree: *Tree, offset: u32, data: []const u8) !void {
    try self.replaceData(tree, offset, 0, data);
}

// The deleteData(offset, count) method steps are to replace data with node this, offset offset, count count, and data the empty string.
pub fn deleteData(self: *Self, tree: *Tree, offset: u32, count: u32) !void {
    try self.replaceData(tree, offset, count, "");
}
pub fn getFirstChildId(self: *Self) ?NodeId {
    if (self.children.items.len == 0) {
        return null;
    }
    return self.children.items[0];
}

pub fn getFirstChild(self: *Self, tree: *Tree) ?*Self {
    if (self.getFirstChildId()) |id| {
        return tree.getNode(id);
    }
    return null;
}

// Editing host and editable node functions based on execCommand spec

/// Check if this node is an editing host (element with contenteditable="true")
pub fn isEditingHost(self: *Self, tree: *Tree) bool {
    _ = tree;
    // Must be an element node
    // if (self.kind != .node) return false;

    // Check if contenteditable attribute is set to "true"
    if (self.getAttribute("contenteditable")) |value| {
        return std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "");
    }

    return false;
}

/// Check if this node is editable according to execCommand spec:
/// - It is a node (not an editing host itself)
/// - It does not have contenteditable="false"
/// - Its parent is an editing host or editable
/// - It is an HTML element, SVG/Math element, or non-element with HTML parent
pub fn isEditable(self: *Self, tree: *Tree) bool {
    // Cannot be editable if it's an editing host
    if (self.isEditingHost(tree)) return false;

    // Check if contenteditable is explicitly false
    if (self.getAttribute("contenteditable")) |value| {
        if (std.mem.eql(u8, value, "false")) {
            return false;
        }
    }

    // Must have a parent that is either editing host or editable
    if (self.parent) |parent_id| {
        const parent = tree.getNode(parent_id);
        if (parent.isEditingHost(tree) or parent.isEditable(tree)) {
            return true;
        }
    }
    return false;
}

/// Get the editing host of this node:
/// - null if node is neither editable nor an editing host
/// - the node itself if it's an editing host
/// - the nearest ancestor that is an editing host if node is editable
pub fn getEditingHost(self: *Self, tree: *Tree) ?NodeId {
    if (self.isEditingHost(tree)) {
        return self.id;
    }

    var current_id = self.parent;
    while (current_id) |id| {
        const node = tree.getNode(id);
        if (node.isEditingHost(tree)) {
            return id;
        }
        current_id = node.parent;
    }

    return null;
}

/// Check if two nodes are in the same editing host
pub fn inSameEditingHost(self: *Self, tree: *Tree, other_id: NodeId) bool {
    const other = tree.getNode(other_id);
    const self_host = self.getEditingHost(tree);
    const other_host = other.getEditingHost(tree);

    return self_host != null and self_host == other_host;
}

// The replaceData(offset, count, data) method steps are to replace data with node this, offset offset, count count, and data data.
fn updateRangesAfterReplace(self: *Self, tree: *Tree, offset: u32, count: u32, new_data_length: usize) void {
    // Get the node's ID for comparison
    const node_id = self.id;
    var iter = tree.live_ranges.iterator();

    // Iterate through all live ranges in the tree
    while (iter.next()) |entry| {
        var range = entry.value_ptr;
        // Step 8: For each live range whose start node is node and start offset is greater than offset but less than or equal to offset plus count, set its start offset to offset.
        if (range.start.node_id == node_id and range.start.offset > offset and range.start.offset <= offset + count) {
            range.start.offset = offset;
        }

        // Step 9: For each live range whose end node is node and end offset is greater than offset but less than or equal to offset plus count, set its end offset to offset.
        if (range.end.node_id == node_id and range.end.offset > offset and range.end.offset <= offset + count) {
            range.end.offset = offset;
        }

        // Step 10: For each live range whose start node is node and start offset is greater than offset plus count, increase its start offset by data’s length and decrease it by count
        if (range.start.node_id == node_id and range.start.offset > offset + count) {
            const new_offset = range.start.offset + @as(u32, @intCast(new_data_length)) - count;
            range.start.offset = new_offset;
        }

        // Step 11: For each live range whose end node is node and end offset is greater than offset plus count, increase its end offset by data’s length and decrease it by count.
        if (range.end.node_id == node_id and range.end.offset > offset + count) {
            const new_offset = range.end.offset + @as(u32, @intCast(new_data_length)) - count;
            range.end.offset = new_offset;
        }
    }
}

pub fn setText(self: *Self, tree: *Tree, text: []const u8) !void {
    self.text.clearRetainingCapacity();
    self.requestRecompute();
    try self.text.append(tree.allocator, text);
}

pub fn setAttribute(self: *Self, name: []const u8, value: []const u8) !void {
    try self.attributes.set(name, value);
}
pub fn getAttribute(self: *Self, name: []const u8) ?Attributes.AttrValue {
    const attr = self.attributes.get(name);
    if (attr) |a| {
        return a.value;
    }
    return null;
}
pub fn hasAttribute(self: *Self, name: []const u8) bool {
    return self.attributes.get(name) != null;
}

pub fn removeAttribute(self: *Self, name: []const u8) void {
    self.attributes.remove(name);
}

// DOM compareDocumentPosition implementation
pub const DocumentPosition = struct {
    pub const DISCONNECTED: u16 = 0x01;
    pub const PRECEDING: u16 = 0x02;
    pub const FOLLOWING: u16 = 0x04;
    pub const CONTAINS: u16 = 0x08;
    pub const CONTAINED_BY: u16 = 0x10;
};

/// Compare the position of this node relative to another node according to DOM spec
/// Note: We don't support attributes as nodes, so we skip all attribute-related logic
pub fn compareDocumentPosition(self: *Self, tree: *Tree, other_id: NodeId) u16 {
    // If this is other, then return zero
    if (self.id == other_id) {
        return 0;
    }

    const node1_id = other_id;
    const node2_id = self.id;

    // Check if nodes are in the same tree
    const node1_root = tree.getNodeRoot(node1_id);
    const node2_root = tree.getNodeRoot(node2_id);

    if (node1_root != node2_root) {
        // Nodes are disconnected
        // Use node IDs for consistent ordering
        if (node1_id < node2_id) {
            return DocumentPosition.DISCONNECTED | DocumentPosition.PRECEDING;
        } else {
            return DocumentPosition.DISCONNECTED | DocumentPosition.FOLLOWING;
        }
    }

    // Check if node1 is ancestor of node2
    if (tree.isNodeAncestor(node1_id, node2_id)) {
        return DocumentPosition.CONTAINS | DocumentPosition.PRECEDING;
    }

    // Check if node1 is descendant of node2 (node2 is ancestor of node1)
    if (tree.isNodeAncestor(node2_id, node1_id)) {
        return DocumentPosition.CONTAINED_BY | DocumentPosition.FOLLOWING;
    }

    // Neither ancestor nor descendant - must be siblings or cousins
    // Use tree order to determine preceding/following
    const order = tree.treeOrder(node1_id, node2_id) catch {
        // Should not happen since we already checked they're in the same tree
        return DocumentPosition.DISCONNECTED;
    };

    switch (order) {
        .lt => return DocumentPosition.PRECEDING,
        .gt => return DocumentPosition.FOLLOWING,
        .eq => return 0, // Should not happen as we checked equality at the start
    }
}

// Client rect structure for returning bounds information
pub const ClientRect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};

/// Get all client rects for this node
/// For block elements, returns a single rect
/// For inline elements, returns one rect per line box
pub fn getClientRects(self: *Self, tree: *Tree, allocator: std.mem.Allocator) ![]ClientRect {
    const items = tree.render_list.items.items;

    var rects = ArrayList(ClientRect){};
    defer rects.deinit(allocator);

    var current_line_rects = ArrayList(ClientRect){};
    defer current_line_rects.deinit(allocator);
    var current_line_index: ?usize = null;

    for (items) |item| {
        switch (item) {
            .box => |box| {
                // For box elements, emit one rect
                if (box.doc_node_id == self.id) {
                    try rects.append(allocator, .{
                        .x = box.bounds.x,
                        .y = box.bounds.y,
                        .width = box.bounds.width,
                        .height = box.bounds.height,
                    });
                }
            },
            .text_fragment => |fragment| {
                // For text fragments, collect by line box
                if (fragment.doc_node_id == self.id) {
                    // If we're on a new line, flush previous line's fragments
                    if (current_line_index != null and current_line_index.? != fragment.linebox_index) {
                        if (current_line_rects.items.len > 0) {
                            // Merge contiguous fragments into one rect per line
                            var merged_rect = current_line_rects.items[0];
                            for (current_line_rects.items[1..]) |rect| {
                                const right = @max(merged_rect.x + merged_rect.width, rect.x + rect.width);
                                merged_rect.width = right - merged_rect.x;
                            }
                            try rects.append(allocator, merged_rect);
                            current_line_rects.clearRetainingCapacity();
                        }
                    }

                    current_line_index = fragment.linebox_index;
                    try current_line_rects.append(allocator, .{
                        .x = fragment.bounds.x,
                        .y = fragment.bounds.y,
                        .width = fragment.bounds.width,
                        .height = fragment.bounds.height,
                    });
                }
            },
            else => {},
        }
    }

    // Flush any remaining fragments
    if (current_line_rects.items.len > 0) {
        var merged_rect = current_line_rects.items[0];
        for (current_line_rects.items[1..]) |rect| {
            const right = @max(merged_rect.x + merged_rect.width, rect.x + rect.width);
            merged_rect.width = right - merged_rect.x;
        }
        try rects.append(allocator, merged_rect);
    }

    return try rects.toOwnedSlice(allocator);
}

/// Get the bounding client rect that encompasses all client rects
pub fn getBoundingClientRect(self: *Self, tree: *Tree) ClientRect {
    const rects = self.getClientRects(tree, std.heap.page_allocator) catch {
        return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    };
    defer std.heap.page_allocator.free(rects);

    if (rects.len == 0) {
        return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    }

    // Calculate bounding box that encompasses all rects
    var min_x = rects[0].x;
    var min_y = rects[0].y;
    var max_x = rects[0].x + rects[0].width;
    var max_y = rects[0].y + rects[0].height;

    for (rects[1..]) |rect| {
        min_x = @min(min_x, rect.x);
        min_y = @min(min_y, rect.y);
        max_x = @max(max_x, rect.x + rect.width);
        max_y = @max(max_y, rect.y + rect.height);
    }

    return .{
        .x = min_x,
        .y = min_y,
        .width = max_x - min_x,
        .height = max_y - min_y,
    };
}

pub fn getScrollHeight(self: *Self, tree: *Tree) f32 {
    const box_index = tree.render_list.getDocNodeBoxIndex(self.id) orelse return self.getClientHeight(tree);
    const render_list = tree.render_list.slice();
    const box: RenderList.BoxItem = render_list[box_index].box;
    if (box_index == box.last_index) {
        return self.getClientHeight(tree);
    }
    var max_y: f32 = -std.math.inf(f32);
    var min_y: f32 = std.math.inf(f32);
    var i = box_index + 1;

    while (i <= box.last_index) : (i += 1) {
        const item: RenderList.RenderItem = render_list[i];
        switch (item) {
            .line_box => |b| {
                max_y = @max(max_y, b.bounds.bottom());
                min_y = @min(min_y, b.bounds.top());
            },
            .box => |b| {
                max_y = @max(max_y, b.bounds.bottom());
                min_y = @min(min_y, b.bounds.top());
                if (b.is_scroll_container) {
                    i = b.last_index;
                }
            },
            else => {
                continue;
            },
        }
    }
    const scroll_height = @max(max_y - min_y, self.getClientHeight(tree));
    return scroll_height;
}
pub fn getScrollWidth(self: *Self, tree: *Tree) f32 {
    const box_index = tree.render_list.getDocNodeBoxIndex(self.id) orelse return self.getClientWidth(tree);
    const render_list = tree.render_list.slice();
    const box: RenderList.BoxItem = render_list[box_index].box;
    if (box_index == box.last_index) {
        return self.getClientWidth(tree);
    }
    var max_x: f32 = -std.math.inf(f32);
    var min_x: f32 = std.math.inf(f32);
    var i = box_index + 1;
    while (i <= box.last_index) : (i += 1) {
        const item: RenderList.RenderItem = render_list[i];

        switch (item) {
            .line_box => |b| {
                max_x = @max(max_x, b.bounds.right());
                min_x = @min(min_x, b.bounds.left());
            },
            .box => |b| {
                max_x = @max(max_x, b.bounds.right());
                min_x = @min(min_x, b.bounds.left());
                if (b.is_scroll_container) {
                    i = b.last_index;
                }
            },
            else => {},
        }
    }
    const scroll_width = @max(max_x - min_x, self.getClientWidth(tree));
    return scroll_width;
}

pub fn getScrollLeft(self: *Self) f32 {
    return self.scroll_offset.x;
}
pub fn getScrollTop(self: *Self) f32 {
    return self.scroll_offset.y;
}
pub fn getScrollTopMax(self: *Self, tree: *Tree) f32 {
    return self.getScrollHeight(tree) - self.getClientHeight(tree);
}
pub fn getScrollLeftMax(self: *Self, tree: *Tree) f32 {
    return self.getScrollWidth(tree) - self.getClientWidth(tree);
}
pub fn setScrollTop(self: *Self, tree: *Tree, value: f32) void {
    self.scroll_offset.y = std.math.clamp(value, 0, self.getScrollTopMax(tree));
}
pub fn setScrollLeft(self: *Self, tree: *Tree, value: f32) void {
    self.scroll_offset.x = std.math.clamp(value, 0, self.getScrollLeftMax(tree));
}

fn getLayoutNode(self: *Self, tree: *Tree) ?*LayoutTree.LayoutNode {
    const layout_node_id = tree.layout_tree.doc_to_layout.get(self.id) orelse return null;
    return tree.layout_tree.getNodePtr(layout_node_id);
}
pub fn getClientHeight(self: *Self, tree: *Tree) f32 {
    const layout_node = self.getLayoutNode(tree) orelse return 0;

    return layout_node.box.size.y - layout_node.box.border.top - layout_node.box.border.bottom;
}
pub fn getClientWidth(self: *Self, tree: *Tree) f32 {
    const layout_node = self.getLayoutNode(tree) orelse return 0;
    return layout_node.box.size.x - layout_node.box.border.left - layout_node.box.border.right;
}

// const ScrollDirection = enum(u8) {
//     up = 0,
//     down = 1,
//     left = 2,
//     right = 3,
// };
const ScrollDirection = enum(u8) {
    horizontal = 0,
    vertical = 1,
};

// FIXME: this is for quick check for implementing scroll on the js side. In the future, when we expose the computed styles
// we probably should do this in js land.
pub fn canScroll(self: *Self, tree: *Tree, direction: ScrollDirection, delta: f32) bool {
    const overflow = self.styles.overflow;
    switch (direction) {
        .vertical => {
            if (overflow.y != .scroll) return false;
            const scroll_top = self.getScrollTop();
            if (delta < 0) {
                return scroll_top > 0;
            }
            return scroll_top < self.getScrollTopMax(tree);
        },
        .horizontal => {
            if (overflow.x != .scroll) return false;
            const scroll_left = self.getScrollLeft();
            if (delta < 0) {
                return scroll_left > 0;
            }

            return scroll_left < self.getScrollLeftMax(tree);
        },
    }
}
