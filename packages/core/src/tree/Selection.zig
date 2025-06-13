const std = @import("std");
const Range = @import("Range.zig");
const BoundaryPoint = @import("./BoundaryPoint.zig");
const Tree = @import("./Tree.zig");
const Node = @import("./Node.zig");
const GraphemeIterator = @import("../uni/GraphemeBreak.zig").Iterator;
const LineBox = @import("../layout/compute/text/ComputedText.zig").LineBox;
const LineBoxPart = @import("../layout/compute/text/ComputedText.zig").TextPart;
const RenderList = @import("../layout/v2/RenderList.zig");
const measureText = @import("../uni/string-width.zig").visible.width.exclude_ansi_colors.utf8;
range_id: Range.Id,
direction: Direction,
pub const Id = Range.Id;

pub const Direction = enum(i2) {
    forward = 1,
    backward = -1,
    none = 0,
};
const Self = @This();
// pub fn format(self: Self, fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
//     // switch (self.direction) {
//     //     .forward =>
//     // }
//     try writer.print("⌖ {} ⚓ {}", .{ self.getAnchor(tree), self.getFocus(tree) });
// }

pub fn getRange(self: Self, tree: *Tree) *Range {
    // std.fmt.format
    return tree.live_ranges.getPtr(self.range_id).?;
}

pub fn getAnchor(self: Self, tree: *Tree) BoundaryPoint {
    return switch (self.direction) {
        .forward, .none => self.getRange(tree).start,
        .backward => self.getRange(tree).end,
    };
}

pub fn getFocus(self: Self, tree: *Tree) BoundaryPoint {
    return switch (self.direction) {
        .forward, .none => self.getRange(tree).end,
        .backward => self.getRange(tree).start,
    };
}

pub fn setRange(self: *Self, tree: *Tree, start: BoundaryPoint, end: BoundaryPoint) !void {
    const order = try Range.boundaryPointTreeOrder(tree, start, end);
    switch (order) {
        .lt => {
            var range = self.getRange(tree);
            try range.setStart(tree, start.node_id, start.offset);
            try range.setEnd(tree, end.node_id, end.offset);
            self.direction = .forward;
        },
        .gt => {
            var range = self.getRange(tree);
            try range.setStart(tree, end.node_id, end.offset);
            try range.setEnd(tree, start.node_id, start.offset);
            self.direction = .backward;
        },
        .eq => {
            var range = self.getRange(tree);
            try range.setStart(tree, start.node_id, start.offset);
            try range.setEnd(tree, end.node_id, end.offset);
            self.direction = .none;
        },
    }
}
pub fn setAnchor(self: *Self, tree: *Tree, anchor: BoundaryPoint) !void {
    const current_focus = self.getFocus(tree);
    try self.setRange(tree, anchor, current_focus);
}
pub fn setFocus(self: *Self, tree: *Tree, focus: BoundaryPoint) !void {
    const current_anchor = self.getAnchor(tree);
    try self.setRange(tree, current_anchor, focus);
}
pub fn deleteFromDocument(self: *Self, tree: *Tree) !void {
    const range = self.getRange(tree);
    try range.deleteContents(tree);
    self.direction = .none;
}

pub fn collapseToStart(self: *Self, tree: *Tree) !void {
    const range = self.getRange(tree);

    switch (self.direction) {
        .forward, .none => {
            range.end = range.start;
        },
        .backward => {
            range.start = range.end;
        },
    }
    self.direction = .none;
}

pub fn collapseToEnd(self: *Self, tree: *Tree) !void {
    const range = self.getRange(tree);
    switch (self.direction) {
        .forward, .none => {
            range.start = range.end;
        },
        .backward => {
            range.end = range.start;
        },
    }
    self.direction = .none;
}

pub fn extend(self: *Self, tree: *Tree, node_id: Node.NodeId, offset: ?u32) !void {
    const old_anchor = self.getAnchor(tree);
    try self.setRange(tree, old_anchor, BoundaryPoint{ .node_id = node_id, .offset = offset orelse 0 });
}
pub fn isCollapsed(self: Self) bool {
    return self.direction == .none;
}

pub const ExtendDirection = enum(u8) {
    forward = 0,
    backward = 1,
};

pub const ExtendGranularity = enum(u8) {
    character = 0,
    word = 1,
    line = 2,
    lineboundary = 3,
    documentboundary = 4,
};
// pub fn findLineBox(tree: *Tree, focus: BoundaryPoint) ?struct {
//     line_index: usize,
//     part_index: usize,
//     root_node_id: Node.NodeId,
// } {
//     if (tree.getNodeKind(focus.node_id) != .text) {
//         return null;
//     }
//     // find root
//     const root_node_id = findLineBoxAncestor(tree, focus.node_id);
//     const computed_style = tree.getComputedText(root_node_id) orelse return null;

//     if (computed_style.lines.items.len == 0) {
//         return null;
//     }

//     for (computed_style.lines.items, 0..) |line, i| {
//         for (line.parts.items, 0..) |part, j| {
//             if (part.node_id == focus.node_id and
//                 focus.offset >= part.node_offset and
//                 focus.offset <= part.node_offset + part.length)
//             {
//                 return .{ .line_index = i, .part_index = j, .root_node_id = root_node_id };
//             }
//         }
//     }
//     return null;
// }
// pub fn findLineBoxAncestor(tree: *Tree, node_id: Node.NodeId) Node.NodeId {
//     var current = node_id;
//     // if (tree.getNode(current).style.display.) {
//     //     return current;
//     // }
//     while (tree.getNode(current).parent) |parent| {
//         if (!tree.getStyle(parent).display.isInlineFlow()) {
//             break;
//         }
//         current = parent;
//     }
//     return current;
// }

