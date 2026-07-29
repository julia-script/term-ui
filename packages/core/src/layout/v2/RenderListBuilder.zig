const std = @import("std");
const mod = @import("mod.zig");
const LayoutTree = @import("LayoutTree.zig");
const DocTree = @import("../../tree/Tree.zig");
const Style = @import("../../tree/Style.zig");
const styles = @import("../../styles/styles.zig");
const RenderList = @import("RenderList.zig");
const Color = @import("../../colors/Color.zig");
const Range = @import("../../tree/Range.zig");
const BoundaryPoint = @import("../../tree/BoundaryPoint.zig");

const SelectionState = struct {
    i: usize = 0,
    selection_boundaries: std.ArrayList(Item),
    allocator: std.mem.Allocator,

    const Item = struct {
        bp: BoundaryPoint,
        is_start: bool,
        selection: DocTree.Selection.Id,
    };
    const SortContext = struct {
        doc_tree: *DocTree,
        pub fn lessThanFn(ctx: SortContext, a: Item, b: Item) bool {
            const order = ctx.doc_tree.treeOrder(a.bp.node_id, b.bp.node_id) catch return false;
            return switch (order) {
                .lt => true,
                .gt => false,
                .eq => a.bp.offset < b.bp.offset,
            };
        }
    };
    pub fn getActiveSelection(self: *SelectionState) ?DocTree.Selection.Id {
        if (self.i >= self.selection_boundaries.items.len) return null;

        const item = self.selection_boundaries.items[self.i];
        if (item.is_start == false) {
            return item.selection;
        }

        return null;
    }

    pub fn init(doc_tree: *DocTree, allocator: std.mem.Allocator) !SelectionState {
        var selection_boundaries: std.ArrayList(Item) = .empty;
        var iter = doc_tree.selections.iterator();

        while (iter.next()) |entry| {
            const range = entry.value_ptr.getRange(doc_tree);
            try selection_boundaries.append(allocator, .{
                .bp = range.start,
                .is_start = true,
                .selection = entry.key_ptr.*,
            });

            try selection_boundaries.append(allocator, .{
                .bp = range.end,
                .is_start = false,
                .selection = entry.key_ptr.*,
            });
        }
        std.mem.sort(Item, selection_boundaries.items, SortContext{ .doc_tree = doc_tree }, SortContext.lessThanFn);

        // std.sort.sort(*Range, selections_list.items, {});
        return .{
            .selection_boundaries = selection_boundaries,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SelectionState) void {
        self.selection_boundaries.deinit(self.allocator);
    }
    pub fn peek(self: *SelectionState) ?Item {
        if (self.i >= self.selection_boundaries.items.len) return null;
        return self.selection_boundaries.items[self.i];
    }
    pub fn consume(self: *SelectionState) void {
        self.i += 1;
    }

    pub fn next(self: *SelectionState) ?Item {
        const item = self.peek();
        self.i += 1;
        return item;
    }
    pub fn consumeIfNode(self: *SelectionState, node_id: DocTree.Node.NodeId) void {
        while (self.peek()) |item| {
            if (item.bp.node_id == node_id) {
                self.consume();
                continue;
            }
            break;
        }
    }
};
const HashMap = std.AutoHashMapUnmanaged;
const SelectionSet = HashMap(DocTree.Selection.Id, void);
const SelectionBoundariesMap = HashMap(DocTree.Node.NodeId, SelectionSet);
layout_tree: *LayoutTree,
doc_tree: *DocTree,
render_list: *RenderList,
/// Track current absolute position as we traverse
current_offset: mod.CSSPoint = .{ .x = 0, .y = 0 },
/// Track current z-index for stacking context
current_z_index: i32 = 0,
/// Map from doc node ID to selection IDs that have boundaries in that node
selection_boundaries: SelectionBoundariesMap = .{},
active_selection: ?DocTree.Selection.Id = null,
active_editing_host_index: ?usize = null,
selection_state: SelectionState,

const Self = @This();

pub fn init(layout_tree: *LayoutTree, doc_tree: *DocTree, render_list: *RenderList) !Self {
    return .{
        .layout_tree = layout_tree,
        .doc_tree = doc_tree,
        .render_list = render_list,
        .selection_state = try SelectionState.init(doc_tree, layout_tree.allocator),
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.selection_boundaries.iterator();
    self.selection_state.deinit();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.layout_tree.allocator);
    }
    self.selection_boundaries.deinit(self.layout_tree.allocator);
}
pub fn clear(self: *Self) void {
    var iter = self.selection_boundaries.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.layout_tree.allocator);
    }
    self.selection_boundaries.clearRetainingCapacity();
    self.render_list.items.clearRetainingCapacity();
}

