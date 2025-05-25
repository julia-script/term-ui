const DocTree = @import("../../tree/Tree.zig");
const mod = @import("./mod.zig");
const LayoutTree = mod.LayoutTree;
const css_types = @import("../../css/types.zig");
const LineBox = @import("./text/LineBox.zig");
const ArrayList = std.ArrayList;
const docFromXml = mod.docFromXml;

const std = @import("std");

layout_tree: *LayoutTree,
doc_tree: *DocTree,
allocator: std.mem.Allocator,

pub fn info(self: *Self, l_node_id: mod.LayoutNode.Id, comptime format: []const u8, args: anytype) void {
    const writer = std.io.getStdErr().writer().any();
    var current = l_node_id;
    while (true) {
        if (self.layout_tree.getNodePtr(current).parent) |parent_id| {
            current = parent_id;
        } else {
            break;
        }
        writer.writeAll("  ") catch @panic("failed to write");
    }

    writer.print("\x1b[38;5;{d}m", .{1 + l_node_id % 14}) catch @panic("failed to print");
    writer.print("[{s}#{d}] ", .{ @tagName(self.layout_tree.getNodePtr(l_node_id).data), l_node_id }) catch @panic("failed to print");
    writer.print("\x1b[0m", .{}) catch @panic("failed to print");
    writer.print(format, args) catch @panic("failed to print");
    writer.writeAll("\n") catch @panic("failed to write");
}

pub fn setBox(self: *Self, l_node_id: mod.LayoutNode.Id, box: mod.Box, line_boxes: ?LineBox.LineBoxList) void {
    self.layout_tree.getNodePtr(l_node_id).box = box;
    if (line_boxes) |lb| {
        const container = &self.layout_tree.getNodePtr(l_node_id).data.inline_container_node;
        container.line_boxes.deinit();
        container.line_boxes = lb;
        self.updateFragmentBounds(l_node_id, container);
    }
}

fn updateFragmentBounds(
    self: *Self,
    root_id: mod.LayoutNode.Id,
    container: *LayoutTree.InlineContainerNode,
) void {
    var visited = std.AutoHashMapUnmanaged(mod.LayoutNode.Id, void){};
    defer visited.deinit(self.allocator);

    for (container.line_boxes.items()) |*line| {
        for (line.fragments.items) |fragment| {
            var current_id = fragment.l_node_id;
            const frag_loc = mod.CSSPoint{
                .x = line.location.x + fragment.position.x,
                .y = line.location.y + (line.size.y - fragment.size.y),
            };
            const frag_size = fragment.size;

            while (true) {
                if (current_id == root_id) break;
                const node = self.layout_tree.getNodePtr(current_id);
                if (!visited.contains(current_id)) {
                    visited.put(self.allocator, current_id, {}) catch @panic("oom");
                    node.box.location = frag_loc;
                    node.box.size = frag_size;
                    node.box.content_size = frag_size;
                } else {
                    unionBox(&node.box, frag_loc, frag_size);
                }
                if (node.parent) |p| {
                    current_id = p;
                } else break;
            }
        }
    }
}

fn unionBox(box: *mod.Box, loc: mod.CSSPoint, size: mod.CSSPoint) void {
    const right = loc.x + size.x;
    const bottom = loc.y + size.y;
    const box_right = box.location.x + box.size.x;
    const box_bottom = box.location.y + box.size.y;

    const new_left = @min(box.location.x, loc.x);
    const new_top = @min(box.location.y, loc.y);
    const new_right = @max(box_right, right);
    const new_bottom = @max(box_bottom, bottom);

    box.location = .{ .x = new_left, .y = new_top };
    box.size = .{ .x = new_right - new_left, .y = new_bottom - new_top };
    box.content_size = box.size;
}
pub const StyleProperty = enum {
    margin,
    padding,
    border_width,
    inset,
    size,
    max_size,
    min_size,
    aspect_ratio,
    display,
    position,
    overflow,
    scrollbar_width,
    flex_direction,
    flex_wrap,
    flex_basis,
    flex_grow,
    flex_shrink,
    align_items,
    align_self,
    justify_content,
    align_content,
    gap,
    text_align,
    white_space,
};
const styles = @import("../../styles/styles.zig");
const Styles = @import("../../tree/Style.zig");
fn getLayoutNodeStyles(self: *Self, l_node_id: mod.LayoutNode.Id) ?*Styles {
    const l_node = self.layout_tree.getNodePtr(l_node_id);
    switch (l_node.ref) {
        .doc_node => |doc_node| {
            return self.doc_tree.getStyle(doc_node);
        },
        else => {
            return null;
        },
    }
}

