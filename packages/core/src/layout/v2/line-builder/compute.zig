const mod = @import("../mod.zig");
const WhitespaceRules = @import("WhitespaceRules.zig");
const Tokenizer = @import("Tokenizer.zig");
const Token = @import("Token.zig");
const css_types = @import("../../../css/types.zig");
const TextAlignment = @import("TextAlignment.zig");
const LineBox = @import("LineBox.zig");
const LineBoxFragment = @import("LineBoxFragment.zig");
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
    text_align: css_types.TextAlign,
) Error!LineBox.LineBoxList {
    const tokens = try Tokenizer.tokenizeLayoutNode(
        allocator,
        context,
        inputs,
        l_node_id,
        collapse_mode,
    );
    defer tokens.deinit();

    // Phase I: Collapse and transformation
    WhitespaceRules.applyPhase1Rules(tokens.items, collapse_mode);
    WhitespaceRules.measureTokens(tokens.items);

    // Line breaking
    const resolved_width = wrap.resolveLineWidth(tokens.items, inputs.available_space.x);
    std.debug.print("\n=== Wrapping with width={d} ===\n", .{resolved_width});
    wrap.wrapTokens(tokens.items, resolved_width, wrap_mode, collapse_mode);

    // Phase II: Trimming and positioning (mark hanging spaces)
    WhitespaceRules.applyPhase2Rules(tokens.items, collapse_mode);

    // Text alignment (if we have a definite width)
    TextAlignment.applyTextAlignment(tokens.items, resolved_width, text_align, collapse_mode);
    WhitespaceRules.TestHelper.printTokens(tokens.items, std.io.getStdErr().writer().any()) catch {};

    // Convert tokens to line boxes and fragments
    const line_boxes = try tokensToLineBoxes(allocator, tokens.items, resolved_width);

    return line_boxes;
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

const snapshot = @import("../../../testing/snapshot.zig");

pub fn testFullPipeline(
    comptime name: []const u8,
    nodes: []const WhitespaceRules.TestHelper.TestNode,
    collapse_mode: css_types.WhiteSpaceCollapse,
    wrap_mode: css_types.TextWrapMode,
    text_align: css_types.TextAlign,
    available_width: mod.constants.AvailableSpace,
    comptime src: std.builtin.SourceLocation,
) !void {
    var helper = WhitespaceRules.TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(nodes, collapse_mode);
    defer tokens.deinit();

    // Phase I: Collapse and transformation
    WhitespaceRules.applyPhase1Rules(tokens.items, collapse_mode);
    WhitespaceRules.measureTokens(tokens.items);

    // Line breaking
    const resolved_width = wrap.resolveLineWidth(tokens.items, available_width);
    wrap.wrapTokens(tokens.items, resolved_width, wrap_mode, collapse_mode);

    // Phase II: Trimming and positioning
    WhitespaceRules.applyPhase2Rules(tokens.items, collapse_mode);

    // Phase III: Text alignment (if we have a definite width)
    TextAlignment.applyTextAlignment(tokens.items, resolved_width, text_align, collapse_mode);

    // Build output for snapshot
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    const writer = output.writer().any();

    // Header
    try writer.print("Full pipeline test: collapse_mode={s}, wrap_mode={s}, text_align={s}, width=", .{
        @tagName(collapse_mode),
        @tagName(wrap_mode),
        @tagName(text_align),
    });
    switch (available_width) {
        .definite => |w| try writer.print("{d}", .{w}),
        .max_content => try writer.writeAll("max-content"),
        .min_content => try writer.writeAll("min-content"),
    }
    try writer.writeAll("\n\n");

    // Rendered lines with alignment info
    try writer.writeAll("Rendered lines:\n");
    var current_line: ?usize = null;
    var line_content_width: f32 = 0;
    var line_offset: f32 = 0;

    for (tokens.items) |token| {
        if (current_line == null or token.line_index != current_line.?) {
            if (current_line != null) {
                try writer.print(" (content_width={d:.1})\n", .{line_content_width});
            }
            current_line = token.line_index;
            line_content_width = 0;

            // Get line offset from first token
            if (token.text.len > 0 or token.kind == .segment_break) {
                line_offset = token.position_in_line;
            }

            try writer.print("  Line {d} [offset={d:.1}]: ", .{ current_line.?, line_offset });
        }

        if (token.text.len > 0) {
            try writer.print("{s}", .{token.text});
            if (!token.is_hanging) {
                line_content_width += token.size.x;
            }
        }
    }

    if (current_line != null) {
        try writer.print(" (content_width={d:.1})\n", .{line_content_width});
    }

    try snapshot.expectMatchSnapshot(
        src,
        std.testing.allocator,
        name,
        output.items,
    );
}

test "full pipeline: center with hanging spaces" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Center" },
        .{ .id = 2, .text = "  " },
        .{ .id = 3, .text = "this" },
        .{ .id = 4, .text = "   " }, // Should hang and not affect centering
        .{ .id = 5, .text = "\n" },
        .{ .id = 6, .text = "Line" },
        .{ .id = 7, .text = " " },
        .{ .id = 8, .text = "two" },
    };

    try testFullPipeline(
        "full pipeline center with hanging spaces",
        &nodes,
        .@"preserve-breaks",
        .wrap,
        .center,
        .{ .definite = 30 },
        @src(),
    );
}

