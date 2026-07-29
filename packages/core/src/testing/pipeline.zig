const std = @import("std");
const Tree = @import("../tree/Tree.zig");
const layout_v2 = @import("../layout/v2/mod.zig");
const renderer_v2 = @import("../renderer/v2/mod.zig");
const snapshot = @import("../tests/utils/snapshot.zig");

pub const PipelineOptions = struct {
    /// Show escape sequences in visual output (replaced with \E)
    show_escape_sequences: bool = true,
    /// Available space for layout computation
    available_space: layout_v2.constants.AvailableSpacePoint,
};

/// Captures the entire rendering pipeline for testing
pub fn expectPipeline(
    allocator: std.mem.Allocator,
    xml: []const u8,
    description: []const u8,
    options: PipelineOptions,
    comptime loc: std.builtin.SourceLocation,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var buffer = std.ArrayList(u8).init(arena_allocator);
    const writer = buffer.writer();

    // Header
    try writer.print("=== Pipeline Snapshot: {s} ===\n\n", .{description});

    // 1. Input XML
    try writer.writeAll("--- Input XML ---\n");
    try writer.writeAll(xml);
    try writer.writeAll("\n\n");

    // 2. Parse and show DOM tree
    try writer.writeAll("--- DOM Tree ---\n");
    var doc_tree = try layout_v2.docFromXml(allocator, xml, .{});
    defer doc_tree.deinit();

    try doc_tree.print(writer.any());
    try writer.writeAll("\n");

    // 3. Compute styles
    try writer.writeAll("--- Computing Styles ---\n");
    try doc_tree.computeStyles();
    try writer.writeAll("Styles computed successfully\n\n");

    // 4. Build layout tree
    try writer.writeAll("--- Building Layout Tree ---\n");
    try doc_tree.buildLayoutTree();
    try writer.writeAll("Layout tree built successfully\n\n");

    // 5. Show layout tree before computation
    try writer.writeAll("--- Layout Tree (before computation) ---\n");
    try doc_tree.layout_tree.printRoot(writer.any());
    try doc_tree.layout_tree.printRoot(std.io.getStdErr().writer().any());
    try writer.writeAll("\n");

    // 6. Compute layout
    try writer.writeAll("--- Layout Computation ---\n");
    try doc_tree.computeLayout(allocator, options.available_space);
    try writer.print("Available space: [{}] x [{}]\n", .{ options.available_space.x, options.available_space.y });
    try writer.writeAll("\n");

    // 7. Show layout tree after computation
    try writer.writeAll("--- Layout Tree (after computation) ---\n");
    try doc_tree.layout_tree.printRoot(writer.any());
    try writer.writeAll("\n");

    // 8. Render to terminal string
    try writer.writeAll("--- Rendered Output ---\n");
    var renderer = try renderer_v2.Renderer.init(allocator);
    defer renderer.deinit();

    // Create a sub-buffer for rendered output
    var render_buffer = std.ArrayList(u8).init(arena_allocator);
    try doc_tree.paint(&renderer, render_buffer.writer().any(), .app);

    // Show the raw output with escape sequences visible
    try writer.writeAll("Raw (escape sequences as \\E):\n");
    for (render_buffer.items) |c| {
        switch (c) {
            '\x1b' => try writer.writeAll("\\E"),
            '\n' => try writer.writeAll("\\n\n"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeAll("\n\n");

    // Show the visual output
    try writer.writeAll("Visual:\n");
    if (options.show_escape_sequences) {
        // Show with escape sequences visible as \E
        for (render_buffer.items) |c| {
            switch (c) {
                '\x1b' => try writer.writeAll("\\E"),
                else => try writer.writeByte(c),
            }
        }
    } else {
        // Strip escape sequences
        try writeVisualOutputStripped(writer, render_buffer.items);
    }
    try writer.writeAll("\n\n");

    // 8. Canvas state (optional debug info)
    try writer.writeAll("--- Canvas Info ---\n");
    const dims = renderer.canvas.getDimensions();
    try writer.print("Dimensions: {d}x{d}\n", .{ dims.width, dims.height });
    try writer.print("Total cells: {d}\n", .{dims.width * dims.height});

    // Write the complete snapshot
    try snapshot.expectMatchSnapshot(loc, allocator, description, buffer.items);
}

fn writeVisualOutputStripped(writer: anytype, output: []const u8) !void {
    var i: usize = 0;
    while (i < output.len) {
        if (output[i] == '\x1b') {
            // Skip escape sequence
            i += 1;
            if (i < output.len and output[i] == '[') {
                i += 1;
                // Skip until 'm' or other terminator
                while (i < output.len and !std.ascii.isAlphabetic(output[i])) {
                    i += 1;
                }
                if (i < output.len) i += 1; // Skip terminator
            }
        } else {
            try writer.writeByte(output[i]);
            i += 1;
        }
    }
}
