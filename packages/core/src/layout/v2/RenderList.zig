const std = @import("std");
const mod = @import("mod.zig");
const LayoutTree = @import("LayoutTree.zig");
const DocTree = @import("../../tree/Tree.zig");
const Style = @import("../../tree/Style.zig");
const styles = @import("../../styles/styles.zig");
const Color = @import("../../colors/Color.zig");
const Canvas = @import("../../renderer/v2/Canvas.zig");
const NodeId = @import("../../tree/Tree.zig").Node.NodeId;
pub const TextFormat = Canvas.TextFormat;
const GraphemeIterator = @import("../../uni/GraphemeBreak.zig").Iterator;
const BoundaryPoint = @import("../../tree/BoundaryPoint.zig");
const measureText = @import("../../uni/string-width.zig").measureText;

/// A flat list of render items representing the paint order of the layout tree
items: std.ArrayListUnmanaged(RenderItem) = .empty,
allocator: std.mem.Allocator,
node_boxes_map: std.AutoHashMapUnmanaged(NodeId, usize) = .{},

const Self = @This();

/// DOM text range for mapping between processed and original text
pub const DomRange = struct {
    start: u32,
    end: u32,
};

/// Rectangle for painting and hit testing
pub const Rect = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn top(self: Rect) f32 {
        return self.y;
    }
    pub fn bottom(self: Rect) f32 {
        return self.y + self.height;
    }
    pub fn left(self: Rect) f32 {
        return self.x;
    }
    pub fn right(self: Rect) f32 {
        return self.x + self.width;
    }

    pub fn fromCSSRect(css_rect: mod.CSSRect, location: mod.CSSPoint) Rect {
        return .{
            .x = location.x + css_rect.left,
            .y = location.y + css_rect.top,
            .width = css_rect.right - css_rect.left,
            .height = css_rect.bottom - css_rect.top,
        };
    }

    pub fn fromBox(box: mod.Box, abs_pos: mod.CSSPoint) Rect {
        return .{
            .x = abs_pos.x + box.location.x,
            .y = abs_pos.y + box.location.y,
            .width = box.size.x,
            .height = box.size.y,
        };
    }

    pub fn contains(self: Rect, point: mod.CSSPoint) bool {
        return point.x >= self.x and point.x < self.x + self.width and
            point.y >= self.y and point.y < self.y + self.height;
    }

    pub fn containsXY(self: Rect, x: f32, y: f32) bool {
        return x >= self.x and x < self.x + self.width and
            y >= self.y and y < self.y + self.height;
    }

    pub fn intersectsWith(self: Rect, other: Rect) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    pub fn intersect(self: Rect, other: Rect) Rect {
        const x1 = @max(self.x, other.x);
        const y1 = @max(self.y, other.y);
        const x2 = @min(self.x + self.width, other.x + other.width);
        const y2 = @min(self.y + self.height, other.y + other.height);

        return .{
            .x = x1,
            .y = y1,
            .width = @max(0, x2 - x1),
            .height = @max(0, y2 - y1),
        };
    }
    pub fn offset(self: Rect, distance: mod.CSSPoint) Rect {
        return .{
            .x = self.x + distance.x,
            .y = self.y + distance.y,
            .width = self.width,
            .height = self.height,
        };
    }
    pub fn format(self: Rect, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Rect(x={d:.1}, y={d:.1}, width={d:.1}, height={d:.1})", .{ self.x, self.y, self.width, self.height });
    }
    pub fn round(self: Rect) Rect {
        return .{
            .x = @round(self.x),
            .y = @round(self.y),
            .width = @round(self.width),
            .height = @round(self.height),
        };
    }
    pub fn isZero(self: Rect) bool {
        return self.width == 0 or self.height == 0;
    }
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    self.node_boxes_map.deinit(self.allocator);
    for (self.items.items) |*item| {
        item.deinit(self.allocator);
    }
    self.items.deinit(self.allocator);
}