// pub fn findInlineLineBox(
//     tree: *Tree,
//     start_node_id: Node.NodeId,
//     root_node_id: Node.NodeId,
//     direction: ExtendDirection,
// ) ?*LineBox {
//     // First handle the common case in tests: direct sibling text nodes that represent different lines
//     if (direction == .forward) {
//         var node_iter = tree.createNodeIterator(start_node_id);
//         while (node_iter.nextNode()) |node| {
//             if (tree.getNode(node).styles.display.outside == .@"inline") {
//                 if (node != root_node_id and !tree.isNodeDescendant(node, root_node_id)) break;
//                 const new_root = findLineBoxAncestor(tree, node);
//                 const new_computed = tree.getComputedText(new_root) orelse return null;
//                 if (new_computed.lines.items.len > 0) {
//                     return &new_computed.lines.items[0];
//                 }
//             }
//         }
//     } else {
//         const current_root = findLineBoxAncestor(tree, start_node_id);
//         var node_iter = tree.createNodeIterator(current_root);
//         _ = node_iter.previousNode(); // skip initial
//         while (node_iter.previousNode()) |node| {
//             if (tree.getNode(node).styles.display.outside == .@"inline") {
//                 if (node != root_node_id and !tree.isNodeDescendant(node, root_node_id)) break;
//                 const new_root = findLineBoxAncestor(tree, node);
//                 const new_computed = tree.getComputedText(new_root) orelse return null;
//                 if (new_computed.lines.items.len > 0) {
//                     return &new_computed.lines.items[new_computed.lines.items.len - 1];
//                 }
//             }
//         }
//     }
//     return null;
// }
// // const LineBoxIterator = struct {
// //     tree: *Tree,
// //     inline_run_root_node_id: Node.NodeId,
// //     root_node_limit: Node.NodeId,

// //     line_box_index: usize,

// //     fn next(self: *LineBoxIterator) ?struct { line_box_index: LineBox, part_index: usize } {
// //         const computed_text = self.tree.getComputedText(self.inline_run_root_node_id) orelse return null;
// //         if (self.line_box_index < computed_text.lines.items.len) {
// //         const line_box = computed_text.lines.items[self.line_box_index];
// //         self.line_box_index += 1;
// //         return .{ .line_box = line_box, .part_index = 0 };
// //         }
// //     }
// // };
// pub fn getNextLineBox(
//     tree: *Tree,
//     current_run_root_node_id: Node.NodeId,
//     current_line_index: usize,
//     root_node_limit: Node.NodeId,
//     // start_node_id: Node.NodeId,
// ) ?LineBox {
//     const computed_text = tree.getComputedText(current_run_root_node_id) orelse return null;
//     if (current_line_index + 1 < computed_text.lines.items.len) {
//         return computed_text.lines.items[current_line_index + 1];
//     }

//     const current_node_id = blk: {
//         var i: usize = current_line_index;
//         while (i >= 0) : (i -= 1) {
//             const line = computed_text.lines.items[i];
//             if (line.parts.items.len > 0) {
//                 break :blk line.parts.items[line.parts.items.len - 1].node_id;
//             }
//         }
//         return null;
//     };

//     var node_iter = tree.createNodeIterator(current_node_id);
//     while (node_iter.nextNode()) |node| {
//         if (tree.getNode(node).styles.display.outside == .@"inline") {
//             if (node != root_node_limit and !tree.isNodeDescendant(node, root_node_limit)) break;
//             const new_root = findLineBoxAncestor(tree, node);
//             const new_computed = tree.getComputedText(new_root) orelse return null;
//             if (new_computed.lines.items.len > 0) {
//                 return new_computed.lines.items[0];
//             }
//         }
//     }
//     return null;
// }
// pub fn getPreviousLineBox(
//     tree: *Tree,
//     current_run_root_node_id: Node.NodeId,
//     current_line_index: usize,
//     root_node_limit: Node.NodeId,
// ) ?LineBox {
//     const computed_text = tree.getComputedText(current_run_root_node_id) orelse return null;
//     if (current_line_index > 0) {
//         return computed_text.lines.items[current_line_index - 1];
//     }

//     const current_root = findLineBoxAncestor(tree, current_run_root_node_id);
//     var node_iter = tree.createNodeIterator(current_root);
//     _ = node_iter.previousNode(); // skip initial
//     while (node_iter.previousNode()) |node| {
//         if (tree.getNode(node).styles.display.outside == .@"inline") {
//             if (node != root_node_limit and !tree.isNodeDescendant(node, root_node_limit)) break;
//             const new_root = findLineBoxAncestor(tree, node);
//             const new_computed = tree.getComputedText(new_root) orelse return null;
//             if (new_computed.lines.items.len > 0) {
//                 return new_computed.lines.items[new_computed.lines.items.len - 1];
//             }
//         }
//     }
//     return null;
// }
// fn getNextLineBoxPart(
//     tree: *Tree,
//     current_run_root_node_id: Node.NodeId,
//     current_line_index: usize,
//     current_part_index: usize,
//     root_node_limit: Node.NodeId,
// ) ?LineBoxPart {
//     const computed_text = tree.getComputedText(current_run_root_node_id) orelse return null;
//     const line = computed_text.lines.items[current_line_index];
//     if (current_part_index + 1 < line.parts.items.len) {
//         return line.parts.items[current_part_index + 1];
//     }
//     const next_line = getNextLineBox(tree, current_run_root_node_id, current_line_index, root_node_limit) orelse return null;
//     if (next_line.parts.items.len > 0) {
//         return next_line.parts.items[0];
//     }
//     return null;
// }

// fn getPreviousLineBoxPart(
//     tree: *Tree,
//     current_run_root_node_id: Node.NodeId,
//     current_line_index: usize,
//     current_part_index: usize,
//     root_node_limit: Node.NodeId,
// ) ?LineBoxPart {
//     if (current_part_index > 0) {
//         const computed_text = tree.getComputedText(current_run_root_node_id) orelse return null;
//         const line = computed_text.lines.items[current_line_index];
//         return line.parts.items[current_part_index - 1];
//     }
//     const previous_line = getPreviousLineBox(tree, current_run_root_node_id, current_line_index, root_node_limit) orelse return null;

