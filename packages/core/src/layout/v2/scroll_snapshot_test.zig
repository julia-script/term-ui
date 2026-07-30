//! Scroll & overflow snapshots for the v2 pipeline: clipping (hidden/scroll/
//! visible), scrolled content at offsets, nested containers, partial line
//! clipping. Regenerate with `zig build test -Dupdate=true`.
const std = @import("std");
const Tree = @import("../../tree/Tree.zig");
const Node = @import("../../tree/Node.zig");
const docFromXml = @import("doc-from-xml.zig").docFromXml;
const Renderer = @import("../../renderer/v2/Renderer.zig");
const constants = @import("constants.zig");
const snapshot = @import("../../testing/snapshot.zig");

const viewport = constants.AvailableSpacePoint{ .x = .{ .definite = 24 }, .y = .{ .definite = 10 } };

const ScrollSet = struct { id: []const u8, top: f32 = 0, left: f32 = 0 };

fn expectScrollSnapshot(
    comptime loc: std.builtin.SourceLocation,
    description: []const u8,
    xml: []const u8,
    scrolls: []const ScrollSet,
) !void {
    const allocator = std.testing.allocator;
    var tree = try docFromXml(allocator, xml, .{});
    defer tree.deinit();
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, viewport);

    // paint once so scroll maxima (from laid-out geometry) are available
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    var warmup: std.Io.Writer.Allocating = .init(allocator);
    defer warmup.deinit();
    try tree.paint(&renderer, &warmup.writer, .simple);

    for (scrolls) |s| {
        const node_id = tree.getElementById(s.id) orelse return error.NoSuchElement;
        const node = tree.getNode(node_id);
        node.setScrollTop(&tree, s.top);
        node.setScrollLeft(&tree, s.left);
        node.requestRepaint();
    }
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, viewport);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    var renderer2 = try Renderer.init(allocator);
    defer renderer2.deinit();
    try w.writeAll("--- paint ---\n");
    try tree.paint(&renderer2, w, .simple);

    if (scrolls.len > 0) {
        try w.writeAll("--- scroll state ---\n");
        for (scrolls) |s| {
            const node_id = tree.getElementById(s.id) orelse return error.NoSuchElement;
            const node = tree.getNode(node_id);
            try w.print("{s}: top={d:.1}/{d:.1} left={d:.1}/{d:.1}\n", .{
                s.id,
                node.getScrollTop(),
                node.getScrollTopMax(&tree),
                node.getScrollLeft(),
                node.getScrollLeftMax(&tree),
            });
        }
    }

    try snapshot.expectMatchSnapshot(loc, allocator, description, aw.writer.buffered(), .{});
}

test "overflow hidden clips tall content" {
    try expectScrollSnapshot(@src(), "hidden clips",
        \\<div style="width: 20px; height: 4px; overflow: hidden; border-style: solid;">
        \\<div>line one</div>
        \\<div>line two</div>
        \\<div>line three</div>
        \\<div>line four</div>
        \\<div>line five</div>
        \\</div>
    , &.{});
}

test "overflow visible does not clip" {
    // fixed-height wrapper so the canvas is taller than the visible div
    try expectScrollSnapshot(@src(), "visible overflows",
        \\<div style="width: 22px; height: 8px;">
        \\<div style="width: 20px; height: 2px; overflow: visible;">
        \\<div>line one</div>
        \\<div>line two</div>
        \\<div>line three</div>
        \\</div>
        \\<div>after the box</div>
        \\</div>
    , &.{});
}

test "scroll container shifts content by offset" {
    try expectScrollSnapshot(@src(), "scrolled by 2",
        \\<div id="outer" style="width: 20px; height: 4px; overflow: scroll;">
        \\<div>line one</div>
        \\<div>line two</div>
        \\<div>line three</div>
        \\<div>line four</div>
        \\<div>line five</div>
        \\<div>line six</div>
        \\</div>
    , &.{.{ .id = "outer", .top = 2 }});
}

test "scroll clamps to content extent" {
    try expectScrollSnapshot(@src(), "clamped",
        \\<div id="outer" style="width: 20px; height: 4px; overflow: scroll;">
        \\<div>line one</div>
        \\<div>line two</div>
        \\<div>line three</div>
        \\<div>line four</div>
        \\<div>line five</div>
        \\<div>line six</div>
        \\</div>
    , &.{.{ .id = "outer", .top = 99 }});
}

test "nested scroll containers clip to intersection" {
    try expectScrollSnapshot(@src(), "nested",
        \\<div style="width: 22px; height: 8px; overflow: hidden; border-style: solid;">
        \\<div>above above above</div>
        \\<div id="inner" style="width: 16px; height: 3px; overflow: scroll;">
        \\<div>inner one</div>
        \\<div>inner two</div>
        \\<div>inner three</div>
        \\<div>inner four</div>
        \\</div>
        \\<div>below below below</div>
        \\</div>
    , &.{.{ .id = "inner", .top = 1 }});
}

test "wrapped text partial line clipping" {
    try expectScrollSnapshot(@src(), "partial lines",
        \\<div id="outer" style="width: 10px; height: 3px; overflow: scroll;">
        \\<div>words that wrap across several lines in here</div>
        \\</div>
    , &.{.{ .id = "outer", .top = 1 }});
}