pub fn slice(self: *Self) []RenderItem {
    return self.items.items;
}
/// Clear all items but retain allocated capacity for reuse
pub fn clear(self: *Self) void {
    // Deinit existing items
    for (self.items.items) |*item| {
        item.deinit(self.allocator);
    }
    // Clear the list but keep the allocated memory
    self.items.clearRetainingCapacity();
    self.node_boxes_map.clearRetainingCapacity();
}

/// Format function for RenderList that shows each item with its index
pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    for (self.items.items, 0..) |item, i| {
        if (i > 0) try writer.print("\n", .{});
        try writer.print("#{d} {}", .{ i, item });
    }
}
pub fn at(self: *const Self, index: usize) ?RenderItem {
    return self.items.items[index];
}

/// Render item types for TUI rendering
pub const RenderItem = union(enum) {
    /// Draw a box (background, borders)
    box: BoxItem,
    /// Draw text fragment
    text_fragment: TextFragmentItem,
    /// Push a clipping region
    push_clip: ClipItem,
    /// Pop a clipping region
    pop_clip: void,
    /// Draw selection overlay
    selection_overlay: SelectionOverlayItem,
    /// Line box for hit testing (not rendered)
    line_box: LineBoxItem,
    /// Last index of the item in the render list
    pub fn deinit(self: *RenderItem, allocator: std.mem.Allocator) void {
        _ = allocator;
        switch (self.*) {
            .line_box => |*item| item.deinit(),
            else => {}, // Other items don't allocate
        }
    }
    pub fn format(self: RenderItem, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
        _ = fmt; // autofix
        _ = options; // autofix

        switch (self) {
            .box => |box| {
                try writer.print("[box bb={{{d:.1}, {d:.1}, {d:.1}, {d:.1}}} nid={d} lid={d}", .{
                    box.bounds.x,
                    box.bounds.y,
                    box.bounds.width,
                    box.bounds.height,
                    box.doc_node_id,
                    box.node_id,
                });
                if (box.background) |bg| {
                    switch (bg) {
                        .solid => |color| try writer.print(" bg=#{x:0>6}", .{color.toHex() & 0xFFFFFF}),
                        .linear_gradient => try writer.print(" bg=linear-gradient", .{}),
                        .radial_gradient => try writer.print(" bg=radial-gradient", .{}),
                    }
                }
                try writer.print("]", .{});
            },
            .text_fragment => |text| {
                try writer.print("[text_fragment bb={{{d:.1}, {d:.1}, {d:.1}, {d:.1}}} nid={d} lid={d} host={?d} range={d}~{d} text=\"{s}\"]", .{
                    text.bounds.x,
                    text.bounds.y,
                    text.bounds.width,
                    text.bounds.height,
                    text.doc_node_id,
                    text.node_id,
                    text.editing_host_index,
                    text.dom_range.start,
                    text.dom_range.end,
                    text.text,
                });
            },
            .push_clip => |clip| {
                try writer.print("[push_clip rect={{{d:.1}, {d:.1}, {d:.1}, {d:.1}}}]", .{
                    clip.rect.x,
                    clip.rect.y,
                    clip.rect.width,
                    clip.rect.height,
                });
            },
            .pop_clip => {
                try writer.print("[pop_clip]", .{});
            },
            .selection_overlay => |sel| {
                try writer.print("[selection_overlay bb={{{d:.1}, {d:.1}, {d:.1}, {d:.1}}} id={d}]", .{
                    sel.bounds.x,
                    sel.bounds.y,
                    sel.bounds.width,
                    sel.bounds.height,
                    sel.selection_id,
                });
            },
            .line_box => |line| {
                try writer.print("[line_box bb={{{d:.1}, {d:.1}, {d:.1}, {d:.1}}} nid={d} lid={d} fragments={{", .{
                    line.bounds.x,
                    line.bounds.y,
                    line.bounds.width,
                    line.bounds.height,
                    line.doc_node_id,
                    line.node_id,
                });
                for (line.fragment_indexes, 0..) |idx, i| {
                    if (i > 0) try writer.print(", ", .{});
                    try writer.print("{d}", .{idx});
                }
                try writer.print("}}]", .{});
            },
        }
    }
};

