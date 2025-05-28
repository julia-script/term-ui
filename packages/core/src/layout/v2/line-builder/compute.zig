const mod = @import("../mod.zig");
const WhitespaceRules = @import("WhitespaceRules.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");
const css_types = @import("../../../css/types.zig");
const std = @import("std");
const Error = Tokenizer.Error;
const wrap = @import("wrap.zig");

pub fn compute(
    context: *mod.LayoutContext,
    allocator: std.mem.Allocator,
    inputs: mod.ContainerContext,
    l_node_id: mod.LayoutNode.Id,
    collapse_mode: css_types.WhiteSpaceCollapse,
    wrap_mode: css_types.TextWrapMode,
) Error!void {
    const tokens = try Tokenizer.tokenizeLayoutNode(
        allocator,
        context,
        inputs,
        l_node_id,
        collapse_mode,
    );
    defer tokens.deinit();
    WhitespaceRules.applyPhase1Rules(tokens.items, collapse_mode);
    wrap.wrapTokens(tokens.items, inputs.available_space.x, wrap_mode);
    WhitespaceRules.TestHelper.printTokens(tokens.items, std.io.getStdErr().writer().any()) catch {};
}

test "compute" {
    var doc = try mod.docFromXml(std.testing.allocator, "<div>Hello, world!</div>", .{});
    defer doc.deinit();
    var layout_tree = try mod.LayoutTree.fromTree(std.testing.allocator, &doc);
    defer layout_tree.deinit();
    var context = mod.LayoutContext{
        .allocator = std.testing.allocator,
        .layout_tree = &layout_tree,
        .doc_tree = &doc,
    };
    try mod.computeLayout(&context, .{ .x = .{ .definite = 30 }, .y = .max_content });
}
