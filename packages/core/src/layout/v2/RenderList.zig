const std = @import("std");
const mod = @import("mod.zig");
const LayoutTree = @import("LayoutTree.zig");
const DocTree = @import("../../tree/Tree.zig");
const Style = @import("../../tree/Style.zig");
const styles = @import("../../styles/styles.zig");
const Color = @import("../../colors/Color.zig");
const Canvas = @import("../../renderer/v2/Canvas.zig");
pub const TextFormat = Canvas.TextFormat;

/// A flat list of render items representing the paint order of the layout tree
items: std.ArrayListUnmanaged(RenderItem) = .{},
allocator: std.mem.Allocator,

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

    pub fn fromCSSRect(css_rect: mod.CSSRect, location: mod.CSSPoint) Rect {
        return .{
            .x = location.x + css_rect.left,
            .y = location.y + css_rect.top,
            .width = css_rect.right - css_rect.left,
            .height = css_rect.bottom - css_rect.top,
        };
    }

    pub fn fromBox(box: mod.Box) Rect {
        return .{
            .x = box.location.x,
            .y = box.location.y,
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
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    for (self.items.items) |*item| {
        item.deinit(self.allocator);
    }
    self.items.deinit(self.allocator);
}

/// Clear all items but retain allocated capacity for reuse
pub fn clearRetainingCapacity(self: *Self) void {
    // Deinit existing items
    for (self.items.items) |*item| {
        item.deinit(self.allocator);
    }
    // Clear the list but keep the allocated memory
    self.items.clearRetainingCapacity();
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

    pub fn deinit(self: *RenderItem, allocator: std.mem.Allocator) void {
        _ = allocator;
        switch (self.*) {
            .line_box => |*item| item.deinit(),
            else => {}, // Other items don't allocate
        }
    }
};

pub const BoxItem = struct {
    /// Bounding box for painting and hit testing
    bounds: Rect,
    /// Content bounds (inside padding/border) for hit testing children
    content_bounds: Rect,
    /// Background color/gradient
    background: ?styles.background.Background,
    /// Border styles
    border_style: mod.RectOf(styles.border.BoxChar.Cell),
    border_color: mod.RectOf(styles.background.Background),
    /// Z-index for stacking context
    z_index: i32 = 0,
    /// Layout node ID for debugging and hit testing
    node_id: LayoutTree.LayoutNode.Id,
    /// Whether this element can receive click events
    is_clickable: bool = true,
};

pub const TextFragmentItem = struct {
    /// Bounding box for hit testing
    bounds: Rect,
    /// Text baseline position
    position: mod.CSSPoint,
    /// Reference to text in layout tree (not owned)
    text: []const u8,
    /// Text color
    color: styles.color.Color,
    /// Text formatting (bold, italic, underline, etc)
    format: TextFormat,
    /// For getting styles and hit testing
    node_id: LayoutTree.LayoutNode.Id,
    /// Z-index for stacking context
    z_index: i32 = 0,
    /// Range in the original DOM text node (for caret positioning)
    dom_range: DomRange,
    /// Whether this element can receive click events (usually false for text)
    is_clickable: bool = false,
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
    /// Indices of text fragments within this line box
    fragment_indices: []const usize,
    /// Layout node ID of the inline container
    node_id: LayoutTree.LayoutNode.Id,
    /// Allocator for fragment indices
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *LineBoxItem) void {
        self.allocator.free(self.fragment_indices);
    }
};

