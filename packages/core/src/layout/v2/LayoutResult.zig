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

pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
    _ = fmt; // autofix
    _ = options; // autofix
    try writer.print("LayoutResult {{\n", .{});
    // try writer.print("  line_boxes: {any},\n", .{self.line_boxes});
    try writer.print("  size: {any},\n", .{self.size});
    try writer.print("  content_size: {any},\n", .{self.content_size});
    try writer.print("  first_baselines: {any},\n", .{self.first_baselines});
    try writer.print("  top_margin: {any},\n", .{self.top_margin});
    try writer.print("  bottom_margin: {any},\n", .{self.bottom_margin});
    try writer.print("  margins_can_collapse_through: {any},\n", .{self.margins_can_collapse_through});
    try writer.print("  resolved_margin: {any},\n", .{self.resolved_margin});
    try writer.print("  resolved_padding: {any},\n", .{self.resolved_padding});
    try writer.print("  resolved_border: {any},\n", .{self.resolved_border});
    try writer.print("  scrollbar_size: {any},\n", .{self.scrollbar_size});
    try writer.print("}}\n", .{});
}
