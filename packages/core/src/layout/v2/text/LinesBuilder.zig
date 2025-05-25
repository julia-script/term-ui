const mod = @import("../mod.zig");
const LineBox = @import("./LineBox.zig");
const LineBoxFragment = @import("./LineBoxFragment.zig");
const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const LineBreakStream = @import("../../../uni/LineBreakStream.zig");
const WhiteSpaceProcessor = @import("./white-space-processor.zig").WhiteSpaceProcessor;
const WhiteSpace = @import("../../../styles/white-space.zig").WhiteSpace;
const css_types = @import("../../../css/types.zig");
const TextWrapMode = @import("../../../styles/white-space.zig").TextWrapMode;
const TabSize = @import("../../../styles/white-space.zig").TabSize;

lines: LineBox.LineBoxList,
available_width: mod.constants.AvailableSpace,
white_space_processor: WhiteSpaceProcessor,
allocator: std.mem.Allocator,
/// Tracks if the previous node ended with collapsible whitespace for cross-boundary collapsing
previous_node_ends_with_collapsible_whitespace: bool,

const Self = @This();

/// Track text inputs and their corresponding node IDs for proper fragment creation
const TextInput = struct {
    node_id: u32,
    start_offset: u32, // Offset in the segmenter buffer where this text starts
    length: u32, // Length of the processed text
};

pub fn init(allocator: std.mem.Allocator, available_width: mod.constants.AvailableSpace) Self {
    return Self{
        .available_width = available_width,
        .white_space_processor = WhiteSpaceProcessor.init(allocator),
        .allocator = allocator,
        .lines = LineBox.LineBoxList{
            .allocator = allocator,
        },
        .previous_node_ends_with_collapsible_whitespace = false,
    };
}

pub fn deinit(self: *Self) void {
    // Deinitialize all lines (which will deinitialize their fragments and text)
    self.lines.deinit();
    // Reset whitespace state
    self.previous_node_ends_with_collapsible_whitespace = false;
}

/// Transfer ownership of line boxes to caller, preventing deallocation when LinesBuilder is destroyed
/// Caller becomes responsible for deallocating the returned ArrayList and all fragment ArrayLists within each LineBox
pub fn toOwnedLineBoxes(self: *Self, allocator: std.mem.Allocator) !LineBox.LineBoxList {
    const copy = try self.lines.dupe(allocator);
    self.lines.deinit();
    self.lines = .{
        .allocator = self.allocator,
    };
    // Reset whitespace state when transferring ownership
    self.previous_node_ends_with_collapsible_whitespace = false;
    return copy;
}

fn addNewLine(self: *Self, available_width: f32) !void {
    const loc: mod.CSSPoint = blk: {
        const prev = if (self.lines.len() > 0) self.lines.items()[self.lines.len() - 1] else break :blk .{ .x = 0, .y = 0 };
        break :blk .{ .x = 0, .y = prev.location.y + prev.size.y };
    };
    const line = LineBox{ .location = loc, .size = mod.CSSPoint{ .x = 0, .y = 0 }, .available_width = available_width, .fragments = .{}, .allocator = self.allocator };

    try self.lines.list.append(self.allocator, line);
}

fn ensureLine(self: *Self, available_width: f32) !void {
    if (self.lines.len() == 0) {
        try self.addNewLine(available_width);
    }
}

