const std = @import("std");
const mod = @import("mod.zig");
const LayoutTree = @import("LayoutTree.zig");
const DocTree = @import("../../tree/Tree.zig");
const Style = @import("../../tree/Style.zig");
const styles = @import("../../styles/styles.zig");
const RenderList = @import("RenderList.zig");
const Color = @import("../../colors/Color.zig");

layout_tree: *LayoutTree,
doc_tree: *DocTree,
render_list: *RenderList,
/// Track current absolute position as we traverse
current_offset: mod.CSSPoint = .{ .x = 0, .y = 0 },
/// Track current z-index for stacking context
current_z_index: i32 = 0,
/// Map from doc node ID to selection IDs that have boundaries in that node
selection_boundaries: std.AutoHashMapUnmanaged(DocTree.Node.NodeId, std.ArrayListUnmanaged(DocTree.Selection.Id)) = .{},

const Self = @This();

pub fn init(layout_tree: *LayoutTree, doc_tree: *DocTree, render_list: *RenderList) Self {
    return .{
        .layout_tree = layout_tree,
        .doc_tree = doc_tree,
        .render_list = render_list,
    };
}

pub fn deinit(self: *Self) void {
    var iter = self.selection_boundaries.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.layout_tree.allocator);
    }
    self.selection_boundaries.deinit(self.layout_tree.allocator);
}

/// Build the render list from the layout tree
pub fn build(self: *Self) !void {
    // Preprocess selections to find which nodes contain boundaries
    try self.preprocessSelections();

    // Start from the root node (0)
    try self.buildNode(self.layout_tree.root_id);

    // TODO: Implement proper CSS stacking context handling
    // Currently we just traverse in tree order which is incorrect for:
    // - Elements with z-index (should be sorted within their stacking context)
    // - Positioned elements (have different paint order rules)
    // - Proper stacking context creation (position + z-index, opacity < 1, etc.)
    //
    // For now, we don't sort at all and just render in tree order with
    // selections immediately after their text fragments
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
        const start_entry = try self.selection_boundaries.getOrPut(self.layout_tree.allocator, range.start.node_id);
        if (!start_entry.found_existing) {
            start_entry.value_ptr.* = .{};
        }
        try start_entry.value_ptr.append(self.layout_tree.allocator, selection_id);

        // Add end boundary if different from start
        if (range.start.node_id != range.end.node_id) {
            const end_entry = try self.selection_boundaries.getOrPut(self.layout_tree.allocator, range.end.node_id);
            if (!end_entry.found_existing) {
                end_entry.value_ptr.* = .{};
            }
            try end_entry.value_ptr.append(self.layout_tree.allocator, selection_id);
        }
    }
}

/// Build render items for a node and its children
fn buildNode(self: *Self, node_id: LayoutTree.LayoutNode.Id) !void {
    const node = self.layout_tree.getNodePtr(node_id);
    const box = node.box;

    // Calculate absolute position
    const abs_pos = mod.CSSPoint{
        .x = self.current_offset.x + box.location.x,
        .y = self.current_offset.y + box.location.y,
    };

    // Get styles from doc tree if this is a doc node
    var node_style: ?Style = null;
    var z_index = self.current_z_index;

    if (node.ref == .doc_node) {
        node_style = self.doc_tree.getStyle(node.ref.doc_node).*;

        // Update z-index if positioned
        if (node_style.?.position != .relative or node_style.?.z_index != .auto) {
            z_index = switch (node_style.?.z_index) {
                .auto => self.current_z_index,
                .integer => |val| val,
            };
        }
    }

    // Add box render item if it has visual properties
    if (shouldRenderBox(node, node_style)) {
        const bounds = RenderList.Rect.fromBox(box);
        // Adjust bounds to absolute position
        var abs_bounds = bounds;
        abs_bounds.x = abs_pos.x;
        abs_bounds.y = abs_pos.y;

        // Calculate content bounds (inside padding/border)
        var content_bounds = abs_bounds;
        content_bounds.x += box.border.left + box.padding.left;
        content_bounds.y += box.border.top + box.padding.top;
        content_bounds.width -= (box.border.left + box.border.right + box.padding.left + box.padding.right);
        content_bounds.height -= (box.border.top + box.border.bottom + box.padding.top + box.padding.bottom);

        try self.render_list.addItem(.{
            .box = .{
                .bounds = abs_bounds,
                .content_bounds = content_bounds,
                .background = if (node_style) |s| s.background_color else null,
                .border_style = if (node_style) |s| s.border_style else .{
                    .top = .{},
                    .right = .{},
                    .bottom = .{},
                    .left = .{},
                },
                .border_color = if (node_style) |s| s.border_color else .{
                    .top = .{ .solid = Color.tw.white },
                    .right = .{ .solid = Color.tw.white },
                    .bottom = .{ .solid = Color.tw.white },
                    .left = .{ .solid = Color.tw.white },
                },
                .z_index = z_index,
                .node_id = node_id,
                .is_clickable = isElementClickable(node_style),
            },
        });
    }

    // Handle different node types
    switch (node.data) {
        .text_node => {
            // Text nodes are handled by their parent inline containers
        },
        .inline_node => {
            // Inline nodes may have continuations
            const saved_offset = self.current_offset;
            const saved_z = self.current_z_index;
            self.current_offset = abs_pos;
            self.current_z_index = z_index;
            defer {
                self.current_offset = saved_offset;
                self.current_z_index = saved_z;
            }

            // Process children
            for (node.data.inline_node.children.items) |child_id| {
                try self.buildNode(child_id);
            }
        },
        .block_container_node => {
            const saved_offset = self.current_offset;
            const saved_z = self.current_z_index;
            self.current_offset = abs_pos;
            self.current_z_index = z_index;
            defer {
                self.current_offset = saved_offset;
                self.current_z_index = saved_z;
            }

            // Process children
            for (node.data.block_container_node.children.items) |child_id| {
                try self.buildNode(child_id);
            }
        },
        .inline_container_node => |*container| {
            // Add line box fragments
            try self.buildLineBoxes(container, node_id, abs_pos, z_index);

            // Also process any child nodes (though inline containers typically don't have layout children)
            const saved_offset = self.current_offset;
            const saved_z = self.current_z_index;
            self.current_offset = abs_pos;
            self.current_z_index = z_index;
            defer {
                self.current_offset = saved_offset;
                self.current_z_index = saved_z;
            }

            for (container.children.items) |child_id| {
                try self.buildNode(child_id);
            }
        },
    }
}

