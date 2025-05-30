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
pub const NodeKind = enum(u8) {
    node = 1,
    text = 2,
};

id: NodeId,
kind: NodeKind = .node,
parent: ?NodeId = null,
children: ArrayList(NodeId) = .{},
styles: Style,
unrounded_layout: Layout = Layout.EMPTY,
layout: Layout = Layout.EMPTY,
cache: Cache = .{},
text: String = .{},

scroll_offset: Point(f32) = .{
    .x = 0,
    .y = 0,
},
computed_text: ?ComputedText = null,
text_root_id: ?NodeId = null,
content_editable: ContentEditable = .false,
tabindex: i32 = -1,

// Element ID for getElementById lookups
element_id: []const u8 = "",

// Invalidation tracking
needs_repaint: bool = false,
needs_recompute: bool = false,
needs_regenerate: bool = false,

const Self = @This();
pub const NodeId = usize;
pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    self.children.deinit(allocator);
    self.text.deinit(allocator);

    if (self.computed_text) |*computed_text| {
        computed_text.deinit();
    }

    if (self.element_id.len > 0) {
        allocator.free(self.element_id);
    }
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

pub const ContentEditable = enum {
    true,
    false,
    plaintext_only,
};

pub fn replaceData(self: *Self, tree: *Tree, offset: u32, count: u32, data: []const u8) !void {
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

pub fn updateRangesAfterReplace(self: *Self, tree: *Tree, offset: u32, count: u32, new_data_length: usize) void {
    // Get the node's ID for comparison
    const node_id = self.id;
    var iter = tree.live_ranges.iterator();

    // Iterate through all live ranges in the tree
    while (iter.next()) |entry| {
        var range = entry.value_ptr;
        // Step 8: Update start points in the affected range
        if (range.start.node_id == node_id and range.start.offset > offset and range.start.offset <= offset + count) {
            range.start.offset = offset;
        }

        // Step 9: Update end points in the affected range
        if (range.end.node_id == node_id and range.end.offset > offset and range.end.offset <= offset + count) {
            range.end.offset = offset;
        }

        // Step 10: Update start points after the affected range
        if (range.start.node_id == node_id and range.start.offset > offset + count) {
            const new_offset = range.start.offset + @as(u32, @intCast(new_data_length)) - count;
            range.start.offset = new_offset;
        }

        // Step 11: Update end points after the affected range
        if (range.end.node_id == node_id and range.end.offset > offset + count) {
            const new_offset = range.end.offset + @as(u32, @intCast(new_data_length)) - count;
            range.end.offset = new_offset;
        }
    }
}

pub fn setText(self: *Self, tree: *Tree, text: []const u8) !void {
    self.text.clearRetainingCapacity();
    try self.text.append(tree.allocator, text);
}