/// Add text content with white-space processing and node ID tracking
pub fn appendNodeSlice(self: *Self, text: []const u8, white_space_mode: WhiteSpace, node_id: u32) !void {
    // Determine if we should collapse initial whitespace for cross-boundary collapsing
    const should_collapse_initial = self.previous_node_ends_with_collapsible_whitespace and
        white_space_mode.toLonghand().collapse != .preserve;

    // Check if this is a whitespace-only node that should be skipped entirely
    if (should_collapse_initial and isWhitespaceOnly(text, white_space_mode)) {
        // create an empty fragment directly
        try self.createFragment("", white_space_mode, node_id, 0);
        return;
    }

    // Process text according to white-space rules (Phase I) with initial collapse support
    const processed_text = try self.white_space_processor.processTextWithWhiteSpace(text, white_space_mode, should_collapse_initial);

    // Update state for the next node - check if this processed text ends with collapsible whitespace
    self.previous_node_ends_with_collapsible_whitespace = endsWithCollapsibleWhitespace(processed_text, white_space_mode);

    // Create fragments immediately based on forced line breaks (max_content layout)
    try self.createFragmentsFromProcessedText(processed_text, white_space_mode, node_id);
}

/// Create fragments from processed text, breaking only at forced line breaks (max_content layout)
fn createFragmentsFromProcessedText(self: *Self, processed_text: []u8, white_space_mode: WhiteSpace, node_id: u32) !void {
    if (processed_text.len == 0) {
        self.allocator.free(processed_text);
        return;
    }

    // Split text only at forced line breaks (LF) for max_content layout
    var line_start: usize = 0;
    while (std.mem.indexOf(u8, processed_text, "\n")) |lf_index| {
        const fragment_text = processed_text[line_start..lf_index];
        try self.createFragment(fragment_text, white_space_mode, node_id, @intCast(line_start));
        line_start = lf_index + 1;
        try self.ensureNewLine();
    }
    // Handle remaining text after last line break
    if (line_start < processed_text.len) {
        const fragment_text = processed_text[line_start..];
        try self.createFragment(fragment_text, white_space_mode, node_id, @intCast(line_start));
    }

    // Free the original processed_text since fragments now own their portions
    self.allocator.free(processed_text);
}

/// Create a fragment with owned text and add it to the current or new line
fn createFragment(self: *Self, text_slice: []const u8, white_space_mode: WhiteSpace, node_id: u32, start_offset: u32) !void {
    // Ensure we have a line to add the fragment to
    try self.ensureCurrentLine();

    // Clone the text for the fragment to own
    const owned_text = try self.allocator.dupe(u8, text_slice);

    // Calculate fragment width immediately
    const fragment_width = self.measureTextWidth(text_slice);

    // Create the fragment
    const fragment = LineBoxFragment{
        .l_node_id = node_id,
        .start = start_offset,
        .length = @intCast(text_slice.len),
        .size = mod.CSSPoint{ .x = fragment_width, .y = 1.0 },
        .is_atomic = false,
        .white_space_info = .{
            .has_preserved_spaces = false,
            .has_preserved_tabs = false,
            .has_collapsible_spaces = false,
            .original_white_space_mode = white_space_mode,
            .tab_size = .{ .number = 8 },
        },
        .text = owned_text,
        .allocator = self.allocator,
    };

    // Add fragment to the current line
    try self.appendFragment(fragment);
}
pub fn appendFragment(self: *Self, fragment: LineBoxFragment) !void {
    var current_line = &self.lines.items()[self.lines.len() - 1];
    try current_line.fragments.append(self.allocator, fragment);
    current_line.fragments.items[current_line.fragments.items.len - 1].position.x = current_line.size.x;
    current_line.size.x += fragment.size.x;
    current_line.size.y = @max(current_line.size.y, fragment.size.y);
}

/// Ensure there's a current line, create one if none exists
fn ensureCurrentLine(self: *Self) !void {
    if (self.lines.len() == 0) {
        try self.addNewLine(switch (self.available_width) {
            .definite => |width| width,
            .min_content, .max_content => 999999.0, // Large value for content-based width
        });
    }
}

/// Force creation of a new line
fn ensureNewLine(self: *Self) !void {
    try self.addNewLine(switch (self.available_width) {
        .definite => |width| width,
        .min_content, .max_content => 999999.0, // Large value for content-based width
    });
}

