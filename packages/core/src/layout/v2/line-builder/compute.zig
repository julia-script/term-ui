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
    wrap.wrapTokens(tokens.items, resolved_width, wrap_mode, collapse_mode);

    // Phase II: Trimming and positioning (mark hanging spaces)
    WhitespaceRules.applyPhase2Rules(tokens.items, collapse_mode);

    // Text alignment (if we have a definite width)
    TextAlignment.applyTextAlignment(tokens.items, resolved_width, text_align, collapse_mode);

    // Convert tokens to line boxes and fragments
    const line_boxes = try tokensToLineBoxes(allocator, tokens.items, resolved_width);
    return line_boxes;
}

/// Convert tokens into line boxes with fragments
/// Each token becomes a separate fragment for easier caret positioning
fn tokensToLineBoxes(allocator: std.mem.Allocator, tokens: []const Token, width: f32) !LineBox.LineBoxList {
    var line_boxes = LineBox.LineBoxList{
        .allocator = allocator,
    };
    if (tokens.len == 0) {
        return line_boxes;
    }

    var current_line_index: usize = 0;
    var i: usize = 0;

    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];
        defer current_line_index = token.line_index;
        while (current_line_index < token.line_index) : (current_line_index += 1) {
            try line_boxes.breakLine();
        }

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
        // Keep each token as a separate fragment for easier caret positioning
        try line_boxes.appendFragmentToLastLine(.{
            .text = try allocator.dupe(u8, token.text),
            .l_node_id = token.l_node_id,
            .start = token.dom_range.start,
            .length = token.dom_range.end - token.dom_range.start,
            .size = if (token.is_hanging) .{ .x = 0, .y = token.size.y } else token.size,
            .is_atomic = false,
            .allocator = allocator,
            .position = .{ .x = token.position_in_line, .y = 0 },
            .dom_range = .{ .start = token.dom_range.start, .end = token.dom_range.end },
        });
    }

    if (line_boxes.list.items.len > 1) {
        for (line_boxes.list.items) |*line| {
            line.size.x = width;
            for (line.fragments.items) |*fragment| {
                fragment.position.y = line.size.y - fragment.size.y;
            }
        }
    }

    return line_boxes;
}