pub const BoxItem = struct {
    /// Bounding box for painting and hit testing
    bounds: Rect,
    // /// Content bounds (inside padding/border) for hit testing children
    // content_bounds: Rect,
    /// Background color/gradient
    background: ?styles.background.Background,
    /// Border styles
    border_style: mod.RectOf(styles.border.BoxChar.Cell),
    border_color: mod.RectOf(styles.background.Background),
    /// Z-index for stacking context
    z_index: i32 = 0,
    /// Layout node ID for debugging and hit testing
    node_id: LayoutTree.LayoutNode.Id,
    doc_node_id: NodeId,
    /// Whether this element can receive click events
    is_clickable: bool = true,
    last_index: usize,
    is_editing_host: bool,
    is_scroll_container: bool,
    scroll_offset: mod.CSSPoint,
};

pub const TextFragmentItem = struct {
    /// Bounding box for hit testing
    bounds: Rect,
    /// Reference to text in layout tree (not owned)
    text: []const u8,
    /// Text color
    color: styles.color.Color,
    /// Text formatting (bold, italic, underline, etc)
    format: TextFormat,
    /// For getting styles and hit testing
    node_id: LayoutTree.LayoutNode.Id,
    doc_node_id: NodeId,
    /// Z-index for stacking context
    z_index: i32 = 0,
    /// Range in the original DOM text node (for caret positioning)
    dom_range: DomRange,
    /// Whether this element can receive click events (usually false for text)
    is_clickable: bool = false,
    linebox_index: usize,
    editing_host_index: ?usize,
    is_atomic: bool = false,
    pub fn getOffsetPosition(self: TextFragmentItem, offset: usize) mod.CSSPoint {
        if (offset <= self.dom_range.start) {
            return .{ .x = self.bounds.x, .y = self.bounds.y };
        }
        if (offset >= self.dom_range.end) {
            return .{ .x = self.bounds.x + self.bounds.width, .y = self.bounds.y };
        }

        const end: usize = @min(self.dom_range.end, offset) - self.dom_range.start;

        const width = measureText(self.text[0..end]);
        return .{ .x = self.bounds.x + width, .y = self.bounds.y };
    }
    pub fn getOffsetAtX(self: TextFragmentItem, x: f32) u32 {
        if (x <= self.bounds.x) {
            return self.dom_range.start;
        }
        if (x >= self.bounds.x + self.bounds.width) {
            return self.dom_range.end;
        }
        var pos = @round(self.bounds.x);
        var iter = GraphemeIterator.init(self.text);
        while (iter.next()) |grapheme| {
            const width = measureText(grapheme.bytes(self.text));
            if ((pos + width) > x) {
                return @min(self.dom_range.start + grapheme.offset, self.dom_range.end);
            }
            pos += width;
        }
        return self.dom_range.end;
    }
    pub fn visibleDomEnd(self: TextFragmentItem) u32 {
        return @intCast(self.dom_range.start + self.text.len);
    }
    pub fn containsBp(self: TextFragmentItem, bp: BoundaryPoint) bool {
        if (bp.node_id != self.doc_node_id) return false;
        return bp.offset >= self.dom_range.start and bp.offset <= self.dom_range.end;
    }
};

pub const ClipItem = struct {
    /// Clipping rectangle
    rect: Rect,
};

pub const SelectionOverlayItem = struct {
    /// Bounding box for the selection overlay
    bounds: Rect,
    /// Semi-transparent color for the selection
    color: styles.color.Color = styles.color.Color.rgba(0.0, 123.0 / 255.0, 1.0, 0.3),
    /// Selection ID to identify which selection this belongs to
    selection_id: u32,
};