/// Add text content with specific collapse mode
pub fn addTextWithCollapse(self: *Self, text: []const u8, collapse_mode: css_types.WhiteSpaceCollapse) !void {
    const processed_text = try self.white_space_processor.processText(text, collapse_mode);
    defer self.allocator.free(processed_text);

    try self.segmenter.append(processed_text);
}

/// Add text for preserve-spaces mode (SVG xml:space="preserve")
pub fn addPreserveSpacesText(self: *Self, text: []const u8) !void {
    const processed_text = try self.white_space_processor.processPreserveSpaces(text);
    defer self.allocator.free(processed_text);

    try self.segmenter.append(processed_text);
}

/// Add text for break-spaces mode with soft wrap opportunities
pub fn addBreakSpacesText(self: *Self, text: []const u8) !void {
    const processed_text = try self.white_space_processor.processBreakSpaces(text);

    // Add to segmenter buffer for backward compatibility
    try self.segmenter.append(processed_text);

    // Create fragments using pre-wrap mode (which preserves spaces and adds wrap opportunities)
    try self.createFragmentsFromProcessedText(processed_text, .@"pre-wrap", 0);
}

/// Add text with full preprocessing pipeline
/// This demonstrates the complete text preprocessing before LineBreakStream
pub fn addTextWithFullPreprocessing(self: *Self, text: []const u8, white_space_mode: WhiteSpace, tab_size: TabSize) !void {
    // Phase I: White-space processing (collapsing/transformation)
    const phase1_text = try self.white_space_processor.processTextWithWhiteSpace(text, white_space_mode, false);
    defer self.allocator.free(phase1_text);

    // Store metadata about processing for potential Phase II usage
    // In a real implementation, this would be associated with text fragments
    _ = tab_size; // Will be used in Phase II during actual rendering

    // Add processed text to line break segmenter
    try self.segmenter.append(phase1_text);
}

/// Process text for nowrap mode: remove soft wrap opportunities, preserve forced breaks
/// Soft wrap opportunities are typically spaces and zero-width spaces (U+200B)
/// Forced line breaks are segment breaks like LF (U+000A)
fn processTextForNowrap(self: *Self, text: []const u8) ![]u8 {
    var result = try ArrayList(u8).initCapacity(self.allocator, text.len);
    defer result.deinit(self.allocator);

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        switch (codepoint) {
            // Preserve forced line breaks (segment breaks)
            0x000A => { // LF
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const start_pos = iter.i - char_len;
                try result.appendSlice(self.allocator, text[start_pos..iter.i]);
            },
            // Remove soft wrap opportunity markers inserted by break-spaces processing
            0x200B => { // ZERO WIDTH SPACE (soft wrap opportunity marker)
                // Skip this character in nowrap mode
            },
            // For spaces, we need to check if they're at soft wrap opportunities
            // In the current implementation, spaces are treated as potential wrap points
            // In nowrap mode, we preserve them but they won't cause wrapping
            else => {
                // Preserve all other characters including spaces
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const start_pos = iter.i - char_len;
                try result.appendSlice(self.allocator, text[start_pos..iter.i]);
            },
        }
    }

    return result.toOwnedSlice(self.allocator);
}

/// Check if text content can fit in available width without wrapping
/// This is used to determine overflow in nowrap mode
/// Uses terminal-aware text measurement that handles ANSI colors, Unicode, and wide characters
pub fn measureTextWidth(self: *Self, text: []const u8) f32 {
    _ = self; // unused for now

    // Use the terminal-aware width function that excludes ANSI colors
    // and properly handles Unicode characters (CJK, emojis, combining chars)
    const utf8WidthExcludingAnsiColors = @import("../../../uni/string-width.zig").utf8WidthExcludingAnsiColors;
    const measured_width = utf8WidthExcludingAnsiColors(text);

    return @as(f32, @floatFromInt(measured_width));
}
pub fn trimAndMeasureText(self: *Self, text: []const u8) struct {
    trimmed: []const u8,
    trimmed_width: f32,
    full_width: f32,
} {
    const trimmed = std.mem.trimEnd(u8, text, " \t"); // new liens should be handled by this point
    const trimmed_width = self.measureTextWidth(trimmed);
    // whitespace will always be 1 char wide
    const trailing_width: f32 = @floatFromInt(text.len - trimmed.len);
    return .{ .trimmed = trimmed, .trimmed_width = trimmed_width, .full_width = trimmed_width + trailing_width };
}