//     if (previous_line.parts.items.len > 0) {
//         return previous_line.parts.items[previous_line.parts.items.len - 1];
//     }
//     return null;
// }

// pub fn getHorizontalOffset(
//     tree: *Tree,
//     bp: BoundaryPoint,
// ) ?f32 {
//     const indexes = findLineBox(tree, bp) orelse return null;
//     const computed_text = tree.getComputedText(indexes.root_node_id) orelse return null;
//     const line = computed_text.lines.items[indexes.line_index];
//     const part = line.parts.items[indexes.part_index];
//     var pos = line.position.x;
//     for (line.parts.items, 0..) |current, i| {
//         if (i == indexes.part_index) break;
//         pos += current.size.x;
//     }
//     const slice = computed_text.slice(part.node_offset, bp.offset);
//     pos += @floatFromInt(measureText(slice));
//     return pos;
// }

// pub fn getBoundaryAt(
//     tree: *Tree,
//     focus: BoundaryPoint,
//     root_node_id: Node.NodeId,
//     granularity: ExtendGranularity,
//     direction: ExtendDirection,
//     ghost_horizontal_position: ?f32,
// ) ?BoundaryPoint {
//     if (granularity == .documentboundary) {
//         if (direction == .forward) {
//             var last_root: ?Node.NodeId = null;
//             var iter = tree.createNodeIterator(root_node_id);
//             while (iter.nextNode()) |node| {
//                 if (tree.getStyle(node).display.isInlineFlow()) {
//                     if (tree.getNode(node).parent) |parent| {
//                         if (!tree.getStyle(parent).display.isInlineFlow()) {
//                             last_root = node;
//                         }
//                     } else {
//                         last_root = node;
//                     }
//                 }
//             }
//             const root = last_root orelse return null;
//             const ct = tree.getComputedText(root) orelse return null;
//             const last_line = ct.lines.items[ct.lines.items.len - 1];
//             const last_part = last_line.parts.getLast();
//             return BoundaryPoint{ .node_id = last_part.node_id, .offset = @intCast(last_part.node_offset + last_part.length) };
//         } else {
//             var first_root: ?Node.NodeId = null;
//             var iter = tree.createNodeIterator(root_node_id);
//             while (iter.nextNode()) |node| {
//                 if (tree.getStyle(node).display.isInlineFlow()) {
//                     if (tree.getNode(node).parent) |parent| {
//                         if (!tree.getStyle(parent).display.isInlineFlow()) {
//                             first_root = node;
//                             break;
//                         }
//                     } else {
//                         first_root = node;
//                         break;
//                     }
//                 }
//             }
//             const root = first_root orelse return null;
//             const ct = tree.getComputedText(root) orelse return null;
//             const first_line = ct.lines.items[0];
//             const first_part = first_line.parts.items[0];
//             return BoundaryPoint{ .node_id = first_part.node_id, .offset = @intCast(first_part.node_offset) };
//         }
//     }
//     const line_box_indexes = findLineBox(tree, focus) orelse return null;
//     const computed_text = tree.getComputedText(line_box_indexes.root_node_id) orelse return null;
//     const line = computed_text.lines.items[line_box_indexes.line_index];
//     const part = line.parts.items[line_box_indexes.part_index];

//     if (granularity == .character) {
//         if (direction == .forward) {
//             // std.debug.print("FORWARD focus offset: {d} part end: {d}\n", .{ focus.offset, part.node_offset + part.length });
//             // var abs_offset: usize = part.node_offset;
//             if (focus.offset >= part.node_offset + part.length) {
//                 const target_part = getNextLineBoxPart(
//                     tree,
//                     line_box_indexes.root_node_id,
//                     line_box_indexes.line_index,
//                     line_box_indexes.part_index,
//                     root_node_id,
//                 ) orelse return null;

//                 const part_root = findLineBoxAncestor(tree, target_part.node_id);
//                 const part_ct = tree.getComputedText(part_root) orelse return null;
//                 var grapheme_iter = GraphemeIterator.init(
//                     part_ct.slice(
//                         target_part.node_offset,
//                         target_part.node_offset + target_part.length,
//                     ),
//                 );
//                 const next_grapheme = grapheme_iter.next() orelse return null;
//                 return BoundaryPoint{ .node_id = target_part.node_id, .offset = @intCast(target_part.node_offset + next_grapheme.len) };
//             }
//             // std.debug.print("SAME PART\n", .{});

//             var grapheme_iter = GraphemeIterator.init(computed_text.slice(focus.offset, part.node_offset + part.length));
//             // var abs_offset: usize = part.node_offset;
//             const next_grapheme = grapheme_iter.next() orelse return null;
//             return BoundaryPoint{ .node_id = part.node_id, .offset = @intCast(focus.offset + next_grapheme.len) };
//         } else {
//             // std.debug.print("BACKWARD focus offset: {d} part start: {d}\n", .{ focus.offset, part.node_offset });
//             if (focus.offset <= part.node_offset) {
//                 const target_part = getPreviousLineBoxPart(
//                     tree,
//                     line_box_indexes.root_node_id,
//                     line_box_indexes.line_index,
//                     line_box_indexes.part_index,
//                     root_node_id,
//                 ) orelse return null;

//                 const part_root = findLineBoxAncestor(tree, target_part.node_id);
//                 const part_ct = tree.getComputedText(part_root) orelse return null;
//                 var grapheme_iter = GraphemeIterator.init(
//                     part_ct.slice(
//                         target_part.node_offset,
//                         target_part.node_offset + target_part.length,
//                     ),
//                 );
//                 var abs_offset: usize = target_part.node_offset;
//                 while (grapheme_iter.next()) |grapheme| {
//                     if (abs_offset + grapheme.len >= focus.offset) {
//                         break;
//                     }
//                     abs_offset += grapheme.len;
//                 }
//                 return BoundaryPoint{ .node_id = target_part.node_id, .offset = @intCast(abs_offset) };
//             }
//             var grapheme_iter = GraphemeIterator.init(computed_text.slice(part.node_offset, focus.offset));
//             var abs_offset: usize = part.node_offset;
//             while (grapheme_iter.next()) |grapheme| {
//                 if (abs_offset + grapheme.len >= focus.offset) {
//                     break;
//                 }
//                 abs_offset += grapheme.len;
//             }
//             return BoundaryPoint{ .node_id = part.node_id, .offset = @intCast(abs_offset) };
//         }
//     }

