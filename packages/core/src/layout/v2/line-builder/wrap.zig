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

const snapshot = @import("../../../tests/utils/snapshot.zig");

pub const TestHelper = struct {
    pub fn testWrap(
        comptime name: []const u8,
        nodes: []const WhitespaceRules.TestHelper.TestNode,
        collapse_mode: css_types.WhiteSpaceCollapse,
        wrap_mode: css_types.TextWrapMode,
        available_width: mod.constants.AvailableSpace,
        comptime src: std.builtin.SourceLocation,
    ) !void {
        var helper = WhitespaceRules.TestHelper.init(std.testing.allocator);
        defer helper.deinit();

        var tokens = try helper.tokenizeTestNodes(nodes, collapse_mode);
        defer tokens.deinit();

        // Apply whitespace rules and measure
        WhitespaceRules.applyPhase1Rules(tokens.items, collapse_mode);
        WhitespaceRules.measureTokens(tokens.items);

        // Apply wrapping
        const resolved_width = resolveLineWidth(tokens.items, available_width);
        wrapTokens(tokens.items, resolved_width, wrap_mode, collapse_mode);

        // Build output for snapshot
        var output = std.ArrayList(u8).init(std.testing.allocator);
        defer output.deinit();
        const writer = output.writer().any();

        // Header with parameters
        try writer.print("Wrap test: collapse_mode={s}, wrap_mode={s}, width=", .{
            @tagName(collapse_mode),
            @tagName(wrap_mode),
        });
        switch (available_width) {
            .definite => |w| try writer.print("{d}", .{w}),
            .max_content => try writer.writeAll("max-content"),
            .min_content => try writer.writeAll("min-content"),
        }
        try writer.writeAll("\n\n");

        // Token details
        try writer.writeAll("Tokens after wrapping:\n");
        for (tokens.items, 0..) |token, i| {
            if (token.kind == .segment_break) {
                try writer.print("  [{d}] Line {d}: segment_break (mandatory) (width={d:.1})\n", .{
                    i,
                    token.line_index,
                    token.size.x,
                });
            } else if (token.text.len > 0) {
                try writer.print("  [{d}] Line {d}: {s} \"{s}\" (width={d:.1})\n", .{
                    i,
                    token.line_index,
                    @tagName(token.kind),
                    token.text,
                    token.size.x,
                });
            }
        }
        try writer.writeAll("\n");

        // Rendered lines
        try writer.writeAll("Rendered lines:\n");
        var current_line: usize = 0;
        var line_width: f32 = 0;
        var line_start = true;

        for (tokens.items) |token| {
            if (token.line_index != current_line) {
                if (!line_start) {
                    try writer.print(" (width={d:.1})\n", .{line_width});
                }
                current_line = token.line_index;
                line_width = 0;
                line_start = true;
            }

            if (line_start) {
                try writer.print("  Line {d}: ", .{current_line});
                line_start = false;
            }

            try writer.print("{s}", .{token.text});
            line_width += token.size.x;
        }

        if (!line_start) {
            try writer.print(" (width={d:.1})\n", .{line_width});
        }

        try snapshot.expectMatchSnapshot(
            src,
            std.testing.allocator,
            name,
            output.items,
            .{},
        );
    }
};

test "wrap basic text" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Hello" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "world" },
        .{ .id = 4, .text = " " },
        .{ .id = 5, .text = "this" },
        .{ .id = 6, .text = " " },
        .{ .id = 7, .text = "is" },
        .{ .id = 8, .text = " " },
        .{ .id = 9, .text = "text" },
    };

    try TestHelper.testWrap(
        "wrap basic text",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 12 },
        @src(),
    );
}

test "wrap long word" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Supercalifragilisticexpialidocious" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "word" },
    };

    try TestHelper.testWrap(
        "wrap long word",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 20 },
        @src(),
    );
}

test "wrap with newlines" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Line one" },
        .{ .id = 2, .text = "\n" },
        .{ .id = 3, .text = "Line two is longer" },
        .{ .id = 4, .text = "\n" },
        .{ .id = 5, .text = "Line three" },
    };

    try TestHelper.testWrap(
        "wrap with newlines",
        &nodes,
        .@"preserve-breaks",
        .wrap,
        .{ .definite = 50 },
        @src(),
    );
}

