const WhiteSpaceCollapse = @import("../../../styles/white-space.zig").WhiteSpaceCollapse;
const unicode = @import("../../../uni/codepoint.zig");

const TextWrapMode = @import("../../../styles/white-space.zig").TextWrapMode;
const css_types = @import("../../../css/types.zig");
const TabSize = @import("../../../styles/white-space.zig").TabSize;
const LineBox = @import("./LineBox.zig");
const std = @import("std");
const mod = @import("../mod.zig");
const snapshot = @import("../../../testing/snapshot.zig");
const LineBoxFragment = mod.LineBoxFragment;

lines: LineBox.LineBoxList,
available_width: mod.constants.AvailableSpace,
allocator: std.mem.Allocator,
context: *mod.LayoutContext,
wrap_mode: TextWrapMode,
collapse: WhiteSpaceCollapse,

const Self = @This();

pub fn init(
    allocator: std.mem.Allocator,
    available_width: mod.constants.AvailableSpace,
    context: *mod.LayoutContext,
    wrap_mode: TextWrapMode,
    collapse: WhiteSpaceCollapse,
) Self {
    return Self{
        .allocator = allocator,
        .available_width = available_width,
        .context = context,
        .wrap_mode = wrap_mode,
        .collapse = collapse,
        .lines = LineBox.LineBoxList{
            .allocator = allocator,
        },
    };
}
pub fn resolveAvailableWidth(self: *Self) f32 {
    return switch (self.available_width) {
        .definite => |width| width,
        .min_content, .max_content => std.math.floatMax(f32),
    };
}
pub fn newLine(self: *Self) !void {
    try self.lines.appendLine(.{
        .allocator = self.allocator,
        .available_width = self.resolveAvailableWidth(),
        .fragments = .{},
    });
}
pub fn ensureFirstLine(self: *Self) !void {
    if (self.lines.len() == 0) {
        try self.newLine();
    }
}
pub fn appendNodeSlice(self: *Self, text: []const u8, node_id: mod.LayoutNode.Id) !void {
    try self.ensureFirstLine();
    try self.lines.appendFragmentToLastLine(.{
        .text = try self.allocator.dupe(u8, text),
        .l_node_id = node_id,
        .dom_range = .{
            .start = 0,
            .end = @intCast(text.len),
        },
        .is_atomic = false,
        .allocator = self.allocator,
        .start = 0,
        .length = @intCast(text.len),

        // right now we are just collecting the fragments from node so we dont measure them now
        .size = .{
            .x = 0,
            .y = 1,
        },

        .position = .{
            .x = 0,
            .y = 0,
        },
    });
}
pub fn toOwnedLineBoxes(self: *Self, allocator: std.mem.Allocator) !LineBox.LineBoxList {
    const owned_lines = try self.lines.dupe(allocator);

    self.lines.deinit();
    self.lines = .{
        .allocator = allocator,
    };

    return owned_lines;
}

pub fn deinit(self: *Self) void {
    self.lines.deinit();
}

// Except where specified otherwise, white space processing in CSS affects only the document white space characters: spaces (U+0020), tabs (U+0009), and segment breaks.

// Tests
// Note: The set of characters considered document white space (part of the document content) and those considered syntactic white space (part of the CSS syntax) are not necessarily identical. However, since both include spaces (U+0020), tabs (U+0009), and line feeds (U+000A) most authors won't notice any differences.

// Besides space (U+0020) and no-break space (U+00A0), Unicode defines a number of additional space separator characters. [UNICODE] In this specification all characters in the Unicode general category Zs except space (U+0020) and no-break space (U+00A0) are collectively referred to as other space separators.

// Tests

const BytePosition = struct {
    line_index: usize,
    fragment_index: usize,
    byte_index: usize,
};

const CodepointWithPosition = struct {
    codepoint: u21,
    pos: BytePosition,
};

// Besides space (U+0020) and no-break space (U+00A0),
// Unicode defines a number of additional space separator characters.
// [UNICODE] In this specification all characters in the Unicode general category Zs except space (U+0020) and no-break space (U+00A0)
// are collectively referred to as other space separators.
pub fn isOtherSpaceSeparator(codepoint: u21) bool {
    const cat = unicode.getCategory(codepoint);
    if (cat != .Zs) {
        return false;
    }
    if (codepoint == '\u{00A0}' or codepoint == '\u{0020}') {
        return false;
    }
    return true;
}
pub fn isCollapsible(codepoint: u21, collapse_mode: WhiteSpaceCollapse) bool {
    return switch (collapse_mode) {
        .collapse => switch (codepoint) {
            ' ', '\t', '\n' => true,
            else => isOtherSpaceSeparator(codepoint),
        },
        .preserve => false, // Nothing is collapsible in preserve mode
        .@"preserve-breaks" => switch (codepoint) {
            ' ', '\t' => true,
            else => false,
        },
        .@"preserve-spaces" => switch (codepoint) {
            '\t', '\n' => true, // Tabs and segment breaks are collapsible (converted to spaces)
            else => false,
        },
        .inherit => std.debug.panic("inherit property should be resolved during style computation", .{}),
    };
}

