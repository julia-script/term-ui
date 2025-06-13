const mod = @import("mod.zig");
const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

line_boxes: ?mod.LineBox.LineBoxList = null,
size: mod.CSSPoint = .{ .x = 0, .y = 0 },
content_size: mod.CSSPoint = .{ .x = 0, .y = 0 },
first_baselines: mod.CSSMaybePoint = .{ .x = null, .y = null },
top_margin: mod.CollapsibleMarginSet = .{ .positive = 0, .negative = 0 },
bottom_margin: mod.CollapsibleMarginSet = .{ .positive = 0, .negative = 0 },
margins_can_collapse_through: bool = false,

// Box model fields for preserving computed layout data
resolved_margin: mod.CSSRect = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
resolved_padding: mod.CSSRect = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
resolved_border: mod.CSSRect = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
scrollbar_size: mod.CSSPoint = .{ .x = 0, .y = 0 },
const Self = @This();

pub fn deinit(self: *Self) void {
    if (self.line_boxes) |*line_boxes| {
        line_boxes.deinit();
    }
}
pub fn dupe(self: @This(), allocator: std.mem.Allocator) !Self {
    return .{
        .line_boxes = if (self.line_boxes) |*line_boxes| try line_boxes.dupe(allocator) else null,
        .size = self.size,
        .content_size = self.content_size,
        .first_baselines = self.first_baselines,
        .top_margin = self.top_margin,
        .bottom_margin = self.bottom_margin,
        .margins_can_collapse_through = self.margins_can_collapse_through,
        .resolved_margin = self.resolved_margin,
        .resolved_padding = self.resolved_padding,
        .resolved_border = self.resolved_border,
        .scrollbar_size = self.scrollbar_size,
    };
}