test "full pipeline: right align wrapped text" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "This is a long line that will wrap to multiple lines" },
    };

    try testFullPipeline(
        "full pipeline right align wrapped text",
        &nodes,
        .collapse,
        .wrap,
        .right,
        .{ .definite = 20 },
        @src(),
    );
}

test "full pipeline: preserve spaces with alignment" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "  Start" },
        .{ .id = 2, .text = "  with" },
        .{ .id = 3, .text = "  spaces  " },
    };

    try testFullPipeline(
        "full pipeline preserve spaces with alignment",
        &nodes,
        .@"preserve-spaces",
        .wrap,
        .center,
        .{ .definite = 40 },
        @src(),
    );
}

test "full pipeline: break-spaces no hanging" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Break" },
        .{ .id = 2, .text = "   " }, // Should not hang, affects alignment
        .{ .id = 3, .text = "spaces" },
    };

    try testFullPipeline(
        "full pipeline break-spaces no hanging",
        &nodes,
        .@"break-spaces",
        .wrap,
        .center,
        .{ .definite = 30 },
        @src(),
    );
}

/// Convert tokens into line boxes with fragments
/// Sequential tokens with the same node and line are grouped into a single fragment
fn tokensToLineBoxes(allocator: std.mem.Allocator, tokens: []const Token, width: f32) !LineBox.LineBoxList {
    var line_boxes = LineBox.LineBoxList{
        .allocator = allocator,
    };

    if (tokens.len == 0) {
        return line_boxes;
    }

    // Debug: Log all incoming tokens
    std.debug.print("\n=== tokensToLineBoxes Debug ===\n", .{});
    std.debug.print("Available width: {d}\n", .{width});
    std.debug.print("Incoming tokens ({d} total):\n", .{tokens.len});
    for (tokens, 0..) |token, idx| {
        std.debug.print("  [{d}] line={d} node={d} text=\"{s}\" size={d} pos={d} hanging={} kind={s}\n", .{
            idx,
            token.line_index,
            token.l_node_id,
            token.text,
            token.size.x,
            token.position_in_line,
            token.is_hanging,
            @tagName(token.kind),
        });
    }

    var accumulated_text = std.ArrayList(u8).init(allocator);
    defer accumulated_text.deinit();

    var current_line_index: usize = 0;
    var i: usize = 0;

    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];
        defer current_line_index = token.line_index;
        while (current_line_index < token.line_index) : (current_line_index += 1) {
            try line_boxes.breakLine();
        }

        // // Break to new line if line index changed, creating empty lines if needed
        // if (current_line_index) |prev_line| {
        //     if (prev_line != token.line_index) {
        //         std.debug.print("  Breaking line: {d} -> {d}\n", .{ prev_line, token.line_index });
        //         // Create empty lines for any skipped line indices
        //         var line_idx = prev_line + 1;
        //         while (line_idx <= token.line_index) : (line_idx += 1) {
        //             try line_boxes.breakLine();
        //         }
        //     }
        // }
        // current_line_index = token.line_index;

        // // Handle atomic tokens separately
        if (token.kind == .atomic) {
            try line_boxes.appendFragmentToLastLine(.{
                .l_node_id = token.l_node_id,
                .start = token.dom_range.start,
                .length = 0,
                .size = token.size,
                .is_atomic = true,
                .text = "",
                .allocator = allocator,
                .position = .{ .x = token.position_in_line, .y = 0 },
                .dom_range = .{ .start = token.dom_range.start, .end = token.dom_range.end },
            });
            continue;
        }
        // let's not try to group tokens for now
        // // we'll just add them to the last line
        // try line_boxes.appendFragmentToLastLine(.{
        //     .text = try allocator.dupe(u8, token.text),
        //     .l_node_id = token.l_node_id,
        //     .start = token.dom_range.start,
        //     .length = token.dom_range.end - token.dom_range.start,
        //     .size = token.size,
        //     .is_atomic = false,
        //     .allocator = allocator,
        //     .position = .{ .x = token.position_in_line, .y = 0 },
        //     .dom_range = .{ .start = token.dom_range.start, .end = token.dom_range.end },
        // });

        // Clear text accumulator for new fragment group
        accumulated_text.clearRetainingCapacity();

        // Start accumulating text and size from first token
        try accumulated_text.appendSlice(token.text);
        var accumulated_size: mod.CSSPoint = if (token.is_hanging) .{ .x = 0, .y = token.size.y } else token.size;
        const position_in_line = token.position_in_line;
        const dom_start = token.dom_range.start;
        var dom_end = token.dom_range.end;

        const group_start_idx = i;

        // Group consecutive tokens from same node and line
        while (i < tokens.len - 1) {
            const next_token = tokens[i + 1];
            // Stop if next token is on different line, different node, or is atomic
            if (next_token.line_index != token.line_index or
                next_token.l_node_id != token.l_node_id or
                next_token.kind == .atomic)
            {
                break;
            }

            // Add this token to the group
            i += 1;
            // Only add size if not hanging
            if (!next_token.is_hanging) {
                accumulated_size.x += next_token.size.x;
            }
            accumulated_size.y = @max(accumulated_size.y, next_token.size.y);
            try accumulated_text.appendSlice(next_token.text);
            dom_end = next_token.dom_range.end;
        }

        // Create fragment with accumulated content
        const fragment = LineBoxFragment{
            .l_node_id = token.l_node_id,
            .start = dom_start,
            .length = dom_end - dom_start,
            .size = accumulated_size,
            .is_atomic = false,
            .text = try allocator.dupe(u8, accumulated_text.items),
            .allocator = allocator,
            .position = .{ .x = position_in_line, .y = 0 },
            .dom_range = .{ .start = dom_start, .end = dom_end },
        };

        std.debug.print("  Creating fragment: grouped tokens [{d}..{d}] -> text=\"{s}\" size={d} pos={d}\n", .{
            group_start_idx,
            i,
            fragment.text,
            fragment.size.x,
            fragment.position.x,
        });

        try line_boxes.appendFragmentToLastLine(fragment);
    }

    for (line_boxes.list.items) |*line| {
        line.available_width = width;
        for (line.fragments.items) |*fragment| {
            fragment.position.y = line.size.y - fragment.size.y;
        }
    }

    // Debug: Log final line boxes
    std.debug.print("\nFinal line boxes ({d} lines):\n", .{line_boxes.list.items.len});
    for (line_boxes.list.items, 0..) |line, line_idx| {
        std.debug.print("  Line {d}: {d} fragments, width={d}\n", .{ line_idx, line.fragments.items.len, line.available_width });
        for (line.fragments.items, 0..) |fragment, frag_idx| {
            std.debug.print("    Fragment {d}: text=\"{s}\" size={d} pos=({d},{d})\n", .{
                frag_idx,
                fragment.text,
                fragment.size.x,
                fragment.position.x,
                fragment.position.y,
            });
        }
    }
    std.debug.print("=== End tokensToLineBoxes Debug ===\n\n", .{});

    return line_boxes;
}
