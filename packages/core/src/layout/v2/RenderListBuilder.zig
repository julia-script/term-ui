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

const Self = @This();

pub fn init(layout_tree: *LayoutTree, doc_tree: *DocTree, render_list: *RenderList) Self {
    return .{
        .layout_tree = layout_tree,
        .doc_tree = doc_tree,
        .render_list = render_list,
    };
}

/// Build the render list from the layout tree
pub fn build(self: *Self) !void {
    // Start from the root node (0)
    try self.buildNode(0);

    // Sort by paint order after building
    self.render_list.sortByPaintOrder();
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
    _ = container_id;

    for (container.line_boxes.items()) |line_box| {
        for (line_box.fragments.items) |fragment| {
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

            // The fragment's l_node_id points to a text node. We need its parent inline node for styling.
            if (layout_node.parent) |parent_id| {
                const parent_node = self.layout_tree.getNodePtr(parent_id);
                if (parent_node.ref == .doc_node) {
                    const doc_node_id = parent_node.ref.doc_node;
                    const style = self.doc_tree.getComputedStyle(doc_node_id);

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
                },
            });
        }
    }
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
test "RenderListBuilder - z-index sorting" {
    const docFromXml = @import("doc-from-xml.zig").docFromXml;

    var tree = try docFromXml(std.testing.allocator,
        \\<div style="position: relative; background-color: #808080;">
        \\  <div style="position: absolute; z-index: 2; background-color: #ff0000;"></div>
        \\  <div style="position: absolute; z-index: 1; background-color: #00ff00;"></div>
        \\  <div style="position: absolute; z-index: 3; background-color: #0000ff;"></div>
        \\</div>
    , .{});
    defer tree.deinit();

    var layout_tree = try LayoutTree.fromTree(std.testing.allocator, &tree);
    defer layout_tree.deinit();

    // Create render list
    var render_list = RenderList.init(std.testing.allocator);
    defer render_list.deinit();

    // Build render list
    var builder = init(&layout_tree, &tree, &render_list);
    try builder.build();

    // Should have 4 boxes (parent + 3 children)
    try std.testing.expectEqual(@as(usize, 4), render_list.items.items.len);

    // Verify z-index ordering
    // Parent should be first (z-index 0)
    try std.testing.expectEqual(@as(i32, 0), render_list.items.items[0].box.z_index);
    // Then child with z-index 1
    try std.testing.expectEqual(@as(i32, 1), render_list.items.items[1].box.z_index);
    // Then child with z-index 2
    try std.testing.expectEqual(@as(i32, 2), render_list.items.items[2].box.z_index);
    // Finally child with z-index 3
    try std.testing.expectEqual(@as(i32, 3), render_list.items.items[3].box.z_index);
}