/// Build the render list from the layout tree
pub fn build(self: *Self) !void {
    self.clear();
    // Preprocess selections to find which nodes contain boundaries
    try self.preprocessSelections();

    var active_selections = std.AutoHashMapUnmanaged(DocTree.Selection.Id, void){};
    defer active_selections.deinit(self.layout_tree.allocator);
    self.render_list.items.clearRetainingCapacity();
    self.render_list.node_boxes_map.clearRetainingCapacity();
    try self.buildNode(self.layout_tree.root_id, .{ .x = 0, .y = 0 });
}

/// Preprocess selections to build a map of layout nodes to selection boundaries
fn preprocessSelections(self: *Self) !void {
    // Clear any existing data
    var iter = self.selection_boundaries.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.layout_tree.allocator);
    }
    self.selection_boundaries.clearRetainingCapacity();

    // Iterate through all selections
    var sel_iter = self.doc_tree.selections.iterator();
    while (sel_iter.next()) |entry| {
        const selection_id = entry.key_ptr.*;
        const selection = entry.value_ptr;
        const range = selection.getRange(self.doc_tree);

        // Add start boundary
        const start_entry_gop = try self.selection_boundaries.getOrPut(self.layout_tree.allocator, range.start.node_id);

        if (!start_entry_gop.found_existing) {
            start_entry_gop.value_ptr.* = .{};
        }
        // var start_entry: *SelectionSet = start_entry_gop.value_ptr;
        try start_entry_gop.value_ptr.put(self.layout_tree.allocator, selection_id, {});
        // try start_entry.set(self.layout_tree.allocator, selection_id, {});

        // Add end boundary if different from start
        if (range.start.node_id != range.end.node_id) {
            const end_entry = try self.selection_boundaries.getOrPut(self.layout_tree.allocator, range.end.node_id);
            if (!end_entry.found_existing) {
                end_entry.value_ptr.* = .{};
            }
            try end_entry.value_ptr.put(self.layout_tree.allocator, selection_id, {});
        }
    }
}
pub fn addSelectionBox(
    self: *Self,
    rect: RenderList.Rect,
    color: Color,
    selection_id: DocTree.Selection.Id,
) !void {
    _ = try self.render_list.addItem(.{
        .selection_overlay = .{
            .bounds = rect,
            .color = color,
            .selection_id = selection_id,
        },
    });
}
pub fn generateSelectionBoxForFragment(
    self: *Self,
    fragment: *const RenderList.TextFragmentItem,
    color: Color,
) !void {
    const doc_node_id = fragment.doc_node_id;
    const boundaries: SelectionSet = self.selection_boundaries.get(doc_node_id) orelse {
        // no explicit boundaries for this fragment:
        if (self.active_selection) |selection_id| {

            // it’s fully selected by the currently active selection
            try self.addSelectionBox(fragment.bounds, color, selection_id);
            return;
        }
        // nothing selected here
        return;
    };

    const fragment_bounds = fragment.bounds;
    var iter = boundaries.keyIterator();
    while (iter.next()) |selection_id_ptr| {
        const selection_id = selection_id_ptr.*;
        // 0) gather selection endpoints + fragment metadata
        const selection = self.doc_tree.getSelection(selection_id).getRange(self.doc_tree);
        const has_active_selection = self.active_selection != null;
        const s_start_id = selection.start.node_id;
        const s_start_off = selection.start.offset;
        const s_end_id = selection.end.node_id;
        const s_end_off = selection.end.offset;

        const f_node_id = fragment.doc_node_id;
        const f_start_off = fragment.dom_range.start;
        const f_end_off = fragment.dom_range.end;

        const start_in_node = (s_start_id == f_node_id);
        const end_in_node = (s_end_id == f_node_id);

        const start_in_frag =
            start_in_node and s_start_off >= f_start_off and s_start_off <= f_end_off;

        const end_in_frag =
            end_in_node and s_end_off >= f_start_off and s_end_off <= f_end_off;

        const start_before =
            if (start_in_node)
            s_start_off < f_start_off
        else
            end_in_frag or has_active_selection;

        const end_after =
            if (end_in_node)
            s_end_off > f_end_off
        else
            has_active_selection and !end_in_frag;
        // std.debug.print(
        //     \\==========
        //     \\fragment: "{s}"
        //     \\s_start_id/off: {d} {d}
        //     \\s_end_id/off: {d} {d}
        //     \\f_node_id: {d} {d}~{d}
        //     \\start_in_node: {any}
        //     \\end_in_node: {any}
        //     \\start_in_frag: {any}
        //     \\end_in_frag: {any}
        //     \\start_before: {any}
        //     \\end_after: {any}
        //     \\active_selection: {?d}
        //     \\
        // , .{
        //     fragment.text,
        //     s_start_id,
        //     s_start_off,
        //     s_end_id,
        //     s_end_off,
        //     f_node_id,
        //     f_start_off,
        //     f_end_off,
        //     start_in_node,
        //     end_in_node,
        //     start_in_frag,
        //     end_in_frag,
        //     start_before,
        //     end_after,
        //     self.active_selection,
        // });

        // 1) SKIP entirely before:
        //    - both endpoints outside this node, and no activeSelection yet (cross-node before)
        // OR - ends in this node but before fragment start (not at fragment start)
        if ((!start_in_node and !end_in_node and !has_active_selection) or (end_in_node and s_end_off < f_start_off)) {
            continue;
        }

        // 2) SKIP entirely after:
        //    - both endpoints outside this node, and we already have an activeSelection (cross-node after)
        // OR - starts in this node but after fragment end (not at fragment end)
        if ((!start_in_node and !end_in_node and has_active_selection) or (start_in_node and s_start_off > f_end_off)) {
            continue;
        }

        // 3) START-ONLY: start inside fragment, but end in a later node
        if (start_in_frag and !end_in_node) {
            const start_x = fragment_bounds.x + measureTextWidth(fragment.text, 0, s_start_off - f_start_off);
            const width = measureTextWidth(fragment.text, s_start_off - f_start_off, f_end_off - f_start_off);
            try self.addSelectionBox(.{
                .x = start_x,
                .y = fragment_bounds.y,
                .width = width,
                .height = fragment_bounds.height,
            }, color, selection_id);
            // e.g.  <p>{f}he[llo</p>  (end spills to next node)
            self.active_selection = selection_id;
            continue;
        }

        // 4) BEFORE-INSIDE: start before fragment, end inside
        if (start_before and end_in_frag) {
            // e.g.  <p>[hello {f}wor]ld{/f}</p>
            const local_x = fragment_bounds.x;
            const width = measureTextWidth(fragment.text, 0, s_end_off - f_start_off);
            try self.addSelectionBox(.{
                .x = local_x,
                .y = fragment_bounds.y,
                .width = width,
                .height = fragment_bounds.height,
            }, color, selection_id);
            // consumed the end boundary, so clear
            self.active_selection = null;
            continue;
        }

        // 5) BEFORE-AFTER (CONTAINS): start before and end after
        if (start_before and end_after) {
            // e.g.  <p>[{f}hello {/f}world]</p>
            try self.addSelectionBox(fragment_bounds, color, selection_id);
            continue;
        }

        // 6) INSIDE-INSIDE: both endpoints inside fragment
        if (start_in_frag and end_in_frag) {
            // e.g. <p>{f}hel[lo] {/f}world</p>
            const start_x = fragment_bounds.x + measureTextWidth(fragment.text, 0, s_start_off - f_start_off);
            const width = measureTextWidth(fragment.text, s_start_off - f_start_off, s_end_off - f_start_off);
            try self.addSelectionBox(.{
                .x = start_x,
                .y = fragment_bounds.y,
                .width = width,
                .height = fragment_bounds.height,
            }, color, selection_id);
            // now we’re in “active” until we see the end
            // Selection is complete within this fragment, dont set active_selection
            continue;
        }

        // 7) INSIDE-AFTER: start inside, end after fragment
        if (start_in_frag and end_after) {
            // e.g. <p>{f}hello[ world]</p>
            const start_x = fragment_bounds.x + measureTextWidth(fragment.text, 0, s_start_off - f_start_off);
            const width = measureTextWidth(fragment.text, s_start_off - f_start_off, f_end_off - f_start_off);
            try self.addSelectionBox(.{
                .x = start_x,
                .y = fragment_bounds.y,
                .width = width,
                .height = fragment_bounds.height,
            }, color, selection_id);
            self.active_selection = selection_id;
            continue;
        }
    }
}
fn isRealNode(self: *Self, l_node_id: LayoutTree.LayoutNode.Id) bool {
    const node = self.layout_tree.getNodePtr(l_node_id);
    return switch (node.ref) {
        .doc_node => true,
        .anonymous => false,
    };
}