/// Apply text alignment to all lines based on the specified alignment mode
/// This adjusts fragment positions within each line to achieve left, right, or center alignment
pub fn applyTextAlignment(self: *Self, text_align: css_types.TextAlign, container_width: f32) void {
    // For simplicity, map start/end to left/right (RTL not implemented yet)
    const physical_align = switch (text_align) {
        .start => css_types.TextAlign.left,
        .end => css_types.TextAlign.right,
        else => text_align,
    };

    for (self.lines.items()) |*line| {
        if (line.fragments.items.len == 0) continue;

        // Calculate the total width of content in this line
        var line_content_width: f32 = 0;
        for (line.fragments.items) |fragment| {
            line_content_width += fragment.size.x;
        }
        // TODO: account for trailing whitespace

        // Calculate the alignment offset based on alignment mode
        const alignment_offset = switch (physical_align) {
            .left, .start => 0.0, // No offset needed for left alignment
            .right, .end => container_width - line_content_width,
            .center => (container_width - line_content_width) / 2.0,
            .inherit => 0.0, // Fallback to left
        };

        // Apply the alignment offset to all fragments in this line
        var current_x: f32 = alignment_offset;
        for (line.fragments.items) |*fragment| {
            // Update fragment position with alignment offset
            fragment.position.x = current_x;
            current_x += fragment.size.x;
        }
    }
}

/// Build lines with wrap mode consideration
/// Reorganizes existing fragments based on available width and wrap mode
pub fn buildLinesWithWrapMode(self: *Self, wrap_mode: TextWrapMode) !void {
    if (wrap_mode == .nowrap) {
        return;
    }
    switch (self.available_width) {
        .definite => |width| {
            try self.reorganizeFragmentsWithWrapping(width);
        },
        .min_content => {
            const min_width = try self.calculateMinContentWidth();
            try self.reorganizeFragmentsWithWrapping(min_width);
        },
        .max_content => {
            // max_content doesn't wrap - keep existing layout
        },
    }
}

