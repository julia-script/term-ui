const mod = @import("mod.zig");
const std = @import("std");

size: mod.CSSPoint = .{ .x = 0, .y = 0 },
content_size: mod.CSSPoint = .{ .x = 0, .y = 0 },
scrollbar_size: mod.CSSPoint = .{ .x = 0, .y = 0 },
location: mod.CSSPoint = .{ .x = 0, .y = 0 },
padding: mod.CSSRect = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
border: mod.CSSRect = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
margin: mod.CSSRect = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },

const Self = @This();

pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try writer.print("[loc: {any} size: {any} content: {any}]", .{ self.location, self.size, self.content_size });
}