pub fn getChildren(self: *Self, l_node_id: mod.LayoutNode.Id) []const mod.LayoutNode.Id {
    return self.layout_tree.getChildren(l_node_id);
}

pub fn getStyleValue(self: *Self, T: type, l_node_id: mod.LayoutNode.Id, comptime property: StyleProperty) T {
    const maybe_node_styles = self.getLayoutNodeStyles(l_node_id);

    switch (comptime property) {
        .margin => {
            return if (maybe_node_styles) |node_styles| node_styles.margin else css_types.LengthPercentageAutoRect{
                .top = .{ .length = 0 },
                .right = .{ .length = 0 },
                .bottom = .{ .length = 0 },
                .left = .{ .length = 0 },
            };
        },
        .padding => {
            return if (maybe_node_styles) |node_styles| node_styles.padding else css_types.LengthPercentageRect{
                .top = .{ .length = 0 },
                .right = .{ .length = 0 },
                .bottom = .{ .length = 0 },
                .left = .{ .length = 0 },
            };
        },
        .border_width => {
            return if (maybe_node_styles) |node_styles| node_styles.border else css_types.LengthPercentageRect{
                .top = .{ .length = 0 },
                .right = .{ .length = 0 },
                .bottom = .{ .length = 0 },
                .left = .{ .length = 0 },
            };
        },
        .inset => {
            return if (maybe_node_styles) |node_styles| node_styles.inset else css_types.LengthPercentageAutoRect{
                .top = .auto,
                .right = .auto,
                .bottom = .auto,
                .left = .auto,
            };
        },
        .size => {
            return if (maybe_node_styles) |node_styles| node_styles.size else css_types.LengthPercentageAutoPoint{
                .x = .auto,
                .y = .auto,
            };
        },
        .max_size => {
            return if (maybe_node_styles) |node_styles| node_styles.max_size else css_types.LengthPercentageAutoPoint{
                .x = .auto,
                .y = .auto,
            };
        },
        .min_size => {
            return if (maybe_node_styles) |node_styles| node_styles.min_size else css_types.LengthPercentageAutoPoint{
                .x = .auto,
                .y = .auto,
            };
        },
        .position => {
            return if (maybe_node_styles) |node_styles| node_styles.position else styles.position.Position.DEFAULT;
        },
        .display => {
            return if (maybe_node_styles) |node_styles| node_styles.display else styles.display.Display.BLOCK;
        },
        .overflow => {
            return if (maybe_node_styles) |node_styles| node_styles.overflow else css_types.OverflowPoint{
                .x = .visible,
                .y = .visible,
            };
        },
        .aspect_ratio => {
            return if (maybe_node_styles) |node_styles| node_styles.aspect_ratio else @as(?f32, null);
        },
        .scrollbar_width => {
            return if (maybe_node_styles) |node_styles| node_styles.scrollbar_width else @as(f32, 0);
        },
        .flex_direction => {
            return if (maybe_node_styles) |node_styles| node_styles.flex_direction else styles.flex_direction.FlexDirection.row;
        },
        .flex_wrap => {
            return if (maybe_node_styles) |node_styles| node_styles.flex_wrap else styles.flex_wrap.FlexWrap.no_wrap;
        },
        .flex_basis => {
            return if (maybe_node_styles) |node_styles| node_styles.flex_basis else styles.length_percentage_auto.LengthPercentageAuto.auto;
        },
        .flex_grow => {
            return if (maybe_node_styles) |node_styles| node_styles.flex_grow else @as(f32, 0);
        },
        .flex_shrink => {
            return if (maybe_node_styles) |node_styles| node_styles.flex_shrink else @as(f32, 1);
        },
        .align_items => {
            return if (maybe_node_styles) |node_styles| node_styles.align_items orelse .stretch else .stretch;
        },
        .align_self => {
            return if (maybe_node_styles) |node_styles| node_styles.align_self orelse .auto else .auto;
        },
        .justify_content => {
            return if (maybe_node_styles) |node_styles| node_styles.justify_content orelse .flex_start else .flex_start;
        },
        .align_content => {
            return if (maybe_node_styles) |node_styles| node_styles.align_content orelse .stretch else .stretch;
        },
        .gap => {
            return if (maybe_node_styles) |node_styles| node_styles.gap else css_types.LengthPercentagePoint{
                .x = .{ .length = 0 },
                .y = .{ .length = 0 },
            };
        },
        .text_align => {
            return if (maybe_node_styles) |node_styles| node_styles.text_align else .inherit;
        },
        .white_space => {
            return if (maybe_node_styles) |node_styles| node_styles.white_space else .normal;
        },
    }
}

const Self = @This();