pub const LineBoxItem = struct {
    /// Bounding box spanning the full line width
    bounds: Rect,
    /// Layout node ID of the inline container
    node_id: LayoutTree.LayoutNode.Id,
    doc_node_id: NodeId,
    fragment_indexes: []const usize,
    /// Allocator for fragment indices
    allocator: std.mem.Allocator,
    editing_host_index: ?usize,

    /// Allocator for fragment indices
    pub fn deinit(self: *LineBoxItem) void {
        // self.fragment_indexes.deinit(self.allocator);
        self.allocator.free(self.fragment_indexes);
    }
    pub fn getFirstNonEmptyFragmentIndex(self: LineBoxItem, render_list: *Self) ?usize {
        for (self.fragment_indexes) |index| {
            const fragment = render_list.at(index).?.text_fragment;
            if (fragment.text.len > 0) return index;
        }
        return null;
    }
    pub fn getLastNonEmptyFragmentIndex(self: LineBoxItem, render_list: *Self) ?usize {
        var i = self.fragment_indexes.len;
        while (i > 0) : (i -= 1) {
            const fragment = render_list.at(self.fragment_indexes[i - 1]).?.text_fragment;
            if (fragment.text.len > 0) return self.fragment_indexes[i - 1];
        }
        return null;
    }
};

/// Add a render item to the list
pub fn addItem(self: *Self, item: RenderItem) !usize {
    try self.items.append(self.allocator, item);
    return self.items.items.len - 1;
}

/// Sort items by paint order (z-index and tree order)
pub fn sortByPaintOrder(self: *Self) void {
    std.sort.insertion(RenderItem, self.items.items, {}, compareRenderItems);
}

fn compareRenderItems(_: void, a: RenderItem, b: RenderItem) bool {
    const a_z = getZIndex(a);
    const b_z = getZIndex(b);

    // Lower z-index paints first
    if (a_z != b_z) {
        return a_z < b_z;
    }

    // Same z-index: maintain tree order (which is insertion order)
    return false;
}

fn getZIndex(item: RenderItem) i32 {
    return switch (item) {
        .box => |box| box.z_index,
        .text_fragment => |text| text.z_index,
        .push_clip, .pop_clip => 0,
        .selection_overlay => 0, // Selections are rendered in tree order, right after their text
        .line_box => 0, // Line boxes are for hit testing only
    };
}

/// Debug print the render list
pub fn print(self: *Self, writer: std.io.AnyWriter) !void {
    try writer.print("RenderList ({d} items):\n", .{self.items.items.len});
    for (self.items.items, 0..) |item, i| {
        try writer.print("  [{d}] ", .{i});

        switch (item) {
            .box => |box| {
                try writer.print("Box #{d} bounds=[pos:({d:.1},{d:.1}) size:({d:.1}x{d:.1})] z={d}", .{
                    box.node_id,
                    box.bounds.x,
                    box.bounds.y,
                    box.bounds.width,
                    box.bounds.height,
                    box.z_index,
                });

                if (box.background) |bg| {
                    switch (bg) {
                        .solid => |color| try writer.print(" bg=#{x:0>8}", .{color.toHex()}),
                        else => try writer.print(" bg=<gradient>", .{}),
                    }
                }
            },
            .text_fragment => |text| {
                try writer.print("TextFragment #{d} bounds=[pos:({d:.1},{d:.1}) size:({d:.1}x{d:.1})] z={d} text=\"{s}\"", .{
                    text.node_id,
                    text.bounds.x,
                    text.bounds.y,
                    text.bounds.width,
                    text.bounds.height,
                    text.z_index,
                    text.text,
                });

                // Print formatting info if any
                if (text.format.is_bold or text.format.is_italic or text.format.decoration_line != .none) {
                    try writer.print(" format=[", .{});
                    var first = true;
                    if (text.format.is_bold) {
                        try writer.print("bold", .{});
                        first = false;
                    }
                    if (text.format.is_italic) {
                        if (!first) try writer.print(",", .{});
                        try writer.print("italic", .{});
                        first = false;
                    }
                    if (text.format.decoration_line != .none) {
                        if (!first) try writer.print(",", .{});
                        try writer.print("{s}", .{@tagName(text.format.decoration_line)});
                    }
                    try writer.print("]", .{});
                }
            },
            .push_clip => |clip| {
                try writer.print("PushClip rect=({d:.1},{d:.1} {d:.1}x{d:.1})", .{
                    clip.rect.x,
                    clip.rect.y,
                    clip.rect.width,
                    clip.rect.height,
                });
            },
            .pop_clip => try writer.print("PopClip", .{}),
            .selection_overlay => |sel| {
                try writer.print("SelectionOverlay #{d} bounds=({d:.1},{d:.1} {d:.1}x{d:.1}) color=#{x:0>8}", .{
                    sel.selection_id,
                    sel.bounds.x,
                    sel.bounds.y,
                    sel.bounds.width,
                    sel.bounds.height,
                    sel.color.toHex(),
                });
            },
            .line_box => |line| {
                try writer.print("LineBox #{d} bounds=({d:.1},{d:.1} {d:.1}x{d:.1}) fragments=[", .{
                    line.node_id,
                    line.bounds.x,
                    line.bounds.y,
                    line.bounds.width,
                    line.bounds.height,
                });
                for (line.fragment_indexes, 0..) |idx, j| {
                    if (j > 0) try writer.writeAll(",");
                    try writer.print("{d}", .{idx});
                }
                try writer.writeAll("]");
            },
        }
        try writer.print("\n", .{});
    }
}

