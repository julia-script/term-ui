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
const snapshot = @import("../../../tests/utils/snapshot.zig");

pub fn testAlignment(
    comptime name: []const u8,
    nodes: []const TestHelper.TestNode,
    collapse_mode: css_types.WhiteSpaceCollapse,
    text_align: css_types.TextAlign,
    line_width: f32,
    comptime src: std.builtin.SourceLocation,
) !void {
    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(nodes, collapse_mode);
    defer tokens.deinit();

    // Apply Phase 1: Whitespace collapse/transformation
    WhitespaceRules.applyPhase1Rules(tokens.items, collapse_mode);
    WhitespaceRules.measureTokens(tokens.items);

    // Simulate line breaking - for testing, we'll manually set line indices
    // In real usage, this would be done by the wrap module

    // Apply Phase 2: Trimming and marking hanging
    WhitespaceRules.applyPhase2Rules(tokens.items, collapse_mode);

    // Apply Phase 3: Text alignment
    applyTextAlignment(tokens.items, line_width, text_align, collapse_mode);

    // Build output for snapshot
    var output = std.ArrayList(u8).init(std.testing.allocator);
    defer output.deinit();
    const writer = output.writer().any();

    // Header
    try writer.print("Text alignment test: collapse_mode={s}, text_align={s}, width={d}\n\n", .{
        @tagName(collapse_mode),
        @tagName(text_align),
        line_width,
    });

    // Token details with positions
    try writer.writeAll("Tokens with positions:\n");
    var current_line: ?usize = null;
    for (tokens.items, 0..) |token, i| {
        if (current_line == null or token.line_index != current_line.?) {
            current_line = token.line_index;
            try writer.print("\nLine {d}:\n", .{current_line.?});
        }

        if (token.text.len > 0 or token.kind == .segment_break) {
            try writer.print("  [{d}] pos={d:.1} width={d:.1} {s}{s} \"{s}\"\n", .{
                i,
                token.position_in_line,
                token.size.x,
                @tagName(token.kind),
                if (token.is_hanging) " (hanging)" else "",
                token.text,
            });
        }
    }

    try snapshot.expectMatchSnapshot(
        src,
        std.testing.allocator,
        name,
        output.items,
        .{},
    );
}

test "left alignment" {
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Left" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "aligned" },
    };

    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    WhitespaceRules.applyPhase1Rules(tokens.items, .collapse);
    WhitespaceRules.measureTokens(tokens.items);

    // All on line 0
    for (tokens.items) |*token| {
        token.line_index = 0;
    }

    WhitespaceRules.applyPhase2Rules(tokens.items, .collapse);

    try testAlignment(
        "left alignment",
        &nodes,
        .collapse,
        .left,
        50,
        @src(),
    );
}

test "right alignment" {
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Right" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "aligned" },
    };

    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    WhitespaceRules.applyPhase1Rules(tokens.items, .collapse);
    WhitespaceRules.measureTokens(tokens.items);

    // All on line 0
    for (tokens.items) |*token| {
        token.line_index = 0;
    }

    WhitespaceRules.applyPhase2Rules(tokens.items, .collapse);

    try testAlignment(
        "right alignment",
        &nodes,
        .collapse,
        .right,
        50,
        @src(),
    );
}

test "center alignment" {
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Center" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "me" },
    };

    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    WhitespaceRules.applyPhase1Rules(tokens.items, .collapse);
    WhitespaceRules.measureTokens(tokens.items);

    // All on line 0
    for (tokens.items) |*token| {
        token.line_index = 0;
    }

    WhitespaceRules.applyPhase2Rules(tokens.items, .collapse);

    try testAlignment(
        "center alignment",
        &nodes,
        .collapse,
        .center,
        50,
        @src(),
    );
}

test "alignment with hanging spaces" {
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "Text" },
        .{ .id = 2, .text = "    " }, // Trailing spaces that should hang
    };

    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(&nodes, .preserve);
    defer tokens.deinit();

    WhitespaceRules.applyPhase1Rules(tokens.items, .preserve);
    WhitespaceRules.measureTokens(tokens.items);

    // All on line 0
    for (tokens.items) |*token| {
        token.line_index = 0;
    }

    WhitespaceRules.applyPhase2Rules(tokens.items, .preserve);

    try testAlignment(
        "alignment with hanging spaces",
        &nodes,
        .preserve,
        .center,
        20,
        @src(),
    );
}

test "alignment with multiple lines" {
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "First" },
        .{ .id = 2, .text = " " },
        .{ .id = 3, .text = "line" },
        .{ .id = 4, .text = "\n" },
        .{ .id = 5, .text = "Second" },
    };

    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(&nodes, .@"preserve-breaks");
    defer tokens.deinit();

    WhitespaceRules.applyPhase1Rules(tokens.items, .@"preserve-breaks");
    WhitespaceRules.measureTokens(tokens.items);

    // Simulate line breaking
    tokens.items[0].line_index = 0; // "First"
    tokens.items[1].line_index = 0; // " "
    tokens.items[2].line_index = 0; // "line"
    tokens.items[3].line_index = 0; // "\n"
    tokens.items[4].line_index = 1; // "Second"

    WhitespaceRules.applyPhase2Rules(tokens.items, .@"preserve-breaks");

    try testAlignment(
        "alignment with multiple lines",
        &nodes,
        .@"preserve-breaks",
        .right,
        30,
        @src(),
    );
}

test "no alignment when content exceeds width" {
    const nodes = [_]TestHelper.TestNode{
        .{ .id = 1, .text = "This is a very long line that exceeds the container width" },
    };

    var helper = TestHelper.init(std.testing.allocator);
    defer helper.deinit();

    var tokens = try helper.tokenizeTestNodes(&nodes, .collapse);
    defer tokens.deinit();

    WhitespaceRules.applyPhase1Rules(tokens.items, .collapse);
    WhitespaceRules.measureTokens(tokens.items);

    // All on line 0
    for (tokens.items) |*token| {
        token.line_index = 0;
    }

    WhitespaceRules.applyPhase2Rules(tokens.items, .collapse);

    try testAlignment(
        "no alignment when content exceeds width",
        &nodes,
        .collapse,
        .center,
        10, // Very small width
        @src(),
    );
}
