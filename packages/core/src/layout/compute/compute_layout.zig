const std = @import("std");
const Tree = @import("../../tree/Tree.zig");
const Style = @import("../../tree/Style.zig");
const AvailableSpace = @import("compute_constants.zig").AvailableSpace;
const Point = @import("../point.zig").Point;
const computeRootLayout = @import("compute_root_layout.zig").computeRootLayout;
const roundLayout = @import("round_layout.zig").roundLayout;

pub fn computeLayout(self: *Tree, allocator: std.mem.Allocator, available_space: Point(AvailableSpace)) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    // var root_style: Style = .{};
    try self.computed_style_cache.computeRootStyle(self);
    try computeRootLayout(arena.allocator(), self, available_space);
    roundLayout(0, self, 0);
}