//     if (granularity == .lineboundary) {
//         if (direction == .forward) {
//             const last_part = line.parts.getLast();

//             return BoundaryPoint{ .node_id = last_part.node_id, .offset = @intCast(last_part.node_offset + last_part.length) };
//         }
//         const first_part = line.parts.items[0];
//         return BoundaryPoint{ .node_id = first_part.node_id, .offset = @intCast(first_part.node_offset) };
//     }
//     if (granularity == .line) {
//         const offset_horizontal_position = ghost_horizontal_position orelse
//             (getHorizontalOffset(tree, focus) orelse line.position.x);

//         // const maybe_target_line = findInlineLineBox(tree, focus.node_id, root_node_id, direction);
//         const maybe_target_line = switch (direction) {
//             .forward => getNextLineBox(
//                 tree,
//                 line_box_indexes.root_node_id,
//                 line_box_indexes.line_index,
//                 root_node_id,
//             ),
//             .backward => getPreviousLineBox(
//                 tree,
//                 line_box_indexes.root_node_id,
//                 line_box_indexes.line_index,
//                 root_node_id,
//             ),
//         };
//         // std.debug.print("maybe_target_line: {any}\n", .{maybe_target_line});
//         if (maybe_target_line) |target_line| {
//             if (target_line.parts.items.len == 0) return null;

//             var pos = target_line.position.x;

//             var part_index: usize = 0;

//             while (part_index < target_line.parts.items.len - 1) {
//                 const current_part = target_line.parts.items[part_index];
//                 if (pos + current_part.size.x >= offset_horizontal_position) {
//                     break;
//                 }
//                 pos += current_part.size.x;
//                 part_index += 1;
//             }
//             const target_part = target_line.parts.items[part_index];

//             const part_root = findLineBoxAncestor(tree, target_part.node_id);
//             // std.debug.print("part_root: {any}\n", .{part_root});
//             var target_computed_text = tree.getComputedText(part_root) orelse return null;
//             const part_slice = target_computed_text.slice(target_part.node_offset, target_part.node_offset + target_part.length);
//             var grapheme_iter = GraphemeIterator.init(part_slice);
//             var index = target_part.node_offset;
//             while (grapheme_iter.next()) |grapheme| {
//                 const grapheme_width: f32 = @floatFromInt(measureText(grapheme.bytes(part_slice)));
//                 if (pos + grapheme_width > offset_horizontal_position) {
//                     break;
//                 }
//                 pos += grapheme_width;
//                 index += grapheme.len;
//             }
//             // std.debug.print("node_id: {d} offset: {d}\n", .{ target_part.node_id, index });
//             return .{
//                 .node_id = target_part.node_id,
//                 .offset = @intCast(index),
//             };
//         }
//         if (direction == .forward) {
//             const last = line.parts.getLast();
//             return BoundaryPoint{ .node_id = last.node_id, .offset = @intCast(last.node_offset + last.length) };
//         }
//         if (direction == .backward) {
//             const first = line.parts.items[0];
//             return BoundaryPoint{ .node_id = first.node_id, .offset = @intCast(first.node_offset) };
//         }
//     }
//     return null;
// }
// pub fn extendBy(
//     self: *Self,
//     tree: *Tree,
//     granularity: ExtendGranularity,
//     direction: ExtendDirection,
//     ghost_horizontal_position: ?f32,
//     root_node_id: Node.NodeId,
// ) !void {
//     const current_focus = self.getFocus(tree);
//     const new_focus = getBoundaryAt(tree, current_focus, root_node_id, granularity, direction, ghost_horizontal_position) orelse return;
//     try self.setFocus(tree, new_focus);
// }

// // ----- Tests -----

const testing = std.testing;
fn expectSelection(selection: *Self, description: []const u8, tree: *Tree, anchor: BoundaryPoint, focus: BoundaryPoint, direction: Direction) !void {
    const actual_anchor = selection.getAnchor(tree);
    const actual_focus = selection.getFocus(tree);
    const actual_direction = selection.direction;

    if (actual_anchor.node_id != anchor.node_id or actual_anchor.offset != anchor.offset or actual_focus.node_id != focus.node_id or actual_focus.offset != focus.offset or actual_direction != direction) {
        var buf = std.ArrayList(u8).init(testing.allocator);
        defer buf.deinit();
        const buf_writer = buf.writer().any();

        try buf_writer.print("\n\n\x1b[31m✗\x1b[0m {s}\n\n", .{description});
        try buf_writer.print("Selection mismatch: \n\n", .{});
        try tree.print(buf_writer);
        try buf_writer.writeAll("\n\nExpected:\n");

        const maybe_expected_selection_id = tree.createSelection(anchor, focus) catch |err| blk: {
            try buf_writer.print("Failed to create selection: {s}\n", .{@errorName(err)});
            break :blk null;
        };
        if (maybe_expected_selection_id) |expected_selection_id| {
            const expected_selection = tree.getSelection(expected_selection_id);
            const expected_range = expected_selection.getRange(tree);
            try expected_range.formatTree(tree, 0, buf_writer, .{
                // .collapsed_caret = "|",
                // .range_close = "]",
                // .range_open = "[",
            });
        }

        try buf_writer.writeAll("\nActual:\n");
        const actual_range = selection.getRange(tree);
        try actual_range.formatTree(tree, 0, buf_writer, .{
            // .collapsed_caret = "|",
            // .range_close = "]",
            // .range_open = "[",
        });
        try buf_writer.writeAll("\n");

        try buf_writer.print("expected: {any} {s} {any}\n", .{ anchor, if (direction == .forward) "⮕" else "⬅", focus });
        try buf_writer.print("actual:   {any} {s} {any}\n", .{ actual_anchor, if (actual_direction == .forward) "⮕" else "⬅", actual_focus });
        try std.debug.panic("{s}\n", .{buf.items});

        return error.TestExpectedEqual;
    }
    std.debug.print("\x1b[32m✓\x1b[0m {s}\n", .{description});
}

