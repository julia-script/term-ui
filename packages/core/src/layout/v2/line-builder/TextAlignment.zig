const std = @import("std");
const Token = @import("Token.zig");
const css_types = @import("../../../css/types.zig");

/// Apply text alignment after line breaking and whitespace phase II
/// This adjusts the position of tokens within their lines based on the alignment mode
pub fn applyTextAlignment(
    tokens: []Token,
    line_width: f32,
    text_align: css_types.TextAlign,
    white_space_collapse: css_types.WhiteSpaceCollapse,
) void {
    // Process each line
    var current_line: usize = 0;
    var line_start: usize = 0;
    var i: usize = 0;

    while (i < tokens.len) : (i += 1) {
        const token = &tokens[i];

        // Detect line change or end
        if (current_line != token.line_index) {
            // Process previous line if exists
            alignLine(tokens[line_start..i], line_width, text_align, white_space_collapse);
            current_line = token.line_index;
            line_start = i;
        }
    }
    alignLine(tokens[line_start..], line_width, text_align, white_space_collapse);
}

/// Aligns a single line of tokens
fn alignLine(
    line_tokens: []Token,
    container_width: f32,
    text_align: css_types.TextAlign,
    white_space_collapse: css_types.WhiteSpaceCollapse,
) void {
    if (line_tokens.len == 0) return;

    // Calculate the line's content width, excluding hanging spaces
    const content_width = calculateLineContentWidth(line_tokens, white_space_collapse);

    // Calculate offset based on alignment
    const offset = calculateAlignmentOffset(content_width, container_width, text_align);

    // Apply offset to all tokens in the line
    var position: f32 = offset;
    for (line_tokens) |*token| {
        token.position_in_line = position;

        // Don't advance position for hanging tokens
        if (!token.is_hanging) {
            position += token.size.x;
        }
    }
}

/// Calculates the content width of a line, excluding hanging spaces
fn calculateLineContentWidth(
    line_tokens: []const Token,
    white_space_collapse: css_types.WhiteSpaceCollapse,
) f32 {
    _ = white_space_collapse; // Currently unused, but may be needed for future logic
    var width: f32 = 0;

    for (line_tokens) |token| {
        // Skip hanging tokens when calculating line width for alignment
        if (!token.is_hanging) {
            width += token.size.x;
        }
    }

    return width;
}

/// Calculates the offset to apply based on alignment mode
fn calculateAlignmentOffset(
    content_width: f32,
    container_width: f32,
    text_align: css_types.TextAlign,
) f32 {
    // No offset if content exceeds container
    if (content_width >= container_width) {
        return 0;
    }

    const available_space = container_width - content_width;

    return switch (text_align) {
        .left, .start => 0,
        .right, .end => available_space,
        .center => available_space / 2,
        // .justify => 0, // TODO: Implement justify spacing distribution
        .inherit => unreachable, // Should be resolved before this point
    };
}

// Test utilities
const TestHelper = @import("WhitespaceRules.zig").TestHelper;
const WhitespaceRules = @import("WhitespaceRules.zig");