/// Reorganize fragments with soft wrapping at the specified width
fn reorganizeFragmentsWithWrapping(self: *Self, available_width: f32) !void {
    var prev_lines = try self.toOwnedLineBoxes(self.allocator);
    defer prev_lines.deinit();

    for (prev_lines.list.items) |*line| {
        try self.addNewLine(available_width);

        if (line.size.x <= available_width) {
            for (line.fragments.items) |*fragment| {
                const owned_text = try self.allocator.dupe(u8, fragment.text);
                var cloned_fragment = fragment.*;
                cloned_fragment.text = owned_text;
                try self.appendFragment(cloned_fragment);
            }
        } else {
            try self.breakAndWrapLine(line, available_width);
        }
    }

    // Trim trailing whitespace from the last fragment of the final line
    try self.trimLastFragmentTrailingWhitespace();
}
fn breakAndWrapLine(self: *Self, line: *LineBox, available_width: f32) !void {
    var current_line_width: f32 = 0;

    for (line.fragments.items) |*fragment| {
        var segmenter = LineBreakStream.init(self.allocator);
        defer segmenter.deinit();

        try segmenter.append(fragment.text);

        var segment_start: usize = 0;

        while (segmenter.next()) |break_point| {
            const segment_text = fragment.text[segment_start..break_point.i];
            const measurements = self.trimAndMeasureText(segment_text);

            // Use trimmed width for overflow check - trailing whitespace can overflow
            if (current_line_width + measurements.trimmed_width > available_width and current_line_width > 0) {
                // Trim trailing whitespace from the last fragment of the current line before wrapping
                try self.trimLastFragmentTrailingWhitespace();
                try self.addNewLine(available_width);
                current_line_width = 0;
            }

            // Store full width in fragment since it contains the actual text with spaces
            try self.appendFragment(.{
                .l_node_id = fragment.l_node_id,
                .allocator = self.allocator,
                .start = @intCast(segment_start),
                .length = @intCast(segment_text.len),
                .size = mod.CSSPoint{ .x = measurements.full_width, .y = fragment.size.y },
                .is_atomic = fragment.is_atomic,
                .white_space_info = fragment.white_space_info,
                .text = try self.allocator.dupe(u8, segment_text),
            });

            // Update line width with trimmed width for layout decisions
            current_line_width += measurements.full_width;
            segment_start = break_point.i;
        }

        // Handle the remaining text after the last break point
        if (segment_start < fragment.text.len) {
            const remaining_text = fragment.text[segment_start..];
            const measurements = self.trimAndMeasureText(remaining_text);

            if (current_line_width + measurements.trimmed_width > available_width and current_line_width > 0) {
                // Trim trailing whitespace from the last fragment of the current line before wrapping
                try self.trimLastFragmentTrailingWhitespace();
                try self.addNewLine(available_width);
                current_line_width = 0;
            }

            try self.appendFragment(.{
                .l_node_id = fragment.l_node_id,
                .allocator = self.allocator,
                .start = @intCast(segment_start),
                .length = @intCast(remaining_text.len),
                .size = mod.CSSPoint{ .x = measurements.full_width, .y = fragment.size.y },
                .is_atomic = fragment.is_atomic,
                .white_space_info = fragment.white_space_info,
                .text = try self.allocator.dupe(u8, remaining_text),
            });

            current_line_width += measurements.full_width;
        }
    }
}

/// Calculate the min-content width by finding the longest unbreakable segment
/// This represents the smallest width that can contain the content without overflow
fn calculateMinContentWidth(self: *Self) !f32 {
    var max_segment_width: f32 = 0;

    for (self.lines.items()) |*line| {
        for (line.fragments.items) |*fragment| {
            var segmenter = LineBreakStream.init(self.allocator);
            defer segmenter.deinit();

            try segmenter.append(fragment.text);

            var segment_start: usize = 0;

            // Check each segment between break opportunities
            while (segmenter.next()) |break_point| {
                const segment_text = fragment.text[segment_start..break_point.i];
                const measurements = self.trimAndMeasureText(segment_text);

                // Use trimmed width since trailing whitespace can overflow
                max_segment_width = @max(max_segment_width, measurements.trimmed_width);
                segment_start = break_point.i;
            }

            // Handle the remaining text after the last break point
            if (segment_start < fragment.text.len) {
                const remaining_text = fragment.text[segment_start..];
                const measurements = self.trimAndMeasureText(remaining_text);
                max_segment_width = @max(max_segment_width, measurements.trimmed_width);
            }
        }
    }

    // Ensure minimum width of at least 1 unit
    return @max(max_segment_width, 1.0);
}

test "reorganizeFragmentsWithWrapping" {
    var lines_builder = Self.init(std.testing.allocator, .{ .definite = 30 });
    defer lines_builder.deinit();

    try lines_builder.appendNodeSlice("Lorem    ipsum dolor sit amet, consectetur adipiscing elit. Sed ", .normal, 0);
    try lines_builder.appendNodeSlice("   do eiusmod tempor incididunt ut labore et dolore magna aliqua.", .normal, 1);
    try lines_builder.buildLinesWithWrapMode(.wrap);
    try lines_builder.print(std.io.getStdErr().writer().any());
    try lines_builder.printText(std.io.getStdErr().writer().any(), true);
}