fn buildNode(self: *Self, l_node_id: LayoutTree.LayoutNode.Id, parent_abs_pos: mod.CSSPoint) !void {
    const node = self.layout_tree.getNodePtr(l_node_id);
    const box = node.box;
    const abs_pos = parent_abs_pos.add(box.location);
    var content_abs = abs_pos;
    var is_scroll_container: bool = false;
    switch (node.data) {
        .text_node, .inline_node => {
            unreachable;
        },
        .block_container_node => |*container| {
            const current_editing_host_index: ?usize = self.active_editing_host_index;
            defer self.active_editing_host_index = current_editing_host_index;
            var box_index: ?usize = null;
            var did_clip: bool = false;
            if (self.layout_tree.resolveDocNodeId(l_node_id)) |doc_node_id| {
                const doc_node = self.doc_tree.getNode(doc_node_id);
                self.selection_state.consumeIfNode(doc_node_id);

                var style = self.doc_tree.getComputedStyle(doc_node_id);
                if (node.ref == .anonymous) {
                    style = LayoutTree.anonymousInheritStyles(style);
                }

                const bounds = RenderList.Rect.fromBox(box, parent_abs_pos);
                var box_doc_node = self.doc_tree.getNode(doc_node_id);
                const is_editing_host = box_doc_node.isEditingHost(self.doc_tree);
                if (is_editing_host) {
                    self.active_editing_host_index = self.render_list.items.items.len;
                }
                is_scroll_container = style.overflow.x.isScrollContainer() or style.overflow.y.isScrollContainer();
                if (is_scroll_container) {
                    // bounds = bounds.offset(doc_node.scroll_offset);
                    content_abs = content_abs.sub(doc_node.scroll_offset);
                }
                box_index = try self.render_list.addItem(.{
                    .box = .{
                        .bounds = bounds,
                        .background = style.background_color,
                        .border_style = style.border_style,
                        .border_color = style.border_color,

                        .doc_node_id = doc_node_id,
                        .z_index = 0,
                        .node_id = l_node_id,
                        .is_clickable = style.pointer_events != .none,
                        .last_index = self.render_list.items.items.len,
                        .is_editing_host = is_editing_host,
                        .is_scroll_container = is_scroll_container,
                        .scroll_offset = doc_node.scroll_offset,
                    },
                });
                try self.render_list.putDocNodeBoxIndex(doc_node_id, box_index.?);
                if (is_scroll_container) {
                    did_clip = true;
                    _ = try self.render_list.addItem(.{
                        .push_clip = .{
                            .rect = .{
                                .x = bounds.x + box.border.left,
                                .y = bounds.y + box.border.top,
                                .width = bounds.width - box.border.left - box.border.right,
                                .height = bounds.height - box.border.top - box.border.bottom,
                            },
                        },
                    });
                }
            }

            for (container.children.items) |child_id| {
                try self.buildNode(child_id, content_abs);
            }
            if (box_index) |index| {
                self.render_list.items.items[index].box.last_index = self.render_list.items.items.len - 1;
            }
            if (did_clip) {
                _ = try self.render_list.addItem(.pop_clip);
            }
        },
        .inline_container_node => |*container| {
            const current_editing_host_index: ?usize = self.active_editing_host_index;
            defer self.active_editing_host_index = current_editing_host_index;
            var box_index: ?usize = null;
            var did_clip: bool = false;
            if (self.layout_tree.getDocNodeId(l_node_id)) |doc_node_id| {
                self.selection_state.consumeIfNode(doc_node_id);
                const doc_node = self.doc_tree.getNode(doc_node_id);

                const style = self.doc_tree.getComputedStyle(doc_node_id);
                is_scroll_container = style.overflow.x.isScrollContainer() or style.overflow.y.isScrollContainer();
                const bounds = RenderList.Rect.fromBox(box, parent_abs_pos);
                var box_doc_node = self.doc_tree.getNode(doc_node_id);
                const is_editing_host = box_doc_node.isEditingHost(self.doc_tree);
                if (is_editing_host) {
                    self.active_editing_host_index = self.render_list.items.items.len;
                }
                if (is_scroll_container) {
                    // bounds = bounds.offset(doc_node.scroll_offset);
                    content_abs = content_abs.sub(doc_node.scroll_offset);
                }
                box_index = try self.render_list.addItem(.{
                    .box = .{
                        .bounds = bounds,
                        // .content_bounds = bounds,
                        .background = style.background_color,
                        .border_style = style.border_style,
                        .border_color = style.border_color,

                        .doc_node_id = doc_node_id,
                        .z_index = 0,
                        .node_id = l_node_id,
                        .is_clickable = style.pointer_events != .none,
                        .last_index = self.render_list.items.items.len,
                        .is_editing_host = is_editing_host,
                        .is_scroll_container = is_scroll_container,
                        .scroll_offset = doc_node.scroll_offset,
                    },
                });
                try self.render_list.putDocNodeBoxIndex(doc_node_id, box_index.?);
                if (is_scroll_container) {
                    did_clip = true;
                    _ = try self.render_list.addItem(.{
                        .push_clip = .{
                            .rect = .{
                                .x = bounds.x + box.border.left,
                                .y = bounds.y + box.border.top,
                                .width = bounds.width - box.border.left - box.border.right,
                                .height = bounds.height - box.border.top - box.border.bottom,
                            },
                        },
                    });
                }
            }
            for (container.line_boxes.items()) |line_box| {
                const line_abs = content_abs.add(line_box.location);
                const line_box_index = self.render_list.items.items.len;
                var fragment_indexes = try self.layout_tree.allocator.alloc(usize, line_box.fragments.items.len);
                _ = try self.render_list.addItem(.{
                    .line_box = .{
                        .bounds = .{
                            .x = line_abs.x,
                            .y = line_abs.y,
                            .width = line_box.size.x,
                            .height = line_box.size.y,
                        },
                        .node_id = l_node_id,
                        .doc_node_id = self.layout_tree.resolveDocNodeId(l_node_id) orelse unreachable,
                        .fragment_indexes = fragment_indexes,
                        .allocator = self.layout_tree.allocator,
                        .editing_host_index = self.active_editing_host_index,
                    },
                });

                // const line_box_abs_pos = abs_pos.add(line_box.location);
                for (line_box.fragments.items, 0..) |fragment, i| {
                    // const peeked_selection = self.selection_state.peek();
                    // _ = peeked_selection; // autofix

                    const doc_node_id = self.layout_tree.resolveDocNodeId(fragment.l_node_id) orelse unreachable;
                    const style = self.doc_tree.getComputedStyle(doc_node_id);
                    const frag_abs = line_abs.add(fragment.position);
                    const index = try self.render_list.addItem(.{
                        .text_fragment = .{
                            .bounds = RenderList.Rect{
                                .x = @round(frag_abs.x),
                                .y = @round(frag_abs.y),
                                .width = @round(fragment.size.x),
                                .height = @round(fragment.size.y),
                            },
                            .linebox_index = line_box_index,
                            .text = fragment.text,
                            .color = style.foreground_color.?,
                            .format = RenderList.TextFormat.fromStyle(style.font_weight, style.font_style, style.text_decoration),
                            .node_id = fragment.l_node_id,
                            .doc_node_id = doc_node_id,
                            .is_clickable = style.pointer_events != .none,
                            .dom_range = fragment.dom_range,
                            .is_atomic = fragment.is_atomic,
                            .editing_host_index = self.active_editing_host_index,
                        },
                    });
                    var fragment_item = &self.render_list.items.items[index].text_fragment;
                    const contains_selection_boundary = if (self.selection_state.peek()) |selection_item| fragment_item.containsBp(selection_item.bp) else false;

                    if (contains_selection_boundary) {
                        var x = fragment_item.bounds.x;

                        while (self.selection_state.peek()) |selection_boundary| {
                            if (fragment_item.containsBp(selection_boundary.bp)) {
                                self.selection_state.consume();
                                const offset_position = fragment_item.getOffsetPosition(selection_boundary.bp.offset);
                                if (selection_boundary.is_start) {
                                    x = offset_position.x;
                                } else {
                                    try self.addSelectionBox(.{
                                        .x = x,
                                        .y = fragment_item.bounds.y,
                                        .width = offset_position.x - x,
                                        .height = fragment_item.bounds.height,
                                    }, .{ .r = 1, .g = 0, .b = 0, .a = 0.5 }, selection_boundary.selection);
                                    fragment_item = &self.render_list.items.items[index].text_fragment;
                                    x = fragment_item.bounds.right();
                                }
                                continue;
                            }
                            break;
                        }
                        if (self.selection_state.getActiveSelection()) |selection_id| {
                            try self.addSelectionBox(.{
                                .x = x,
                                .y = fragment_item.bounds.y,
                                .width = fragment_item.bounds.right() - x,
                                .height = fragment_item.bounds.height,
                            }, .{ .r = 0, .g = 0, .b = 0.8, .a = 0.5 }, selection_id);
                        }
                    } else {
                        if (self.selection_state.getActiveSelection()) |selection_id| {
                            try self.addSelectionBox(
                                fragment_item.bounds,
                                .{ .r = 0, .g = 0, .b = 0.8, .a = 0.5 },
                                selection_id,
                            );
                        }
                    }

                    fragment_indexes[i] = index;
                    if (fragment.is_atomic) {
                        try self.buildNode(fragment.l_node_id, line_abs);
                    }
                }
                if (box_index) |index| {
                    self.render_list.items.items[index].box.last_index = self.render_list.items.items.len - 1;
                }
            }
            if (did_clip) {
                _ = try self.render_list.addItem(.pop_clip);
            }
        },
    }
}

fn measureTextWidth(text: []const u8, start: usize, end: usize) f32 {
    const clamped_start = @min(start, text.len);
    const clamped_end = @min(end, text.len);
    if (clamped_start >= clamped_end) return 0;
    const utf8WidthExcludingAnsiColors = @import("../../uni/string-width.zig").utf8WidthExcludingAnsiColors;
    const measured_width = utf8WidthExcludingAnsiColors(text[clamped_start..clamped_end]);

    return @floatFromInt(measured_width);
}
