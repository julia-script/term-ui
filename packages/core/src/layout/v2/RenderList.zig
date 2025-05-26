const std = @import("std");
const mod = @import("mod.zig");
const LayoutTree = @import("LayoutTree.zig");
const DocTree = @import("../../tree/Tree.zig");
const Style = @import("../../tree/Style.zig");
const styles = @import("../../styles/styles.zig");
const Color = @import("../../colors/Color.zig");

/// A flat list of render items representing the paint order of the layout tree
items: std.ArrayListUnmanaged(RenderItem) = .{},
allocator: std.mem.Allocator,

const Self = @This();

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
    
    pub fn contains(self: Rect, x: f32, y: f32) bool {
        return x >= self.x and x < self.x + self.width and
               y >= self.y and y < self.y + self.height;
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
    
    pub fn deinit(self: *RenderItem, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // No allocations to free since we reference layout tree data
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
};

pub const TextFragmentItem = struct {
    /// Bounding box for hit testing
    bounds: Rect,
    /// Text baseline position
    position: mod.CSSPoint,
    /// Reference to text in layout tree (not owned)
    text: []const u8,
    /// For getting styles and hit testing
    node_id: LayoutTree.LayoutNode.Id,
    /// Z-index for stacking context
    z_index: i32 = 0,
};

pub const ClipItem = struct {
    /// Clipping rectangle
    rect: Rect,
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
    };
}

/// Debug print the render list
pub fn print(self: *Self, writer: std.io.AnyWriter) !void {
    try writer.print("RenderList ({d} items):\n", .{self.items.items.len});
    for (self.items.items, 0..) |item, i| {
        try writer.print("  [{d}] ", .{i});
        switch (item) {
            .box => |box| {
                try writer.print("Box #{d} bounds=({:.1},{:.1} {:.1}x{:.1}) z={d}", .{
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
                try writer.print("TextFragment #{d} bounds=({:.1},{:.1} {:.1}x{:.1}) z={d} text=\"{s}\"", .{
                    text.node_id,
                    text.bounds.x,
                    text.bounds.y,
                    text.bounds.width,
                    text.bounds.height,
                    text.z_index,
                    text.text,
                });
            },
            .push_clip => |clip| {
                try writer.print("PushClip rect=({:.1},{:.1} {:.1}x{:.1})", .{
                    clip.rect.x,
                    clip.rect.y,
                    clip.rect.width,
                    clip.rect.height,
                });
            },
            .pop_clip => try writer.print("PopClip", .{}),
        }
        try writer.print("\n", .{});
    }
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
            .node_id = 2,
            .z_index = 1,
        },
    });
    
    // Test sorting
    list.sortByPaintOrder();
    
    // Verify order
    try std.testing.expectEqual(@as(usize, 2), list.items.items.len);
    try std.testing.expectEqual(@as(i32, 0), getZIndex(list.items.items[0]));
    try std.testing.expectEqual(@as(i32, 1), getZIndex(list.items.items[1]));
}