test "cross-boundary whitespace collapsing" {
    var lines_builder = Self.init(std.testing.allocator, .{ .definite = 50 });
    defer lines_builder.deinit();

    // Test basic cross-boundary collapsing
    try lines_builder.appendNodeSlice("Hello ", .normal, 0);
    try lines_builder.appendNodeSlice("   world", .normal, 1);

    // Should result in "Hello world" (single space)
    try std.testing.expect(lines_builder.lines.len() == 1);
    const line = &lines_builder.lines.items()[0];
    try std.testing.expect(line.fragments.items.len == 2);

    // First fragment should be "Hello "
    try std.testing.expectEqualStrings("Hello ", line.fragments.items[0].text);
    // Second fragment should be "world" (leading spaces collapsed)
    try std.testing.expectEqualStrings("world", line.fragments.items[1].text);
}

test "whitespace-only node skipping" {
    var lines_builder = Self.init(std.testing.allocator, .{ .definite = 50 });
    defer lines_builder.deinit();

    // Test that whitespace-only nodes get skipped when previous node ends with whitespace
    try lines_builder.appendNodeSlice("Hello ", .normal, 0);
    try lines_builder.appendNodeSlice("   ", .normal, 1); // Should be skipped
    try lines_builder.appendNodeSlice("world", .normal, 2);

    // Should result in only 2 fragments: "Hello " and "world"
    try std.testing.expect(lines_builder.lines.len() == 1);
    const line = &lines_builder.lines.items()[0];
    try std.testing.expect(line.fragments.items.len == 2);

    try std.testing.expectEqualStrings("Hello ", line.fragments.items[0].text);
    try std.testing.expectEqualStrings("world", line.fragments.items[1].text);
}

test "preserve mode no collapsing" {
    var lines_builder = Self.init(std.testing.allocator, .{ .definite = 50 });
    defer lines_builder.deinit();

    // In preserve mode, cross-boundary collapsing should not happen
    try lines_builder.appendNodeSlice("Hello ", .pre, 0);
    try lines_builder.appendNodeSlice("   world", .pre, 1);

    try std.testing.expect(lines_builder.lines.len() == 1);
    const line = &lines_builder.lines.items()[0];
    try std.testing.expect(line.fragments.items.len == 2);

    try std.testing.expectEqualStrings("Hello ", line.fragments.items[0].text);
    try std.testing.expectEqualStrings("   world", line.fragments.items[1].text); // Spaces preserved
}

test "trailing whitespace removal on line break" {
    var lines_builder = Self.init(std.testing.allocator, .{ .definite = 10 });
    defer lines_builder.deinit();

    // Text that will wrap and should have trailing spaces removed
    try lines_builder.appendNodeSlice("Hello world   ", .normal, 0);
    try lines_builder.buildLinesWithWrapMode(.wrap);

    // Should have wrapped into 2 lines: "Hello" and "world"
    try std.testing.expect(lines_builder.lines.len() == 2);

    // First line should be "Hello" (no trailing space)
    const line1 = &lines_builder.lines.items()[0];
    try std.testing.expect(line1.fragments.items.len == 1);
    try std.testing.expectEqualStrings("Hello", line1.fragments.items[0].text);

    // Second line should be "world" (no trailing spaces)
    const line2 = &lines_builder.lines.items()[1];
    try std.testing.expect(line2.fragments.items.len == 1);
    try std.testing.expectEqualStrings("world", line2.fragments.items[0].text);
}

test "preserve mode keeps trailing whitespace" {
    var lines_builder = Self.init(std.testing.allocator, .{ .definite = 10 });
    defer lines_builder.deinit();

    // In preserve mode, trailing whitespace should not be removed even when forced to wrap
    try lines_builder.appendNodeSlice("Hello world   ", .@"pre-wrap", 0); // Use pre-wrap which allows wrapping
    try lines_builder.buildLinesWithWrapMode(.wrap);

    // Should have multiple lines
    try std.testing.expect(lines_builder.lines.len() >= 1);

    // Find the last line and check that it preserves trailing spaces
    const last_line = &lines_builder.lines.items()[lines_builder.lines.len() - 1];
    const last_fragment = &last_line.fragments.items[last_line.fragments.items.len - 1];

    // Should keep trailing spaces in preserve mode (pre-wrap preserves spaces)
    try std.testing.expect(std.mem.endsWith(u8, last_fragment.text, "   "));
}

