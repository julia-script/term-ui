const std = @import("std");
const Range = @import("Range.zig");
const BoundaryPoint = @import("./BoundaryPoint.zig");
const Tree = @import("./Tree.zig");
const Node = @import("./Node.zig");
const GraphemeIterator = @import("../uni/GraphemeBreak.zig").Iterator;
const LineBox = @import("../layout/compute/text/ComputedText.zig").LineBox;
const db = @import("../uni/db.zig");
const LineBoxPart = @import("../layout/compute/text/ComputedText.zig").TextPart;
const RenderList = @import("../layout/v2/RenderList.zig");
const mod = @import("../layout/v2/mod.zig");
const measureTextInt = @import("../uni/string-width.zig").visible.width.exclude_ansi_colors.utf8;
range_id: Range.Id,
direction: Direction,
pub const Id = Range.Id;

fn measureText(text: []const u8) f32 {
    return @floatFromInt(measureTextInt(text));
}

pub const Direction = enum(i2) {
    forward = 1,
    backward = -1,
    none = 0,
};
const Self = @This();

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

fn findFirstTextElementWithinHostInner(tree: *Tree, host: Node.NodeId, node_id: Node.NodeId) ?usize {
    const node = tree.getNode(node_id);
    if (node.isCharacterData()) {
        return node_id;
    }
    if (node.isEditingHost(tree)) {
        return null;
    }
    for (node.children.items) |child_id| {
        if (findFirstTextElementWithinHostInner(tree, host, child_id)) |result| {
            return result;
        }
    }
    return null;
}

fn findFirstTextElementWithinHost(tree: *Tree, host: Node.NodeId) ?usize {
    return findFirstTextElementWithinHostInner(tree, host, host);
}

