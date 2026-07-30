//! Scenario tests for `Tree.caretPositionFromPoint` per the caret-positioning
//! spec: grapheme-half resolution, past-end-of-line clicks, and the
//! WebKit-style nearest-position fallback for clicks on empty space.
const std = @import("std");
const Tree = @import("Tree.zig");
const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;
const Renderer = @import("../renderer/v2/Renderer.zig");
const constants = @import("../layout/v2/constants.zig");
const BoundaryPoint = @import("BoundaryPoint.zig");

fn setup(allocator: std.mem.Allocator, xml: []const u8, width: f32) !Tree {
    var tree = try docFromXml(allocator, xml, .{});
    errdefer tree.deinit();
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{ .x = .{ .definite = width }, .y = .max_content });
    // caretPositionFromPoint reads the render list, which paint builds
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    var discard: std.Io.Writer.Allocating = .init(allocator);
    defer discard.deinit();
    try tree.paint(&renderer, &discard.writer, .simple);
    return tree;
}

fn expectCaret(tree: *Tree, x: f32, y: f32, node_id: usize, offset: u32) !void {
    const bp = tree.caretPositionFromPoint(.{ .x = x, .y = y }) orelse {
        std.debug.print("caretPositionFromPoint({d},{d}) returned null, expected ({d},{d})\n", .{ x, y, node_id, offset });
        return error.TestExpectedEqual;
    };
    if (bp.node_id != node_id or bp.offset != offset) {
        std.debug.print("caretPositionFromPoint({d},{d}) = ({d},{d}), expected ({d},{d})\n", .{ x, y, bp.node_id, bp.offset, node_id, offset });
        return error.TestExpectedEqual;
    }
}

test "caret from point: grapheme halves" {
    const allocator = std.testing.allocator;
    var tree = try setup(allocator,
        \\<div style="width: 20px;">hello world</div>
    , 20);
    defer tree.deinit();

    // 'h' occupies x in [0,1): left half -> before it, right half -> after it
    try expectCaret(&tree, 0.2, 0.5, 2, 0);
    try expectCaret(&tree, 0.8, 0.5, 2, 1);
    // 'w' of "world" occupies x in [6,7)
    try expectCaret(&tree, 6.2, 0.5, 2, 6);
    try expectCaret(&tree, 6.8, 0.5, 2, 7);
}

test "caret from point: past end of line resolves to that line's end" {
    const allocator = std.testing.allocator;
    // width 12 wraps: line 0 = "words that", line 1 = "wrap here"
    var tree = try setup(allocator,
        \\<div style="width: 12px;">words that wrap here</div>
    , 12);
    defer tree.deinit();

    // x beyond "words that" (10 cols) on line 0: caret at end of line 0,
    // not at the start of line 1
    try expectCaret(&tree, 11.5, 0.5, 2, 10);
}

test "caret from point: empty space falls back to nearest text" {
    const allocator = std.testing.allocator;
    // a block taller than its single line of text: clicking the empty area
    // below the text must still produce a caret near the text, not null
    var tree = try setup(allocator,
        \\<div style="width: 20px; height: 10px;">hi</div>
    , 20);
    defer tree.deinit();

    const bp = tree.caretPositionFromPoint(.{ .x = 1, .y = 7 });
    try std.testing.expect(bp != null);
    try std.testing.expectEqual(@as(usize, 2), bp.?.node_id);
}

test "caret from point: geometry round-trip" {
    const allocator = std.testing.allocator;
    var tree = try setup(allocator,
        \\<div style="width: 20px;">hello world</div>
    , 20);
    defer tree.deinit();

    const bp = tree.caretPositionFromPoint(.{ .x = 6.2, .y = 0.5 }).?;
    const pos = tree.getBoundaryPointPosition(bp.node_id, bp.offset);
    try std.testing.expect(@abs(pos.x - 6.0) <= 1.0);
    try std.testing.expect(pos.y >= 0 and pos.y < 1.5);
}