/// Hit test result containing the render item and its node ID
pub const HitTestResult = struct {
    item_index: usize,
    external_id: u32,
    item_type: enum(u8) { box = 1, text_fragment = 2, line_box = 3, selection_overlay = 4 },
    bounds: Rect,
};

pub const HitTestFilter = struct {
    pub const BOX: u8 = 0b0001;
    pub const INCLUDE_DISABLED_POINTER_EVENTS: u8 = 0b0010;
    pub const TEXT_FRAGMENT: u8 = 0b0100;
    pub const SELECTION_OVERLAY: u8 = 0b1000;
    pub const LINE_BOX: u8 = 0b10000;

    pub fn matches(self: u8, matcher: u8) bool {
        return (self & matcher) == matcher;
    }
};
test "HitTestFilter" {
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX,
        HitTestFilter.BOX,
    ));
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
        HitTestFilter.BOX,
    ));
    try std.testing.expect(!HitTestFilter.matches(HitTestFilter.BOX, HitTestFilter.TEXT_FRAGMENT));
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
        HitTestFilter.BOX,
    ));
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
        HitTestFilter.TEXT_FRAGMENT,
    ));
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
    ));
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
        HitTestFilter.BOX,
    ));
    try std.testing.expect(HitTestFilter.matches(
        HitTestFilter.BOX | HitTestFilter.TEXT_FRAGMENT,
        HitTestFilter.TEXT_FRAGMENT,
    ));
}