pub fn setRange(self: *Self, tree: *Tree, start: BoundaryPoint, _end: BoundaryPoint) !void {
    var end = _end;
    // lets make sure we dont select accross different editing hosts..this deviates from the spec, but matches chrome behavior for example
    const start_node_host = tree.getNode(start.node_id).getEditingHost(tree);
    const end_node_host = tree.getNode(end.node_id).getEditingHost(tree);

    const order = try Range.boundaryPointTreeOrder(tree, start, end);
    if (start_node_host != end_node_host) {
        switch (order) {
            .gt => {
                var iter = tree.createNodeIterator(start.node_id);
                end = BoundaryPoint{ .node_id = start.node_id, .offset = 0 };
                while (iter.previousNode()) |node_id| {
                    const node = tree.getNode(node_id);
                    if (node.getEditingHost(tree) != start_node_host) {
                        break;
                    }
                    if (node.isCharacterData()) {
                        end = BoundaryPoint{ .node_id = node_id, .offset = 0 };
                    }
                }
            },
            .lt => {
                var iter = tree.createNodeIterator(start.node_id);
                const start_node = tree.getNode(start.node_id);
                end = BoundaryPoint{ .node_id = start.node_id, .offset = @intCast(start_node.text.length()) };
                while (iter.nextNode()) |node_id| {
                    const node = tree.getNode(node_id);
                    const node_host = node.getEditingHost(tree);

                    if (node_host == end_node_host) {
                        break;
                    }
                    if (node_host == start_node_host and node.isCharacterData()) {
                        end = BoundaryPoint{ .node_id = node_id, .offset = @intCast(node.text.length()) };
                    }
                }
            },
            .eq => {},
        }
    }

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
pub fn getFocusPosition(self: *Self, tree: *Tree) ?mod.CSSPoint {
    const focus = self.getFocus(tree);
    const focus_item_index = tree.render_list.findItemAtBoundaryPoint(focus.node_id, focus.offset) orelse return null;
    switch (tree.render_list.at(focus_item_index).?) {
        .text_fragment => |fragment| {
            return fragment.getOffsetPosition(focus.offset);
        },
        else => return null,
    }
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

pub const Alteration = enum(u8) {
    move = 0,
    extend = 1,
};

pub const ExtendGranularity = enum(u8) {
    character = 0,
    word = 1,
    line = 2,
    lineboundary = 3,
    documentboundary = 4,
};

const testing = std.testing;
fn expectSelection(selection: *Self, description: []const u8, tree: *Tree, anchor: BoundaryPoint, focus: BoundaryPoint, direction: Direction) !void {
    const actual_anchor = selection.getAnchor(tree);
    const actual_focus = selection.getFocus(tree);
    const actual_direction = selection.direction;

    if (actual_anchor.node_id != anchor.node_id or actual_anchor.offset != anchor.offset or actual_focus.node_id != focus.node_id or actual_focus.offset != focus.offset or actual_direction != direction) {
        var buf = std.array_list.Managed(u8).init(testing.allocator);
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

pub fn modify(
    selection: *Self,
    tree: *Tree,
    alter: Alteration,
    direction: ExtendDirection,
    granularity: ExtendGranularity,
    ghost_position: ?f32,
) !void {
    // Browser arrow-key behavior: moving by character over a non-collapsed
    // range collapses to the range's directional edge without further movement.
    if (alter == .move and !selection.isCollapsed() and granularity == .character) {
        const anchor_bp = selection.getAnchor(tree);
        const focus_bp = selection.getFocus(tree);
        const edge = switch (direction) {
            .forward => if (selection.direction == .backward) anchor_bp else focus_bp,
            .backward => if (selection.direction == .backward) focus_bp else anchor_bp,
        };
        try selection.setRange(tree, edge, edge);
        return;
    }

    const focus = selection.getFocus(tree);
    const anchor = selection.getAnchor(tree);
    const full_list = tree.render_list.slice();

    const host = tree.getNode(anchor.node_id).getEditingHost(tree);

    switch (granularity) {
        .character => {
            if (getNextCharacter(tree, host, focus, direction)) |new_bp| {
                try selection.setFocus(tree, new_bp);
            }
        },
        .word => {
            if (getNextWord(tree, host, focus, direction)) |new_bp| {
                try selection.setFocus(tree, new_bp);
            }
        },
        .line => {
            if (getNextLineInSlice(tree, host, focus, direction, ghost_position)) |new_bp| {
                try selection.setFocus(tree, new_bp);
            }
        },
        .lineboundary => {
            const focus_item_index = tree.render_list.findItemAtBoundaryPoint(focus.node_id, focus.offset) orelse return;
            switch (full_list[focus_item_index]) {
                .text_fragment => |fragment| {
                    // Use the full list since line box indices reference the full render list
                    const line_box = full_list[fragment.linebox_index].line_box;
                    if (direction == .forward) {
                        const last_fragment_index = line_box.fragment_indexes[line_box.fragment_indexes.len - 1];
                        const last_fragment = full_list[last_fragment_index].text_fragment;
                        try selection.setFocus(tree, BoundaryPoint{ .node_id = last_fragment.doc_node_id, .offset = last_fragment.visibleDomEnd() });
                    } else {
                        const first_fragment_index = line_box.fragment_indexes[0];
                        const first_fragment = full_list[first_fragment_index].text_fragment;
                        try selection.setFocus(tree, BoundaryPoint{ .node_id = first_fragment.doc_node_id, .offset = first_fragment.dom_range.start });
                    }
                },
                else => {},
            }
        },
        .documentboundary => {
            const host_index: ?usize = if (host) |h| tree.render_list.findNodeBox(h) else null;
            switch (direction) {
                .forward => {
                    if (tree.render_list.firstTextFragment(host_index)) |first_fragment_index| {
                        const first_fragment = tree.render_list.at(first_fragment_index).?.text_fragment;
                        try selection.setFocus(tree, BoundaryPoint{ .node_id = first_fragment.doc_node_id, .offset = first_fragment.dom_range.start });
                    }
                },
                .backward => {
                    if (tree.render_list.lastTextFragment(host_index)) |last_fragment_index| {
                        const last_fragment = tree.render_list.at(last_fragment_index).?.text_fragment;
                        try selection.setFocus(tree, BoundaryPoint{ .node_id = last_fragment.doc_node_id, .offset = last_fragment.visibleDomEnd() });
                    }
                },
            }
            try selection.setFocus(tree, .{ .node_id = host orelse Tree.ROOT_NODE_ID, .offset = 0 });
        },
    }

    if (alter == .move) {
        const new_focus = selection.getFocus(tree);
        try selection.setRange(tree, new_focus, new_focus);
    }
}

/// Word-constituent classification for word-granularity movement, based on
/// UAX-29 word-break classes (same database the segmenter uses).
fn isWordCp(cp: u21) bool {
    return switch (db.getWordBreak(cp)) {
        .ALetter, .Hebrew_Letter, .Katakana, .Numeric, .ExtendNumLet => true,
        .Extend, .Format, .ZWJ => true,
        else => false,
    };
}

/// The codepoint that character-movement in `direction` would cross from `bp`,
/// or null at the document/context edge.
fn peekCp(tree: *Tree, host: ?usize, bp: BoundaryPoint, direction: ExtendDirection) ?u21 {
    var fragment: RenderList.TextFragmentItem = undefined;
    var offset: u32 = bp.offset;
    const item_index = tree.render_list.findItemAtBoundaryPoint(bp.node_id, bp.offset) orelse return null;
    const host_index: ?usize = if (host) |h| tree.render_list.findNodeBox(h) else null;

    switch (tree.render_list.at(item_index).?) {
        .text_fragment => |_fragment| fragment = _fragment,
        else => return null,
    }

    switch (direction) {
        .forward => {
            if (offset >= fragment.visibleDomEnd()) {
                // collapsed whitespace (fragment's invisible tail, or a DOM-offset
                // gap between fragments) reads as a space for word segmentation
                if (offset < fragment.dom_range.end) return ' ';
                const next_index = tree.render_list.firstTextFragmentAfterIndexWithinContext(host_index, item_index) orelse return null;
                fragment = tree.render_list.at(next_index).?.text_fragment;
                if (fragment.dom_range.start > offset) return ' ';
                offset = fragment.dom_range.start;
            }
            const local = offset - fragment.dom_range.start;
            if (local >= fragment.text.len) return null;
            const len = std.unicode.utf8ByteSequenceLength(fragment.text[local]) catch return null;
            return std.unicode.utf8Decode(fragment.text[local .. local + len]) catch null;
        },
        .backward => {
            if (offset <= fragment.dom_range.start) {
                const prev_index = tree.render_list.firstTextFragmentBeforeIndexWithinContext(host_index, item_index) orelse return null;
                fragment = tree.render_list.at(prev_index).?.text_fragment;
                if (fragment.visibleDomEnd() < offset) return ' ';
                offset = fragment.visibleDomEnd();
            }
            // find the codepoint ending at `offset`
            var iter = std.unicode.Utf8Iterator{ .bytes = fragment.text, .i = 0 };
            var cp: ?u21 = null;
            var pos = fragment.dom_range.start;
            while (pos < offset) {
                const slice = iter.nextCodepointSlice() orelse break;
                cp = std.unicode.utf8Decode(slice) catch null;
                pos += @intCast(slice.len);
            }
            return cp;
        },
    }
}

/// Word-granularity movement: skip non-word codepoints, then run to the far
/// edge of the word (forward -> end of word, backward -> start of word).
fn getNextWord(
    tree: *Tree,
    host: ?usize,
    bp: BoundaryPoint,
    direction: ExtendDirection,
) ?BoundaryPoint {
    var current = bp;

    while (peekCp(tree, host, current, direction)) |cp| {
        if (isWordCp(cp)) break;
        current = getNextCharacter(tree, host, current, direction) orelse break;
    }
    while (peekCp(tree, host, current, direction)) |cp| {
        if (!isWordCp(cp)) break;
        current = getNextCharacter(tree, host, current, direction) orelse break;
    }

    if (current.node_id == bp.node_id and current.offset == bp.offset) return null;
    return current;
}

// Now let's update the helper functions to work with slices

fn getNextCharacter(
    tree: *Tree,
    host: ?usize,
    bp: BoundaryPoint,
    direction: ExtendDirection,
) ?BoundaryPoint {
    var fragment: RenderList.TextFragmentItem = undefined;
    var offset: u32 = bp.offset;
    const focus_item_index = tree.render_list.findItemAtBoundaryPoint(bp.node_id, bp.offset) orelse 0;
    const host_index: ?usize = if (host) |h| tree.render_list.findNodeBox(h) else null;

    switch (tree.render_list.at(focus_item_index).?) {
        .text_fragment => |_fragment| {
            fragment = _fragment;
            switch (direction) {
                .forward => {
                    if (bp.offset >= fragment.visibleDomEnd()) {
                        const next_fragment_index = tree.render_list.firstTextFragmentAfterIndexWithinContext(host_index, focus_item_index) orelse return null;
                        fragment = tree.render_list.at(next_fragment_index).?.text_fragment;
                        offset = fragment.dom_range.start;
                    }
                    var iter = GraphemeIterator.init(fragment.text);
                    var current_offset = fragment.dom_range.start;
                    while (iter.next()) |grapheme| {
                        if (current_offset + grapheme.len > offset) {
                            return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = current_offset + grapheme.len };
                        }
                        current_offset += grapheme.len;
                    }
                    return null;
                },
                .backward => {
                    if (bp.offset <= fragment.dom_range.start) {
                        const next_fragment_index = tree.render_list.firstTextFragmentBeforeIndexWithinContext(host_index, focus_item_index) orelse return null;
                        const item = tree.render_list.at(next_fragment_index).?;
                        fragment = item.text_fragment;
                        offset = fragment.visibleDomEnd();
                    }
                    var iter = GraphemeIterator.init(fragment.text);
                    var current_offset = fragment.dom_range.start;
                    // var prev_offset = current_offset;
                    while (iter.next()) |grapheme| {
                        if (current_offset + grapheme.len >= offset) {
                            return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = current_offset };
                        }
                        // prev_offset = current_offset;
                        current_offset += grapheme.len;
                    }
                    return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = current_offset };
                },
            }
        },
        else => {
            switch (direction) {
                .forward => {
                    const next_fragment_index = tree.render_list.firstTextFragmentAfterIndexWithinContext(host_index, focus_item_index) orelse return null;
                    fragment = tree.render_list.at(next_fragment_index).?.text_fragment;
                    offset = fragment.dom_range.start;
                },
                .backward => {
                    const next_fragment_index = tree.render_list.firstTextFragmentBeforeIndexWithinContext(host_index, focus_item_index) orelse return null;
                    fragment = tree.render_list.at(next_fragment_index).?.text_fragment;
                    offset = fragment.visibleDomEnd();
                },
            }
            return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = offset };
        },
    }
}

