const std = @import("std");
const Token = @import("./Token.zig");
const Tokenizer = @import("./Tokenizer.zig");
const WhiteSpaceCollapse = @import("../../../styles/white-space.zig").WhiteSpaceCollapse;
const snapshot = @import("../../../testing/snapshot.zig");
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
    ) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(self.allocator);

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

    fn testPhase1(
        self: *TestHelper,
        comptime name: []const u8,
        tokens: []Token,
        collapse_mode: WhiteSpaceCollapse,
        comptime src: std.builtin.SourceLocation,
    ) !void {
        self.buf.clearRetainingCapacity();
        const writer = self.buf.writer().any();

        // Add legend
        try writer.writeAll("Legend:\n");
        try writer.writeAll("  Token types: T = Text, SP = Space, LB = LineBreak\n");
        try writer.writeAll("  Break types: × = NoBreak, ÷ = BreakAllowed, ! = MandatoryBreak\n");
        try writer.writeAll("  Characters: _ = Space, \\t = Tab\n");
        try writer.print("  White-space: {s}\n\n", .{@tagName(collapse_mode)});

        try writer.writeAll("Input: ");
        try printTokensGrouped(tokens, writer);

        applyPhase1Rules(tokens, collapse_mode);

        try writer.writeAll("\nOutput: ");
        try printTokensGrouped(tokens, writer);

        try snapshot.expectMatchSnapshot(src, self.allocator, name, self.buf.items);
    }

    fn testAllModes(
        self: *TestHelper,
        comptime name: []const u8,
        nodes: []const TestNode,
        comptime src: std.builtin.SourceLocation,
    ) !void {
        self.buf.clearRetainingCapacity();
        const writer = self.buf.writer().any();

        // Add legend
        try writer.writeAll("Legend:\n");
        try writer.writeAll("  Token types: T = Text, SP = Space, LB = LineBreak\n");
        try writer.writeAll("  Break types: × = NoBreak, ÷ = BreakAllowed, ! = MandatoryBreak\n");
        try writer.writeAll("  Characters: _ = Space, \\t = Tab\n\n");

        const modes = [_]WhiteSpaceCollapse{
            .collapse,
            .@"preserve-breaks",
            .@"preserve-spaces",
            .preserve,
            .@"break-spaces",
        };

        for (modes) |mode| {
            try writer.print("=== White-space: {s} ===\n", .{@tagName(mode)});

            // Tokenize for this mode
            var tokens = try self.tokenizeTestNodes(nodes, mode);
            defer tokens.deinit();

            // Make a copy for phase 1 application
            var tokens_copy = try std.ArrayList(Token).initCapacity(self.allocator, tokens.items.len);
            defer tokens_copy.deinit();
            for (tokens.items) |tok| {
                try tokens_copy.append(tok);
            }

            try writer.writeAll("Input:  ");
            try printTokensGrouped(tokens.items, writer);

            applyPhase1Rules(tokens_copy.items, mode);

            try writer.writeAll("\nOutput: ");
            try printTokensGrouped(tokens_copy.items, writer);
            try writer.writeAll("\n\n");
        }

        try snapshot.expectMatchSnapshot(src, self.allocator, name, self.buf.items);
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

test "All modes: Remove spaces around segment breaks" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test spaces around segment breaks
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello   \n   world" },
    };

    try helper.testAllModes("remove spaces around segment breaks", &nodes, @src());
}

test "All modes: Collapse consecutive segment breaks" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "line1\n\n\nline2" },
    };

    try helper.testAllModes("collapse consecutive segment breaks", &nodes, @src());
}

test "All modes: Collapse consecutive spaces" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello   world" }, // Three spaces
    };

    try helper.testAllModes("collapse consecutive spaces", &nodes, @src());
}

test "All modes: Tab and newline handling" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello\t\n world" },
    };

    try helper.testAllModes("tab and newline handling", &nodes, @src());
}

test "All modes: Spaces around preserved breaks" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello   \n   world" },
    };

    try helper.testAllModes("spaces around preserved breaks", &nodes, @src());
}

test "All modes: Complex mixed whitespace sequence" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "start  \t\n\n\t  end" },
    };

    try helper.testAllModes("complex mixed whitespace sequence", &nodes, @src());
}

test "All modes: Tokenizer grouping of mixed whitespace" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test how different modes group spaces, tabs, and newlines
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello  \t\n  world" },
    };

    try helper.testAllModes("tokenizer grouping of mixed whitespace", &nodes, @src());
}