/// Perform hit testing at the given coordinates
/// Returns the topmost item that contains the point, respecting z-order and filters
pub fn hitTest(self: *const Self, point: mod.CSSPoint, filter: u8) ?HitTestResult {
    var result: ?HitTestResult = null;

    // Iterate through all items to find hits
    for (self.items.items, 0..) |item, i| {
        switch (item) {
            .box => |box| {
                if (HitTestFilter.matches(filter, HitTestFilter.BOX) and box.bounds.contains(point)) {
                    // Skip non-clickable boxes when filtering for pointer events
                    if (!box.is_clickable and !HitTestFilter.matches(filter, HitTestFilter.INCLUDE_DISABLED_POINTER_EVENTS)) continue;

                    result = .{
                        .item_index = i,
                        .external_id = @intCast(box.doc_node_id),
                        .item_type = .box,
                        .bounds = box.bounds,
                    };
                }
            },
            .text_fragment => |text| {
                if (HitTestFilter.matches(filter, HitTestFilter.TEXT_FRAGMENT) and text.bounds.contains(point)) {
                    // Skip non-clickable text when filtering for pointer events
                    if (!text.is_clickable and !HitTestFilter.matches(filter, HitTestFilter.INCLUDE_DISABLED_POINTER_EVENTS)) continue;

                    result = .{
                        .item_index = i,
                        .external_id = @intCast(text.doc_node_id),
                        .item_type = .text_fragment,
                        .bounds = text.bounds,
                    };
                }
            },
            .selection_overlay => |sel| {
                if (HitTestFilter.matches(filter, HitTestFilter.SELECTION_OVERLAY) and sel.bounds.contains(point)) {
                    // Selection overlays typically have high z-index
                    result = .{
                        .item_index = i,
                        .external_id = @intCast(sel.selection_id),
                        .item_type = .selection_overlay,
                        .bounds = sel.bounds,
                    };
                }
            },
            .line_box => |line| {
                if (HitTestFilter.matches(filter, HitTestFilter.LINE_BOX) and line.bounds.contains(point)) {
                    result = .{
                        .item_index = i,
                        .external_id = @intCast(line.doc_node_id),
                        .item_type = .line_box,
                        .bounds = line.bounds,
                    };
                }
            },
            .push_clip, .pop_clip => {
                // These don't participate in hit testing
            },
        }
    }

    return result;
}

pub fn firstTextFragmentBeforeBox(self: *const Self, node_index: usize) ?usize {
    const list = self.items.items;
    var i: usize = node_index;
    while (i > 0) : (i -= 1) {
        const item = list[i];
        switch (item) {
            .text_fragment => {
                return i;
            },
            else => {},
        }
    }
    return null;
}
pub fn findNodeBox(self: *const Self, node_id: NodeId) ?usize {
    const list = self.items.items;
    for (list, 0..) |item, i| {
        switch (item) {
            .box => |box| {
                if (box.doc_node_id == node_id) return i;
            },
            else => {},
        }
    }
    return null;
}

pub fn findItemAtBoundaryPoint(self: *const Self, doc_node_id: NodeId, offset: u32) ?usize {
    const list = self.items.items;

    var candidate: ?usize = null;
    for (list, 0..) |item, i| {
        switch (item) {
            .text_fragment => |text| {
                if (text.doc_node_id == doc_node_id) {
                    if (offset >= text.dom_range.start or candidate == null) {
                        candidate = i;
                    }
                } else {
                    if (candidate) |candidate_index| {
                        return candidate_index;
                    }
                }
            },
            .box => |box| {
                if (doc_node_id == box.doc_node_id) {
                    return i;
                }
            },
            else => {},
        }
    }
    return candidate;
}

pub fn firstTextFragmentAfterBox(self: *const Self, node_index: usize) ?usize {
    const list = self.items.items;
    var i: usize = list[node_index].box.last_index;
    while (i < list.len) : (i += 1) {
        const item = list[i];
        switch (item) {
            .text_fragment => {
                return i;
            },
            else => {},
        }
    }
    return null;
}

pub fn firstTextFragmentAfterIndexWithinContext(self: *const Self, context_index: ?usize, index: usize) ?usize {
    const list = self.items.items;
    var i: usize = index + 1;
    while (i < list.len) : (i += 1) {
        const item = list[i];
        switch (item) {
            .text_fragment => |text| {
                if (text.editing_host_index == context_index and text.text.len > 0) return i;
            },
            else => {},
        }
    }
    return null;
}
pub fn firstTextFragmentBeforeIndexWithinContext(self: *const Self, context_index: ?usize, index: usize) ?usize {
    const list = self.items.items;
    if (index == 0) return null;
    var i: usize = index - 1;

    while (i > 0) : (i -= 1) {
        const item = list[i];
        switch (item) {
            .text_fragment => |text| {
                if (text.editing_host_index == context_index and text.text.len > 0) return i;
            },
            else => {},
        }
    }
    return null;
}