/// Add a render item to the list
pub fn addItem(self: *Self, item: RenderItem) !void {
    try self.items.append(self.allocator, item);
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
                for (line.fragment_indices, 0..) |idx, j| {
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
    node_id: LayoutTree.LayoutNode.Id,
    item_type: enum { box, text_fragment, selection_overlay, line_box },
};

/// Hit test filtering options
pub const HitTestOptions = struct {
    /// Include text fragments in hit testing
    include_text: bool = true,
    /// Include boxes in hit testing  
    include_boxes: bool = true,
    /// Include selection overlays in hit testing
    include_selections: bool = false,
    /// Include line boxes in hit testing
    include_line_boxes: bool = true,
    /// Only hit test elements with pointer events enabled (requires layout tree context)
    pointer_events_only: bool = false,
};

/// Perform hit testing at the given coordinates
/// Returns the topmost item that contains the point, respecting z-order and filters
pub fn hitTest(self: *const Self, point: mod.CSSPoint, options: HitTestOptions) ?HitTestResult {
    var result: ?HitTestResult = null;
    var highest_z: i32 = std.math.minInt(i32);
    
    // Iterate through all items to find hits
    for (self.items.items, 0..) |item, i| {
        switch (item) {
            .box => |box| {
                if (options.include_boxes and box.bounds.contains(point)) {
                    // Skip non-clickable boxes when filtering for pointer events
                    if (options.pointer_events_only and !box.is_clickable) continue;
                    
                    if (box.z_index >= highest_z) {
                        highest_z = box.z_index;
                        result = .{
                            .item_index = i,
                            .node_id = box.node_id,
                            .item_type = .box,
                        };
                    }
                }
            },
            .text_fragment => |text| {
                if (options.include_text and text.bounds.contains(point)) {
                    // Skip non-clickable text when filtering for pointer events
                    if (options.pointer_events_only and !text.is_clickable) continue;
                    
                    if (text.z_index >= highest_z) {
                        highest_z = text.z_index;
                        result = .{
                            .item_index = i,
                            .node_id = text.node_id,
                            .item_type = .text_fragment,
                        };
                    }
                }
            },
            .selection_overlay => |sel| {
                if (options.include_selections and sel.bounds.contains(point)) {
                    // Selection overlays typically have high z-index
                    result = .{
                        .item_index = i,
                        .node_id = 0, // Selection overlays don't have node IDs
                        .item_type = .selection_overlay,
                    };
                }
            },
            .line_box => |line| {
                if (options.include_line_boxes and line.bounds.contains(point)) {
                    if (0 >= highest_z) { // Line boxes have z-index 0
                        highest_z = 0;
                        result = .{
                            .item_index = i,
                            .node_id = line.node_id,
                            .item_type = .line_box,
                        };
                    }
                }
            },
            .push_clip, .pop_clip => {
                // These don't participate in hit testing
            },
        }
    }
    
    return result;
}

/// Get all items that contain the given point (useful for debugging)
pub fn hitTestAll(self: *const Self, allocator: std.mem.Allocator, point: mod.CSSPoint, options: HitTestOptions) !std.ArrayList(HitTestResult) {
    var results = std.ArrayList(HitTestResult).init(allocator);
    for (self.items.items, 0..) |item, i| {
        switch (item) {
            .box => |box| {
                if (options.include_boxes and box.bounds.contains(point)) {
                    try results.append(.{
                        .item_index = i,
                        .node_id = box.node_id,
                        .item_type = .box,
                    });
                }
            },
            .text_fragment => |text| {
                if (options.include_text and text.bounds.contains(point)) {
                    try results.append(.{
                        .item_index = i,
                        .node_id = text.node_id,
                        .item_type = .text_fragment,
                    });
                }
            },
            .selection_overlay => |sel| {
                if (options.include_selections and sel.bounds.contains(point)) {
                    try results.append(.{
                        .item_index = i,
                        .node_id = 0,
                        .item_type = .selection_overlay,
                    });
                }
            },
            .line_box => |line| {
                if (options.include_line_boxes and line.bounds.contains(point)) {
                    try results.append(.{
                        .item_index = i,
                        .node_id = line.node_id,
                        .item_type = .line_box,
                    });
                }
            },
            .push_clip, .pop_clip => {},
        }
    }
    return results;
}

test "RenderList hit testing" {
    var list = init(std.testing.allocator);
    defer list.deinit();

    // Add test items
    try list.addItem(.{
        .box = .{
            .bounds = .{ .x = 10, .y = 10, .width = 20, .height = 15 },
            .content_bounds = .{ .x = 11, .y = 11, .width = 18, .height = 13 },
            .background = null,
            .border_style = .{ .top = .{}, .right = .{}, .bottom = .{}, .left = .{} },
            .border_color = .{ .top = .{ .solid = Color.tw.gray_500 }, .right = .{ .solid = Color.tw.gray_500 }, .bottom = .{ .solid = Color.tw.gray_500 }, .left = .{ .solid = Color.tw.gray_500 } },
            .z_index = 1,
            .node_id = 1,
        },
    });
    
    try list.addItem(.{
        .text_fragment = .{
            .bounds = .{ .x = 5, .y = 5, .width = 10, .height = 5 },
            .position = .{ .x = 5, .y = 8 },
            .text = "Hello",
            .color = Color.tw.blue_500,
            .format = .{},
            .node_id = 2,
            .z_index = 2,
            .dom_range = .{ .start = 0, .end = 5 },
        },
    });

    // Test hit testing with different options
    const options_all = HitTestOptions{ .include_text = true, .include_boxes = true };
    const options_boxes_only = HitTestOptions{ .include_text = false, .include_boxes = true };

    // Hit the text (higher z-index, should win)
    const hit1 = list.hitTest(.{ .x = 8, .y = 7 }, options_all);
    try std.testing.expect(hit1 != null);
    try std.testing.expectEqual(@as(usize, 2), hit1.?.node_id);
    try std.testing.expectEqual(@as(@TypeOf(hit1.?.item_type), .text_fragment), hit1.?.item_type);

    // Hit the box only
    const hit2 = list.hitTest(.{ .x = 25, .y = 20 }, options_all);
    try std.testing.expect(hit2 != null);
    try std.testing.expectEqual(@as(usize, 1), hit2.?.node_id);
    try std.testing.expectEqual(@as(@TypeOf(hit2.?.item_type), .box), hit2.?.item_type);

    // Hit text area but with text filtering disabled
    const hit3 = list.hitTest(.{ .x = 8, .y = 7 }, options_boxes_only);
    try std.testing.expect(hit3 == null); // Should miss because text is filtered out

    // Hit outside any item
    const hit4 = list.hitTest(.{ .x = 100, .y = 100 }, options_all);
    try std.testing.expect(hit4 == null);

    // Test hitTestAll
    var all_hits = try list.hitTestAll(std.testing.allocator, .{ .x = 12, .y = 12 }, options_all);
    defer all_hits.deinit();
    try std.testing.expectEqual(@as(usize, 1), all_hits.items.len); // Only the box should be hit
    try std.testing.expectEqual(@as(usize, 1), all_hits.items[0].node_id);
}

test "RenderList" {
    var list = init(std.testing.allocator);
    defer list.deinit();

    // Add some test items
    try list.addItem(.{
        .box = .{
            .bounds = .{ .x = 0, .y = 0, .width = 20, .height = 10 },
            .content_bounds = .{ .x = 1, .y = 1, .width = 18, .height = 8 },
            .background = .{ .solid = Color.tw.blue_500 },
            .border_style = .{ .top = .{}, .right = .{}, .bottom = .{}, .left = .{} },
            .border_color = .{
                .top = .{ .solid = Color.tw.white },
                .right = .{ .solid = Color.tw.white },
                .bottom = .{ .solid = Color.tw.white },
                .left = .{ .solid = Color.tw.white },
            },
            .z_index = 0,
            .node_id = 1,
        },
    });

    try list.addItem(.{
        .text_fragment = .{
            .bounds = .{ .x = 5, .y = 5, .width = 5, .height = 1 },
            .position = .{ .x = 5, .y = 5 },
            .text = "Hello", // Just a reference, not owned
            .color = Color.tw.white,
            .format = .{},
            .node_id = 2,
            .z_index = 1,
            .dom_range = .{ .start = 0, .end = 5 },
        },
    });

    // Test sorting
    list.sortByPaintOrder();

    // Verify order
    try std.testing.expectEqual(@as(usize, 2), list.items.items.len);
    try std.testing.expectEqual(@as(i32, 0), getZIndex(list.items.items[0]));
    try std.testing.expectEqual(@as(i32, 1), getZIndex(list.items.items[1]));
}