// Enhanced iterator that tracks byte positions correctly
const IterCodepointWithPosition = struct {
    iter_fragment: IterFragments,
    codepoint_iter: std.unicode.Utf8Iterator,
    current_pos: BytePosition,

    pub fn init(lines: *LineBox.LineBoxList) IterCodepointWithPosition {
        var iter = IterFragments{ .line_index = 0, .fragment_index = 0, .lines = lines };
        const first_fragment = iter.next();

        if (first_fragment == null) {
            return IterCodepointWithPosition{
                .iter_fragment = iter,
                .codepoint_iter = std.unicode.Utf8Iterator{ .i = 0, .bytes = "" },
                .current_pos = BytePosition{ .line_index = 0, .fragment_index = 0, .byte_index = 0 },
            };
        }

        return IterCodepointWithPosition{
            .iter_fragment = iter,
            .codepoint_iter = std.unicode.Utf8Iterator{ .i = 0, .bytes = first_fragment.?.text },
            .current_pos = BytePosition{ .line_index = 0, .fragment_index = 0, .byte_index = 0 },
        };
    }

    pub fn next(self: *IterCodepointWithPosition) ?CodepointWithPosition {
        while (true) {
            const start_pos = self.current_pos;

            if (self.codepoint_iter.nextCodepoint()) |codepoint| {
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                self.current_pos.byte_index += char_len;
                return .{ .codepoint = codepoint, .pos = start_pos };
            }

            // Current fragment is exhausted, try to get next fragment
            const next_fragment = self.iter_fragment.next() orelse return null;

            // Update position to next fragment
            self.current_pos.line_index = self.iter_fragment.line_index;
            self.current_pos.fragment_index = self.iter_fragment.fragment_index - 1; // iter_fragment increments after returning
            self.current_pos.byte_index = 0;

            // Skip empty fragments
            if (next_fragment.text.len == 0) {
                continue;
            }

            // Initialize iterator for the new fragment
            self.codepoint_iter = std.unicode.Utf8Iterator{
                .bytes = next_fragment.text,
                .i = 0,
            };
        }
    }

    pub fn peek(self: *IterCodepointWithPosition) ?CodepointWithPosition {
        // Save the current iterator state before peeking
        const saved_fragment_iter = self.iter_fragment;
        const saved_codepoint_iter = self.codepoint_iter;
        const saved_pos = self.current_pos;

        // Get the next character
        const next_char = self.next();

        // Restore the iterator state
        self.iter_fragment = saved_fragment_iter;
        self.codepoint_iter = saved_codepoint_iter;
        self.current_pos = saved_pos;

        return next_char;
    }
};

pub fn runPhase1CollapseAndTransformation(self: *Self) !void {
    switch (self.collapse) {
        .collapse, .@"preserve-breaks" => {
            // Apply Phase I rules in the correct order:

            // 1. Remove spaces/tabs around segment breaks
            try self.removeSpaceAroundSegmentBreak();

            // 2. Remove consecutive segment breaks and transform remaining ones
            try self.processSegmentBreaks();

            // 3. Convert collapsible tabs to spaces
            try self.convertTabsToSpaces();

            // 4. Collapse consecutive spaces
            try self.collapseConsecutiveSpaces();
        },
        .@"preserve-spaces" => {
            // For preserve-spaces: each tab and segment break is converted to a space
            try self.convertTabsAndSegmentBreaksToSpaces();

            // Sequences of spaces are treated as non-breaking spaces with wrap opportunities
            try self.markPreserveSpaceSequences();
        },
        .preserve => {
            // For preserve mode: treat spaces as non-breaking spaces
            // Sequences have soft wrap opportunities at the end of each maximal sequence
            try self.markPreserveSpaceSequences();
        },
        .inherit => std.debug.panic("inherit property should be resolved during style computation", .{}),
    }
}

