const std = @import("std");
const print = std.debug.print;

// Import the WASM API functions we'll use
const wasm = @import("wasm.zig");

// Helper to create null-terminated strings for WASM API
fn createNullTermString(str: []const u8) [*:0]u8 {
    const ptr: [*:0]u8 = wasm.allocNullTerminatedBuffer(str.len);
    @memcpy(ptr[0..str.len], str);
    return ptr;
}

pub fn playground() !void {
    print("=== CSS Layout Engine Playground ===\n\n", .{});
    const stderr = std.io.getStdErr().writer().any();

    // Create a new tree
    const tree = wasm.Tree_init();
    defer wasm.Tree_deinit(tree);

    print("\n=== DocTree ===\n", .{});
    const container_id = wasm.Tree_createNode(tree, createNullTermString("background-color: blue; padding: 1; text-align: center;"));
    wasm.Tree_setElementId(tree, container_id, createNullTermString("container"));

    const button_id = wasm.Tree_createNode(tree, createNullTermString("background-color: white; padding: 1;"));
    wasm.Tree_setElementId(tree, button_id, createNullTermString("my-button"));
    _ = wasm.Tree_appendChild(tree, container_id, button_id);
    const text_id = wasm.Tree_createTextNode(tree, createNullTermString("Click me!"));
    _ = wasm.Tree_appendChild(tree, button_id, text_id);

    // wasm.Tree_computeStyles(tree);
    // print("\n=== Before computeLayout ===\n", .{});

    // try tree.print(stderr);

    // print("\n=== LayoutTree ===\n", .{});
    // wasm.Tree_computeLayout(tree, createNullTermString("20"), createNullTermString("10"));
    // try tree.layout_tree.printRoot(stderr);

    // print("\n=== Rendering ===\n", .{});
    const renderer = wasm.Renderer_init();
    defer wasm.Renderer_deinit(renderer);
    // clear screen
    var frame: u32 = 0;
    var buf = try std.BoundedArray(u8, 100).init(0);

    while (frame < 10) : (frame += 1) {
        try stderr.print("\x1b[2J\x1b[H", .{});
        buf.clear();
        buf.writer().print("Hello {d}!\n", .{frame}) catch unreachable;
        // DOM changes
        wasm.Tree_setText(tree, text_id, createNullTermString(buf.slice()));

        wasm.Tree_computeStyles(tree);
        wasm.Tree_computeLayoutTree(tree);
        try tree.print(stderr);
        try tree.layout_tree.printRoot(stderr);
        wasm.Tree_computeLayout(tree, createNullTermString("20"), createNullTermString("10"));

        std.debug.print("Frame {d}\n", .{frame});
        wasm.Tree_paintApp(tree, renderer);
        try tree.print(stderr);

        std.time.sleep(1 * std.time.ns_per_s);
    }
}

test "playground full demo" {
    try playground();
}
