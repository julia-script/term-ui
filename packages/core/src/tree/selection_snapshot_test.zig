//! Selection behavior snapshots: documents carry an initial selection via
//! `$S[`/`$S]` markers, `Selection.modify` drives movement, and the snapshot
//! records the DOM with `[`/`]` range markers (`|` for a collapsed caret)
//! plus the selection-highlighted paint. Regenerate with
//! `zig build test -Dupdate=true`.
//!
const std = @import("std");
const Tree = @import("Tree.zig");
const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;
const Renderer = @import("../renderer/v2/Renderer.zig");
const constants = @import("../layout/v2/constants.zig");
const snapshot = @import("../testing/snapshot.zig");
const Selection = @import("Selection.zig");

const viewport = constants.AvailableSpacePoint{ .x = .{ .definite = 20 }, .y = .max_content };

const Step = union(enum) {
    modify: struct {
        alter: Selection.Alteration,
        direction: Selection.ExtendDirection,
        granularity: Selection.ExtendGranularity,
    },
    collapse_to_start,
    collapse_to_end,
};

fn ext(direction: Selection.ExtendDirection, granularity: Selection.ExtendGranularity) Step {
    return .{ .modify = .{ .alter = .extend, .direction = direction, .granularity = granularity } };
}

fn mv(direction: Selection.ExtendDirection, granularity: Selection.ExtendGranularity) Step {
    return .{ .modify = .{ .alter = .move, .direction = direction, .granularity = granularity } };
}

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
            .modify => |e| {
                try selection.modify(&tree, e.alter, e.direction, e.granularity, null);
                try w.print("--- after step {d}: {s} {s} {s} ---\n", .{
                    i, @tagName(e.alter), @tagName(e.direction), @tagName(e.granularity),
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
        ext(.forward, .character),
        ext(.backward, .character),
        .collapse_to_end,
        ext(.forward, .character),
    });
}

test "selection extend to line boundary" {
    try expectSelectionSnapshot(@src(), "lineboundary",
        \\<div style="width: 20px;">alpha bra$S[$S]vo charlie delta</div>
    , &.{
        ext(.forward, .lineboundary),
        .collapse_to_start,
        ext(.backward, .lineboundary),
    });
}

test "selection across wrapped lines" {
    try expectSelectionSnapshot(@src(), "wrap selection",
        \\<div style="width: 12px;">words $S[that will wrap$S] across lines in this box</div>
    , &.{
        ext(.forward, .line),
        .collapse_to_end,
        ext(.backward, .line),
    });
}

test "selection word granularity" {
    try expectSelectionSnapshot(@src(), "word moves",
        \\<div style="width: 20px;">alpha bra$S[$S]vo charlie delta</div>
    , &.{
        ext(.forward, .word),
        ext(.forward, .word),
        ext(.backward, .word),
        mv(.backward, .word),
        mv(.backward, .word),
    });
}

test "selection move collapses to edge" {
    try expectSelectionSnapshot(@src(), "move edge collapse",
        \\<div style="width: 20px;">hel$S[lo wor$S]ld here</div>
    , &.{
        mv(.forward, .character),
        mv(.forward, .character),
        mv(.backward, .word),
    });
}

test "selection move by line keeps caret collapsed" {
    try expectSelectionSnapshot(@src(), "move by line",
        \\<div style="width: 12px;">words $S[$S]that will wrap across lines here</div>
    , &.{
        mv(.forward, .line),
        mv(.forward, .line),
        mv(.backward, .line),
    });
}