// test "Selection creation and basic movement" {
//     const allocator = testing.allocator;

//     var tree = try Tree.parseTree(allocator,
//         \\<view
//         \\  style="display:flex;flex-direction: column;background-color: red; height:10;width:50;"
//         \\>
//         \\<view style="width:30;background-color: blue;text-align: center;margin:auto">
//         \\    <text>Lorem ipsum dolor sit amet </text>
//         \\    <text>Lorem ipsum dolor sit amet </text>
//         \\    <text>Lorem ipsum dolor sit amet </text>
//         \\ </view>
//         \\</view>
//     );
//     defer tree.deinit();

//     try computeLayout(&tree, allocator, .{
//         .x = .{
//             .definite = 50,
//         },
//         .y = .max_content,
//     });

//     // Node structure with shell + inner text nodes:
//     // 0: root view
//     // 1: inner view
//     // 2: first text shell node
//     // 3: first text inner node
//     // 4: second text shell node
//     // 5: second text inner node
//     // 6: third text shell node
//     // 7: third text inner node

//     // Use an inner text node for selection
//     const text_node_id: Node.NodeId = 3; // First text inner node
//     const second_text_node_id: Node.NodeId = 5; // Second text inner node
//     const third_text_node_id: Node.NodeId = 7; // Third text inner node
//     _ = third_text_node_id; // autofix

//     // Create a selection with a starting point
//     const focus = BoundaryPoint{ .node_id = text_node_id, .offset = 4 };
//     const selection_id = try tree.createSelection(focus, null);
//     var selection = tree.getSelection(selection_id);

//     // Test initial state - when created at a single point, direction is "none"
//     try expectSelection(
//         selection,
//         "Initial selection should be collapsed at offset 4 with direction none",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 4 },
//         .{ .node_id = text_node_id, .offset = 4 },
//         Direction.none,
//     );

//     // Test character forward movement
//     // Anchor stays at 4, focus moves to 5, direction is forward because focus is after anchor
//     try selection.extendBy(&tree, .character, .forward, null, Tree.ROOT_NODE_ID);
//     try expectSelection(
//         selection,
//         "After moving forward by a character, focus should be at offset 5 with forward direction",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 4 },
//         .{ .node_id = text_node_id, .offset = 5 },
//         Direction.forward,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 4 }, .{ .node_id = text_node_id, .offset = 5 });

//     // Test character backward movement from position 5 to 4
//     // This moves the focus back to where the anchor is, so direction becomes none
//     try selection.extendBy(&tree, .character, .backward, null, Tree.ROOT_NODE_ID);
//     // At this point, focus is at the same position as anchor (both at offset 4)
//     try expectSelection(
//         selection,
//         "After moving backward by a character, selection should collapse with direction none",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 4 },
//         .{ .node_id = text_node_id, .offset = 4 },
//         Direction.none,
//     );

//     // Test moving character backward across segment boundary
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 0 }, .{ .node_id = text_node_id, .offset = 21 });
//     inline for (0..20) |i| {
//         // std.debug.print("BACKWARD {d}\n", .{i});
//         try selection.extendBy(&tree, .character, .backward, null, Tree.ROOT_NODE_ID);
//         try expectSelection(
//             selection,
//             "After moving backward by a character across segment boundary, focus should be at offset 3 with backward direction",
//             &tree,
//             .{ .node_id = text_node_id, .offset = 0 },
//             .{ .node_id = text_node_id, .offset = @intCast(20 - i) },
//             Direction.forward,
//         );
//     }

//     try selection.setRange(&tree, .{ .node_id = second_text_node_id, .offset = 0 }, .{ .node_id = second_text_node_id, .offset = 0 });
//     try selection.extendBy(&tree, .character, .backward, null, Tree.ROOT_NODE_ID);
//     try expectSelection(
//         selection,
//         "After moving backward by a character inline run boundary",
//         &tree,
//         .{ .node_id = second_text_node_id, .offset = 0 },
//         .{ .node_id = text_node_id, .offset = 22 },
//         Direction.backward,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 4 }, .{ .node_id = text_node_id, .offset = 4 });

//     // Now let's move backward again, which will move focus before anchor
//     // Anchor stays at 4, focus moves to 3, direction becomes backward
//     try selection.extendBy(&tree, .character, .backward, null, Tree.ROOT_NODE_ID);
//     try expectSelection(
//         selection,
//         "After moving backward again, focus should be at offset 3 with backward direction",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 4 },
//         .{ .node_id = text_node_id, .offset = 3 },
//         Direction.backward,
//     );

//     // Explicitly set the range for testing line movement
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 4 }, .{ .node_id = text_node_id, .offset = 4 });

//     // Test line forward movement (going to next line)
//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);
//     // We can't verify the exact position, but we can verify direction is forward
//     // and that focus has moved to a reasonable position
//     const line_forward_focus = selection.getFocus(&tree);
//     try expectSelection(
//         selection,
//         "After moving to next line, focus should move down while maintaining approx column position",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 4 },
//         line_forward_focus,
//         Direction.forward,
//     );

//     // Explicitly store the current position before testing backward movement
//     const current_anchor = selection.getAnchor(&tree);
//     const current_focus = selection.getFocus(&tree);
//     try selection.setRange(&tree, current_anchor, current_focus);

//     // Test line backward movement (going back to original line)
//     try selection.extendBy(&tree, .line, .backward, null, Tree.ROOT_NODE_ID);
//     // We can't reliably predict the exact direction without knowing the layout
//     const line_backward_focus = selection.getFocus(&tree);
//     // We'll just use the helper to assert whatever state we currently have
//     try expectSelection(
//         selection,
//         "After moving back to original line, focus should return to approx original position",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 4 },
//         line_backward_focus,
//         selection.direction,
//     );
// }

