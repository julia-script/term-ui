const DocTree = @import("../../tree/Tree.zig");
const mod = @import("./mod.zig");
const LayoutTree = mod.LayoutTree;
const css_types = @import("../../css/types.zig");
const ArrayList = std.ArrayList;
const docFromXml = mod.docFromXml;

const std = @import("std");

// Scoped logger for layout debugging
const log = std.log.scoped(.layout);

layout_tree: *LayoutTree,
doc_tree: *DocTree,
allocator: std.mem.Allocator,

pub fn info(self: *Self, l_node_id: mod.LayoutNode.Id, comptime format: []const u8, args: anytype) void {
    // Use scoped logger instead of direct printing
    // This allows controlling output via log level
    if (@import("builtin").mode == .Debug) {
        var buf: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        // Build indentation
        var current = l_node_id;
        while (true) {
            if (self.layout_tree.getNodePtr(current).parent) |parent_id| {
                current = parent_id;
            } else {
                break;
            }
            writer.writeAll("  ") catch {};
        }

        // Build the message
        writer.print("[{s}#{d}] ", .{ @tagName(self.layout_tree.getNodePtr(l_node_id).data), l_node_id }) catch {};
        writer.print(format, args) catch {};

        // Use debug log level so it can be filtered
        log.debug("{s}", .{fbs.getWritten()});
    }
}

pub fn setBox(self: *Self, l_node_id: mod.LayoutNode.Id, box: mod.Box, line_boxes: ?mod.LineBox.LineBoxList) !void {
    self.layout_tree.getNodePtr(l_node_id).box = box;
    var node = self.layout_tree.getNodePtr(l_node_id);
    switch (node.data) {
        .inline_container_node => {
            node.data.inline_container_node.line_boxes.deinit();
            if (line_boxes) |*lb| {
                node.data.inline_container_node.line_boxes = try lb.dupe(self.allocator);
            }
        },
        else => {},
    }
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
    white_space_collapse,
    text_wrap_mode,
};
const styles = @import("../../styles/styles.zig");
const Styles = @import("../../tree/Style.zig");

pub fn getChildren(self: *Self, l_node_id: mod.LayoutNode.Id) []const mod.LayoutNode.Id {
    return self.layout_tree.getChildren(l_node_id);
}

pub fn getStyleValue(self: *Self, T: type, l_node_id: mod.LayoutNode.Id, comptime property: StyleProperty) T {
    const node_styles = self.layout_tree.getNodeStyle(self.doc_tree, l_node_id);

    switch (comptime property) {
        .margin => {
            return node_styles.margin;
        },
        .padding => {
            return node_styles.padding;
        },
        .border_width => {
            return node_styles.border;
        },
        .inset => {
            return node_styles.inset;
        },
        .size => {
            return node_styles.size;
        },
        .max_size => {
            return node_styles.max_size;
        },
        .min_size => {
            return node_styles.min_size;
        },
        .position => {
            return node_styles.position;
        },
        .display => {
            return node_styles.display;
        },
        .overflow => {
            return node_styles.overflow;
        },
        .aspect_ratio => {
            return node_styles.aspect_ratio;
        },
        .scrollbar_width => {
            return node_styles.scrollbar_width;
        },
        .flex_direction => {
            return node_styles.flex_direction;
        },
        .flex_wrap => {
            return node_styles.flex_wrap;
        },
        .flex_basis => {
            return node_styles.flex_basis;
        },
        .flex_grow => {
            return node_styles.flex_grow;
        },
        .flex_shrink => {
            return node_styles.flex_shrink;
        },
        .align_items => {
            return node_styles.align_items;
        },
        .align_self => {
            return node_styles.align_self;
        },
        .justify_content => {
            return node_styles.justify_content;
        },
        .align_content => {
            return node_styles.align_content;
        },
        .gap => {
            return node_styles.gap;
        },
        .text_align => {
            return node_styles.text_align;
        },
        .white_space_collapse => {
            return node_styles.white_space_collapse;
        },
        .text_wrap_mode => {
            return node_styles.text_wrap_mode;
        },
    }
}

const Self = @This();
