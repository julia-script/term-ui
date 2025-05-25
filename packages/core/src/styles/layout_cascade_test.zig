const std = @import("std");
const Tree = @import("../tree/Tree.zig");
const Style = @import("../tree/Style.zig");
const styles = @import("styles.zig");
const Point = @import("../layout/point.zig").Point;
const AvailableSpace = @import("../layout/compute/compute_constants.zig").AvailableSpace;
const computeLayout = @import("../layout/compute/compute_layout.zig").computeLayout;
test "cascaded styles affect layout and rendering" {
    const allocator = std.testing.allocator;

    // Create a tree with a parent and child
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create parent node
    const parent_id = try tree.createNode();

    // Create child node
    const child_id = try tree.createNode();
    try tree.appendChild(parent_id, child_id);

    // Create grandchild text node
    const text_id = try tree.createTextNode("Hello World");
    try tree.appendChild(child_id, text_id);

    // Set styles: parent sets text color to red
    {
        var parent_style = tree.getStyle(parent_id);
        parent_style.foreground_color = styles.color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 }; // Red
        parent_style.text_align = .center;
    }

    // Compute layout
    try computeLayout(tree, allocator, .{
        .x = .{ .definite = 100 },
        .y = .{ .definite = 100 },
    });

    // Test that computed styles were properly calculated
    const child_computed = (try tree.getComputedStyle(child_id));
    try std.testing.expect(child_computed.foreground_color != null);
    if (child_computed.foreground_color) |color| {
        // Child should inherit the red color from parent
        try std.testing.expectEqual(color.r, 1);
        try std.testing.expectEqual(color.g, 0);
        try std.testing.expectEqual(color.b, 0);
    }

    // Test that text node also inherits
    const text_computed = (try tree.getComputedStyle(text_id));
    try std.testing.expectEqual(text_computed.text_align, .center);
    try std.testing.expect(text_computed.foreground_color != null);
}