// test "Selection with XML attributes" {
//     const allocator = testing.allocator;

//     var tree = try Tree.parseTree(allocator,
//         \\<view
//         \\  style="display:flex;flex-direction: column;background-color: red; height:10;width:50;"
//         \\>
//         \\<view selectionStart="3" style="width:30;background-color: blue;text-align: center;margin:auto">
//         \\    <text>Lorem ipsum dolor sit amet </text>
//         \\    <text>Lorem ipsum dolor sit amet </text>
//         \\    <text selectionEnd="10">Lorem ipsum dolor sit amet </text>
//         \\ </view>
//         \\</view>
//     );
//     defer tree.deinit();

//     try computeLayout(&tree, allocator, .{
//         .x = .{
//             .definite = 50,
//         },
//         .y = .max_content,
//     });

//     // Node structure with shell + inner text nodes:
//     // 0: root view
//     // 1: inner view with selectionStart
//     // 2: first text shell node
//     // 3: first text inner node
//     // 4: second text shell node
//     // 5: second text inner node
//     // 6: third text shell node with selectionEnd
//     // 7: third text inner node

//     const view_node_id: Node.NodeId = 1; // Inner view with selectionStart
//     const text_node_id: Node.NodeId = 7; // Third text inner node

//     // Create a selection based on attributes
//     const start = BoundaryPoint{ .node_id = view_node_id, .offset = 3 };
//     const end = BoundaryPoint{ .node_id = text_node_id, .offset = 10 };
//     const selection_id = try tree.createSelection(start, end);
//     var selection = tree.getSelection(selection_id);

//     // Test initial state - the actual implementation creates this with backward direction
//     // This is because the selection is created with tree order being considered
//     try expectSelection(
//         selection,
//         "Selection created from XML attributes should have correct endpoints and direction",
//         &tree,
//         .{ .node_id = view_node_id, .offset = 3 },
//         .{ .node_id = text_node_id, .offset = 10 },
//         Direction.backward,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = view_node_id, .offset = 3 }, .{ .node_id = text_node_id, .offset = 10 });

//     // Test extending forward - focus moves forward, anchor stays
//     try selection.extendBy(&tree, .character, .forward, null, Tree.ROOT_NODE_ID);
//     try expectSelection(
//         selection,
//         "After extending forward by a character, focus should move to offset 11",
//         &tree,
//         .{ .node_id = view_node_id, .offset = 3 },
//         .{ .node_id = text_node_id, .offset = 11 },
//         Direction.backward,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = view_node_id, .offset = 3 }, .{ .node_id = text_node_id, .offset = 11 });

//     // Test moving backward - focus moves backward but stays after anchor
//     try selection.extendBy(&tree, .character, .backward, null, Tree.ROOT_NODE_ID);
//     // Direction remains backward as we started with backward
//     try expectSelection(
//         selection,
//         "After extending backward by a character, focus should return to offset 10",
//         &tree,
//         .{ .node_id = view_node_id, .offset = 3 },
//         .{ .node_id = text_node_id, .offset = 10 },
//         Direction.backward,
//     );
// }

// test "Selection line movement" {
//     const allocator = testing.allocator;

//     var tree = try Tree.parseTree(allocator,
//         \\<view
//         \\  style="display:flex;flex-direction: column;background-color: red; height:10;width:50;"
//         \\>
//         \\<view style="width:30;background-color: blue;text-align: center;margin:auto">
//         \\    <text>First line</text>
//         \\    <text>Second line</text>
//         \\    <text>Third line</text>
//         \\ </view>
//         \\</view>
//     );
//     defer tree.deinit();

//     try computeLayout(&tree, allocator, .{
//         .x = .{
//             .definite = 50,
//         },
//         .y = .max_content,
//     });

//     // Node structure with shell + inner text nodes:
//     // 0: root view
//     // 1: inner view
//     // 2: first text shell node
//     // 3: first text inner node
//     // 4: second text shell node
//     // 5: second text inner node
//     // 6: third text shell node
//     // 7: third text inner node

//     const first_text_node_id: Node.NodeId = 3; // First text inner node
//     const second_text_node_id: Node.NodeId = 5; // Second text inner node
//     const third_text_node_id: Node.NodeId = 7; // Third text inner node

//     // Create selection in first line at offset 2 (the 'r' in "First")
//     const start = BoundaryPoint{ .node_id = first_text_node_id, .offset = 2 };
//     const selection_id = try tree.createSelection(start, null);
//     var selection = tree.getSelection(selection_id);

//     // Verify initial state - collapsed selection has direction none
//     try expectSelection(
//         selection,
//         "Initial selection in line test should be collapsed at offset 2 in first line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         Direction.none,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = first_text_node_id, .offset = 2 }, .{ .node_id = first_text_node_id, .offset = 2 });

//     // Test moving down one line
//     // Since we're at offset 2 in "First line" (the 'r'),
//     // we should end up at offset 2 in "Second line" (the 'c')
//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);

//     // For simple ASCII text, character width is predictable (1 char = 1 width unit)
//     // So we should maintain the same horizontal position (offset 2)
//     try expectSelection(
//         selection,
//         "Moving down one line should put focus at offset 2 in second line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = second_text_node_id, .offset = 2 },
//         Direction.forward,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = first_text_node_id, .offset = 2 }, .{ .node_id = second_text_node_id, .offset = 2 });

//     // Test moving down one more line
//     // Similarly, we should end up at offset 2 in "Third line" (the 'i')
//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);

//     try expectSelection(
//         selection,
//         "Moving down one more line should put focus at offset 2 in third line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = third_text_node_id, .offset = 2 },
//         Direction.forward,
//     );

//     // Explicitly set the range for the next test
//     try selection.setRange(&tree, .{ .node_id = first_text_node_id, .offset = 2 }, .{ .node_id = third_text_node_id, .offset = 2 });

