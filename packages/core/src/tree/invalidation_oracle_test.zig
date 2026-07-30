//! Invalidation oracle: applies a seeded random mutation sequence to a tree
//! that recomputes layout incrementally (caches warm), then replays the same
//! sequence into a fresh tree computed cold, and requires both to agree on
//! per-node geometry and painted output. Any divergence is an invalidation
//! bug; the failing seed + mutation log make it reproducible.
const std = @import("std");
const Tree = @import("Tree.zig");
const Node = @import("Node.zig");
const parsers = @import("../styles/styles.zig");
const Renderer = @import("../renderer/v2/Renderer.zig");

const constants = @import("../layout/v2/constants.zig");
const viewport = constants.AvailableSpacePoint{
    .x = .{ .definite = 80 },
    .y = .{ .definite = 24 },
};

const style_palette = [_][]const u8{
    "display: block",
    "display: flex",
    "display: flex; flex-direction: column",
    "width: 20px",
    "width: 50%",
    "width: auto",
    "height: 5px",
    "padding: 1px",
    "margin: 1px",
    "border-style: double",
    "text-align: center",
    "display: flex; width: 40px; height: 8px",
};

const text_palette = [_][]const u8{
    "hello",
    "lorem ipsum dolor sit amet consectetur",
    "a b c",
    "words that will wrap once the line gets long enough",
    "x",
};

const Op = union(enum) {
    append_element: struct { parent: Node.NodeId, style: usize },
    append_text: struct { parent: Node.NodeId, text: usize },
    remove: struct { parent: Node.NodeId, child: Node.NodeId },
    set_text: struct { node: Node.NodeId, text: usize },
    restyle: struct { node: Node.NodeId, style: usize },
};

fn applyOp(tree: *Tree, op: Op) !void {
    switch (op) {
        .append_element => |o| {
            const id = try tree.createNode();
            try parsers.parseStyleString(tree, id, style_palette[o.style]);
            _ = try tree.appendChild(o.parent, id);
        },
        .append_text => |o| {
            const id = try tree.createTextNode(text_palette[o.text]);
            _ = try tree.appendChild(o.parent, id);
        },
        .remove => |o| try tree.removeChild(o.parent, o.child),
        .set_text => |o| try tree.setText(o.node, text_palette[o.text]),
        .restyle => |o| try parsers.parseStyleString(tree, o.node, style_palette[o.style]),
    }
}

const LiveNodes = struct {
    elements: std.ArrayList(Node.NodeId),
    texts: std.ArrayList(Node.NodeId),

    fn deinit(self: *LiveNodes, allocator: std.mem.Allocator) void {
        self.elements.deinit(allocator);
        self.texts.deinit(allocator);
    }
};

fn collectLive(tree: *Tree, allocator: std.mem.Allocator, root: Node.NodeId) !LiveNodes {
    var live: LiveNodes = .{ .elements = .empty, .texts = .empty };
    errdefer live.deinit(allocator);
    try collectLiveInner(tree, allocator, root, &live);
    return live;
}

fn collectLiveInner(tree: *Tree, allocator: std.mem.Allocator, id: Node.NodeId, live: *LiveNodes) !void {
    const node = tree.getNode(id);
    switch (node.kind) {
        .text => try live.texts.append(allocator, id),
        .node => {
            try live.elements.append(allocator, id);
            for (node.children.items) |child| {
                try collectLiveInner(tree, allocator, child, live);
            }
        },
    }
}

fn runPipeline(tree: *Tree, allocator: std.mem.Allocator) !void {
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, viewport);
}

/// Dump per-node geometry plus a fresh-renderer paint. Generation counters and
/// cache state are deliberately excluded: only observable output may be compared.
fn dumpObservable(tree: *Tree, allocator: std.mem.Allocator, root: Node.NodeId) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    var live = try collectLive(tree, allocator, root);
    defer live.deinit(allocator);

    for ([_][]const Node.NodeId{ live.elements.items, live.texts.items }) |ids| {
        for (ids) |id| {
            const rect = tree.getNode(id).getBoundingClientRect(tree);
            try w.print("#{d}: {d:.2},{d:.2} {d:.2}x{d:.2}\n", .{ id, rect.x, rect.y, rect.width, rect.height });
        }
    }

    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    try w.writeAll("--- paint ---\n");
    try tree.paint(&renderer, w, .simple);

    return try allocator.dupe(u8, aw.writer.buffered());
}

