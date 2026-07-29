const std = @import("std");
const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;
const assertDocumentSnapshotFromXml = @import("utils/assert-document-snapshot.zig").assertDocumentSnapshotFromXml;
const Renderer = @import("../renderer/v2/Renderer.zig");

test "rounded" {
    var tree = try docFromXml(std.testing.allocator,
        \\<div style="height:100%;width:100%; display: flex; overflow-y: scroll;background-color: linear-gradient(to right, red, blue);">
        \\<div id="box" style="border-style: rounded;color: white; height: 10; margin-top: -3">
        // \\  Hello, world!
        // \\  The quick brown fox jumps over the lazy dog.
        \\ When the sunlight strikes raindrops in the air, they act like a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon. There is, according to legend, a boiling pot of gold at one end. People look but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow
        \\</div>
        // \\ <span>Hi</span>
        \\</div>
    , .{});
    defer tree.deinit();
    try tree.computePipelines(
        .{ .x = .{ .definite = 40 }, .y = .{ .definite = 5 } },
    );
    const box_id = tree.getElementById("box") orelse return error.ElementNotFound;
    var box = tree.getNode(box_id);
    box.styles.background_color = .{
        .linear_gradient = .{
            .angle = 0,
            .color_stops = .{},
        },
    };
    try box.styles.background_color.?.linear_gradient.color_stops.append(.{
        .color = .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        .hint = null,
        .position = null,
    });
    try box.styles.background_color.?.linear_gradient.color_stops.append(.{
        .color = .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        .hint = null,
        .position = null,
    });

    var renderer = try Renderer.init(
        std.testing.allocator,
    );
    defer renderer.deinit();
    const stderr = std.io.getStdErr().writer().any();
    try tree.paint(&renderer, stderr, .simple);
}