test "All modes: Multiple whitespace types in sequence" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test different sequences of spaces, tabs, and newlines
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "a  b\t\tc\n\nd  \t\n  e" },
    };

    try helper.testAllModes("multiple whitespace types in sequence", &nodes, @src());
}

test "All modes: Whitespace at text boundaries" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test whitespace at start, middle, and end
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "  \tstart middle\t\n  end  \n" },
    };

    try helper.testAllModes("whitespace at text boundaries", &nodes, @src());
}

test "Node boundaries prevent whitespace grouping" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Simulate: "hello  "<b>" world"</b> - spaces from different nodes aren't grouped
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello  " }, // Text node with trailing spaces
        .{ .id = 2, .text = " world" }, // Bold node with leading space
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    try helper.testPhase1("node boundaries prevent grouping", tokens.items, .collapse, @src());
}

test "Whitespace collapsing across multiple nodes" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Simulate: "start "<em>"  middle  "</em>" end"
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "start " },
        .{ .id = 2, .text = "  middle  " }, // em node
        .{ .id = 3, .text = " end" },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    try helper.testPhase1("whitespace across multiple nodes", tokens.items, .collapse, @src());
}

test "Tokenizer groups collapsible whitespace with newlines" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test that in collapse mode, spaces+newline+spaces are grouped together
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello   \n   world" },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    try helper.testPhase1("tokenizer groups whitespace with newlines", tokens.items, .collapse, @src());
}

test "All modes: Cross-node boundary segment break" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test spaces around segment breaks across node boundaries
    // Simulate: "hello  "<br/><span>"\n  world"</span>
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello  " },
        .{ .id = 2, .text = "\n  world" },
    };

    try helper.testAllModes("cross-node boundary segment break", &nodes, @src());
}

test "Phase 1: Adjacent whitespace from different nodes" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test that adjacent whitespace tokens from different nodes both get collapsed
    // Simulate: "hello  "<em>"  "</em>"world"
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello  " },
        .{ .id = 2, .text = "  " }, // em node with just spaces
        .{ .id = 3, .text = "world" },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    try helper.testPhase1("adjacent whitespace from different nodes", tokens.items, .collapse, @src());
}

test "All modes: Complex text with newlines and tabs" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test how different white-space modes handle complex whitespace
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "hello  \t" },
        .{ .id = 2, .text = "\n  world\t\n" },
        .{ .id = 3, .text = "  end" },
    };

    try helper.testAllModes("all modes complex whitespace", &nodes, @src());
}

test "Measure tokens after Phase 1" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test measuring various text content
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Hello" },
        .{ .id = 2, .text = "  " },
        .{ .id = 3, .text = "World" },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    // Apply Phase 1 rules
    applyPhase1Rules(tokens.items, .collapse);

    // Measure tokens
    measureTokens(tokens.items);

    // Create snapshot with measured tokens
    var output = std.ArrayList(u8).init(helper.allocator);
    defer output.deinit();

    try output.appendSlice("Tokens after measurement:\n");
    for (tokens.items, 0..) |token, i| {
        try output.writer().print("Token {d}: kind={s}, text=\"{s}\", size=({d:.1}, {d:.1})\n", .{
            i,
            @tagName(token.kind),
            token.text,
            token.size.x,
            token.size.y,
        });
    }

    try snapshot.expectMatchSnapshot(
        @src(),
        helper.allocator,
        "measure tokens basic",
        output.items,
    );
}

test "Measure tokens with unicode" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test measuring unicode content
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Hello😀" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "中文" },
        .{ .id = 4, .text = "\t" },
        .{ .id = 5, .text = "café" },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    // Apply Phase 1 rules
    applyPhase1Rules(tokens.items, .collapse);

    // Measure tokens
    measureTokens(tokens.items);

    // Create snapshot with measured tokens
    var output = std.ArrayList(u8).init(helper.allocator);
    defer output.deinit();

    try output.appendSlice("Unicode tokens after measurement:\n");
    for (tokens.items, 0..) |token, i| {
        try output.writer().print("Token {d}: kind={s}, text=\"{s}\", size=({d:.1}, {d:.1})\n", .{
            i,
            @tagName(token.kind),
            token.text,
            token.size.x,
            token.size.y,
        });
    }

    try snapshot.expectMatchSnapshot(
        @src(),
        helper.allocator,
        "measure tokens unicode",
        output.items,
    );
}

