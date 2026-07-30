//! Layout snapshot tests for the v2 pipeline. Each case builds a document
//! from nodes (via XML), runs the full pipeline, and snapshots the layout
//! tree structure (which exposes anonymous boxes), per-node geometry, and
//! the painted output. Regenerate with `zig build test -Dupdate=true`.
const std = @import("std");
const Tree = @import("../../tree/Tree.zig");
const docFromXml = @import("doc-from-xml.zig").docFromXml;
const Renderer = @import("../../renderer/v2/Renderer.zig");
const constants = @import("constants.zig");
const snapshot = @import("../../testing/snapshot.zig");

fn expectLayoutSnapshot(
    comptime loc: std.builtin.SourceLocation,
    description: []const u8,
    xml: []const u8,
    viewport: constants.AvailableSpacePoint,
) !void {
    const allocator = std.testing.allocator;
    var tree = try docFromXml(allocator, xml, .{});
    defer tree.deinit();
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, viewport);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    try w.writeAll("--- layout tree ---\n");
    try tree.layout_tree.printRoot(w);
    try w.writeAll("\n--- paint ---\n");
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    try tree.paint(&renderer, w, .simple);

    try snapshot.expectMatchSnapshot(loc, allocator, description, aw.writer.buffered(), .{});
}

const wide = constants.AvailableSpacePoint{ .x = .{ .definite = 40 }, .y = .max_content };

test "layout block flow" {
    try expectLayoutSnapshot(@src(), "nested blocks",
        \\<div style="width: 40px;">
        \\<div style="height: 2px;"></div>
        \\<div style="height: 3px; margin: 1px;"></div>
        \\</div>
    , wide);
}

test "layout flex row" {
    try expectLayoutSnapshot(@src(), "flex row",
        \\<div style="display: flex; width: 40px; height: 6px;">
        \\<div style="width: 10px;"></div>
        \\<div style="flex-grow: 1;"></div>
        \\<div style="width: 5px;"></div>
        \\</div>
    , wide);
}

test "layout flex column" {
    try expectLayoutSnapshot(@src(), "flex column",
        \\<div style="display: flex; flex-direction: column; width: 20px; height: 12px;">
        \\<div style="height: 3px;"></div>
        \\<div style="flex-grow: 1;"></div>
        \\</div>
    , wide);
}

test "layout anonymous boxes" {
    // mixed text and element children force anonymous box generation
    try expectLayoutSnapshot(@src(), "anonymous boxes",
        \\<div style="width: 40px;">before<div style="height: 2px;"></div>after</div>
    , wide);
}

test "layout text wrapping" {
    try expectLayoutSnapshot(@src(), "wrap narrow",
        \\<div style="width: 12px;">words that will wrap once the line gets long enough</div>
    , .{ .x = .{ .definite = 12 }, .y = .max_content });
}

test "layout text align center" {
    try expectLayoutSnapshot(@src(), "align center",
        \\<div style="width: 20px; text-align: center;">a bb ccc</div>
    , .{ .x = .{ .definite = 20 }, .y = .max_content });
}

test "layout whitespace collapse" {
    try expectLayoutSnapshot(@src(), "whitespace collapse",
        \\<div style="width: 30px;">a   b
        \\
        \\   c</div>
    , wide);
}

test "layout gradient background" {
    try expectLayoutSnapshot(@src(), "gradient background",
        \\<div style="width: 20px; height: 4px; background-color: linear-gradient(90deg, #e66465, #9198e5);"></div>
    , wide);
}

test "layout radial gradient background" {
    try expectLayoutSnapshot(@src(), "radial gradient",
        \\<div style="width: 20px; height: 4px; background-color: radial-gradient(circle at top left, #e66465, #9198e5);"></div>
    , wide);
}

test "layout preserved segment breaks wrap" {
    // pre-wrap must honor the newline as a forced break AND still wrap the
    // long line; regression for a mandatory break being swallowed when the
    // break token got absorbed into a preceding text group
    try expectLayoutSnapshot(@src(), "pre-wrap segment breaks",
        \\<div style="width: 12px; white-space: pre-wrap;">one
        \\two words that wrap here</div>
    , .{ .x = .{ .definite = 12 }, .y = .max_content });
}

test "layout preserved breaks nowrap" {
    try expectLayoutSnapshot(@src(), "pre segment breaks",
        \\<div style="width: 12px; white-space: pre;">one
        \\two</div>
    , .{ .x = .{ .definite = 12 }, .y = .max_content });
}

test "layout trailing segment break yields empty final line" {
    // textarea semantics: "hey\n" occupies two lines so the caret after the
    // break has a line to land on (deliberate deviation from CSS static
    // rendering, which drops the final empty line)
    try expectLayoutSnapshot(@src(), "trailing break",
        \\<div style="width: 12px; white-space: pre-wrap;">hey
        \\</div>
    , .{ .x = .{ .definite = 12 }, .y = .max_content });
}