pub fn removeSpaceAroundSegmentBreak(self: *Self) !void {
    // 1. Any sequence of collapsible spaces and tabs immediately preceding or following a segment break is removed.
    var iter = IterCodepointWithPosition.init(&self.lines);
    var ranges_to_clear = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    defer ranges_to_clear.deinit();

    while (true) {
        // Find the next segment break
        var segment_break_pos: ?BytePosition = null;
        var collapsible_before_start: ?BytePosition = null;
        var collapsible_before_end: ?BytePosition = null;

        // Scan for collapsible characters before segment break
        while (iter.next()) |item| {
            if (isSegmentBreak(item.codepoint)) {
                segment_break_pos = item.pos;
                break;
            } else if (isCollapsible(item.codepoint, self.collapse)) {
                if (collapsible_before_start == null) {
                    collapsible_before_start = item.pos;
                }
                collapsible_before_end = BytePosition{
                    .line_index = item.pos.line_index,
                    .fragment_index = item.pos.fragment_index,
                    .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(item.codepoint) catch unreachable),
                };
            } else {
                // Non-collapsible character, reset collapsible tracking
                collapsible_before_start = null;
                collapsible_before_end = null;
            }
        }

        // If no segment break found, we're done
        const break_pos = segment_break_pos orelse break;
        _ = break_pos; // autofix

        // Mark collapsible characters before segment break for removal
        if (collapsible_before_start != null and collapsible_before_end != null) {
            try ranges_to_clear.append(.{
                .start = collapsible_before_start.?,
                .end = collapsible_before_end.?,
            });
        }

        // Now scan for collapsible characters after the segment break
        var collapsible_after_start: ?BytePosition = null;
        var collapsible_after_end: ?BytePosition = null;

        while (iter.peek()) |item| {
            if (isCollapsible(item.codepoint, self.collapse) and !isSegmentBreak(item.codepoint)) {
                if (collapsible_after_start == null) {
                    collapsible_after_start = item.pos;
                }
                collapsible_after_end = BytePosition{
                    .line_index = item.pos.line_index,
                    .fragment_index = item.pos.fragment_index,
                    .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(item.codepoint) catch unreachable),
                };
                _ = iter.next(); // consume the character
            } else {
                break;
            }
        }

        // Mark collapsible characters after segment break for removal
        if (collapsible_after_start != null and collapsible_after_end != null) {
            try ranges_to_clear.append(.{
                .start = collapsible_after_start.?,
                .end = collapsible_after_end.?,
            });
        }
    }

    // Clear all marked ranges in reverse order to avoid position shifts
    var i = ranges_to_clear.items.len;
    while (i > 0) {
        i -= 1;
        try self.clearRange(ranges_to_clear.items[i].start, ranges_to_clear.items[i].end);
    }
}

/// 2. Process segment break transformation rules
pub fn processSegmentBreaks(self: *Self) !void {
    var iter = IterCodepointWithPosition.init(&self.lines);
    var ranges_to_clear = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    var ranges_to_replace = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    defer ranges_to_clear.deinit();
    defer ranges_to_replace.deinit();

    var prev_codepoint: ?u21 = null;
    var prev_was_segment_break = false;

    while (iter.next()) |item| {
        const codepoint = item.codepoint;
        const is_segment_break = isSegmentBreak(codepoint);
        const is_collapsible = isCollapsible(codepoint, self.collapse);

        if (is_segment_break and is_collapsible) {
            if (prev_was_segment_break) {
                // This is a consecutive segment break - remove it
                try ranges_to_clear.append(.{
                    .start = item.pos,
                    .end = BytePosition{
                        .line_index = item.pos.line_index,
                        .fragment_index = item.pos.fragment_index,
                        .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable),
                    },
                });
            } else {
                // This is the first segment break in a sequence
                // Decide whether to transform to space or remove based on context

                // Look ahead to see what comes after
                var next_codepoint: ?u21 = null;
                if (iter.peek()) |next_item| {
                    next_codepoint = next_item.codepoint;
                }

                if (shouldRemoveSegmentBreak(prev_codepoint, next_codepoint)) {
                    // Remove the segment break entirely
                    try ranges_to_clear.append(.{
                        .start = item.pos,
                        .end = BytePosition{
                            .line_index = item.pos.line_index,
                            .fragment_index = item.pos.fragment_index,
                            .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable),
                        },
                    });
                } else {
                    // Transform segment break to space
                    try ranges_to_replace.append(.{
                        .start = item.pos,
                        .end = BytePosition{
                            .line_index = item.pos.line_index,
                            .fragment_index = item.pos.fragment_index,
                            .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable),
                        },
                    });
                }
            }
            prev_was_segment_break = true;
        } else {
            prev_was_segment_break = false;
        }

        prev_codepoint = codepoint;
    }

    // Apply all modifications in reverse order to avoid position shifts
    // First do replacements, then removals
    var i = ranges_to_replace.items.len;
    while (i > 0) {
        i -= 1;
        try self.replaceRangeWithSpace(ranges_to_replace.items[i].start, ranges_to_replace.items[i].end);
    }

    i = ranges_to_clear.items.len;
    while (i > 0) {
        i -= 1;
        try self.clearRange(ranges_to_clear.items[i].start, ranges_to_clear.items[i].end);
    }
}

