const std = @import("std");
const root = @import("root");
const layout_mod = @import("../layout/v2/mod.zig");
const Tree = @import("../tree/Tree.zig");
const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;
const assertDocumentSnapshotFromXml = @import("utils/assert-document-snapshot.zig").assertDocumentSnapshotFromXml;
const Renderer = @import("../renderer/v2/Renderer.zig");

fn computeDocFromXml(xml: []const u8, available_space: layout_mod.constants.AvailableSpacePoint) !Tree {
    var tree = try docFromXml(
        std.testing.allocator,
        xml,
        .{},
    );
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(std.testing.allocator, available_space);
    try tree.buildRenderList();
    return tree;
}
test "cache" {
    const xml =
        \\<div style="color: white;background-color: black;overflow: scroll;">
        \\  <div id="element" style="width: 30;height: 10;border-style: double;color: white;background-color: cyan;">
        // \\ When the sunlight strikes raindrops in the air, they act like a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon. There is, according to legend, a boiling pot of gold at one end. People look but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow.
        \\</div>
        \\</div>
        \\
    ;
    var tree = try docFromXml(
        std.testing.allocator,
        xml,
        .{},
    );

    defer tree.deinit();
    const element_id = tree.getElementById("element") orelse return error.ElementNotFound;

    // var element = tree.getNode(element_id);
    // var text_node = (element.getFirstChild(&tree)) orelse return error.NodeNotFound;
    const writer = std.io.getStdErr().writer().any();

    var renderer = try Renderer.init(std.testing.allocator);
    defer renderer.deinit();

    // try tree.computePipelines(.{
    //     .x = .{ .definite = 30 },
    //     .y = .{ .definite = 20 },
    // });

    // try tree.print(writer);
    // try tree.paint(&renderer, writer, .simple);

    // std.debug.print("node: {any}\n", .{element_id});
    // try text_node.setText(&tree, "Hello ");
    // try tree.print(writer);
    const stderr = std.io.getStdErr().writer().any();
    try stderr.writeAll("initial\n");
    try tree.print(stderr);
    tree.propagateNodeRecomputeStatus();
    try tree.print(stderr);

    try stderr.writeAll("--------------------------------\n");
    for (0..3) |_| {
        const new_child = try tree.createTextNode("X");

        _ = try tree.appendChild(element_id, new_child);
        tree.propagateNodeRecomputeStatus();
        // std.debug.print("{}", .{tree.print})
        try stderr.writeAll("before\n");
        try tree.print(stderr);
        try tree.computePipelines(.{
            .x = .{ .definite = 30 },
            .y = .max_content,
        });
        try tree.paint(&renderer, writer, .simple);
        try stderr.writeAll("after\n");
        try tree.print(stderr);
        try stderr.writeAll("--------------------------------\n");
    }
    // for (tree.render_list.items.items, 0..) |item, i| {
    //     std.debug.print("{d}: {any}\n", .{ i, item });
    // }

    // for (0..20) |_| {
    //     element.setScrollTop(&tree, element.getScrollTop() + 1);

    //     try tree.computePipelines(.{
    //         .x = .{ .definite = 30 },
    //         .y = .max_content,
    //     });
    //     // try tree.buildRenderList();
    //     try tree.paint(&renderer, writer, .simple);
    //     // try tree.buildRenderList();
    //     // for (tree.render_list.items.items, 0..) |item, i| {
    //     //     std.debug.print("{d}: {any}\n", .{ i, item });
    //     // }
    //     std.debug.print("scroll height: {d}\n", .{element.getScrollHeight(&tree)});
    //     std.debug.print("scroll top: {d}\n", .{element.getScrollTop()});
    //     std.debug.print("scroll top max: {d}\n", .{element.getScrollTopMax(&tree)});
    //     std.debug.print("client height: {d}\n", .{element.getClientHeight(&tree)});
    //     // // nothing should have changed because client height fits all content
    //     // try std.testing.expectEqual(0, element.getScrollTop());

    //     // try std.testing.expectEqual(2, element.getClientHeight(&tree));
    //     // try std.testing.expectEqual(2, element.getScrollHeight(&tree));
    //     // try std.testing.expectEqual(0, element.getScrollTopMax(&tree));
    // }

    // {
    //     var tree = try computeDocFromXml(
    //         \\<div id="scrollable" style="height: 10;overflow: scroll;border-style: solid;color: white;background-color: black;" scroll-top="3">
    //         \\  <p>Hello world</p>
    //         \\</div>
    //         \\
    //     ,
    //         .{
    //             .x = .max_content,
    //             .y = .max_content,
    //         },
    //     );

    //     defer tree.deinit();
    //     const element_id = tree.getElementById("scrollable") orelse return error.ElementNotFound;
    //     var element = tree.getNode(element_id);

    //     try tree.buildRenderList();
    //     try std.testing.expectEqual(8, element.getClientHeight(&tree));
    //     try std.testing.expectEqual(8, element.getScrollHeight(&tree));
    //     try std.testing.expectEqual(0, element.getScrollTopMax(&tree));
    // }
}
