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
    const stderr = std.io.getStdErr().writer().any();
    var gpa = std.heap.GeneralPurposeAllocator(.{
        // .enable_memory_limit = true,
        // .verbose_log = true,
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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

        \\<div style="border-style: double;color: white"> 
        \\<span id="hello">Lorem ipsum dolor $S[sit amet, consectetur adipiscing elit. Sed do]$S eiusmod tempor incididunt ut labore et dolore magna aliqua.</span>
        \\</div>
    , .{});
    defer tree.deinit();
    var renderer = try Renderer.init(allocator);
    defer renderer.deinit();
    try tree.computeStyles();
    try tree.print(stderr);
    try tree.buildLayoutTree();

    try tree.computeLayout(allocator, .{
        .x = .{ .definite = 50 },
        .y = .max_content,
    });
    try tree.layout_tree.printRoot(stderr);
    try tree.paint(&renderer, stderr, .simple);
    while (true) {
        // std.debug.print("total_requested_bytes: {d}\n", .{gpa.total_requested_bytes});
        const selection = tree.getFirstSelection() orelse unreachable;
        try selection.modify(&tree, .forward, .character);
        try tree.paint(&renderer, stderr, .simple);
        std.time.sleep(std.time.ns_per_s * 0.1);
    }
}

test "playground full demo" {
    // try main();
}