test "wrap edge cases" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "" },
        .{ .id = 2, .text = "exactfit" }, // 8 chars
        .{ .id = 3, .text = " " },
        .{ .id = 4, .text = "a" },
    };

    try TestHelper.testWrap(
        "wrap edge cases",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 8 },
        @src(),
    );
}

test "wrap max-content" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "This should all stay on one line no matter how long it is" },
    };

    try TestHelper.testWrap(
        "wrap max-content",
        &nodes,
        .collapse,
        .wrap,
        .max_content,
        @src(),
    );
}

test "wrap narrow width" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "a" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "b" },
        .{ .id = 4, .text = " " },
        .{ .id = 5, .text = "c" },
    };

    try TestHelper.testWrap(
        "wrap narrow width",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 2 },
        @src(),
    );
}

test "wrap preserve spaces" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Hello  " },
        .{ .id = 2, .text = "  world" },
        .{ .id = 3, .text = "  " },
        .{ .id = 4, .text = "test" },
    };

    try TestHelper.testWrap(
        "wrap preserve spaces",
        &nodes,
        .@"preserve-spaces",
        .wrap,
        .{ .definite = 15 },
        @src(),
    );
}

test "wrap mixed whitespace types" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Word" },
        .{ .id = 2, .text = "\t" },
        .{ .id = 3, .text = "with" },
        .{ .id = 4, .text = "  " },
        .{ .id = 5, .text = "spaces" },
        .{ .id = 6, .text = "\n" },
        .{ .id = 7, .text = "newline" },
    };

    try TestHelper.testWrap(
        "wrap mixed whitespace types",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 20 },
        @src(),
    );
}

test "wrap fragment boundaries" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Fragment" },
        .{ .id = 2, .text = "boundary" },
        .{ .id = 3, .text = " " },
        .{ .id = 4, .text = "test" },
    };

    try TestHelper.testWrap(
        "wrap fragment boundaries",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 20 },
        @src(),
    );
}

test "wrap consecutive spaces collapse" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Multiple" },
        .{ .id = 2, .text = "   " },
        .{ .id = 3, .text = "   " },
        .{ .id = 4, .text = "spaces" },
    };

    try TestHelper.testWrap(
        "wrap consecutive spaces collapse",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 15 },
        @src(),
    );
}

test "wrap pre mode with long lines" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "This   is   pre   formatted   text" },
        .{ .id = 2, .text = "\n" },
        .{ .id = 3, .text = "With    spaces    preserved" },
    };

    try TestHelper.testWrap(
        "wrap pre mode with long lines",
        &nodes,
        .preserve,
        .wrap,
        .{ .definite = 20 },
        @src(),
    );
}

test "wrap zero width" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Test" },
    };

    try TestHelper.testWrap(
        "wrap zero width",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 0 },
        @src(),
    );
}

test "wrap single character per line" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "ABCD" },
    };

    try TestHelper.testWrap(
        "wrap single character per line",
        &nodes,
        .collapse,
        .wrap,
        .{ .definite = 1 },
        @src(),
    );
}

test "wrap with trailing whitespace" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Word " },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "\n" },
        .{ .id = 4, .text = "Next" },
    };

    try TestHelper.testWrap(
        "wrap with trailing whitespace",
        &nodes,
        .@"preserve-breaks",
        .wrap,
        .{ .definite = 10 },
        @src(),
    );
}

test "wrap min-content basic" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Hello" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "world" },
        .{ .id = 4, .text = " " },
        .{ .id = 5, .text = "this" },
        .{ .id = 6, .text = " " },
        .{ .id = 7, .text = "is" },
        .{ .id = 8, .text = " " },
        .{ .id = 9, .text = "text" },
    };

    try TestHelper.testWrap(
        "wrap min-content basic",
        &nodes,
        .collapse,
        .wrap,
        .min_content,
        @src(),
    );
}

test "wrap min-content with long word" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Short" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "Supercalifragilisticexpialidocious" },
        .{ .id = 4, .text = " " },
        .{ .id = 5, .text = "word" },
    };

    try TestHelper.testWrap(
        "wrap min-content with long word",
        &nodes,
        .collapse,
        .wrap,
        .min_content,
        @src(),
    );
}