//     // Test moving up one line
//     // Going back to offset 2 in "Second line"
//     try selection.extendBy(&tree, .line, .backward, null, Tree.ROOT_NODE_ID);

//     try expectSelection(
//         selection,
//         "Moving up one line should put focus back at offset 2 in second line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = second_text_node_id, .offset = 2 },
//         Direction.forward,
//     );
// }
// test "Selection movement across boundaries" {
//     const allocator = testing.allocator;

//     var tree = try Tree.parseTree(allocator,
//         \\<view
//         \\  style="display:flex;flex-direction: column;background-color: red; height:10;width:50;"
//         \\>
//         \\  <view style="width:30;background-color: blue;text-align: center;margin:auto">
//         \\    <text>First line</text>
//         \\    <view>
//         \\       <text>Second line</text>
//         \\    </view>
//         \\    <view>
//         \\        <view>
//         \\            <text>Third line</text>
//         \\        </view>
//         \\      </view>
//         \\   </view>
//         \\</view>
//     );
//     defer tree.deinit();

//     try computeLayout(&tree, allocator, .{
//         .x = .{
//             .definite = 50,
//         },
//         .y = .max_content,
//     });

//     const first_text_node_id: Node.NodeId = 3; // First text inner node
//     const second_text_node_id: Node.NodeId = 6; // Second text inner node
//     const third_text_node_id: Node.NodeId = 10; // Third text inner node

//     const start = BoundaryPoint{ .node_id = first_text_node_id, .offset = 2 };
//     const selection_id = try tree.createSelection(start, null);
//     const selection = tree.getSelection(selection_id);

//     try expectSelection(
//         selection,
//         "Initial selection in line test should be collapsed at offset 2 in first line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         Direction.none,
//     );

//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);

//     try expectSelection(
//         selection,
//         "Moving down one line should put focus at offset 2 in second line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = second_text_node_id, .offset = 2 },
//         Direction.forward,
//     );

//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);

//     try expectSelection(
//         selection,
//         "Moving down one line should put focus at offset 2 in third line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 2 },
//         .{ .node_id = third_text_node_id, .offset = 2 },
//         Direction.forward,
//     );
// }

// test "Move selection from long line to short line" {
//     const allocator = testing.allocator;

//     var tree = try Tree.parseTree(allocator,
//         \\<view
//         \\  style="display:flex;flex-direction: column;background-color: red; height:10;width:50;"
//         \\>
//         \\  <view style="width:40;background-color: blue;text-align: center;margin:auto">
//         \\    <text>This is a long paragraph of text.</text>
//         \\    <text>short</text>
//         \\    <text>This is another long paragraph of text.</text>
//         \\  </view>
//         \\</view>
//     );
//     defer tree.deinit();

//     try computeLayout(&tree, allocator, .{
//         .x = .{
//             .definite = 50,
//         },
//         .y = .max_content,
//     });

//     const first_text_node_id: Node.NodeId = 3; // First text inner node
//     const second_text_node_id: Node.NodeId = 5; // Second text inner node
//     const third_text_node_id: Node.NodeId = 7; // Third text inner node
//     _ = third_text_node_id; // autofix

//     const start = BoundaryPoint{ .node_id = first_text_node_id, .offset = 20 };
//     const selection_id = try tree.createSelection(start, null);
//     const selection = tree.getSelection(selection_id);

//     try expectSelection(
//         selection,
//         "Initial selection in line test should be collapsed at offset 2 in first line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 20 },
//         .{ .node_id = first_text_node_id, .offset = 20 },
//         Direction.none,
//     );

//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);
//     try expectSelection(
//         selection,
//         "Moving down one, but the next lien is shorter so offset should be at the end of the line",
//         &tree,
//         .{ .node_id = first_text_node_id, .offset = 20 },
//         .{ .node_id = second_text_node_id, .offset = 5 },
//         Direction.forward,
//     );
//     // try expectSelection(
//     //     selection,
//     //     "Moving down one line should put focus at offset 2 in second line",
//     //     &tree,
//     //     .{ .node_id = first_text_node_id, .offset = 2 },
//     //     .{ .node_id = second_text_node_id, .offset = 2 },
//     //     Direction.forward,
//     // );
// }

// test "Selection with wrapped multi-line text" {
//     const allocator = testing.allocator;

//     var tree = try Tree.parseTree(allocator,
//         \\<view
//         \\  style="display:flex;flex-direction: column;background-color: red; height:20;width:30;"
//         \\>
//         \\<view style="width:20;background-color: blue;text-align: center;margin:auto">
//         \\    <text>This is a long paragraph of text that will wrap to multiple lines given the narrow container width. The selection should be able to navigate between the wrapped lines properly.</text>
//         \\ </view>
//         \\</view>
//     );
//     defer tree.deinit();

//     try tree.computeLayout(allocator, .{
//         .x = .{
//             .definite = 30,
//         },
//         .y = .max_content,
//     });

//     // Node structure for this test:
//     // 0: root view
//     // 1: inner view
//     // 2: text shell node
//     // 3: text inner node

//     const text_node_id: Node.NodeId = 3; // Text inner node

//     // Create a selection at the beginning of the text
//     const start = BoundaryPoint{ .node_id = text_node_id, .offset = 5 }; // Position at "is a"
//     const selection_id = try tree.createSelection(start, null);
//     var selection = tree.getSelection(selection_id);

//     // Verify initial state
//     try expectSelection(
//         selection,
//         "Initial selection should be at offset 5 in the long text",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 5 },
//         .{ .node_id = text_node_id, .offset = 5 },
//         Direction.none,
//     );

//     // Test moving to line boundary - end of first line
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 5 }, .{ .node_id = text_node_id, .offset = 5 });
//     try selection.extendBy(&tree, .lineboundary, .forward, null, Tree.ROOT_NODE_ID);

//     const first_line_end = selection.getFocus(&tree);
//     try expectSelection(
//         selection,
//         "Moving to end of first line should reach the line boundary",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 5 },
//         first_line_end,
//         Direction.forward,
//     );

