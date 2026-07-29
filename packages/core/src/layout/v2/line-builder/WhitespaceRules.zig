const std = @import("std");
const Token = @import("./Token.zig");
const Tokenizer = @import("./Tokenizer.zig");
const WhiteSpaceCollapse = @import("../../../styles/white-space.zig").WhiteSpaceCollapse;
const utf8WidthExcludingAnsiColors = @import("../../../uni/string-width.zig").utf8WidthExcludingAnsiColors;

/// Apply CSS Phase 1 whitespace collapsing rules to tokens
/// According to CSS Text Module Level 3, Section 4.3.1
pub fn applyPhase1Rules(tokens: []Token, collapse_mode: WhiteSpaceCollapse) void {
    switch (collapse_mode) {
        .collapse, .@"preserve-breaks" => {
            // Rule 1: Remove spaces/tabs immediately preceding or following a segment break
            removeSpacesAroundSegmentBreaks(tokens);

            // Rule 2: Transform collapsible segment breaks
            transformSegmentBreaks(tokens);

            // Rule 3: Convert collapsible tabs to spaces
            convertTabsToSpaces(tokens);

            // Rule 4: Collapse consecutive spaces
            if (collapse_mode == .collapse) {
                collapseConsecutiveSpaces(tokens);
            }
        },
        .@"preserve-spaces" => {
            // Convert each tab and segment break to a space
            convertTabsAndSegmentBreaksToSpaces(tokens);
        },
        .preserve => {
            // No transformation needed - preserve all whitespace as-is
        },
        .@"break-spaces" => {
            // Like preserve but with different wrapping behavior
            // No transformation needed - preserve all whitespace as-is
        },
        .inherit => unreachable, // Should be resolved by now
    }
}

/// Measure tokens after Phase 1 whitespace processing
/// This sets the size field for all tokens based on their text content
pub fn measureTokens(tokens: []Token) void {
    for (tokens) |*token| {
        switch (token.kind) {
            .text, .whitespace, .segment_break => {
                // Measure text width using utf8WidthExcludingAnsiColors
                const width = utf8WidthExcludingAnsiColors(token.text);
                token.size.x = @floatFromInt(width);

                // TODO: In the future, we'll get proper line height from font metrics
                // For now, all text has height of 1
                token.size.y = 1.0;
            },
            .atomic => {
                // Atomic nodes should already have their size set
                // Nothing to do here
            },
        }
    }
}

// Token manipulation helpers
const TokenOps = struct {
    /// Collapse token to empty (remove it visually but keep for break opportunities)
    fn collapseToEmpty(token: *Token) void {
        token.text = "";
        token.size = .{ .x = 0, .y = 0 };
    }

    /// Collapse token to a single space
    fn collapseToSpace(token: *Token) void {
        token.text = " ";
        // Size will be measured later in line breaking phase
    }

    /// Transform token text (for preserve modes where we keep the same visual width)
    fn transformTo(token: *Token, new_text: []const u8) void {
        token.text = new_text;
        // Size remains the same or will be remeasured
    }
};

/// Rule 1: Remove spaces/tabs immediately preceding or following a segment break
fn removeSpacesAroundSegmentBreaks(tokens: []Token) void {
    for (tokens, 0..) |*token, i| {
        if (token.kind == .segment_break) {
            // Remove preceding whitespace (spaces/tabs)
            if (i > 0 and tokens[i - 1].kind == .whitespace) {
                TokenOps.collapseToEmpty(&tokens[i - 1]);
            }
            // Remove following whitespace (spaces/tabs)
            if (i + 1 < tokens.len and tokens[i + 1].kind == .whitespace) {
                TokenOps.collapseToEmpty(&tokens[i + 1]);
            }
        }
    }
}

/// Rule 2: Transform segment breaks according to segment break transformation rules
fn transformSegmentBreaks(tokens: []Token) void {
    var prev_was_segment_break = false;

    for (tokens) |*token| {
        if (token.kind == .segment_break) {
            if (prev_was_segment_break) {
                // Remove consecutive segment breaks
                TokenOps.collapseToEmpty(token);
            }
            // Note: The transformation to space is already done in tokenization
            // for collapse mode. For preserve-breaks, newlines are preserved.
            prev_was_segment_break = true;
        } else {
            prev_was_segment_break = false;
        }
    }
}

/// Rule 3: Convert collapsible tabs to spaces
fn convertTabsToSpaces(tokens: []Token) void {
    for (tokens) |*token| {
        if (token.kind == .whitespace) {
            // Check if this token contains tabs
            for (token.text) |c| {
                if (c == '\t') {
                    // Tab already converted to space in tokenization for collapse mode
                    break;
                }
            }
        }
    }
}