test "min-content wrapping" {
    var lines_builder = Self.init(std.testing.allocator, .min_content);
    defer lines_builder.deinit();

    // Add text with varying word lengths - "consectetur" (11 chars) should be the longest
    try lines_builder.appendNodeSlice("Lorem ipsum dolor sit amet, consectetur adipiscing elit.", .normal, 0);
    try lines_builder.buildLinesWithWrapMode(.wrap);

    // Should have wrapped based on min-content width (longest unbreakable segment)
    try std.testing.expect(lines_builder.lines.len() > 1);

    // Check that we have reasonable line breaks - each line should fit within min-content width
    for (lines_builder.lines.items()) |line| {
        // Each line should be reasonably sized (not exceed a reasonable multiple of min-content)
        try std.testing.expect(line.size.x <= 20.0); // "consectetur" + some margin
    }

    // The longest word should fit on a single line
    var found_consectetur = false;
    for (lines_builder.lines.items()) |line| {
        for (line.fragments.items) |fragment| {
            if (std.mem.indexOf(u8, fragment.text, "consectetur")) |_| {
                found_consectetur = true;
                // "consectetur" should fit on its line
                try std.testing.expect(fragment.size.x <= line.size.x);
                break;
            }
        }
    }
    try std.testing.expect(found_consectetur);
}

test "min-content width calculation" {
    var lines_builder = Self.init(std.testing.allocator, .max_content);
    defer lines_builder.deinit();

    // Add text with known word lengths
    try lines_builder.appendNodeSlice("short verylongword tiny", .normal, 0);

    // Calculate min-content width - should be the width of "verylongword" (12 chars)
    const min_width = try lines_builder.calculateMinContentWidth();

    // Should be approximately the width of "verylongword"
    try std.testing.expect(min_width >= 12.0);
    try std.testing.expect(min_width <= 15.0); // With some tolerance
}

/// Check if text contains only collapsible whitespace characters
fn isWhitespaceOnly(text: []const u8, white_space_mode: WhiteSpace) bool {
    if (text.len == 0) return true;

    const longhand = white_space_mode.toLonghand();
    const white_space_processor = @import("./white-space-processor.zig");

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iter.nextCodepoint()) |codepoint| {
        if (!white_space_processor.isDocumentWhiteSpace(codepoint)) {
            return false; // Found non-whitespace character
        }

        // Check if this whitespace would be collapsible
        if (!white_space_processor.isCollapsible(codepoint, longhand.collapse)) {
            return false; // Found non-collapsible whitespace (like preserved spaces)
        }
    }
    return true;
}

/// Check if text ends with collapsible whitespace in the given mode
fn endsWithCollapsibleWhitespace(text: []const u8, white_space_mode: WhiteSpace) bool {
    if (text.len == 0) return false;

    const longhand = white_space_mode.toLonghand();
    const white_space_processor = @import("./white-space-processor.zig");

    // Get the last character
    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var last_codepoint: ?u21 = null;
    while (iter.nextCodepoint()) |codepoint| {
        last_codepoint = codepoint;
    }

    if (last_codepoint) |codepoint| {
        return white_space_processor.isDocumentWhiteSpace(codepoint) and
            white_space_processor.isCollapsible(codepoint, longhand.collapse);
    }
    return false;
}

