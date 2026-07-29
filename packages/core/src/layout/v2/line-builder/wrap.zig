const Token = @import("Token.zig");
const Tokenizer = @import("Tokenizer.zig");
const css_types = @import("../../../css/types.zig");
const WhitespaceRules = @import("WhitespaceRules.zig");

const std = @import("std");

const mod = @import("../mod.zig");
pub fn resolveLineWidth(tokens: []Token, available_width: mod.constants.AvailableSpace) f32 {
    switch (available_width) {
        .max_content => return computeMaxContentWidth(tokens),
        .min_content => return computeMinContentWidth(tokens),
        .definite => |width| return width,
    }
}

pub fn wrapTokens(tokens: []Token, resolved_width: f32, wrap_mode: css_types.TextWrapMode, white_space_collapse: css_types.WhiteSpaceCollapse) void {
    switch (wrap_mode) {
        .wrap => {
            wrapDefiniteWidth(tokens, resolved_width, white_space_collapse);
        },
        .nowrap => {
            wrapNoWrap(tokens);
        },
        .inherit => unreachable, // Should be resolved before this point
    }
    // switch (available_width) {
    //     .max_content => {
    //         switch (wrap_mode) {
    //             .wrap => {
    //                 wrapDefiniteWidth(tokens, std.math.floatMax(f32), white_space_collapse);
    //             },
    //             .nowrap => {
    //                 wrapNoWrap(tokens);
    //             },
    //             .inherit => unreachable, // Should be resolved before this point
    //         }
    //     },
    //     .min_content => {
    //         switch (wrap_mode) {
    //             .wrap => {
    //                 const min_width = computeMinContentWidth(tokens);
    //                 wrapDefiniteWidth(tokens, min_width, white_space_collapse);
    //             },
    //             .nowrap => {
    //                 wrapNoWrap(tokens);
    //             },
    //             .inherit => unreachable, // Should be resolved before this point
    //         }
    //     },
    //     .definite => |width| {
    //         switch (wrap_mode) {
    //             .wrap => {
    //                 wrapDefiniteWidth(tokens, width, white_space_collapse);
    //             },
    //             .nowrap => {
    //                 wrapNoWrap(tokens);
    //             },
    //             .inherit => unreachable, // Should be resolved before this point
    //         }
    //     },
    // }
}

/// Computes the min-content width by finding the widest unbreakable group
/// (tokens connected by prohibited breaks), excluding trailing whitespace
fn computeMinContentWidth(tokens: []const Token) f32 {
    var max_width: f32 = 0;
    var i: usize = 0;

    while (i < tokens.len) {
        // Skip leading whitespace and segment breaks
        while (i < tokens.len and (tokens[i].kind == .whitespace or tokens[i].kind == .segment_break)) {
            i += 1;
        }

        if (i >= tokens.len) break;

        // Start measuring a group
        var group_width: f32 = 0;
        var last_non_whitespace_end = i;
        var width_at_last_non_whitespace: f32 = 0;

        // Collect tokens until we hit a non-prohibited break
        while (i < tokens.len) {
            const token = tokens[i];

            // Add token width
            group_width += token.size.x;

            // Track last non-whitespace position
            if (token.kind != .whitespace and token.kind != .segment_break) {
                last_non_whitespace_end = i + 1;
                width_at_last_non_whitespace = group_width;
            }

            // Check if we can break after this token
            if (token.break_after != .prohibited) {
                break;
            }

            i += 1;
        }

        // Use width up to last non-whitespace token
        max_width = @max(max_width, width_at_last_non_whitespace);

        // Move to next token
        if (i < tokens.len) {
            i += 1;
        }
    }

    return max_width;
}

fn computeMaxContentWidth(tokens: []const Token) f32 {
    var max_width: f32 = 0;
    var current_width: f32 = 0;
    for (tokens) |token| {
        current_width += token.size.x;
        if (token.break_after == .mandatory) {
            max_width = @max(max_width, current_width);
            current_width = 0;
        }
    }
    return @max(max_width, current_width);
}

/// Nowrap mode: only break on mandatory breaks (newlines)
fn wrapNoWrap(tokens: []Token) void {
    var line_index: usize = 0;

    for (tokens) |*token| {
        token.line_index = line_index;

        // Only increment line index on mandatory breaks
        if (token.break_after == .mandatory) {
            line_index += 1;
        }
    }
}

/// Determines if end-of-line spaces should hang based on white-space mode
fn shouldHangEndSpaces(collapse_mode: css_types.WhiteSpaceCollapse) bool {
    return switch (collapse_mode) {
        // From the table: "Remove" means they were already removed in Phase I
        // but any remaining spaces at EOL should hang
        .collapse, .@"preserve-breaks" => true,
        // "Hang" in the table (pre-wrap mode)
        .preserve => true,
        // preserve-spaces should hang like preserve
        .@"preserve-spaces" => true,
        // "Preserve" means no hanging - spaces take up space and can wrap
        .@"break-spaces" => false,
        .inherit => unreachable, // Should be resolved before this point
    };
}

pub fn wrapDefiniteWidth(tokens: []Token, width: f32, white_space_collapse: css_types.WhiteSpaceCollapse) void {
    var line_width: f32 = 0;
    var line_index: usize = 0;
    const should_hang = shouldHangEndSpaces(white_space_collapse);

    var i: usize = 0;
    while (i < tokens.len) : (i += 1) {
        const token = tokens[i];
        switch (token.kind) {
            .text, .atomic => {
                // Build a group of tokens with prohibited breaks
                const start_index = i;
                var group_width: f32 = 0;
                var hanging_width: f32 = 0;

                var j: usize = i;

                // Accumulate the group, tracking non-whitespace width
                while (j < tokens.len) {
                    const tok = tokens[j];
                    group_width += tok.size.x;

                    if (should_hang) {
                        if (tok.kind != .whitespace and tok.kind != .segment_break) {
                            hanging_width = 0;
                            // This is non-whitespace, so update our non-trailing width
                            // group_width_without_trailing_spaces = group_width;
                            // last_non_whitespace_width = group_width;
                        } else {
                            hanging_width += tok.size.x;
                        }
                    }

                    j += 1;
                    // Stop if we can break after this token
                    if (tok.break_after != .prohibited) break;
                }

                // For hanging calculation, we need to check if adding this group would overflow
                // const effective_line_width = if (should_hang) line_width_without_trailing_spaces else line_width;
                // const effective_group_width = if (should_hang) group_width_without_trailing_spaces else group_width;

                if (line_width + group_width - hanging_width > width and line_width > 0) {
                    // Wrap to next line
                    line_index += 1;
                    line_width = 0;
                    // line_width_without_trailing_spaces = 0;
                }

                // Place tokens on current line
                for (start_index..j) |k| {
                    tokens[k].line_index = line_index;
                }

                // Update line widths
                line_width += group_width;

                i = j - 1;
            },
            .whitespace => {
                tokens[i].line_index = line_index;
                line_width += token.size.x;
            },
            .segment_break => {
                tokens[i].line_index = line_index;
                // Segment breaks have no width
            },
        }

        if (token.break_after == .mandatory) {
            line_index += 1;
            line_width = 0;
        }
    }
}

pub const TestHelper = struct {};