test "Measure tokens with empty content" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    // Test measuring tokens that become empty after Phase 1
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "text" },
        .{ .id = 2, .text = " \n " }, // Will become empty after Phase 1
        .{ .id = 3, .text = "more" },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    // Apply Phase 1 rules
    applyPhase1Rules(tokens.items, .collapse);

    // Measure tokens
    measureTokens(tokens.items);

    // Create snapshot with measured tokens
    var output = std.ArrayList(u8).init(helper.allocator);
    defer output.deinit();

    try output.appendSlice("Tokens with empty content after measurement:\n");
    for (tokens.items, 0..) |token, i| {
        if (token.text.len == 0) {
            try output.writer().print("Token {d}: kind={s}, text=(empty), size=({d:.1}, {d:.1})\n", .{
                i,
                @tagName(token.kind),
                token.size.x,
                token.size.y,
            });
        } else {
            try output.writer().print("Token {d}: kind={s}, text=\"{s}\", size=({d:.1}, {d:.1})\n", .{
                i,
                @tagName(token.kind),
                token.text,
                token.size.x,
                token.size.y,
            });
        }
    }

    try snapshot.expectMatchSnapshot(
        @src(),
        helper.allocator,
        "measure tokens empty",
        output.items,
    );
}

test "Phase 2: Trim beginning and end of lines" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "  " },
        .{ .id = 2, .text = "First" },
        .{ .id = 3, .text = "  " },
        .{ .id = 4, .text = "\n" },
        .{ .id = 5, .text = "  " },
        .{ .id = 6, .text = "Second" },
        .{ .id = 7, .text = "  " },
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .@"preserve-breaks");
    defer tokens.deinit();

    // Apply Phase 1
    applyPhase1Rules(tokens.items, .@"preserve-breaks");
    measureTokens(tokens.items);

    // Simulate line breaking - put newline on line 0, rest on line 1
    tokens.items[0].line_index = 0; // leading space
    tokens.items[1].line_index = 0; // "First"
    tokens.items[2].line_index = 0; // trailing space
    tokens.items[3].line_index = 0; // newline
    tokens.items[4].line_index = 1; // leading space
    tokens.items[5].line_index = 1; // "Second"
    tokens.items[6].line_index = 1; // trailing space

    // Apply Phase 2
    applyPhase2Rules(tokens.items, .@"preserve-breaks");

    // Check that leading/trailing spaces are removed
    try std.testing.expectEqualStrings("", tokens.items[0].text); // Leading space line 0
    try std.testing.expectEqualStrings("First", tokens.items[1].text);
    try std.testing.expectEqualStrings("", tokens.items[2].text); // Trailing space line 0
    try std.testing.expectEqualStrings("", tokens.items[4].text); // Leading space line 1
    try std.testing.expectEqualStrings("Second", tokens.items[5].text);
    try std.testing.expectEqualStrings("", tokens.items[6].text); // Trailing space line 1
}

test "Phase 2: Mark hanging spaces" {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Text" },
        .{ .id = 2, .text = "   " }, // Trailing spaces
        .{ .id = 3, .text = "\n" },
        .{ .id = 4, .text = "More" },
        .{ .id = 5, .text = "  " }, // Trailing spaces
    };

    var tokens = try helper.tokenizeTestNodes(&nodes, .preserve);
    defer tokens.deinit();

    // Apply Phase 1
    applyPhase1Rules(tokens.items, .preserve);
    measureTokens(tokens.items);

    // Simulate line breaking
    tokens.items[0].line_index = 0; // "Text"
    tokens.items[1].line_index = 0; // trailing spaces
    tokens.items[2].line_index = 0; // newline
    tokens.items[3].line_index = 1; // "More"
    tokens.items[4].line_index = 1; // trailing spaces

    // Apply Phase 2
    applyPhase2Rules(tokens.items, .preserve);

    // Check that trailing spaces are marked as hanging
    try std.testing.expect(!tokens.items[0].is_hanging); // Text - not hanging
    try std.testing.expect(tokens.items[1].is_hanging); // Trailing spaces - hanging
    try std.testing.expect(!tokens.items[2].is_hanging); // Newline - not hanging
    try std.testing.expect(!tokens.items[3].is_hanging); // More - not hanging
    try std.testing.expect(tokens.items[4].is_hanging); // Trailing spaces - hanging
}