/// Remove trailing collapsible whitespace from the last fragment of the current line
/// Per W3C spec Phase II: "A sequence of collapsible spaces at the end of a line is removed"
fn trimLastFragmentTrailingWhitespace(self: *Self) !void {
    if (self.lines.len() == 0) return;

    var current_line = &self.lines.items()[self.lines.len() - 1];
    if (current_line.fragments.items.len == 0) return;

    var last_fragment = &current_line.fragments.items[current_line.fragments.items.len - 1];
    const white_space_mode = last_fragment.white_space_info.original_white_space_mode;
    const longhand = white_space_mode.toLonghand();

    // Only trim if collapsing is allowed
    if (longhand.collapse == .preserve) {
        return; // Don't trim in preserve mode
    }

    // Simple approach: trim trailing ASCII spaces (most common case)
    // This handles the common case efficiently without complex Unicode iteration
    var trimmed_end = last_fragment.text.len;
    while (trimmed_end > 0 and last_fragment.text[trimmed_end - 1] == 0x20) {
        trimmed_end -= 1;
    }

    // If we need to trim, create new text and update fragment
    if (trimmed_end < last_fragment.text.len) {
        const old_text = last_fragment.text;
        const new_text = try self.allocator.dupe(u8, old_text[0..trimmed_end]);

        // Free old text and update fragment
        self.allocator.free(old_text);
        last_fragment.text = new_text;
        last_fragment.length = @intCast(new_text.len);

        // Recalculate fragment width and update line width
        const old_width = last_fragment.size.x;
        last_fragment.size.x = self.measureTextWidth(new_text);
        current_line.size.x = current_line.size.x - old_width + last_fragment.size.x;
    }
}

/// Check if a character provides a soft wrap opportunity
fn isSoftWrapOpportunity(self: *Self, codepoint: u21) bool {
    _ = self; // unused for now
    return switch (codepoint) {
        0x0020 => true, // SPACE
        0x200B => true, // ZERO WIDTH SPACE (soft wrap opportunity marker)
        0x00AD => true, // SOFT HYPHEN
        // Add more soft wrap opportunities as needed
        else => false,
    };
}

/// Check if a character is a forced line break
fn isForcedLineBreak(codepoint: u21) bool {
    return switch (codepoint) {
        0x000A => true, // LINE FEED (LF)
        0x000D => true, // CARRIAGE RETURN (CR) - though these should be normalized to spaces first
        0x2028 => true, // LINE SEPARATOR
        0x2029 => true, // PARAGRAPH SEPARATOR
        else => false,
    };
}

pub fn print(self: *Self, writer: std.io.AnyWriter) !void {
    for (self.lines.items(), 0..) |line, i| {
        try writer.print("[Line#{d} loc: {any} size: {any}\n", .{ i, line.location, line.size });

        for (line.fragments.items) |_fragment| {
            const fragment: LineBoxFragment = _fragment;

            try writer.print("    [Fragment node#{d} {any} range {d}~{d} '{s}']\n", .{ fragment.l_node_id, fragment.size, fragment.start, fragment.start + fragment.length, fragment.text });
        }
    }
}

const RAINBOW = [_][]const u8{
    "\x1b[31m",
    "\x1b[32m",
    "\x1b[33m",
    "\x1b[34m",
    "\x1b[35m",
};
pub fn printText(self: *Self, writer: std.io.AnyWriter, color: bool) !void {
    var fba = try std.BoundedArray(u8, 1024).init(0);
    for (self.lines.items()) |line| {
        const fba_writer = fba.writer();
        for (line.fragments.items) |fragment| {
            if (color) {
                try fba_writer.print("{s}{s}\x1b[0m", .{ RAINBOW[fragment.l_node_id % RAINBOW.len], fragment.text });
            } else {
                try fba_writer.print("{s}", .{fragment.text});
            }
        }
        switch (self.available_width) {
            .definite => |width| {
                var current_size = self.measureTextWidth(fba.slice());
                while (current_size < width) {
                    try fba_writer.writeByte(' ');
                    current_size += 1;
                }
            },
            .min_content, .max_content => {},
        }
        const slice = fba.slice();
        try writer.print("|{s}", .{slice});
        try writer.print("|\n", .{});

        fba.clear();
    }
}