/// Build render items for line boxes
fn buildLineBoxes(self: *Self, container: *LayoutTree.InlineContainerNode, container_id: LayoutTree.LayoutNode.Id, abs_pos: mod.CSSPoint, z_index: i32) !void {
    _ = container_id; // TODO: Remove when line boxes are re-enabled
    for (container.line_boxes.items()) |line_box| {
        // First, add the line box item for hit testing
        const line_abs_pos = mod.CSSPoint{
            .x = abs_pos.x + line_box.location.x,
            .y = abs_pos.y + line_box.location.y,
        };
        _ = line_abs_pos; // TODO: Remove when line boxes are re-enabled

        // Collect fragment indices for this line box
        var fragment_indices = std.ArrayList(usize).init(self.layout_tree.allocator);

        // TODO: Temporarily commenting out line box addition to debug renderer issue
        // We'll fill in the indices after we add the fragments
        // const line_box_index = self.render_list.items.items.len;
        // try self.render_list.addItem(.{
        //     .line_box = .{
        //         .bounds = .{
        //             .x = line_abs_pos.x,
        //             .y = line_abs_pos.y,
        //             .width = line_box.size.x,
        //             .height = line_box.size.y,
        //         },
        //         .fragment_indices = &[_]usize{}, // Will be updated after fragments
        //         .node_id = container_id,
        //         .allocator = self.layout_tree.allocator,
        //     },
        // });

        for (line_box.fragments.items, 0..) |fragment, fragment_idx| {
            _ = fragment_idx;
            // Remember this fragment's index in the render list
            const fragment_render_index = self.render_list.items.items.len;
            try fragment_indices.append(fragment_render_index);

            // Calculate absolute position for fragment
            // Fragment position is relative to the line box, which is relative to the container
            const frag_abs_pos = mod.CSSPoint{
                .x = abs_pos.x + line_box.location.x + fragment.position.x,
                .y = abs_pos.y + line_box.location.y + fragment.position.y,
            };

            // Use the actual measured dimensions from the fragment
            const bounds = RenderList.Rect{
                .x = frag_abs_pos.x,
                .y = frag_abs_pos.y,
                .width = fragment.size.x,
                .height = fragment.size.y,
            };

            // Get the text color and formatting from the parent inline node
            // Text fragments come from text nodes, which are children of inline nodes
            const layout_node = self.layout_tree.getNodePtr(fragment.l_node_id);
            var text_color = Color.tw.white;
            var text_format = RenderList.TextFormat{};
            var parent_style: ?Style = null;

            // The fragment's l_node_id points to a text node. We need its parent inline node for styling.
            if (layout_node.parent) |parent_id| {
                const parent_node = self.layout_tree.getNodePtr(parent_id);
                if (parent_node.ref == .doc_node) {
                    const doc_node_id = parent_node.ref.doc_node;
                    const style = self.doc_tree.getComputedStyle(doc_node_id);
                    parent_style = style;

                    // Extract text color
                    if (style.foreground_color) |color| {
                        text_color = color;
                    }

                    // Extract text formatting
                    text_format = RenderList.TextFormat.fromStyle(
                        style.font_weight,
                        style.font_style,
                        style.text_decoration,
                    );
                }
            }

            try self.render_list.addItem(.{
                .text_fragment = .{
                    .bounds = bounds,
                    .position = frag_abs_pos,
                    .text = fragment.text,
                    .color = text_color,
                    .format = text_format,
                    .node_id = fragment.l_node_id,
                    .z_index = z_index,
                    .dom_range = fragment.dom_range,
                    .is_clickable = isElementClickable(parent_style),
                },
            });

            // Check if this fragment's doc node has any selection boundaries
            const l_node = self.layout_tree.getNodePtr(fragment.l_node_id);
            if (l_node.ref == .doc_node) {
                const doc_node_id = l_node.ref.doc_node;
                if (self.selection_boundaries.get(doc_node_id)) |selection_ids| {
                    // Process each selection that has a boundary in this node
                    for (selection_ids.items) |selection_id| {
                        try self.addSelectionOverlay(&fragment, frag_abs_pos, selection_id);
                    }
                }
            }
        }

        // TODO: Temporarily commenting out line box update to debug renderer issue
        // Update the line box with the collected fragment indices
        // if (self.render_list.items.items[line_box_index] == .line_box) {
        //     self.render_list.items.items[line_box_index].line_box.fragment_indices = try fragment_indices.toOwnedSlice();
        // }

        // Clean up fragment indices since we're not using them
        fragment_indices.deinit();
    }
}