fn findNextTextFragmentInSlice(
    slice: []const RenderList.RenderItem,
    focus_index: usize,
    direction: ExtendDirection,
) ?usize {
    var i: usize = focus_index;

    while (true) {
        switch (direction) {
            .forward => {
                i += 1;
                if (i >= slice.len) return null;
            },
            .backward => {
                if (i == 0) return null;
                i -= 1;
            },
        }

        switch (slice[i]) {
            .text_fragment => |fragment| {
                // Check if this text node creates a new editing context
                // Since we're already within a context slice, we don't need to check boundaries
                if (fragment.text.len > 0) {
                    return i;
                }
            },
            else => {},
        }
    }
}

fn getNextLineInSlice(
    tree: *Tree,
    host: ?usize,
    bp: BoundaryPoint,
    direction: ExtendDirection,
    ghost_position: ?f32,
) ?BoundaryPoint {
    const focus_item_index = tree.render_list.findItemAtBoundaryPoint(bp.node_id, bp.offset) orelse 0;
    // const current_line_box_index: usize = switch (current_item) {
    //     .text_fragment => |fragment| blk: {
    //         // Adjust linebox index to be relative to slice
    //         const adjusted_index = if (fragment.linebox_index >= focus_item_index)
    //             fragment.linebox_index - focus_item_index
    //         else
    //             fragment.linebox_index;
    //         break :blk adjusted_index;
    //     },
    //     else => focus_item_index,
    // };

    const current_fragment_index = switch (tree.render_list.at(focus_item_index).?) {
        .text_fragment => focus_item_index,
        else => blk: {
            switch (direction) {
                .forward => {
                    const next_fragment_index = tree.render_list.firstTextFragmentAfterIndexWithinContext(host, focus_item_index) orelse return null;
                    break :blk next_fragment_index;
                },
                .backward => {
                    const next_fragment_index = tree.render_list.firstTextFragmentBeforeIndexWithinContext(host, focus_item_index) orelse return null;
                    break :blk next_fragment_index;
                },
            }
        },
    };
    const current_item_fragment = tree.render_list.at(current_fragment_index).?.text_fragment;
    const current_line_box_index = current_item_fragment.linebox_index;
    const current_line_box = tree.render_list.at(current_line_box_index).?;

    const x_position = blk: {
        if (ghost_position) |position| break :blk position;
        break :blk blk2: {
            const clamped_offset = @max(current_item_fragment.dom_range.start, @min(bp.offset, current_item_fragment.dom_range.end));
            const relative_offset = clamped_offset - current_item_fragment.dom_range.start;
            const text_len = @min(relative_offset, current_item_fragment.text.len);
            break :blk2 current_item_fragment.bounds.x + measureText(current_item_fragment.text[0..text_len]);
        };
    };

    var candidate_line_box_index: ?usize = null;
    var i: usize = current_line_box_index;
    const current_editing_host_index = current_line_box.line_box.editing_host_index;

    while (true) {
        switch (direction) {
            .forward => {
                i += 1;
                if (i >= tree.render_list.items.items.len) break;
            },
            .backward => {
                if (i == 0) break;
                i -= 1;
            },
        }

        const item: RenderList.RenderItem = tree.render_list.at(i).?;

        switch (item) {
            .box => |box| {
                switch (direction) {
                    .forward => {
                        // skip the entire box
                        if (box.is_editing_host)
                            i = box.last_index;
                    },
                    .backward => {},
                }
            },
            .line_box => |linebox| {
                switch (direction) {
                    .forward => {},
                    .backward => {
                        if (linebox.editing_host_index != current_editing_host_index) {
                            i = linebox.editing_host_index orelse i;
                            continue;
                        }
                    },
                }

                if (linebox.fragment_indexes.len == 0 or (linebox.bounds.width == 0 and linebox.bounds.height == 0)) continue;
                candidate_line_box_index = i;
                break;
            },
            else => {},
        }
    }

    // if no candidate line box, we set focus on the linebox boundaries
    if (candidate_line_box_index == null) {
        const linebox = current_line_box.line_box;
        switch (direction) {
            .forward => {
                const last_fragment_index = linebox.getLastNonEmptyFragmentIndex(&tree.render_list) orelse return null;
                const last_fragment = tree.render_list.at(last_fragment_index).?.text_fragment;
                return BoundaryPoint{ .node_id = last_fragment.doc_node_id, .offset = last_fragment.visibleDomEnd() };
            },
            .backward => {
                const first_fragment_index = linebox.getFirstNonEmptyFragmentIndex(&tree.render_list) orelse return null;
                const first_fragment = tree.render_list.at(first_fragment_index).?.text_fragment;
                return BoundaryPoint{ .node_id = first_fragment.doc_node_id, .offset = first_fragment.dom_range.start };
            },
        }
    }

    const linebox = tree.render_list.at(candidate_line_box_index.?).?.line_box;
    const first_fragment_index = linebox.getFirstNonEmptyFragmentIndex(&tree.render_list) orelse return null;
    const last_fragment_index = linebox.getLastNonEmptyFragmentIndex(&tree.render_list) orelse return null;
    const first_fragment = tree.render_list.at(first_fragment_index).?.text_fragment;
    const last_fragment = tree.render_list.at(last_fragment_index).?.text_fragment;

    if (x_position <= first_fragment.bounds.x) {
        return BoundaryPoint{ .node_id = first_fragment.doc_node_id, .offset = first_fragment.dom_range.start };
    }
    if (x_position >= last_fragment.bounds.x + last_fragment.bounds.width) {
        return BoundaryPoint{ .node_id = last_fragment.doc_node_id, .offset = last_fragment.visibleDomEnd() };
    }

    var frag_index: usize = first_fragment_index;
    for (linebox.fragment_indexes) |fragment_index| {
        const fragment = tree.render_list.at(fragment_index).?.text_fragment;
        if (fragment.bounds.x > x_position) {
            break;
        }
        frag_index = fragment_index;
    }

    const fragment = tree.render_list.at(frag_index).?.text_fragment;
    const offset = fragment.getOffsetAtX(x_position);
    return BoundaryPoint{ .node_id = fragment.doc_node_id, .offset = offset };
}

// Removed old helper functions that are now replaced with slice-based versions

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
                if (fragment.dom_range.end > bp.offset) {
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
