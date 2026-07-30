//! Selection behavior snapshots: documents carry an initial selection via
//! `$S[`/`$S]` markers, `Selection.modify` drives movement, and the snapshot
//! records the DOM with `[`/`]` range markers (`|` for a collapsed caret)
//! plus the selection-highlighted paint. Regenerate with
//! `zig build test -Dupdate=true`.
//!
//! Note: `modify` currently only extends (there is no move/alter parameter)
//! and word granularity is unimplemented — both tracked in the
//! stabilize-selection-input change.
const std = @import("std");
const Tree = @import("Tree.zig");
const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;
const Renderer = @import("../renderer/v2/Renderer.zig");
const constants = @import("../layout/v2/constants.zig");
const snapshot = @import("../testing/snapshot.zig");
const Selection = @import("Selection.zig");

const viewport = constants.AvailableSpacePoint{ .x = .{ .definite = 20 }, .y = .max_content };

const Step = union(enum) {
    extend: struct {
        direction: Selection.ExtendDirection,
        granularity: Selection.ExtendGranularity,
    },
    collapse_to_start,
    collapse_to_end,
};

fn expectSelectionSnapshot(
    comptime loc: std.builtin.SourceLocation,
    description: []const u8,
    xml: []const u8,
    steps: []const Step,
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

    const selection = tree.getFirstSelection() orelse return error.NoSelection;

    try w.writeAll("--- initial ---\n");
    try dumpSelection(&tree, selection, w, allocator);

    for (steps, 0..) |step, i| {
        switch (step) {
            .extend => |e| {
                try selection.modify(&tree, e.direction, e.granularity, null);
                try w.print("--- after step {d}: extend {s} {s} ---\n", .{
                    i, @tagName(e.direction), @tagName(e.granularity),
                });
            },
            .collapse_to_start => {
                try selection.collapseToStart(&tree);
                try w.print("--- after step {d}: collapseToStart ---\n", .{i});
            },
            .collapse_to_end => {
                try selection.collapseToEnd(&tree);
                try w.print("--- after step {d}: collapseToEnd ---\n", .{i});
            },
        }
        try tree.computeStyles();
        try tree.buildLayoutTree();
        try tree.computeLayout(allocator, viewport);
        try dumpSelection(&tree, selection, w, allocator);
    }

    try snapshot.expectMatchSnapshot(loc, allocator, description, aw.writer.buffered(), .{});
}

fn dumpSelection(tree: *Tree, selection: *Selection, w: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    const range = selection.getRange(tree);
    try range.formatTree(tree, 1, w, .{
        .collapsed_caret = "|",
        .range_open = "[",
        .range_close = "]",
    });
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    try tree.paint(&renderer, w, .simple);
}

test "selection extend character" {
    try expectSelectionSnapshot(@src(), "char extends",
        \\<div style="width: 20px;">hel$S[lo wor$S]ld here</div>
    , &.{
        .{ .extend = .{ .direction = .forward, .granularity = .character } },
        .{ .extend = .{ .direction = .backward, .granularity = .character } },
        .collapse_to_end,
        .{ .extend = .{ .direction = .forward, .granularity = .character } },
    });
}

test "selection extend to line boundary" {
    try expectSelectionSnapshot(@src(), "lineboundary",
        \\<div style="width: 20px;">alpha bra$S[$S]vo charlie delta</div>
    , &.{
        .{ .extend = .{ .direction = .forward, .granularity = .lineboundary } },
        .collapse_to_start,
        .{ .extend = .{ .direction = .backward, .granularity = .lineboundary } },
    });
}

test "selection across wrapped lines" {
    try expectSelectionSnapshot(@src(), "wrap selection",
        \\<div style="width: 12px;">words $S[that will wrap$S] across lines in this box</div>
    , &.{
        .{ .extend = .{ .direction = .forward, .granularity = .line } },
        .collapse_to_end,
        .{ .extend = .{ .direction = .backward, .granularity = .line } },
    });
}