/// Add selection overlay for a fragment
fn addSelectionOverlay(
    self: *Self,
    fragment: *const mod.LineBoxFragment,
    frag_abs_pos: mod.CSSPoint,
    selection_id: DocTree.Selection.Id,
) !void {
    const selection = self.doc_tree.getSelection(selection_id);
    const range = selection.getRange(self.doc_tree);

    // Get the doc node ID for this fragment's layout node
    const l_node = self.layout_tree.getNodePtr(fragment.l_node_id);
    if (l_node.ref != .doc_node) return; // Only process nodes with doc references
    const doc_node_id = l_node.ref.doc_node;

    // Check if this fragment contains the selection boundaries
    const has_start = range.start.node_id == doc_node_id;
    const has_end = range.end.node_id == doc_node_id;

    if (!has_start and !has_end) {
        // This fragment is in the middle of the selection - render full overlay
        try self.render_list.addItem(.{
            .selection_overlay = .{
                .bounds = .{
                    .x = frag_abs_pos.x,
                    .y = frag_abs_pos.y,
                    .width = fragment.size.x,
                    .height = fragment.size.y,
                },
                .color = styles.color.Color.rgba(0.0, 123.0 / 255.0, 1.0, 0.3),
                .selection_id = selection_id,
            },
        });
        return;
    }

    // Fragment contains at least one boundary - need to calculate partial overlay
    var start_offset: f32 = 0;
    var end_offset: f32 = fragment.size.x;

    if (has_start and range.start.offset >= fragment.dom_range.start and range.start.offset <= fragment.dom_range.end) {
        // Map DOM offset to position in fragment text
        const processed_offset = self.mapDomOffsetToProcessedOffset(
            range.start.offset,
            fragment.dom_range.start,
            fragment.dom_range.end,
            fragment.l_node_id,
            fragment.text,
        );

        // Measure the text up to this offset to get pixel position
        if (processed_offset > 0) {
            const text_before = fragment.text[0..processed_offset];
            start_offset = measureTextWidth(text_before);
        }
    }

    if (has_end and range.end.offset >= fragment.dom_range.start and range.end.offset <= fragment.dom_range.end) {
        // Map DOM offset to position in fragment text
        const processed_offset = self.mapDomOffsetToProcessedOffset(
            range.end.offset,
            fragment.dom_range.start,
            fragment.dom_range.end,
            fragment.l_node_id,
            fragment.text,
        );

        // Measure the text up to this offset to get pixel position
        if (processed_offset > 0) {
            const text_before = fragment.text[0..processed_offset];
            end_offset = measureTextWidth(text_before);
        }
    }

    // Only add overlay if there's something to render
    if (end_offset > start_offset) {
        try self.render_list.addItem(.{
            .selection_overlay = .{
                .bounds = .{
                    .x = frag_abs_pos.x + start_offset,
                    .y = frag_abs_pos.y,
                    .width = end_offset - start_offset,
                    .height = fragment.size.y,
                },
                .color = styles.color.Color.rgba(0.0, 123.0 / 255.0, 1.0, 0.3),
                .selection_id = selection_id,
            },
        });
    }
}