//     // Test moving down to second line while maintaining horizontal position
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 5 }, .{ .node_id = text_node_id, .offset = 5 });
//     try selection.extendBy(&tree, .line, .forward, null, Tree.ROOT_NODE_ID);

//     const second_line_pos = selection.getFocus(&tree);
//     try expectSelection(
//         selection,
//         "Moving to next wrapped line should maintain approximate horizontal position",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 5 },
//         second_line_pos,
//         Direction.forward,
//     );

//     // Test moving to beginning of current line
//     const current_focus = selection.getFocus(&tree);
//     try selection.setRange(&tree, current_focus, current_focus);
//     try selection.extendBy(&tree, .lineboundary, .backward, null, Tree.ROOT_NODE_ID);

//     const line_start = selection.getFocus(&tree);
//     try expectSelection(
//         selection,
//         "Moving to start of line should reach the beginning of the wrapped line",
//         &tree,
//         current_focus,
//         line_start,
//         Direction.backward,
//     );

//     // Test moving to document start
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 50 }, .{ .node_id = text_node_id, .offset = 50 });
//     try selection.extendBy(&tree, .documentboundary, .backward, null, Tree.ROOT_NODE_ID);

//     try expectSelection(
//         selection,
//         "Moving to document start should reach offset 0",
//         &tree,
//         .{ .node_id = text_node_id, .offset = 50 },
//         .{ .node_id = text_node_id, .offset = 0 },
//         Direction.backward,
//     );

//     // Test moving to document end
//     try selection.setRange(&tree, .{ .node_id = text_node_id, .offset = 10 }, .{ .node_id = text_node_id, .offset = 10 });
//     try selection.extendBy(&tree, .documentboundary, .forward, null, Tree.ROOT_NODE_ID);

//     // const text_length = tree.getNodeText(text_node_id).len;
//     // try expectSelection(
//     //     selection,
//     //     "Moving to document end should reach the end of the text",
//     //     &tree,
//     //     .{ .node_id = text_node_id, .offset = 10 },
//     //     .{ .node_id = text_node_id, .offset = text_length },
//     //     Direction.forward,
//     // );
// }

pub fn modify(
    selection: *Self,
    tree: *Tree,
    direction: ExtendDirection,
    granularity: ExtendGranularity,
) !void {
    const focus = selection.getFocus(tree);
    // tree.render_list.
    std.debug.print("{any}\n", .{tree.render_list});
    const focus_item_index = findBpRenderItem(tree, focus) orelse return;
    switch (granularity) {
        .character => {
            if (getNextCharacter(tree, focus_item_index, focus, direction)) |new_bp| {
                try selection.setFocus(tree, new_bp);
            }
        },
        else => {
            @panic("TODO");
        },
    }
}

fn getNextCharacter(
    tree: *Tree,
    focus_item_index: usize,
    bp: BoundaryPoint,
    direction: ExtendDirection,
) ?BoundaryPoint {
    const focus_item = tree.render_list.slice()[focus_item_index];
    var fragment: RenderList.TextFragmentItem = undefined;
    var offset: u32 = bp.offset;

    switch (focus_item) {
        .text_fragment => |_fragment| {
            fragment = _fragment;
            if (bp.offset >= fragment.dom_range.end or bp.offset <= fragment.dom_range.start) {
                // we should find the next text fragment
                const next_fragment_index: usize = findNextTextFragmentFrom(tree, focus_item_index, direction) orelse return null;
                fragment = tree.render_list.slice()[next_fragment_index].text_fragment;
                offset = switch (direction) {
                    .forward => fragment.dom_range.start,
                    .backward => fragment.dom_range.end,
                };
            }
        },
        else => {
            const next_fragment_index: usize = findNextTextFragmentFrom(tree, focus_item_index, direction) orelse return null;
            fragment = tree.render_list.slice()[next_fragment_index].text_fragment;
            offset = switch (direction) {
                .forward => fragment.dom_range.start,
                .backward => fragment.dom_range.end,
            };
        },
    }
    // const slice = tree.render_list.slice();
    var pos = fragment.dom_range.start;
    var iter = GraphemeIterator.init(fragment.text);
    if (direction == .forward) {
        while (iter.next()) |grapheme| {
            pos += grapheme.len;
            if (pos > offset) {
                return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = @min(pos, fragment.dom_range.end) };
            }
        }
    } else {
        while (iter.next()) |grapheme| {
            if (pos + grapheme.len >= offset) {
                return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = @max(pos, fragment.dom_range.start) };
            }
            pos += grapheme.len;
        }
    }
    return null;
}
fn findNextTextFragmentFrom(
    tree: *Tree,
    focus_item_index: usize,
    direction: ExtendDirection,
) ?usize {
    const list = tree.render_list.slice();
    var i: usize = focus_item_index;

    while (i > 0 and i < list.len - 1) {
        switch (direction) {
            .forward => i += 1,
            .backward => i -= 1,
        }
        switch (list[i]) {
            .text_fragment => |fragment| {
                if (fragment.text.len > 0) {
                    return i;
                }
            },
            else => {},
        }
    }
    return null;
}

pub fn findBpRenderItem(
    tree: *Tree,
    bp: BoundaryPoint,
) ?usize {
    var candidate_box: ?usize = null;
    var candidate_text_fragment: ?usize = null;
    for (tree.render_list.slice(), 0..) |item, i| {
        switch (item) {
            .box => |box| {
                if (candidate_text_fragment != null) {
                    return candidate_text_fragment;
                }
                if (box.doc_node_id != bp.node_id) {
                    continue;
                }
                candidate_box = i;
            },
            .text_fragment => |fragment| {
                if (fragment.doc_node_id != bp.node_id) {
                    if (candidate_text_fragment != null) {
                        // we are past it, return the last candidate
                        return candidate_text_fragment;
                    }
                    continue;
                }
                if (fragment.dom_range.end >= bp.offset) {
                    return i;
                } else {
                    candidate_text_fragment = i;
                }
            },
            else => {},
        }
    }
    return candidate_text_fragment orelse candidate_box;
}
