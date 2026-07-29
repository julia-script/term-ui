const std = @import("std");
const print = std.debug.print;
const HitTestFilter = @import("tree/Tree.zig").HitTestFilter;

const Renderer = @import("renderer/v2/Renderer.zig");
const docFromXml = @import("layout/v2/doc-from-xml.zig").docFromXml;
// Import the WASM API functions we'll use
const wasm = @import("wasm.zig");

// Helper to create null-terminated strings for WASM API
fn createNullTermString(str: []const u8) [*:0]u8 {
    const ptr: [*:0]u8 = wasm.allocNullTerminatedBuffer(str.len);
    @memcpy(ptr[0..str.len], str);
    return ptr;
}

pub const std_options: std.Options = .{
    // .logFn = wasmLog,
    // .log_level = if (is_debug) .debug else .err,
    .log_level = .info,
};

pub fn main() !void {
    print("=== CSS Layout Engine Playground ===\n\n", .{});
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const stderr = &aw.writer;
    defer print("{s}\n", .{aw.writer.buffered()});

    // const tree = wasm.Tree_init();
    // defer wasm.Tree_deinit(tree);

    var tree = try docFromXml(allocator,
        // \\<div style="border-style: double;color: white">
        // // before-inside
        // // \\<span>$S[Hello</span> Wo$S]rld
        // // \\
        // // \\Hel$S[lo<span> Wo$S]rld</span>
        // // \\thisisa$S[verylong$S]wordthat
        // \\asd$S[<span>Hello</span>$S]
        // \\</div>

        \\<div style="border-style: double;color: white; width: 30;text-align: center;"> 
        // \\<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incid$S]idunt ut labore et dolore magna aliqua.</p>
        // \\<p id="hello" contenteditable="true" style="border-style: double;">Lorem ipsum $S[dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        // \\<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        // \\
        \\<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        \\<p id="hello" contenteditable="true" style="border-style: double;">Lorem $S[ipsum dolor sit $S]amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        \\<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        \\<p>The quick brown fox jumps over the lazy dog.</p>
        \\</div>
    , .{});
    defer tree.deinit();
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    try tree.computeStyles();
    try tree.buildLayoutTree();
    try tree.computeLayout(allocator, .{
        .x = .{ .definite = 50 },
        .y = .max_content,
    });

    try tree.paint(&renderer, stderr, .simple);
    try tree.print(stderr);
    // // try selection.modify(&tree, .backward, .line, null);
    // try selection.setFocus(&tree, .{
    //     .node_id = 7,
    //     .offset = 10,
    // });
    var selection = tree.getFirstSelection() orelse unreachable;

    // try tree.paint(&renderer, stderr, .simple);
    // try tree.paint(&renderer, stderr, .simple);
    // try tree.print(stderr);
    // try tree.layout_tree.printRoot(stderr);
    for (0..6) |_| {
        // const selection = tree.getFirstSelection() orelse unreachable;
        try selection.modify(&tree, .backward, .character, null);
        try tree.paint(&renderer, stderr, .simple);
        // std.time.sleep(std.time.ns_per_s * 1);
    }
}

test "playground full demo" {
    // try main();
}