/// Determine if a segment break should be removed based on surrounding characters
/// Since the CSS spec leaves transformation rules as "UA-defined", we use the simple approach:
/// always transform remaining segment breaks to spaces.
fn shouldRemoveSegmentBreak(prev_char: ?u21, next_char: ?u21) bool {
    _ = prev_char; // autofix
    _ = next_char; // autofix

    // Simple UA-defined rule: always transform segment breaks to spaces
    // (never remove them based on context)
    return false;
}

/// Replace a range of text with a single space character
pub fn replaceRangeWithSpace(self: *Self, start: BytePosition, end: BytePosition) !void {
    // Find the fragment containing the start position
    const lines = self.lines.items();
    if (start.line_index >= lines.len) return;

    const line = lines[start.line_index];
    if (start.fragment_index >= line.fragments.items.len) return;

    const fragment = &line.fragments.items[start.fragment_index];

    // For same-fragment replacement (most common case)
    if (start.line_index == end.line_index and start.fragment_index == end.fragment_index) {
        const text_bytes = fragment.text;
        if (end.byte_index > text_bytes.len) return; // Safety check

        const before = text_bytes[0..start.byte_index];
        const after = text_bytes[end.byte_index..];

        const new_text = try fragment.allocator.alloc(u8, before.len + 1 + after.len);
        @memcpy(new_text[0..before.len], before);
        new_text[before.len] = ' '; // Insert space
        @memcpy(new_text[before.len + 1 ..], after);

        fragment.allocator.free(fragment.text);
        fragment.text = new_text;
        fragment.length = @intCast(new_text.len);
        return;
    }

    // For multi-fragment ranges, fall back to clear then insert space
    // TODO: Implement proper multi-fragment replacement
    try self.clearRange(start, end);
}

/// 3. Convert collapsible tabs to spaces
pub fn convertTabsToSpaces(self: *Self) !void {
    var iter = IterCodepointWithPosition.init(&self.lines);
    var ranges_to_replace = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    defer ranges_to_replace.deinit();

    while (iter.next()) |item| {
        const codepoint = item.codepoint;

        // Convert collapsible tabs to spaces
        if (codepoint == '\t' and isCollapsible(codepoint, self.collapse)) {
            try ranges_to_replace.append(.{
                .start = item.pos,
                .end = BytePosition{
                    .line_index = item.pos.line_index,
                    .fragment_index = item.pos.fragment_index,
                    .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable),
                },
            });
        }
    }

    // Apply all replacements in reverse order to avoid position shifts
    var i = ranges_to_replace.items.len;
    while (i > 0) {
        i -= 1;
        try self.replaceRangeWithSpace(ranges_to_replace.items[i].start, ranges_to_replace.items[i].end);
    }
}

/// 4. Collapse consecutive spaces
pub fn collapseConsecutiveSpaces(self: *Self) !void {
    var iter = IterCodepointWithPosition.init(&self.lines);
    var ranges_to_clear = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    defer ranges_to_clear.deinit();

    var prev_was_collapsible_space = false;
    var consecutive_start: ?BytePosition = null;

    while (iter.next()) |item| {
        const codepoint = item.codepoint;
        const is_collapsible_space = codepoint == ' ' and isCollapsible(codepoint, self.collapse);

        if (is_collapsible_space) {
            if (prev_was_collapsible_space) {
                // This is a consecutive collapsible space - mark for removal
                if (consecutive_start == null) {
                    consecutive_start = item.pos;
                }
            } else {
                // First collapsible space in a sequence - keep it
                prev_was_collapsible_space = true;
            }
        } else {
            // Non-collapsible-space character
            if (consecutive_start != null) {
                // End the consecutive space sequence, mark range for clearing
                try ranges_to_clear.append(.{
                    .start = consecutive_start.?,
                    .end = item.pos, // End at current non-space character
                });
                consecutive_start = null;
            }
            prev_was_collapsible_space = false;
        }
    }

    // Handle case where consecutive spaces go to end of text
    if (consecutive_start != null) {
        // Find the end position by getting the last processed position
        var end_iter = IterCodepointWithPosition.init(&self.lines);
        var last_pos = BytePosition{ .line_index = 0, .fragment_index = 0, .byte_index = 0 };

        while (end_iter.next()) |item| {
            last_pos = BytePosition{
                .line_index = item.pos.line_index,
                .fragment_index = item.pos.fragment_index,
                .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(item.codepoint) catch unreachable),
            };
        }

        try ranges_to_clear.append(.{
            .start = consecutive_start.?,
            .end = last_pos,
        });
    }

    // Apply all removals in reverse order to avoid position shifts
    var i = ranges_to_clear.items.len;
    while (i > 0) {
        i -= 1;
        try self.clearRange(ranges_to_clear.items[i].start, ranges_to_clear.items[i].end);
    }
}