pub fn lastTextFragment(self: *const Self, host_box_index: ?usize) ?usize {
    const list = self.items.items;
    const start_index: usize = host_box_index orelse 0;
    var end_index = list.len;
    if (host_box_index) |index| {
        const box = list[index].box;
        end_index = box.last_index + 1;
    }
    // if (host_box_index) |index| {
    //     const box = list[index].box;
    //     list = list[index .. index + box.last_index];
    //     start_index = index;
    // }
    var i: usize = end_index - 1;
    while (i >= start_index) : (i -= 1) {
        const item = list[i];
        switch (item) {
            .text_fragment => |text| {
                if (text.editing_host_index == host_box_index) return i;
            },
            else => {},
        }
    }
    return null;
}

pub fn firstTextFragment(self: *const Self, host_box_index: ?usize) ?usize {
    const list = self.items.items;
    const start_index: usize = host_box_index orelse 0;
    var end_index = list.len;
    if (host_box_index) |index| {
        const box = list[index].box;
        end_index = box.last_index + 1;
    }
    var i: usize = start_index;
    while (i < end_index) : (i += 1) {
        const item = list[i];
        switch (item) {
            .text_fragment => |text| {
                if (text.editing_host_index == host_box_index) return i;
            },
            .box => |box| {
                if (box.is_editing_host) {
                    i = box.last_index;
                }
            },
            else => {},
        }
    }
    return null;
}

pub fn hitTestList(self: *const Self, list: *std.ArrayList(HitTestResult), allocator: std.mem.Allocator, point: mod.CSSPoint, filter: u8) !void {
    for (self.items.items, 0..) |item, i| {
        switch (item) {
            .box => |box| {
                if (HitTestFilter.matches(filter, HitTestFilter.BOX) and box.bounds.contains(point)) {
                    try list.append(allocator, .{
                        .item_index = i,
                        .external_id = @intCast(box.doc_node_id),
                        .item_type = .box,
                        .bounds = box.bounds,
                    });
                }
            },
            .text_fragment => |text| {
                if (HitTestFilter.matches(filter, HitTestFilter.TEXT_FRAGMENT) and text.bounds.contains(point)) {
                    try list.append(allocator, .{
                        .item_index = i,
                        .external_id = @intCast(text.doc_node_id),
                        .item_type = .text_fragment,
                        .bounds = text.bounds,
                    });
                }
            },
            .selection_overlay => |sel| {
                if (HitTestFilter.matches(filter, HitTestFilter.SELECTION_OVERLAY) and sel.bounds.contains(point)) {
                    try list.append(allocator, .{
                        .item_index = i,
                        .external_id = @intCast(sel.selection_id),
                        .item_type = .selection_overlay,
                        .bounds = sel.bounds,
                    });
                }
            },
            .line_box => |line| {
                if (HitTestFilter.matches(filter, HitTestFilter.LINE_BOX) and line.bounds.contains(point)) {
                    try list.append(allocator, .{
                        .item_index = i,
                        .external_id = @intCast(line.doc_node_id),
                        .item_type = .line_box,
                        .bounds = line.bounds,
                    });
                }
            },
            .push_clip, .pop_clip => {
                // These don't participate in hit testing
            },
        }
    }
}

pub fn putDocNodeBoxIndex(self: *Self, doc_node_id: NodeId, index: usize) !void {
    try self.node_boxes_map.put(self.allocator, doc_node_id, index);
}
pub fn getDocNodeBoxIndex(self: *const Self, doc_node_id: NodeId) ?usize {
    return self.node_boxes_map.get(doc_node_id);
}

pub fn getDocNodeBox(self: *const Self, doc_node_id: NodeId) ?BoxItem {
    if (self.node_boxes_map.get(doc_node_id)) |index| {
        return switch (self.items.items[index]) {
            .box => |box| box,
            else => null,
        };
    }
    return null;
}
