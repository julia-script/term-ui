const std = @import("std");
const Tree = @import("Tree.zig");
const snapshot = @import("../tests/utils/snapshot.zig");

test "style invalidation - color change" {
    const allocator = std.testing.allocator;
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a simple tree
    const parent = try tree.createNode();
    const child = try tree.createNode();
    _ = try tree.appendChild(parent, child);

    // Change color - should only mark repaint
    const Color = @import("../colors/Color.zig");
    try tree.setStyleProperty(child, .{ .color = Color.rgb(1.0, 0.0, 0.0) });

    // Print tree with invalidation flags
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "color_change_invalidation.snap", buf.items);
}

test "style invalidation - size change" {
    const allocator = std.testing.allocator;
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a simple tree
    const parent = try tree.createNode();
    const child = try tree.createNode();
    const grandchild = try tree.createNode();
    _ = try tree.appendChild(parent, child);
    _ = try tree.appendChild(child, grandchild);

    // Change size - should mark recompute on node and ancestors
    try tree.setStyleProperty(grandchild, .{ .width = .{ .length = 100 } });

    // Print tree with invalidation flags
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "size_change_invalidation.snap", buf.items);
}

test "style invalidation - display change" {
    const allocator = std.testing.allocator;
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a simple tree
    const parent = try tree.createNode();
    const child = try tree.createNode();
    const sibling = try tree.createNode();
    _ = try tree.appendChild(parent, child);
    _ = try tree.appendChild(parent, sibling);

    // Change display - should mark parent for regeneration
    try tree.setStyleProperty(child, .{ .display = .{ .inside = .flow, .outside = .@"inline" } });

    // Print tree with invalidation flags
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "display_change_invalidation.snap", buf.items);
}

test "style invalidation - DOM manipulation" {
    const allocator = std.testing.allocator;
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a simple tree
    const parent = try tree.createNode();
    const child1 = try tree.createNode();
    const child2 = try tree.createNode();
    _ = try tree.appendChild(parent, child1);

    // Add a new child - should mark parent for regeneration
    _ = try tree.appendChild(parent, child2);

    // Print tree with invalidation flags
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "dom_appendChild_invalidation.snap", buf.items);
}

test "style invalidation - text change" {
    const allocator = std.testing.allocator;
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a tree with text
    const parent = try tree.createNode();
    const text = try tree.createTextNode("Hello");
    _ = try tree.appendChild(parent, text);

    // Change text - should mark recompute
    try tree.setText(text, "Hello World!");

    // Print tree with invalidation flags
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "text_change_invalidation.snap", buf.items);
}

test "style invalidation - flex properties" {
    const allocator = std.testing.allocator;
    var tree = try Tree.init(allocator);
    defer tree.deinit();

    // Create a flexbox container with children
    const flex_container = try tree.createNode();
    const child1 = try tree.createNode();
    const child2 = try tree.createNode();
    _ = try tree.appendChild(flex_container, child1);
    _ = try tree.appendChild(flex_container, child2);

    // Set flex properties - should mark appropriate invalidation
    const s = @import("../styles/styles.zig");
    try tree.setStyleProperty(flex_container, .{ .flex_direction = s.flex_direction.FlexDirection.column });
    try tree.setStyleProperty(child1, .{ .flex_grow = 1.0 });
    try tree.setStyleProperty(child2, .{ .flex_shrink = 0.5 });

    // Print tree with invalidation flags
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "flex_properties_invalidation.snap", buf.items);
}

test "element IDs and getElementById" {
    const allocator = std.testing.allocator;
    const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;

    // Create DOM with IDs
    var tree = try docFromXml(allocator,
        \\<root id="main">
        \\  <div id="header">Header</div>
        \\  <div id="content">
        \\    <span id="title">Title</span>
        \\    <span>No ID</span>
        \\  </div>
        \\</root>
    , .{});
    defer tree.deinit();

    // Test getElementById
    const main_id = tree.getElementById("main");
    try std.testing.expect(main_id != null);
    try std.testing.expectEqual(1, main_id.?);

    const header_id = tree.getElementById("header");
    try std.testing.expect(header_id != null);
    const header_node = tree.getNode(header_id.?);
    try std.testing.expectEqualStrings("header", header_node.getAttribute("id").?);

    const title_id = tree.getElementById("title");
    try std.testing.expect(title_id != null);
    const title_node = tree.getNode(title_id.?);
    try std.testing.expectEqualStrings("title", title_node.getAttribute("id").?);

    // Test non-existent ID
    const missing = tree.getElementById("nonexistent");
    try std.testing.expect(missing == null);

    // Test updating IDs
    const header_node_mut = tree.getNode(header_id.?);
    try header_node_mut.setAttribute("id", "new-header");
    try std.testing.expect(tree.getElementById("header") == null);
    try std.testing.expect(tree.getElementById("new-header") != null);

    // Test printing with IDs
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try tree.print(buf.writer().any());

    try snapshot.expectMatchSnapshot(@src(), allocator, "element_ids.snap", buf.items);
}