/// Rule 4: Collapse consecutive spaces
fn collapseConsecutiveSpaces(tokens: []Token) void {
    for (tokens) |*token| {
        if (token.kind == .whitespace and token.text.len > 0) {
            // Collapse any whitespace token to a single space
            TokenOps.collapseToSpace(token);
        }
    }
}

/// For preserve-spaces mode: convert tabs and segment breaks to spaces
fn convertTabsAndSegmentBreaksToSpaces(tokens: []Token) void {
    for (tokens) |*token| {
        if (token.kind == .segment_break) {
            // Convert segment break to space for preserve-spaces mode
            TokenOps.collapseToSpace(token);
        }
    }
}

/// Phase II: Apply trimming and positioning rules after line breaking
pub fn applyPhase2Rules(tokens: []Token, collapse_mode: WhiteSpaceCollapse) void {
    // Process each line
    var current_line: ?usize = null;
    var line_start: usize = 0;
    var i: usize = 0;

    while (i < tokens.len) : (i += 1) {
        const token = &tokens[i];

        // Detect line change
        if (current_line == null or token.line_index != current_line.?) {
            // Process end of previous line if exists
            if (current_line != null and i > 0) {
                processEndOfLine(tokens[line_start..i], collapse_mode);
            }

            // Start new line
            current_line = token.line_index;
            line_start = i;

            // Process beginning of new line
            processBeginningOfLine(tokens[i..], collapse_mode);
        }
    }

    // Process end of last line
    if (current_line != null and tokens.len > 0) {
        processEndOfLine(tokens[line_start..], collapse_mode);
    }
}

/// Process beginning of line: trim if needed
fn processBeginningOfLine(line_tokens: []Token, collapse_mode: WhiteSpaceCollapse) void {
    const should_trim = switch (collapse_mode) {
        .collapse, .@"preserve-breaks" => true,
        .preserve, .@"preserve-spaces", .@"break-spaces" => false,
        .inherit => unreachable,
    };

    if (!should_trim) return;

    for (line_tokens) |*token| {
        if (token.kind == .whitespace) {
            // Remove leading whitespace
            TokenOps.collapseToEmpty(token);
        } else if (token.kind != .segment_break) {
            // Stop at first non-whitespace, non-segment-break
            break;
        }
    }
}

/// Process end of line: trim and/or mark hanging
fn processEndOfLine(line_tokens: []Token, collapse_mode: WhiteSpaceCollapse) void {
    const should_trim = switch (collapse_mode) {
        .collapse, .@"preserve-breaks" => true,
        .preserve, .@"preserve-spaces", .@"break-spaces" => false,
        .inherit => unreachable,
    };

    const should_hang = switch (collapse_mode) {
        .collapse, .@"preserve-breaks" => true, // Always hang
        .preserve, .@"preserve-spaces" => true, // Hang (conditional for preserve with forced break)
        .@"break-spaces" => false, // Never hang
        .inherit => unreachable,
    };

    // Work backwards from end of line
    var i = line_tokens.len;
    while (i > 0) {
        i -= 1;
        const token = &line_tokens[i];

        if (token.kind == .whitespace) {
            if (should_trim) {
                // Remove trailing whitespace
                TokenOps.collapseToEmpty(token);
            } else if (should_hang) {
                // Mark as hanging
                token.is_hanging = true;
            }
        } else if (token.kind != .segment_break) {
            // Also check for OGHAM SPACE MARK (U+1680)
            if (should_trim and token.kind == .text and std.mem.eql(u8, token.text, "\u{1680}")) {
                TokenOps.collapseToEmpty(token);
            } else {
                // Stop at first non-whitespace, non-segment-break
                break;
            }
        }
    }
}