test "wrap min-content with trailing spaces" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Word" },
        .{ .id = 2, .text = "    " }, // Multiple trailing spaces
        .{ .id = 3, .text = "Next" },
        .{ .id = 4, .text = " " },
        .{ .id = 5, .text = "Line" },
    };

    try TestHelper.testWrap(
        "wrap min-content with trailing spaces",
        &nodes,
        .@"preserve-spaces",
        .wrap,
        .min_content,
        @src(),
    );
}

test "wrap min-content with newlines" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "First line is long" },
        .{ .id = 2, .text = "\n" },
        .{ .id = 3, .text = "Short" },
        .{ .id = 4, .text = "\n" },
        .{ .id = 5, .text = "Medium length line" },
    };

    try TestHelper.testWrap(
        "wrap min-content with newlines",
        &nodes,
        .@"preserve-breaks",
        .wrap,
        .min_content,
        @src(),
    );
}

test "nowrap mode basic" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "This is a very long line that should not wrap even though it exceeds the available width" },
    };

    try TestHelper.testWrap(
        "nowrap mode basic",
        &nodes,
        .collapse,
        .nowrap,
        .{ .definite = 20 },
        @src(),
    );
}

test "nowrap mode with newlines" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "First line that is very long and exceeds width" },
        .{ .id = 2, .text = "\n" },
        .{ .id = 3, .text = "Second line also long" },
        .{ .id = 4, .text = "\n" },
        .{ .id = 5, .text = "Third" },
    };

    try TestHelper.testWrap(
        "nowrap mode with newlines",
        &nodes,
        .@"preserve-breaks",
        .nowrap,
        .{ .definite = 10 },
        @src(),
    );
}

test "nowrap mode with spaces" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Word" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "after" },
        .{ .id = 4, .text = " " },
        .{ .id = 5, .text = "word" },
        .{ .id = 6, .text = " " },
        .{ .id = 7, .text = "should" },
        .{ .id = 8, .text = " " },
        .{ .id = 9, .text = "not" },
        .{ .id = 10, .text = " " },
        .{ .id = 11, .text = "wrap" },
    };

    try TestHelper.testWrap(
        "nowrap mode with spaces",
        &nodes,
        .collapse,
        .nowrap,
        .{ .definite = 5 },
        @src(),
    );
}

test "nowrap with max-content" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "This should stay on one line" },
        .{ .id = 2, .text = "\n" },
        .{ .id = 3, .text = "This is the second line" },
    };

    try TestHelper.testWrap(
        "nowrap with max-content",
        &nodes,
        .@"preserve-breaks",
        .nowrap,
        .max_content,
        @src(),
    );
}

test "nowrap with min-content" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Supercalifragilisticexpialidocious" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "word" },
        .{ .id = 4, .text = "\n" },
        .{ .id = 5, .text = "Next line" },
    };

    try TestHelper.testWrap(
        "nowrap with min-content",
        &nodes,
        .@"preserve-breaks",
        .nowrap,
        .min_content,
        @src(),
    );
}

test "hanging spaces with normal white-space" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Hello" },
        .{ .id = 2, .text = "   " }, // 3 spaces (will collapse to 1)
        .{ .id = 3, .text = "world" },
        .{ .id = 4, .text = "   " }, // trailing spaces
    };

    try TestHelper.testWrap(
        "hanging spaces with normal white-space",
        &nodes,
        .collapse, // normal white-space
        .wrap,
        .{ .definite = 10 }, // Should fit: "Hello" + " " + "world" = 11, but only 10 given
        @src(),
    );
}

test "no hanging with break-spaces" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Hello" },
        .{ .id = 2, .text = "     " }, // 5 spaces
        .{ .id = 3, .text = "world" },
    };

    try TestHelper.testWrap(
        "no hanging with break-spaces",
        &nodes,
        .@"break-spaces",
        .wrap,
        .{ .definite = 11 }, // Should wrap because spaces count
        @src(),
    );
}

test "hanging with pre-wrap" {
    const nodes = [_]WhitespaceRules.TestHelper.TestNode{
        .{ .id = 1, .text = "Line" },
        .{ .id = 2, .text = "   " }, // 3 spaces
        .{ .id = 3, .text = "one" },
        .{ .id = 4, .text = "  " }, // 2 spaces
        .{ .id = 5, .text = "\n" },
        .{ .id = 6, .text = "Next" },
    };

    try TestHelper.testWrap(
        "hanging with pre-wrap",
        &nodes,
        .preserve, // pre-wrap
        .wrap,
        .{ .definite = 10 },
        @src(),
    );
}
