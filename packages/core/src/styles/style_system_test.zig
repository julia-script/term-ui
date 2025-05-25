const std = @import("std");
const Style = @import("../tree/Style.zig");
const Tree = @import("../tree/Tree.zig");
const Node = @import("../tree/Node.zig");
const styles = @import("./styles.zig");
const ComputedStyleCache = @import("./ComputedStyle.zig").ComputedStyleCache;

const testing = std.testing;
const allocator = testing.allocator;

test "basic_style_inheritance" {
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a root node
    const root_id = try tree.createNode();

    // Create child node
    const child_id = try tree.createNode();
    try tree.appendChild(root_id, child_id);

    // Create grandchild node
    const grandchild_id = try tree.createNode();
    try tree.appendChild(child_id, grandchild_id);

    // Set root node styles
    var root_style = tree.getStyle(root_id);
    root_style.foreground_color = styles.color.Color{ .r = 1, .g = 0, .b = 0, .a = 1 }; // Red
    root_style.text_align = .center;

    // Set child styles (with text-align explicitly set)
    var child_style = tree.getStyle(child_id);
    child_style.text_align = .right;

    // Create computed style cache
    var style_cache = try ComputedStyleCache.init(allocator);
    defer style_cache.deinit();

    // Test computed styles
    {
        const root_computed = style_cache.getComputedStyle(&tree, root_id);
        try testing.expectEqual(root_computed.text_align, .center);

        const child_computed = style_cache.getComputedStyle(&tree, child_id);
        try testing.expectEqual(child_computed.text_align, .right);
        try testing.expect(child_computed.foreground_color != null);
        if (child_computed.foreground_color) |color| {
            try testing.expectEqual(color.r, 1);
            try testing.expectEqual(color.g, 0);
            try testing.expectEqual(color.b, 0);
        }

        const grandchild_computed = style_cache.getComputedStyle(&tree, grandchild_id);
        try testing.expectEqual(grandchild_computed.text_align, .right);
        try testing.expect(grandchild_computed.foreground_color != null);
    }

    // Change a parent style and test invalidation
    root_style.foreground_color = styles.color.Color{ .r = 0, .g = 1, .b = 0, .a = 1 }; // Green
    style_cache.invalidateTree(&tree, root_id);

    {
        const root_computed = style_cache.getComputedStyle(&tree, root_id);
        try testing.expect(root_computed.foreground_color != null);
        if (root_computed.foreground_color) |color| {
            try testing.expectEqual(color.r, 0);
            try testing.expectEqual(color.g, 1);
            try testing.expectEqual(color.b, 0);
        }

        const child_computed = style_cache.getComputedStyle(&tree, child_id);
        try testing.expect(child_computed.foreground_color != null);
        if (child_computed.foreground_color) |color| {
            try testing.expectEqual(color.r, 0);
            try testing.expectEqual(color.g, 1);
            try testing.expectEqual(color.b, 0);
        }
    }
}