const IterFragments = struct {
    line_index: usize,
    fragment_index: usize,
    lines: *LineBox.LineBoxList,
    pub fn next(self: *IterFragments) ?*LineBoxFragment {
        const lines = self.lines.items();
        while (true) {
            if (self.line_index >= lines.len) return null;

            const line = lines[self.line_index];
            if (self.fragment_index >= line.fragments.items.len) {
                // Move to next line
                self.line_index += 1;
                self.fragment_index = 0;
                continue;
            }

            const fragment = &line.fragments.items[self.fragment_index];
            self.fragment_index += 1;
            return fragment;
        }
    }
};
pub fn clearRange(self: *Self, start: BytePosition, end: BytePosition) !void {
    var iter = IterFragments{ .line_index = start.line_index, .fragment_index = start.fragment_index, .lines = &self.lines };
    // Handle first fragment - partially clear from start position
    if (iter.next()) |first_fragment| {
        if (start.line_index == end.line_index and start.fragment_index == end.fragment_index) {
            // Start and end are in the same fragment
            const text_bytes = first_fragment.text;
            const before = text_bytes[0..start.byte_index];
            const after = text_bytes[end.byte_index..];

            const new_text = try first_fragment.allocator.alloc(u8, before.len + after.len);
            @memcpy(new_text[0..before.len], before);
            @memcpy(new_text[before.len..], after);

            first_fragment.allocator.free(first_fragment.text);
            first_fragment.text = new_text;
            first_fragment.length = @intCast(new_text.len);
            return;
        } else {
            // Clear from start byte position to end of fragment
            const text_bytes = first_fragment.text;
            const before = text_bytes[0..start.byte_index];

            const new_text = try first_fragment.allocator.dupe(u8, before);
            first_fragment.allocator.free(first_fragment.text);
            first_fragment.text = new_text;
            first_fragment.length = @intCast(new_text.len);
        }
    }

    // Clear all middle fragments completely
    while (iter.next()) |fragment| {
        // Check if this is the last fragment
        if (iter.line_index > end.line_index or
            (iter.line_index == end.line_index and iter.fragment_index > end.fragment_index))
        {
            break;
        }

        if (iter.line_index == end.line_index and iter.fragment_index - 1 == end.fragment_index) {
            // This is the last fragment, handle it separately
            break;
        }

        // Clear middle fragment completely
        fragment.allocator.free(fragment.text);
        fragment.text = try fragment.allocator.alloc(u8, 0);
        fragment.length = 0;
    }

    // Handle last fragment - partially clear from start to end position
    // Reset iterator to find the end fragment
    iter = IterFragments{ .line_index = end.line_index, .fragment_index = end.fragment_index, .lines = &self.lines };
    if (iter.next()) |last_fragment| {
        const text_bytes = last_fragment.text;
        const after = text_bytes[end.byte_index..];

        const new_text = try last_fragment.allocator.dupe(u8, after);
        last_fragment.allocator.free(last_fragment.text);
        last_fragment.text = new_text;
        last_fragment.length = @intCast(new_text.len);
    }
}
/// should be used in the phase 1, this do not compute the size of the fragment
pub fn collapseFragment(fragment: *LineBoxFragment, empty: bool) void {
    fragment.allocator.free(fragment.text);
    fragment.text = if (empty) "" else try fragment.allocator.dupe(u8, " ");
    fragment.length = @intCast(fragment.text.len);
}

/// For CSS processing, each document language–defined "segment break" or "newline sequence"—​or if none are defined, each line feed (U+000A)—​in the text is treated as a segment break, which is then interpreted for rendering as specified by the white-space property.
pub fn isSegmentBreak(c: u21) bool {
    switch (c) {
        '\n' => return true,
        else => return false,
    }
}
/// Test helpers
pub fn expectLines(description: []const u8, docXml: []const u8, available_space: mod.constants.AvailableSpacePoint, comptime loc: std.builtin.SourceLocation) !void {
    var tree = try mod.docFromXml(std.testing.allocator, docXml, .{});
    defer tree.deinit();

    var lt = try mod.LayoutTree.fromTree(std.testing.allocator, &tree);
    defer lt.deinit();
    var layout_context = mod.LayoutContext{
        .doc_tree = &tree,
        .layout_tree = &lt,
        .allocator = std.testing.allocator,
    };
    try mod.computeLayout(&layout_context, available_space);

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    const writer = buf.writer().any();

    // Print input XML
    try writer.print("Input XML:\n{s}\n\n", .{docXml});

    try writer.print("DocTree:\n", .{});
    try tree.print(writer);

    try writer.print("LayoutTree:\n", .{});
    try lt.printRoot(writer);

    // Add rendered text output for easier debugging
    try writer.print("\nRendered Text Output:\n", .{});
    try printRenderedText(&lt, writer);

    try snapshot.expectMatchSnapshot(loc, std.testing.allocator, description, buf.items);
}