/// Map DOM offset to processed text offset (inverse of mapProcessedOffsetWithinRange)
/// Returns the offset in the processed/fragment text
fn mapDomOffsetToProcessedOffset(
    self: *Self,
    dom_offset: u32,
    dom_range_start: u32,
    dom_range_end: u32,
    l_node_id: LayoutTree.LayoutNode.Id,
    processed_text: []const u8,
) usize {
    // Get the original DOM text
    const l_node = self.layout_tree.getNodePtr(l_node_id);
    if (l_node.ref != .doc_node) return 0;

    const doc_node_id = l_node.ref.doc_node;
    const dom_text = self.doc_tree.getText(doc_node_id).bytes.items;
    const dom_text_slice = dom_text[dom_range_start..dom_range_end];

    // If offset is at the start, return 0
    if (dom_offset <= dom_range_start) return 0;

    // If offset is at or past the end, return the full processed text length
    if (dom_offset >= dom_range_end) return processed_text.len;

    // Calculate relative offset within the fragment's DOM range
    const relative_dom_offset = dom_offset - dom_range_start;

    var dom_pos: usize = 0;
    var processed_pos: usize = 0;

    while (dom_pos < relative_dom_offset and dom_pos < dom_text_slice.len and processed_pos < processed_text.len) {
        // If we're at whitespace in the DOM text
        if (std.ascii.isWhitespace(dom_text_slice[dom_pos])) {
            // Skip the entire whitespace sequence in DOM
            while (dom_pos < dom_text_slice.len and std.ascii.isWhitespace(dom_text_slice[dom_pos])) {
                dom_pos += 1;
            }

            // If we've reached or passed the target offset while in whitespace,
            // position is at the processed space (if it exists)
            if (dom_pos >= relative_dom_offset) {
                return processed_pos;
            }

            // If this whitespace sequence produced a space in processed text, advance processed position
            if (processed_pos < processed_text.len and processed_text[processed_pos] == ' ') {
                processed_pos += 1;
            }
        } else {
            // Non-whitespace character - these map 1:1
            dom_pos += 1;
            processed_pos += 1;
        }
    }

    return processed_pos;
}

/// Measure text width using terminal-aware measurement
fn measureTextWidth(text: []const u8) f32 {
    // Use the terminal-aware width function that excludes ANSI colors
    // and properly handles Unicode characters (CJK, emojis, combining chars)
    const utf8WidthExcludingAnsiColors = @import("../../uni/string-width.zig").utf8WidthExcludingAnsiColors;
    const measured_width = utf8WidthExcludingAnsiColors(text);

    return @as(f32, @floatFromInt(measured_width));
}

/// Check if an element should be clickable based on CSS properties
fn isElementClickable(style: ?Style) bool {
    if (style) |s| {
        // Element is not clickable if pointer-events is 'none'
        if (s.pointer_events == .none) return false;

        // Note: Elements with display: none should not be in the render list at all,
        // so we don't need to check for that here. If they somehow make it here,
        // they should still be clickable so the hit testing works correctly.
    }

    // Default to clickable if no style or auto pointer events
    return true;
}

/// Check if a box should be rendered (has background or borders)
fn shouldRenderBox(node: *LayoutTree.LayoutNode, style: ?Style) bool {
    _ = node;

    if (style) |s| {
        // Has background?
        if (s.background_color != null) return true;

        // Has borders?
        const zero = styles.length_percentage.LengthPercentage.ZERO;
        if (!std.meta.eql(s.border.top, zero) or
            !std.meta.eql(s.border.right, zero) or
            !std.meta.eql(s.border.bottom, zero) or
            !std.meta.eql(s.border.left, zero)) return true;
    }

    return false;
}

test "isElementClickable logic" {
    // Test with null style (should default to clickable)
    try std.testing.expect(isElementClickable(null) == true);

    // Test with default style (should be clickable)
    const default_style = Style{};
    try std.testing.expect(isElementClickable(default_style) == true);

    // Test with pointer-events: none (should not be clickable)
    const no_pointer_style = Style{
        .pointer_events = .none,
    };
    try std.testing.expect(isElementClickable(no_pointer_style) == false);

    // Test with pointer-events: auto (should be clickable)
    const auto_pointer_style = Style{
        .pointer_events = .auto,
    };
    try std.testing.expect(isElementClickable(auto_pointer_style) == true);

    // Test with different display types (should all be clickable since display
    // doesn't affect clickability - elements with display: none shouldn't be rendered)
    const styles_mod = @import("../../styles/styles.zig");
    const block_display_style = Style{
        .display = styles_mod.display.Display.BLOCK,
    };
    try std.testing.expect(isElementClickable(block_display_style) == true);

    const inline_display_style = Style{
        .display = styles_mod.display.Display.INLINE,
    };
    try std.testing.expect(isElementClickable(inline_display_style) == true);
}
