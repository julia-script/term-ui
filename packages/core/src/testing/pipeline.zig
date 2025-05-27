const std = @import("std");
const Tree = @import("../tree/Tree.zig");
const layout_v2 = @import("../layout/v2/mod.zig");
const renderer_v2 = @import("../renderer/v2/mod.zig");
const snapshot = @import("snapshot.zig");

pub const PipelineOptions = struct {
    /// Show escape sequences in visual output (replaced with \E)
    show_escape_sequences: bool = true,
    /// Available space for layout computation
    available_space: struct {
        width: f32 = 80,
        height: f32 = 24,
    } = .{},
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
    
    // 3. Build and show layout tree
    try writer.writeAll("--- Layout Tree (before computation) ---\n");
    var layout_tree = try layout_v2.LayoutTree.fromTree(allocator, &doc_tree);
    defer layout_tree.deinit();
    
    try layout_tree.printRoot(writer.any());
    try writer.writeAll("\n");
    
    // 4. Compute layout
    try writer.writeAll("--- Layout Computation ---\n");
    var layout_context = layout_v2.LayoutContext{
        .layout_tree = &layout_tree,
        .doc_tree = &doc_tree,
        .allocator = allocator,
    };
    
    const available_space = layout_v2.PointOf(layout_v2.constants.AvailableSpace){
        .x = .{ .definite = options.available_space.width },
        .y = .{ .definite = options.available_space.height },
    };
    
    try layout_v2.computeLayout(&layout_context, available_space);
    
    try writer.print("Available space: {d}x{d}\n", .{ 
        options.available_space.width, 
        options.available_space.height 
    });
    try writer.writeAll("\n");
    
    // 5. Show layout tree after computation
    try writer.writeAll("--- Layout Tree (after computation) ---\n");
    try layout_tree.printRoot(writer.any());
    try writer.writeAll("\n");
    
    // 6. Build and show render list
    try writer.writeAll("--- Render List ---\n");
    var render_list = layout_v2.RenderList.init(allocator);
    defer render_list.deinit();
    
    var builder = layout_v2.RenderListBuilder.init(&layout_tree, &doc_tree, &render_list);
    try builder.build();
    
    try render_list.print(writer.any());
    try writer.writeAll("\n");
    
    // 7. Render to terminal string
    try writer.writeAll("--- Rendered Output ---\n");
    var renderer = try renderer_v2.Renderer.init(allocator);
    defer renderer.deinit();
    
    // Create a sub-buffer for rendered output
    var render_buffer = std.ArrayList(u8).init(arena_allocator);
    try renderer.render(&render_list, render_buffer.writer().any());
    
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