fn randomIndex(rand: std.Random, len: usize) usize {
    return rand.uintLessThan(usize, len);
}

fn generateOp(rand: std.Random, tree: *Tree, allocator: std.mem.Allocator, root: Node.NodeId) !?Op {
    var live = try collectLive(tree, allocator, root);
    defer live.deinit(allocator);

    const elements = live.elements.items;
    const texts = live.texts.items;

    return switch (rand.uintLessThan(u8, 10)) {
        // weighted: growth is more common than removal so trees stay interesting
        0, 1, 2 => .{ .append_element = .{
            .parent = elements[randomIndex(rand, elements.len)],
            .style = randomIndex(rand, style_palette.len),
        } },
        3, 4 => .{ .append_text = .{
            .parent = elements[randomIndex(rand, elements.len)],
            .text = randomIndex(rand, text_palette.len),
        } },
        5 => blk: {
            // remove a random non-root node
            const total = elements.len - 1 + texts.len;
            if (total == 0) break :blk null;
            const pick = randomIndex(rand, total);
            const child = if (pick < elements.len - 1) elements[pick + 1] else texts[pick - (elements.len - 1)];
            const parent = tree.getNode(child).parent orelse break :blk null;
            break :blk .{ .remove = .{ .parent = parent, .child = child } };
        },
        6, 7 => blk: {
            if (texts.len == 0) break :blk null;
            break :blk .{ .set_text = .{
                .node = texts[randomIndex(rand, texts.len)],
                .text = randomIndex(rand, text_palette.len),
            } };
        },
        else => .{ .restyle = .{
            .node = elements[randomIndex(rand, elements.len)],
            .style = randomIndex(rand, style_palette.len),
        } },
    };
}

fn runOracle(seed: u64, mutation_count: usize) !void {
    const allocator = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var ops: std.ArrayList(Op) = .empty;
    defer ops.deinit(allocator);

    // Incremental tree: recomputes after every mutation with caches warm.
    var incremental = try Tree.init(allocator);
    defer incremental.deinit();
    const root = try incremental.createNode();
    try parsers.parseStyleString(&incremental, root, "width: 80px; height: 24px");
    try runPipeline(&incremental, allocator);

    for (0..mutation_count) |_| {
        const op = try generateOp(rand, &incremental, allocator, root) orelse continue;
        try ops.append(allocator, op);
        try applyOp(&incremental, op);
        try runPipeline(&incremental, allocator);
    }

    // Oracle tree: same ops replayed into a fresh tree, computed once, cold.
    var cold = try Tree.init(allocator);
    defer cold.deinit();
    const cold_root = try cold.createNode();
    try std.testing.expectEqual(root, cold_root);
    try parsers.parseStyleString(&cold, cold_root, "width: 80px; height: 24px");
    for (ops.items) |op| {
        try applyOp(&cold, op);
    }
    try runPipeline(&cold, allocator);

    const incremental_dump = try dumpObservable(&incremental, allocator, root);
    defer allocator.free(incremental_dump);
    const cold_dump = try dumpObservable(&cold, allocator, root);
    defer allocator.free(cold_dump);

    if (!std.mem.eql(u8, cold_dump, incremental_dump)) {
        std.debug.print("invalidation oracle divergence: seed={d} ops={d}\n", .{ seed, ops.items.len });
        for (ops.items, 0..) |op, i| {
            std.debug.print("  [{d}] {any}\n", .{ i, op });
        }
    }
    try std.testing.expectEqualStrings(cold_dump, incremental_dump);
}

test "invalidation oracle" {
    for (0..24) |seed| {
        try runOracle(seed, 30);
    }
}
