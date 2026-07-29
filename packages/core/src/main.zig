pub const std_options: std.Options = .{
    .fmt_max_depth = 20,
};
const builtin = @import("builtin");
const std = @import("std");
// const Node = @import("./layout/tree/Node.zig");
// pub const compute_root_layout = @import("./layout/compute/compute_root_layout.zig").compute_root_layout;
pub fn main() !void {
    const a = @import("demo");
    _ = a; // autofix
    // std.meta.
    // std.debug.print("{any}\n", .{builtin.});
    // const s: SegmentIter = undefined;
    // var segmenter = try LineSegmenter.new();
    // var iter = try segmenter.segmentString("hello, world!\n\n\nmy name is juliaaaa");
    // defer segmenter.deinit();
    // defer iter.deinit();
    // while (iter.next()) |position| {
    //     std.debug.print("Segment: {any}\n", .{position});
    // }
}

test {
    // @compileLog(root);

    _ = std_options;
    _ = @import("./renderer/Canvas.zig");
    _ = @import("./renderer/Renderer.zig");
    _ = @import("./cmd/input.zig");
    _ = @import("./cmd/Trie.zig");
    _ = @import("./cmd/terminfo/main.zig");
    // _ = @import("./styles/style_system_test.zig");
    // _ = @import("./styles/text_formatting_tests.zig");
    _ = @import("./renderer/Renderer.zig");
    _ = @import("./renderer/gradient.zig");
    // _ = @import("./layout/Selection.zig");
}