// Test utilities
pub const TestHelper = struct {
    allocator: std.mem.Allocator,
    buf: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) TestHelper {
        return .{
            .allocator = allocator,
            .buf = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *TestHelper) void {
        self.buf.deinit();
    }

    /// Test tokenization helper that simulates node boundaries
    pub const TestNode = struct {
        id: u32,
        text: []const u8,
    };

    pub fn tokenizeTestNodes(
        self: *TestHelper,
        nodes: []const TestNode,
        collapse_mode: WhiteSpaceCollapse,
    ) !std.array_list.Managed(Token) {
        var tokens_unmanaged = std.ArrayList(Token).empty;
        var tokens = tokens_unmanaged.toManaged(self.allocator);

        var dom_offset: u32 = 0;

        for (nodes) |node| {
            // Direct tokenization without LineBreakStream for testing
            // This simulates what would happen with a proper integration
            try Tokenizer.tokenizeAndAppend(
                &tokens,
                node.text,
                node.id,
                .{ .start = dom_offset, .end = dom_offset + @as(u32, @intCast(node.text.len)) },
                false, // No mandatory break at end of node text
                collapse_mode,
            );

            dom_offset += @intCast(node.text.len);
        }

        return tokens;
    }

    pub fn printTokens(tokens: []const Token, writer: std.io.AnyWriter) !void {
        var prev_node_id: ?u32 = null;

        for (tokens) |tok| {

            // Show node boundary with | when node ID changes
            if (prev_node_id) |prev_id| {
                if (prev_id != tok.l_node_id) {
                    try writer.print("| ", .{});
                }
            }
            prev_node_id = tok.l_node_id;

            // Print node ID prefix
            try writer.print("N{d}:", .{tok.l_node_id});

            // Print token content
            if (tok.text.len == 0) {
                // Show empty tokens with ∅ symbol
                switch (tok.kind) {
                    .text => try writer.print("T[∅]", .{}),
                    .whitespace => try writer.print("SP[∅]", .{}),
                    .segment_break => try writer.print("LB[∅]", .{}),
                    .atomic => try writer.print("A[∅]", .{}),
                }
            } else {
                switch (tok.kind) {
                    .text => try writer.print("T[\"{s}\"]", .{tok.text}),
                    .whitespace => {
                        // Show spaces as underscores for clarity
                        var escaped = std.ArrayList(u8).init(std.testing.allocator);
                        defer escaped.deinit();

                        for (tok.text) |c| {
                            switch (c) {
                                ' ' => try escaped.append('_'),
                                '\t' => try escaped.appendSlice("\\t"),
                                else => try escaped.append(c),
                            }
                        }

                        try writer.print("SP[\"{s}\"]", .{escaped.items});
                    },
                    .segment_break => {
                        // Just show "LB" for line breaks
                        try writer.print("LB", .{});
                    },
                    .atomic => try writer.print("A[\"{s}\"]", .{tok.text}),
                }
            }

            // Print break type indicator
            const break_symbol = switch (tok.break_after) {
                .allowed => "÷",
                .prohibited => "×",
                .mandatory => "!",
            };
            try writer.print("{s} ", .{break_symbol});
        }
    }

    fn printTokensGrouped(tokens: []const Token, writer: std.io.AnyWriter) !void {
        var current_node_id: ?u32 = null;
        var first_in_group = true;

        for (tokens) |tok| {
            // Check if we need to start a new node group
            if (current_node_id == null or current_node_id.? != tok.l_node_id) {
                // Close previous group if any
                if (current_node_id != null) {
                    try writer.writeAll("} ");
                }

                // Start new group
                try writer.print("N{d}{{ ", .{tok.l_node_id});
                current_node_id = tok.l_node_id;
                first_in_group = true;
            }

            if (!first_in_group) {
                try writer.writeAll(" ");
            }
            first_in_group = false;

            // Print token content
            if (tok.text.len == 0) {
                // Show empty tokens with ∅ symbol
                switch (tok.kind) {
                    .text => try writer.print("T[∅]", .{}),
                    .whitespace => try writer.print("SP[∅]", .{}),
                    .segment_break => try writer.print("LB[∅]", .{}),
                    .atomic => try writer.print("A[∅]", .{}),
                }
            } else {
                switch (tok.kind) {
                    .text => try writer.print("T[\"{s}\"]", .{tok.text}),
                    .whitespace => {
                        // Show spaces as underscores for clarity
                        var escaped = std.ArrayList(u8).init(std.testing.allocator);
                        defer escaped.deinit();

                        for (tok.text) |c| {
                            switch (c) {
                                ' ' => try escaped.append('_'),
                                '\t' => try escaped.appendSlice("\\t"),
                                else => try escaped.append(c),
                            }
                        }

                        try writer.print("SP[\"{s}\"]", .{escaped.items});
                    },
                    .segment_break => {
                        // Just show "LB" for line breaks
                        try writer.print("LB", .{});
                    },
                    .atomic => try writer.print("A[\"{s}\"]", .{tok.text}),
                }
            }

            // Print break type indicator
            const break_symbol = switch (tok.break_after) {
                .allowed => "÷",
                .prohibited => "×",
                .mandatory => "!",
            };
            try writer.print("{s}", .{break_symbol});
        }

        // Close final group
        if (current_node_id != null) {
            try writer.writeAll("}");
        }
    }
};