/// Helper function to extract and print rendered text from line boxes
fn printRenderedText(layout_tree: *mod.LayoutTree, writer: anytype) !void {
    var inline_context_count: usize = 0;
    try collectAndPrintLinesByContext(layout_tree, 0, writer, &inline_context_count);
    if (inline_context_count == 0) {
        try writer.writeAll("(no rendered text)\n");
    }
}

fn collectAndPrintLinesByContext(layout_tree: *mod.LayoutTree, node_id: mod.LayoutTree.LayoutNode.Id, writer: anytype, context_count: *usize) !void {
    const node = layout_tree.getNodePtr(node_id);

    switch (node.data) {
        .inline_container_node => |*inline_container| {
            // Print lines from inline containers
            const lines = inline_container.line_boxes.items();
            if (lines.len > 0) {
                context_count.* += 1;
                try writer.print("Inline Context #{}: {} line(s)\n", .{ context_count.*, lines.len });

                for (lines, 0..) |line, line_idx| {
                    // Concatenate all fragment texts in the line
                    var line_text = std.ArrayList(u8).init(std.testing.allocator);
                    defer line_text.deinit();

                    for (line.fragments.items) |fragment| {
                        try line_text.appendSlice(fragment.text);
                    }

                    // Escape and print the line content
                    var escaped_text = std.ArrayList(u8).init(std.testing.allocator);
                    defer escaped_text.deinit();
                    try escapeText(line_text.items, &escaped_text);

                    try writer.print("  Line {}: \"{s}\"\n", .{ line_idx, escaped_text.items });
                }
                try writer.writeAll("\n");
            }
        },
        else => {},
    }

    // Recursively process children
    const children = layout_tree.getChildren(node_id);
    for (children) |child_id| {
        try collectAndPrintLinesByContext(layout_tree, child_id, writer, context_count);
    }
}

/// Escape special characters for better readability in snapshots
fn escapeText(input: []const u8, output: *std.ArrayList(u8)) !void {
    for (input) |c| {
        switch (c) {
            '\n' => try output.appendSlice("\\n"),
            '\t' => try output.appendSlice("\\t"),
            '\r' => try output.appendSlice("\\r"),
            '\\' => try output.appendSlice("\\\\"),
            '"' => try output.appendSlice("\\\""),
            else => try output.append(c),
        }
    }
}

