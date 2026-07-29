const std = @import("std");
const Tree = @import("../../tree/Tree.zig");
const Renderer = @import("../../renderer/v2/Renderer.zig");
const snapshot = @import("snapshot.zig");
const layout = @import("../../layout/v2/mod.zig");
const docFromXml = @import("../../layout/v2/doc-from-xml.zig").docFromXml;
const root = @import("root");
pub fn assertDocumentSnapshot(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    tree: *Tree,
    maybe_available_space: ?layout.constants.AvailableSpacePoint,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var buffer = std.ArrayList(u8).init(arena_allocator);

    const writer = buffer.writer().any();
    {
        // const sub_description = try std.fmt.allocPrint(arena_allocator, "{s}: before layout", .{description});

        try writer.writeAll("--- Document: Before layout ---\n");
        try tree.print(writer);
        try writer.writeAll("\n");
        try root.matchSnapshot(loc, .{
            .namespace = "before-layout",
        }, buffer.items);
    }

    var renderer = try Renderer.init(allocator);
    const available_space: layout.constants.AvailableSpacePoint = maybe_available_space orelse .{
        .x = .{ .definite = 40 },
        .y = .max_content,
    };

    defer renderer.deinit();
    try tree.computeStyles();
    try tree.buildLayoutTree();

    try tree.computeLayout(allocator, available_space);
    {
        buffer.clearRetainingCapacity();

        try writer.writeAll("--- Document: After layout ---\n");
        try tree.print(writer);
        try writer.writeAll("\n");
        try root.matchSnapshot(loc, .{
            .namespace = "after-layout",
        }, buffer.items);
    }

    {
        buffer.clearRetainingCapacity();

        try tree.layout_tree.printRoot(writer);
        try writer.writeAll("\n");
        try root.matchSnapshot(loc, .{
            .namespace = "layout-tree",
        }, buffer.items);
    }
    var paint_buffer = std.ArrayList(u8).init(allocator);
    defer paint_buffer.deinit();
    const paint_writer = paint_buffer.writer().any();
    {
        buffer.clearRetainingCapacity();
        try tree.paint(&renderer, paint_writer, .simple);
        try writer.writeAll(paint_buffer.items);
        try root.matchSnapshot(loc, .{
            .namespace = "paint",
        }, buffer.items);
    }

    {
        buffer.clearRetainingCapacity();
        try writer.writeAll("--- State ---\n");
        try writer.print("Doc Nodes Count: {d}\n", .{tree.node_map.count()});
        try writer.print("Layout Tree Nodes Count: {d}\n", .{tree.layout_tree.nodes.count()});
        try writer.print("Render List Nodes Length: {d}\n", .{tree.render_list.items.items.len});
        try writer.writeAll("\n\n");
        {
            try writer.writeAll("-- Selections ---\n");
            var iter = tree.selections.iterator();
            while (iter.next()) |entry| {
                try writer.print("Selection {d}: {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try writer.writeAll("\n\n");
        }
        {
            try writer.writeAll("--- Live Ranges ---\n");
            var iter = tree.live_ranges.iterator();
            while (iter.next()) |entry| {
                try writer.print("Live Range {d}: {any}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            try writer.writeAll("\n\n");
        }
        {
            try writer.writeAll("--- Render List ---\n");
            try tree.render_list.print(writer);
            try writer.writeAll("\n\n");
        }
        try root.matchSnapshot(loc, .{
            .namespace = "state",
        }, buffer.items);
    }
    {
        buffer.clearRetainingCapacity();
        try tree.paint(&renderer, writer, .svg);
        try root.matchSnapshot(loc, .{
            .ext = "svg",
            .include_header = false,
        }, buffer.items);
    }
    // {"version":3,"term":{"cols":62,"rows":29,"type":"xterm-256color","theme":{"fg":"#e6edf3","bg":"#010409","palette":"#484f58:#ff7b72:#3fb950:#d29922:#58a6ff:#bc8cff:#39c5cf:#b1bac4:#6e7681:#ffa198:#56d364:#e3b341:#79c0ff:#d2a8ff:#56d4dd:#ffffff"}},"timestamp":1750459098,"env":{"TERM":"xterm-256color","SHELL":"/bin/zsh"}}
}

pub fn assertDocumentSnapshotFromXml(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    xml: []const u8,
    maybe_available_space: ?layout.constants.AvailableSpacePoint,
) !void {
    var doc = try docFromXml(allocator, xml, .{});
    defer doc.deinit();
    try assertDocumentSnapshot(loc, allocator, &doc, maybe_available_space);
}