test "line builder" {
    const allocator = std.testing.allocator;
    _ = allocator; // autofix

    try expectLines(
        "line builder",
        \\<div>
        \\  <p>Hello,    &#10;   world!</p>
        \\  <p>Hello,    &#10;<span>   world!</span></p>
        \\</div>
    ,
        .{ .x = .{ .definite = 30 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Remove spaces around segment breaks" {
    try expectLines(
        "spaces around segment breaks",
        \\<div>
        \\  <p>Before   &#10;   After</p>
        \\  <p>Multiple&#9;&#9;&#10;&#9;&#9;tabs</p>
        \\  <p>Mixed &#9; &#10; &#9; spaces</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Process consecutive segment breaks" {
    try expectLines(
        "consecutive segment breaks",
        \\<div>
        \\  <p>Line1&#10;&#10;&#10;Line2</p>
        \\  <p>Single&#10;break</p>
        \\  <p>Mixed&#10;&#10;multiple&#10;breaks</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Convert tabs to spaces" {
    try expectLines(
        "convert tabs to spaces",
        \\<div>
        \\  <p>Hello&#9;world</p>
        \\  <p>Multiple&#9;&#9;&#9;tabs</p>
        \\  <p>Mixed&#9;content&#9;here</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Collapse consecutive spaces" {
    try expectLines(
        "collapse consecutive spaces",
        \\<div>
        \\  <p>Multiple     spaces</p>
        \\  <p>Very        many          spaces</p>
        \\  <p>End with spaces   </p>
        \\  <p>   Start with spaces</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Complex mixed whitespace" {
    try expectLines(
        "complex mixed whitespace",
        \\<div>
        \\  <p>Complex   &#9;&#9; &#10;   &#9; test</p>
        \\  <p>Before&#9;&#9;&#10;&#10;&#9;after</p>
        \\  <p>Multiple   &#9; &#10;&#10;&#10; &#9;  end</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Fragment boundary handling" {
    try expectLines(
        "fragment boundary whitespace",
        \\<div>
        \\  <p>Text <span>   &#10;   </span> more</p>
        \\  <p>Before<span>&#9;&#9;</span>&#10;<span>&#9;&#9;</span>after</p>
        \\  <p>Complex <em>  &#9; </em>&#10;<strong> &#9;  </strong> test</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Edge cases - empty and whitespace-only" {
    try expectLines(
        "edge cases empty and whitespace",
        \\<div>
        \\  <p></p>
        \\  <p>   </p>
        \\  <p>&#9;&#9;&#9;</p>
        \\  <p>&#10;&#10;&#10;</p>
        \\  <p>   &#9; &#10; &#9;   </p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Start and end whitespace" {
    try expectLines(
        "start and end whitespace",
        \\<div>
        \\  <p>   Leading spaces</p>
        \\  <p>Trailing spaces   </p>
        \\  <p>&#9;&#9;Leading tabs</p>
        \\  <p>Trailing tabs&#9;&#9;</p>
        \\  <p>&#10;Leading break</p>
        \\  <p>Trailing break&#10;</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Single character sequences" {
    try expectLines(
        "single character sequences",
        \\<div>
        \\  <p>a &#10; b</p>
        \\  <p>x&#9;y</p>
        \\  <p>m   n</p>
        \\  <p>p&#10;&#10;q</p>
        \\  <p>r &#9; &#10; s</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: Nested elements with whitespace" {
    try expectLines(
        "nested elements whitespace",
        \\<div>
        \\  <p>Before <em>  inside  </em> after</p>
        \\  <p>Text<span>&#9;</span>&#10;<span>&#9;</span>more</p>
        \\  <p>Deep <strong>very <em>  nested  </em> content</strong> end</p>
        \\  <p>Multiple <span> &#9; </span> <em> &#10; </em> <strong>   </strong> spans</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: All rules combined stress test" {
    try expectLines(
        "all rules combined stress test",
        \\<div>
        \\  <p>Start   &#9;&#9; &#10;&#10;&#10;   &#9;  middle   &#9; &#10;   end</p>
        \\  <p>Complex<span>   &#9; </span>&#10;&#10;<em>&#9;&#9;</em>&#10;<strong>   </strong>test</p>
        \\  <p>Maximum     &#9;&#9;&#9;     &#10;&#10;&#10;&#10;     &#9;&#9;     complexity</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

/// Convert tabs and segment breaks to spaces for preserve-spaces mode
fn convertTabsAndSegmentBreaksToSpaces(self: *Self) !void {
    var iter = IterCodepointWithPosition.init(&self.lines);
    var ranges_to_replace = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    defer ranges_to_replace.deinit();

    while (iter.next()) |item| {
        const codepoint = item.codepoint;

        // Convert tabs and segment breaks to spaces (preserve-spaces mode)
        if (codepoint == '\t' or isSegmentBreak(codepoint)) {
            try ranges_to_replace.append(.{
                .start = item.pos,
                .end = BytePosition{
                    .line_index = item.pos.line_index,
                    .fragment_index = item.pos.fragment_index,
                    .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable),
                },
            });
        }
    }

    // Apply all replacements in reverse order to avoid position shifts
    var i = ranges_to_replace.items.len;
    while (i > 0) {
        i -= 1;
        try self.replaceRangeWithSpace(ranges_to_replace.items[i].start, ranges_to_replace.items[i].end);
    }
}

/// Mark space sequences for preserve and preserve-spaces modes
/// In these modes, sequences of spaces are treated as non-breaking spaces
/// with soft wrap opportunities at the end of each maximal sequence
fn markPreserveSpaceSequences(self: *Self) !void {
    var iter = IterCodepointWithPosition.init(&self.lines);
    var sequences = std.ArrayList(struct { start: BytePosition, end: BytePosition }).init(self.allocator);
    defer sequences.deinit();

    var space_sequence_start: ?BytePosition = null;

    while (iter.next()) |item| {
        const codepoint = item.codepoint;

        if (codepoint == ' ' or codepoint == '\t') {
            // Start or continue a space/tab sequence
            if (space_sequence_start == null) {
                space_sequence_start = item.pos;
            }
        } else {
            // End of space/tab sequence
            if (space_sequence_start != null) {
                try sequences.append(.{
                    .start = space_sequence_start.?,
                    .end = item.pos,
                });
                space_sequence_start = null;
            }
        }
    }

    // Handle sequence that goes to end of text
    if (space_sequence_start != null) {
        var end_iter = IterCodepointWithPosition.init(&self.lines);
        var last_pos = BytePosition{ .line_index = 0, .fragment_index = 0, .byte_index = 0 };

        while (end_iter.next()) |item| {
            last_pos = BytePosition{
                .line_index = item.pos.line_index,
                .fragment_index = item.pos.fragment_index,
                .byte_index = item.pos.byte_index + (std.unicode.utf8CodepointSequenceLength(item.codepoint) catch unreachable),
            };
        }

        try sequences.append(.{
            .start = space_sequence_start.?,
            .end = last_pos,
        });
    }

    // TODO: Mark these sequences for special treatment in later phases
    // For now, we store the information but don't modify the text
    // The actual non-breaking space treatment and soft wrap opportunities
    // will be handled during line breaking and rendering phases

    // Store sequences for later processing (this will be used in Phase 2/3)
    for (sequences.items) |sequence| {
        _ = sequence; // For now, just acknowledge we found them
        // In a complete implementation, we'd mark fragments or store metadata
        // about these sequences for the line breaking algorithm
    }
}

test "Phase 1: preserve-spaces mode - tabs and breaks to spaces" {
    try expectLines(
        "preserve-spaces tabs and breaks",
        \\<div style="white-space-collapse: preserve-spaces">
        \\  <p>Hello&#9;world&#10;test</p>
        \\  <p>Multiple&#9;&#9;tabs&#10;&#10;breaks</p>
        \\  <p>Mixed&#9;content&#10;here</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "Phase 1: preserve mode - space sequences" {
    try expectLines(
        "preserve mode sequences",
        \\<div style="white-space-collapse: preserve">
        \\  <p>Multiple     spaces</p>
        \\  <p>Tab&#9;&#9;sequences</p>
        \\  <p>Mixed   &#9;   content</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: normal (collapse + wrap)" {
    try expectLines(
        "white-space normal",
        \\<div>
        \\  <p style="white-space: normal">Before   &#10;   After</p>
        \\  <p style="white-space: normal">Multiple&#9;&#9;&#9;tabs</p>
        \\  <p style="white-space: normal">Very     many     spaces</p>
        \\  <p style="white-space: normal">Complex   &#9; &#10;&#10;   test</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: pre (preserve + nowrap)" {
    try expectLines(
        "white-space pre",
        \\<div>
        \\  <p style="white-space: pre">Before   &#10;   After</p>
        \\  <p style="white-space: pre">Multiple&#9;&#9;&#9;tabs</p>
        \\  <p style="white-space: pre">Very     many     spaces</p>
        \\  <p style="white-space: pre">Complex   &#9; &#10;&#10;   test</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: pre-wrap (preserve + wrap)" {
    try expectLines(
        "white-space pre-wrap",
        \\<div>
        \\  <p style="white-space: pre-wrap">Before   &#10;   After</p>
        \\  <p style="white-space: pre-wrap">Multiple&#9;&#9;&#9;tabs</p>
        \\  <p style="white-space: pre-wrap">Very     many     spaces</p>
        \\  <p style="white-space: pre-wrap">Complex   &#9; &#10;&#10;   test</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: nowrap (collapse + nowrap)" {
    try expectLines(
        "white-space nowrap",
        \\<div>
        \\  <p style="white-space: nowrap">Before   &#10;   After</p>
        \\  <p style="white-space: nowrap">Multiple&#9;&#9;&#9;tabs</p>
        \\  <p style="white-space: nowrap">Very     many     spaces</p>
        \\  <p style="white-space: nowrap">Complex   &#9; &#10;&#10;   test</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: Mixed elements with different values" {
    try expectLines(
        "white-space mixed values",
        \\<div>
        \\  <p style="white-space: normal">Normal:   &#9; &#10;   collapse</p>
        \\  <p style="white-space: pre">Pre:   &#9; &#10;   preserve</p>
        \\  <p style="white-space: pre-wrap">Pre-wrap:   &#9; &#10;   preserve+wrap</p>
        \\  <p style="white-space: nowrap">Nowrap:   &#9; &#10;   collapse+nowrap</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 80 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: Nested elements with inheritance" {
    try expectLines(
        "white-space inheritance",
        \\<div style="white-space: normal">
        \\  <p>Parent normal: &#9; &#10; collapsed</p>
        \\  <p style="white-space: pre">Child pre: &#9; &#10; preserved</p>
        \\  <p><span style="white-space: pre-wrap">Nested pre-wrap: &#9; &#10; preserved</span></p>
        \\  <p>Back to normal: &#9; &#10; collapsed</p>
        \\</div>
    ,
        .{ .x = .{ .definite = 60 }, .y = .max_content },
        @src(),
    );
}

test "CSS white-space: Edge cases with empty and whitespace-only content" {
    try expectLines(
        "white-space edge cases",
        \\<div>
        \\  <p style="white-space: normal"></p>
        \\  <p style="white-space: normal">   &#9; &#10;   </p>
        \\  <p style="white-space: pre">   &#9; &#10;   </p>
        \\  <p style="white-space: pre-wrap">   &#9; &#10;   </p>
        \\  <p style="white-space: nowrap">   &#9; &#10;   </p>
        \\</div>
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
        @src(),
    );
}
