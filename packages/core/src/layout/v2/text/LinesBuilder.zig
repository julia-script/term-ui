const mod = @import("../mod.zig");
const LineBox = @import("./LineBox.zig");
const LineBoxFragment = @import("./LineBoxFragment.zig");
const std = @import("std");
const ArrayList = std.ArrayList;
const LineBreakStream = @import("../../../uni/LineBreakStream.zig");
const WhiteSpaceProcessor = @import("./white-space-processor.zig").WhiteSpaceProcessor;
const WhiteSpaceCollapse = @import("../../../styles/white-space.zig").WhiteSpaceCollapse;
const WhiteSpace = @import("../../../styles/white-space.zig").WhiteSpace;
const TextWrapMode = @import("../../../styles/white-space.zig").TextWrapMode;
const TabSize = @import("../../../styles/white-space.zig").TabSize;

lines: ArrayList(LineBox),
segmenter: LineBreakStream,
available_width: mod.constants.AvailableSpace,
white_space_processor: WhiteSpaceProcessor,
allocator: std.mem.Allocator,
text_inputs: ArrayList(TextInput),

const Self = @This();

/// Track text inputs and their corresponding node IDs for proper fragment creation
const TextInput = struct {
    node_id: u32,
    start_offset: u32, // Offset in the segmenter buffer where this text starts
    length: u32, // Length of the processed text
};

pub fn init(allocator: std.mem.Allocator, available_width: mod.constants.AvailableSpace) Self {
    return Self{
        .lines = ArrayList(LineBox).init(allocator),
        .segmenter = LineBreakStream.init(allocator),
        .available_width = available_width,
        .white_space_processor = WhiteSpaceProcessor.init(allocator),
        .allocator = allocator,
        .text_inputs = ArrayList(TextInput).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    // Deinitialize all lines (which will deinitialize their fragments and text)
    for (self.lines.items) |*line| {
        line.deinit();
    }
    self.lines.deinit();
    self.segmenter.buffer.deinit();
    self.text_inputs.deinit();
}

/// Transfer ownership of line boxes to caller, preventing deallocation when LinesBuilder is destroyed
/// Caller becomes responsible for deallocating the returned ArrayList and all fragment ArrayLists within each LineBox
pub fn toOwnedLineBoxes(self: *Self) ArrayList(LineBox) {
    // Transfer ownership of the lines ArrayList to the caller
    const owned_lines = self.lines;

    // Reset our internal lines to empty state to prevent double-free in deinit()
    self.lines = ArrayList(LineBox).init(self.allocator);

    return owned_lines;
}

fn addNewLine(self: *Self, available_width: f32) !void {
    const line = LineBox{
        .size = mod.CSSPoint{ .x = 0, .y = 0 },
        .available_width = available_width,
        .fragments = ArrayList(LineBoxFragment).init(self.allocator),
    };

    try self.lines.append(line);
}

fn ensureLine(self: *Self, available_width: f32) !void {
    if (self.lines.items.len == 0) {
        try self.addNewLine(available_width);
    }
}

/// Add text content with white-space processing according to CSS rules
pub fn addText(self: *Self, text: []const u8, white_space_mode: WhiteSpace) !void {
    try self.addTextWithNode(text, white_space_mode, 0);
}

/// Add text content with white-space processing and node ID tracking
pub fn addTextWithNode(self: *Self, text: []const u8, white_space_mode: WhiteSpace, node_id: u32) !void {
    // Process text according to white-space rules (Phase I)
    const processed_text = try self.white_space_processor.processTextWithWhiteSpace(text, white_space_mode);
    // Don't defer - we'll store this in the fragment
    
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
    
    for (processed_text, 0..) |byte, i| {
        if (byte == 0x0A) { // LF (forced line break)
            // Create fragment from line_start to current position (excluding LF)
            if (i > line_start) {
                const fragment_text = processed_text[line_start..i];
                try self.createFragment(fragment_text, white_space_mode, node_id, @intCast(line_start));
            }
            
            // Force a new line for the next content
            try self.ensureNewLine();
            line_start = i + 1;
        }
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
    const current_line = &self.lines.items[self.lines.items.len - 1];
    try current_line.fragments.append(fragment);
    
    // Update line size
    self.updateLineSize(current_line);
}

/// Ensure there's a current line, create one if none exists
fn ensureCurrentLine(self: *Self) !void {
    if (self.lines.items.len == 0) {
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

/// Update a line's size to match its fragments
fn updateLineSize(self: *Self, line: *LineBox) void {
    _ = self; // unused
    var total_width: f32 = 0;
    var max_height: f32 = 0;

    for (line.fragments.items) |fragment| {
        total_width += fragment.size.x;
        max_height = @max(max_height, fragment.size.y);
    }

    line.size = mod.CSSPoint{ .x = total_width, .y = max_height };
}

/// Add text content with specific collapse mode
pub fn addTextWithCollapse(self: *Self, text: []const u8, collapse_mode: WhiteSpaceCollapse) !void {
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
    defer self.allocator.free(processed_text);

    try self.segmenter.append(processed_text);
}

/// Add text with full preprocessing pipeline
/// This demonstrates the complete text preprocessing before LineBreakStream
pub fn addTextWithFullPreprocessing(self: *Self, text: []const u8, white_space_mode: WhiteSpace, tab_size: TabSize) !void {
    // Phase I: White-space processing (collapsing/transformation)
    const phase1_text = try self.white_space_processor.processTextWithWhiteSpace(text, white_space_mode);
    defer self.allocator.free(phase1_text);

    // Store metadata about processing for potential Phase II usage
    // In a real implementation, this would be associated with text fragments
    _ = tab_size; // Will be used in Phase II during actual rendering

    // Add processed text to line break segmenter
    try self.segmenter.append(phase1_text);
}

/// Add text content with wrap mode control
/// In nowrap mode, soft wrap opportunities are ignored but forced breaks are preserved
pub fn addTextWithWrapMode(self: *Self, text: []const u8, white_space_mode: WhiteSpace, wrap_mode: TextWrapMode) !void {
    // Phase I: White-space processing (collapsing/transformation)
    const phase1_text = try self.white_space_processor.processTextWithWhiteSpace(text, white_space_mode);
    defer self.allocator.free(phase1_text);

    if (wrap_mode == .nowrap) {
        // In nowrap mode, remove soft wrap opportunities but preserve forced line breaks
        const nowrap_text = try self.processTextForNowrap(phase1_text);
        defer self.allocator.free(nowrap_text);
        try self.segmenter.append(nowrap_text);
    } else {
        // In wrap mode, use normal line breaking
        try self.segmenter.append(phase1_text);
    }
}

/// Process text for nowrap mode: remove soft wrap opportunities, preserve forced breaks
/// Soft wrap opportunities are typically spaces and zero-width spaces (U+200B)
/// Forced line breaks are segment breaks like LF (U+000A)
fn processTextForNowrap(self: *Self, text: []const u8) ![]u8 {
    var result = try ArrayList(u8).initCapacity(self.allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        switch (codepoint) {
            // Preserve forced line breaks (segment breaks)
            0x000A => { // LF
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const start_pos = iter.i - char_len;
                try result.appendSlice(text[start_pos..iter.i]);
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
                try result.appendSlice(text[start_pos..iter.i]);
            },
        }
    }

    return result.toOwnedSlice();
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

/// Build lines with wrap mode consideration
/// Reorganizes existing fragments based on available width and wrap mode
pub fn buildLinesWithWrapMode(self: *Self, wrap_mode: TextWrapMode) !void {
    switch (self.available_width) {
        .definite => |width| {
            // Reorganize fragments to fit within the definite width
            if (wrap_mode == .nowrap) {
                // Keep existing layout but ensure no soft wrapping
                try self.reorganizeFragmentsNowrap();
            } else {
                // Reorganize fragments with soft wrapping at the available width
                try self.reorganizeFragmentsWithWrapping(width);
            }
        },
        .min_content, .max_content => {
            // For content-based sizing, keep the max_content layout we already have
            // (only forced breaks, no soft wrapping)
            // No reorganization needed
        },
    }
}

/// Reorganize fragments with soft wrapping at the specified width
fn reorganizeFragmentsWithWrapping(self: *Self, available_width: f32) !void {
    // Collect all existing fragments
    var all_fragments = std.ArrayList(LineBoxFragment).init(self.allocator);
    defer all_fragments.deinit();
    
    // Extract fragments from existing lines
    for (self.lines.items) |*line| {
        try all_fragments.appendSlice(line.fragments.items);
        line.fragments.deinit(); // Clear the old fragments list
    }
    
    // Clear existing lines 
    self.lines.clearAndFree();
    
    // Reorganize fragments into new lines based on available width
    try self.createLinesFromFragments(all_fragments.items, available_width);
}

/// Reorganize fragments for nowrap mode (keep existing line breaks, no new soft wraps)
fn reorganizeFragmentsNowrap(self: *Self) !void {
    _ = self; // unused
    // For nowrap mode, we keep the existing line organization 
    // (which is based on forced breaks only)
    // No reorganization needed
}

/// Create new lines from a list of fragments, respecting available width
fn createLinesFromFragments(self: *Self, fragments: []LineBoxFragment, available_width: f32) !void {
    var current_line_width: f32 = 0;
    var current_line: ?*LineBox = null;
    
    for (fragments) |fragment| {
        // Check if fragment fits on current line
        if (current_line != null and current_line_width + fragment.size.x <= available_width) {
            // Fragment fits, add to current line
            try current_line.?.fragments.append(fragment);
            current_line_width += fragment.size.x;
        } else {
            // Fragment doesn't fit or no current line, need to handle wrapping
            if (fragment.size.x <= available_width) {
                // Fragment fits on a line by itself, create new line
                try self.addNewLine(available_width);
                current_line = &self.lines.items[self.lines.items.len - 1];
                try current_line.?.fragments.append(fragment);
                current_line_width = fragment.size.x;
            } else {
                // Fragment is too wide, need to split it
                try self.splitFragmentAcrossLines(fragment, available_width, &current_line, &current_line_width);
            }
        }
        
        // Update line size after adding fragment(s)
        if (current_line != null) {
            self.updateLineSize(current_line.?);
        }
    }
}

/// Split a fragment across multiple lines when it's too wide to fit
fn splitFragmentAcrossLines(self: *Self, fragment: LineBoxFragment, available_width: f32, current_line: *?*LineBox, current_line_width: *f32) !void {
    // For now, implement a simple character-based splitting
    // In a real implementation, this should use proper line breaking algorithm
    // with soft wrap opportunities (spaces, hyphens, etc.)
    
    const text = fragment.text;
    var remaining_text = text;
    var text_start: usize = 0;
    var fragment_start_offset = fragment.start;
    
    while (remaining_text.len > 0) {
        // Find how much text fits on the current line
        var chars_that_fit: usize = 0;
        const width_so_far = current_line_width.*;
        
        // Simple character-by-character fitting (could be optimized)
        for (remaining_text, 0..) |_, i| {
            const char_slice = remaining_text[0..i+1];
            const char_width = self.measureTextWidth(char_slice);
            
            if (width_so_far + char_width <= available_width) {
                chars_that_fit = i + 1;
            } else {
                break;
            }
        }
        
        // If nothing fits and we have a current line, start a new line
        if (chars_that_fit == 0 and current_line.* != null) {
            try self.addNewLine(available_width);
            current_line.* = &self.lines.items[self.lines.items.len - 1];
            current_line_width.* = 0;
            continue;
        }
        
        // If still nothing fits (character too wide), take at least one character
        if (chars_that_fit == 0) {
            chars_that_fit = 1;
        }
        
        // Create fragment for the portion that fits
        const partial_text = remaining_text[0..chars_that_fit];
        const owned_partial_text = try self.allocator.dupe(u8, partial_text);
        
        const partial_fragment = LineBoxFragment{
            .l_node_id = fragment.l_node_id,
            .start = fragment_start_offset,
            .length = @intCast(chars_that_fit),
            .size = mod.CSSPoint{ .x = self.measureTextWidth(partial_text), .y = fragment.size.y },
            .is_atomic = fragment.is_atomic,
            .white_space_info = fragment.white_space_info,
            .text = owned_partial_text,
            .allocator = self.allocator,
        };
        
        // Ensure we have a current line
        if (current_line.* == null) {
            try self.addNewLine(available_width);
            current_line.* = &self.lines.items[self.lines.items.len - 1];
            current_line_width.* = 0;
        }
        
        // Add partial fragment to current line
        try current_line.*.?.fragments.append(partial_fragment);
        current_line_width.* += partial_fragment.size.x;
        
        // Move to next portion
        remaining_text = remaining_text[chars_that_fit..];
        text_start += chars_that_fit;
        fragment_start_offset += @intCast(chars_that_fit);
        
        // If there's more text, we'll need a new line
        if (remaining_text.len > 0) {
            try self.addNewLine(available_width);
            current_line.* = &self.lines.items[self.lines.items.len - 1];
            current_line_width.* = 0;
        }
    }
    
    // Free the original fragment's text since we've created new fragments
    fragment.allocator.free(fragment.text);
}

/// Build lines for nowrap mode: only break at forced line breaks
fn buildLinesNowrap(self: *Self) !void {
    const text = self.segmenter.buffer.items;
    var line_start: usize = 0;
    var line_count: usize = 0;

    // Split text only at forced line breaks (LF)
    for (text, 0..) |byte, i| {
        if (byte == 0x0A) { // LF (forced line break)
            // Create line from line_start to current position (excluding LF)
            const line_text = text[line_start..i];
            if (line_text.len > 0) { // Only create non-empty lines
                try self.createLineFromText(line_text);
                line_count += 1;
            }
            // Start new line after the break
            line_start = i + 1;
        }
    }

    // Handle remaining text after last line break
    if (line_start < text.len) {
        const remaining_text = text[line_start..];
        if (remaining_text.len > 0) { // Only create non-empty lines
            try self.createLineFromText(remaining_text);
            line_count += 1;
        }
    }
}

/// Build lines for normal wrap mode: break at soft wrap opportunities when needed
fn buildLinesWrap(self: *Self) !void {
    const text = self.segmenter.buffer.items;
    if (text.len == 0) return;

    switch (self.available_width) {
        .definite => |width| {
            // Use buffer-based line wrapping with width constraints
            try self.wrapBufferToLines(width);
        },
        .min_content, .max_content => {
            // For content-based sizing, only break at forced breaks (like \n)
            // but don't do soft wrapping
            try self.buildLinesNoWrapButPreserveBreaks();
        },
    }
}

/// Build lines with no soft wrapping but preserve forced breaks (for min/max content)
fn buildLinesNoWrapButPreserveBreaks(self: *Self) !void {
    const buffer = self.segmenter.buffer.items;
    if (buffer.len == 0) return;

    var line_start: usize = 0;

    // Only break at forced line breaks (LF), not at soft wrap opportunities
    for (buffer, 0..) |byte, i| {
        if (byte == 0x0A) { // LF (forced line break)
            // Create line from line_start to current position (excluding LF)
            if (i > line_start) {
                try self.createLineFromBufferRange(line_start, i);
            }
            // Force a new line for the next content
            try self.addNewLine(switch (self.available_width) {
                .definite => |width| width,
                .min_content, .max_content => 999999.0, // Large value for content-based width
            });
            // Start new line after the break
            line_start = i + 1;
        }
    }

    // Handle remaining text after last line break
    if (line_start < buffer.len) {
        try self.createLineFromBufferRange(line_start, buffer.len);
    }
}

/// Wrap buffer to lines using soft wrap opportunities with proper position tracking
fn wrapBufferToLines(self: *Self, available_width: f32) !void {
    const buffer = self.segmenter.buffer.items;
    if (buffer.len == 0) return;

    var line_start: usize = 0;
    var current_width: f32 = 0;
    var last_break_opportunity: ?usize = null;
    var last_break_width: f32 = 0;

    var iter = std.unicode.Utf8Iterator{ .bytes = buffer, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        const char_width = self.getCharacterWidth(codepoint);

        // Check if this character is a soft wrap opportunity
        if (self.isSoftWrapOpportunity(codepoint)) {
            last_break_opportunity = iter.i;
            last_break_width = current_width + char_width;
        }

        // Check for forced line breaks
        if (codepoint == 0x000A) { // LF (forced line break)
            // Create line up to this point (excluding the LF)
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const line_end = iter.i - char_len;
            if (line_end > line_start) {
                try self.createLineFromBufferRange(line_start, line_end);
            }

            // Force a new line for the next content
            try self.addNewLine(available_width);

            // Start new line after the break
            line_start = iter.i;
            current_width = 0;
            last_break_opportunity = null;
            last_break_width = 0;
            continue;
        }

        // Check if adding this character would exceed available width
        if (current_width + char_width > available_width) {
            // We need to break the line
            if (last_break_opportunity != null and last_break_opportunity.? > line_start) {
                // Break at the last soft wrap opportunity
                const break_point = last_break_opportunity.?;
                try self.createLineFromBufferRange(line_start, break_point);

                // Create a new line for the next content
                try self.addNewLine(available_width);

                // Skip the break character and any following whitespace
                line_start = self.skipWhitespaceAfterBreakInBuffer(buffer, break_point);

                // Reset width calculation from the new line start
                current_width = self.measureTextWidth(buffer[line_start..iter.i]);
                last_break_opportunity = null;
                last_break_width = 0;
            } else {
                // No suitable break point found - force break at current position
                // This handles cases with very long words
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const break_point = iter.i - char_len;
                if (break_point > line_start) {
                    try self.createLineFromBufferRange(line_start, break_point);

                    // Create a new line for the next content
                    try self.addNewLine(available_width);

                    line_start = break_point;
                    current_width = char_width;
                } else {
                    // Single character that's too wide - still need to place it somewhere
                    current_width += char_width;
                }
                last_break_opportunity = null;
                last_break_width = 0;
            }
        } else {
            current_width += char_width;
        }
    }

    // Handle remaining text at end
    if (line_start < buffer.len) {
        try self.createLineFromBufferRange(line_start, buffer.len);
    }
}

/// Wrap text to lines using soft wrap opportunities with position tracking
fn wrapTextToLines(self: *Self, text: []const u8, available_width: f32) !void {
    try self.wrapTextToLinesWithNode(text, available_width, 0);
}

/// Wrap text to lines using soft wrap opportunities with node ID tracking
fn wrapTextToLinesWithNode(self: *Self, text: []const u8, available_width: f32, node_id: u32) !void {
    var line_start: usize = 0;
    var current_width: f32 = 0;
    var last_break_opportunity: ?usize = null;
    var last_break_width: f32 = 0;

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        const char_width = self.getCharacterWidth(codepoint);

        // Check if this character is a soft wrap opportunity
        if (self.isSoftWrapOpportunity(codepoint)) {
            last_break_opportunity = iter.i;
            last_break_width = current_width + char_width;
        }

        // Check for forced line breaks
        if (codepoint == 0x000A) { // LF (forced line break)
            // Create line up to this point (excluding the LF)
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const line_end = iter.i - char_len;
            if (line_end > line_start) {
                try self.createLineFromTextWithPosition(text[line_start..line_end], @intCast(line_start), node_id);
            }

            // Start new line after the break
            line_start = iter.i;
            current_width = 0;
            last_break_opportunity = null;
            last_break_width = 0;
            continue;
        }

        // Check if adding this character would exceed available width
        if (current_width + char_width > available_width) {
            // We need to break the line
            if (last_break_opportunity != null and last_break_opportunity.? > line_start) {
                // Break at the last soft wrap opportunity
                const break_point = last_break_opportunity.?;
                try self.createLineFromTextWithPosition(text[line_start..break_point], @intCast(line_start), node_id);

                // Skip the break character and any following whitespace
                line_start = self.skipWhitespaceAfterBreak(text, break_point);

                // Reset width calculation from the new line start
                current_width = self.measureTextWidth(text[line_start..iter.i]);
                last_break_opportunity = null;
                last_break_width = 0;
            } else {
                // No suitable break point found - force break at current position
                // This handles cases with very long words
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const break_point = iter.i - char_len;
                if (break_point > line_start) {
                    try self.createLineFromTextWithPosition(text[line_start..break_point], @intCast(line_start), node_id);
                    line_start = break_point;
                    current_width = char_width;
                } else {
                    // Single character that's too wide - still need to place it somewhere
                    current_width += char_width;
                }
                last_break_opportunity = null;
                last_break_width = 0;
            }
        } else {
            current_width += char_width;
        }
    }

    // Handle remaining text at end
    if (line_start < text.len) {
        try self.createLineFromTextWithPosition(text[line_start..], @intCast(line_start), node_id);
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

/// Get the width of a character for line wrapping calculations
fn getCharacterWidth(self: *Self, codepoint: u21) f32 {
    _ = self; // unused for now
    return switch (codepoint) {
        // Zero-width characters
        0x200B => 0.0, // ZERO WIDTH SPACE
        0x200C => 0.0, // ZERO WIDTH NON-JOINER
        0x200D => 0.0, // ZERO WIDTH JOINER
        0x00AD => 0.0, // SOFT HYPHEN (only visible when breaking)
        // Tab character - use tab-size
        0x0009 => 8.0, // TAB (simplified - should use actual tab-size)
        // Regular characters - simplified as 1 unit each
        else => 1.0,
    };
}

/// Skip whitespace after a line break opportunity
fn skipWhitespaceAfterBreak(self: *Self, text: []const u8, break_point: usize) usize {
    _ = self; // unused for now
    var pos = break_point;

    // Skip the break character itself if it's whitespace
    while (pos < text.len) {
        const byte = text[pos];
        if (byte == 0x20 or byte == 0x09) { // SPACE or TAB
            pos += 1;
        } else {
            break;
        }
    }

    return pos;
}

/// Skip whitespace after a line break opportunity in buffer
fn skipWhitespaceAfterBreakInBuffer(self: *Self, buffer: []const u8, break_point: usize) usize {
    _ = self; // unused for now
    var pos = break_point;

    // Skip the break character itself if it's whitespace
    while (pos < buffer.len) {
        const byte = buffer[pos];
        if (byte == 0x20 or byte == 0x09) { // SPACE or TAB
            pos += 1;
        } else {
            break;
        }
    }

    return pos;
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

/// Ensure forced line breaks are preserved regardless of wrap mode
/// This function scans text and creates line breaks at all forced break characters
fn preserveForcedLineBreaks(self: *Self, text: []const u8) !void {
    if (text.len == 0) return;

    var line_start: usize = 0;
    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        if (isForcedLineBreak(codepoint)) {
            // Create line up to this point (excluding the break character)
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const line_end = iter.i - char_len;

            // Always create a line, even if it's empty (important for consecutive breaks)
            const line_text = text[line_start..line_end];
            if (line_text.len > 0) {
                try self.createLineFromText(line_text);
            } else {
                // Create empty line - add a line with minimal content
                try self.addNewLine(switch (self.available_width) {
                    .definite => |width| width,
                    .min_content, .max_content => 999999.0,
                });
            }

            // Start new line after the break
            line_start = iter.i;
        }
    }

    // Handle remaining text after last forced break
    if (line_start < text.len) {
        try self.createLineFromText(text[line_start..]);
    }
}

/// Build lines with forced break preservation as the primary strategy
/// This ensures forced breaks are always honored regardless of wrap mode
pub fn buildLinesWithForcedBreakPreservation(self: *Self, wrap_mode: TextWrapMode) !void {
    const text = self.segmenter.buffer.items;
    if (text.len == 0) return;

    // Check if text contains any forced line breaks
    var has_forced_breaks = false;
    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iter.nextCodepoint()) |codepoint| {
        if (isForcedLineBreak(codepoint)) {
            has_forced_breaks = true;
            break;
        }
    }

    if (has_forced_breaks) {
        // Use forced break preservation strategy
        try self.preserveForcedLineBreaks(text);
    } else {
        // No forced breaks, use wrap mode strategy
        if (wrap_mode == .nowrap) {
            // In nowrap mode without forced breaks, put all text on one line
            try self.createLineFromText(text);
        } else {
            // In wrap mode without forced breaks, use normal wrapping
            const available_width = switch (self.available_width) {
                .definite => |width| width,
                .min_content, .max_content => 999999.0,
            };
            try self.wrapTextToLines(text, available_width);
        }
    }
}

/// Find which text input a buffer position belongs to
fn findTextInputForPosition(self: *Self, buffer_pos: u32) ?struct { input: *const TextInput, local_pos: u32 } {
    for (self.text_inputs.items) |*input| {
        const input_end = input.start_offset + input.length;
        if (buffer_pos >= input.start_offset and buffer_pos < input_end) {
            return .{
                .input = input,
                .local_pos = buffer_pos - input.start_offset,
            };
        }
    }
    return null;
}

/// Update a line's size to match its fragments

/// Create a line box containing the given text as a fragment
fn createLineFromText(self: *Self, text: []const u8) !void {
    try self.createLineFromTextWithPosition(text, 0, 0);
}

/// Create a line box containing the given text as a fragment with position tracking
fn createLineFromTextWithPosition(self: *Self, text: []const u8, start_pos: u32, node_id: u32) !void {
    // Always create a new line for this text
    try self.addNewLine(switch (self.available_width) {
        .definite => |width| width,
        .min_content, .max_content => 999999.0, // Large value for content-based width
    });

    // Create fragment with proper position tracking
    const owned_text = try self.allocator.dupe(u8, text);
    const fragment = LineBoxFragment{
        .l_node_id = node_id,
        .start = start_pos,
        .length = @intCast(text.len),
        .size = mod.CSSPoint{ .x = self.measureTextWidth(text), .y = 1.0 },
        .is_atomic = false,
        .white_space_info = .{
            .has_preserved_spaces = false,
            .has_preserved_tabs = false,
            .has_collapsible_spaces = false,
            .original_white_space_mode = .normal,
            .tab_size = .{ .number = 8 },
        },
        .text = owned_text,
        .allocator = self.allocator,
    };

    // Add fragment to the newly created line
    const current_line = &self.lines.items[self.lines.items.len - 1];
    try current_line.fragments.append(fragment);

    // Update line size to match fragments
    self.updateLineSize(current_line);
}

/// Create a line box from a buffer range with proper node ID and position tracking
fn createLineFromBufferRange(self: *Self, buffer_start: usize, buffer_end: usize) !void {
    if (buffer_end <= buffer_start) return;

    const buffer = self.segmenter.buffer.items;

    // Find or create the current line
    if (self.lines.items.len == 0) {
        try self.addNewLine(switch (self.available_width) {
            .definite => |width| width,
            .min_content, .max_content => 999999.0, // Large value for content-based width
        });
    }

    // Create fragments for each node that overlaps with this buffer range
    var current_pos = buffer_start;

    while (current_pos < buffer_end) {
        // Find which text input this position belongs to
        if (self.findTextInputForPosition(@intCast(current_pos))) |found| {
            // Calculate how much of this node's content is in our range
            const node_start_in_buffer = found.input.start_offset;
            const node_end_in_buffer = found.input.start_offset + found.input.length;

            // Find the intersection of our range with this node's range
            const fragment_start = @max(current_pos, node_start_in_buffer);
            const fragment_end = @min(buffer_end, node_end_in_buffer);

            if (fragment_start < fragment_end) {
                const fragment_text = buffer[fragment_start..fragment_end];
                const local_start = fragment_start - node_start_in_buffer;

                // Create fragment for this portion
                const owned_text = try self.allocator.dupe(u8, fragment_text);
                const fragment = LineBoxFragment{
                    .l_node_id = found.input.node_id,
                    .start = @intCast(local_start),
                    .length = @intCast(fragment_end - fragment_start),
                    .size = mod.CSSPoint{ .x = self.measureTextWidth(fragment_text), .y = 1.0 },
                    .is_atomic = false,
                    .white_space_info = .{
                        .has_preserved_spaces = false,
                        .has_preserved_tabs = false,
                        .has_collapsible_spaces = false,
                        .original_white_space_mode = .normal,
                        .tab_size = .{ .number = 8 },
                    },
                    .text = owned_text,
                    .allocator = self.allocator,
                };

                // Add fragment to the current line
                const current_line = &self.lines.items[self.lines.items.len - 1];
                try current_line.fragments.append(fragment);

                current_pos = fragment_end;
            } else {
                current_pos += 1; // Advance to avoid infinite loop
            }
        } else {
            // No matching text input found, skip this position
            current_pos += 1;
        }
    }

    // Update line size to match all fragments
    const current_line = &self.lines.items[self.lines.items.len - 1];
    self.updateLineSize(current_line);
}

/// Mark text input as complete and finalize line breaking
pub fn finalizeText(self: *Self) void {
    self.segmenter.markStreamDone();
}

fn build(self: *Self) ArrayList(LineBox) {
    return self.lines;
}

test "LinesBuilder white-space integration" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
    defer builder.deinit();

    // Test basic white-space processing
    try builder.addText("hello  \t\nworld", .normal);
    builder.finalizeText();

    // Verify that text was processed and added to segmenter
    // The processed text should be collapsed according to normal mode rules
    const buffer_content = builder.segmenter.buffer.items;
    try testing.expect(buffer_content.len > 0);

    // The exact content depends on the white-space processing
    // For normal mode: "hello  \t\nworld" should become "hello world"
    try testing.expect(std.mem.indexOf(u8, buffer_content, "hello world") != null);
}

test "LinesBuilder different white-space modes" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test normal mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addText("a  \t\n  b", .normal);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should collapse to "a b"
        try testing.expect(std.mem.indexOf(u8, content, "a b") != null);
    }

    // Test pre mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addText("a  \t\n  b", .pre);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should preserve all whitespace including tabs and newlines
        try testing.expect(std.mem.indexOf(u8, content, "\t") != null);
        try testing.expect(std.mem.indexOf(u8, content, "\n") != null);
    }

    // Test nowrap mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addText("a  \t\n  b", .nowrap);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should collapse whitespace like normal mode
        try testing.expect(std.mem.indexOf(u8, content, "a b") != null);
    }
}

test "LinesBuilder preserve-spaces and break-spaces modes" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test preserve-spaces mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addPreserveSpacesText("hello\tworld\ntest");
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Tabs and newlines should be converted to spaces
        try testing.expect(std.mem.indexOf(u8, content, "hello world test") != null);
    }

    // Test break-spaces mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addBreakSpacesText("hello world");
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should contain soft wrap opportunity markers (zero-width spaces)
        try testing.expect(std.mem.indexOf(u8, content, "\u{200B}") != null);
    }
}

test "LinesBuilder with collapse mode" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
    defer builder.deinit();

    try builder.addTextWithCollapse("hello   world", .collapse);
    builder.finalizeText();

    const content = builder.segmenter.buffer.items;
    // Multiple spaces should be collapsed to single space
    try testing.expect(std.mem.indexOf(u8, content, "hello world") != null);
    try testing.expect(std.mem.indexOf(u8, content, "   ") == null);
}

test "LinesBuilder full preprocessing pipeline" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
    defer builder.deinit();

    // Test full preprocessing with white-space and tab-size
    const tab_size = TabSize{ .number = 4.0 };
    try builder.addTextWithFullPreprocessing("hello\t\t  \n\n  world", .normal, tab_size);
    builder.finalizeText();

    const content = builder.segmenter.buffer.items;

    // With normal mode, this should be collapsed according to Phase I rules:
    // 1. Spaces/tabs around segment breaks removed
    // 2. Segment breaks transformed (likely to spaces for normal mode)
    // 3. Tabs converted to spaces
    // 4. Consecutive spaces collapsed
    // Expected result should be roughly "hello world"
    try testing.expect(content.len > 0);
    try testing.expect(std.mem.indexOf(u8, content, "hello") != null);
    try testing.expect(std.mem.indexOf(u8, content, "world") != null);
}

test "LinesBuilder preprocessing with different modes" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test normal mode preprocessing
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const tab_size = TabSize.DEFAULT;
        try builder.addTextWithFullPreprocessing("a\t\n  b", .normal, tab_size);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should collapse to something like "a b"
        try testing.expect(std.mem.indexOf(u8, content, "a") != null);
        try testing.expect(std.mem.indexOf(u8, content, "b") != null);
    }

    // Test pre mode preprocessing
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const tab_size = TabSize{ .number = 4.0 };
        try builder.addTextWithFullPreprocessing("a\t\nb", .pre, tab_size);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should preserve tabs and newlines
        try testing.expect(std.mem.indexOf(u8, content, "\t") != null);
        try testing.expect(std.mem.indexOf(u8, content, "\n") != null);
    }
}
pub fn print(self: *Self, writer: std.io.AnyWriter) !void {
    for (self.lines.items, 0..) |line, i| {
        try writer.print("[#{d} size: {any}", .{ i, line.size });
        if (line.fragments.items.len > 0) {
            try writer.print(" fragments: ", .{});
        }

        for (line.fragments.items) |_fragment| {
            const fragment: LineBoxFragment = _fragment;

            try writer.print(" node#{d} {any} range {d}~{d}", .{ fragment.l_node_id, fragment.size, fragment.start, fragment.start + fragment.length });
        }
        try writer.print("]\n", .{});
    }
}
test "LinesBuilder.print" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    var builder = init(testing.allocator, AvailableSpace{ .definite = 30 });
    defer builder.deinit();

    try builder.addTextWithNode("   Lorem ipsum dolor      \t\nsit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", .normal, 2);

    try builder.buildLinesWrap();
    builder.finalizeText();
    try builder.print(std.io.getStdErr().writer().any());
}

test "LinesBuilder nowrap mode functionality" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test nowrap mode with soft wrap opportunities
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 10 }); // Small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("hello world test", .normal, .nowrap);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should collapse spaces normally but be prepared for no wrapping at spaces
        try testing.expect(std.mem.indexOf(u8, content, "hello world test") != null);
    }

    // Test nowrap mode with forced line breaks (using pre mode to preserve breaks)
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 10 });
        defer builder.deinit();

        try builder.addTextWithWrapMode("line1\nline2\nline3", .pre, .nowrap);
        builder.finalizeText();

        const content = builder.segmenter.buffer.items;
        // Should preserve forced line breaks even in nowrap mode
        try testing.expect(std.mem.indexOf(u8, content, "\n") != null);
    }

    // Test nowrap text processing - remove soft wrap opportunities
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        // First create text with soft wrap opportunities (break-spaces style)
        const input_with_zwsp = "hello\u{200B} world\u{200B} test";
        const result = try builder.processTextForNowrap(input_with_zwsp);
        defer testing.allocator.free(result);

        // Zero-width spaces should be removed in nowrap mode
        try testing.expect(std.mem.indexOf(u8, result, "\u{200B}") == null);
        try testing.expectEqualStrings("hello world test", result);
    }

    // Test nowrap preserves forced breaks but removes soft wrap markers
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const input = "line1\u{200B}\nline2\u{200B}";
        const result = try builder.processTextForNowrap(input);
        defer testing.allocator.free(result);

        // Should preserve LF but remove ZWSP
        try testing.expectEqualStrings("line1\nline2", result);
    }

    // Test text width measurement
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const width1 = builder.measureTextWidth("hello");
        const width2 = builder.measureTextWidth("hello world");
        const width3 = builder.measureTextWidth("hello\u{200B}world"); // ZWSP should not add width

        try testing.expect(width1 == 5.0);
        try testing.expect(width2 == 11.0); // 5 + 1 + 5 (space adds width)
        try testing.expect(width3 == 10.0); // 5 + 5 (ZWSP adds no width)
    }

    // Test tab width measurement
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const width_with_tab = builder.measureTextWidth("a\tb");
        try testing.expectEqual(width_with_tab, 2); // 1 + 0 + 1 (tab = 8 spaces)
    }
}

test "LinesBuilder line building with nowrap" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test building lines in nowrap mode - only break at forced breaks
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 5 }); // Very small width
        defer builder.deinit();

        // Add text with preserved breaks using the text processing pipeline
        try builder.addTextWithWrapMode("short\nvery long line that exceeds width\nshort", .pre, .nowrap);
        builder.finalizeText();

        // Build lines in nowrap mode
        try builder.buildLinesWithWrapMode(.nowrap);

        // Should have 3 lines (split only at \n)
        try testing.expect(builder.lines.items.len == 3);

        // First line should have a fragment
        if (builder.lines.items.len > 0) {
            const first_line = &builder.lines.items[0];
            try testing.expect(first_line.fragments.items.len > 0);
            // Check the fragment length - "short" has 5 characters
            try testing.expect(first_line.fragments.items[0].length == 5);
        }

        // Second line should contain the long text (not wrapped despite width)
        if (builder.lines.items.len > 1) {
            const second_line = &builder.lines.items[1];
            try testing.expect(second_line.fragments.items.len > 0);
            // Check that it has a substantial length (the long line)
            try testing.expect(second_line.fragments.items[0].length > 20);
        }
    }

    // Test building lines in wrap mode (normal wrapping)
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.segmenter.append("hello world test");

        // Build lines in wrap mode
        try builder.buildLinesWithWrapMode(.wrap);

        // Should have at least one line
        try testing.expect(builder.lines.items.len >= 1);

        // Text should be in the line as a fragment
        if (builder.lines.items.len > 0) {
            const line = &builder.lines.items[0];
            try testing.expect(line.fragments.items.len > 0);
            // Check that the fragment has some reasonable length (not empty)
            try testing.expect(line.fragments.items[0].length > 0);
        }
    }
}

test "LinesBuilder wrap mode functionality" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test wrap mode with text that fits on one line
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addTextWithWrapMode("short", .normal, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithWrapMode(.wrap);

        // Should have one line since text fits
        try testing.expect(builder.lines.items.len == 1);

        if (builder.lines.items.len > 0) {
            const line = &builder.lines.items[0];
            try testing.expect(line.fragments.items.len > 0);
            try testing.expect(line.fragments.items[0].length == 5); // "short"
        }
    }

    // Test wrap mode with text that needs wrapping
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 10 }); // Small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("hello world test", .normal, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithWrapMode(.wrap);

        // Should have multiple lines due to small width
        try testing.expect(builder.lines.items.len >= 2);

        // Each line should have fragments
        for (builder.lines.items) |line| {
            try testing.expect(line.fragments.items.len > 0);
            try testing.expect(line.fragments.items[0].length > 0);
        }
    }

    // Test wrap mode with forced line breaks
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.addTextWithWrapMode("line1\nline2", .pre, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithWrapMode(.wrap);

        // Should have 2 lines due to forced break
        try testing.expect(builder.lines.items.len == 2);

        // First line should contain "line1"
        if (builder.lines.items.len > 0) {
            const first_line = &builder.lines.items[0];
            try testing.expect(first_line.fragments.items.len > 0);
            try testing.expect(first_line.fragments.items[0].length == 5); // "line1"
        }

        // Second line should contain "line2"
        if (builder.lines.items.len > 1) {
            const second_line = &builder.lines.items[1];
            try testing.expect(second_line.fragments.items.len > 0);
            try testing.expect(second_line.fragments.items[0].length == 5); // "line2"
        }
    }

    // Test wrap mode with soft wrap opportunities (zero-width spaces)
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 6 }); // Small width
        defer builder.deinit();

        // Add text with zero-width space break opportunities
        try builder.segmenter.append("hello\u{200B}world\u{200B}test");

        try builder.buildLinesWithWrapMode(.wrap);

        // Should wrap at the zero-width spaces when needed
        try testing.expect(builder.lines.items.len >= 2);
    }

    // Test soft wrap opportunity detection
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        // Test various soft wrap opportunities
        try testing.expect(builder.isSoftWrapOpportunity(0x0020)); // SPACE
        try testing.expect(builder.isSoftWrapOpportunity(0x200B)); // ZERO WIDTH SPACE
        try testing.expect(builder.isSoftWrapOpportunity(0x00AD)); // SOFT HYPHEN
        try testing.expect(!builder.isSoftWrapOpportunity('a')); // Regular character
        try testing.expect(!builder.isSoftWrapOpportunity(0x000A)); // LF (forced break, not soft)
    }

    // Test character width calculation
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        // Test various character widths
        try testing.expect(builder.getCharacterWidth('a') == 1.0); // Regular character
        try testing.expect(builder.getCharacterWidth(0x200B) == 0.0); // ZERO WIDTH SPACE
        try testing.expect(builder.getCharacterWidth(0x00AD) == 0.0); // SOFT HYPHEN
        try testing.expect(builder.getCharacterWidth(0x0009) == 8.0); // TAB
        try testing.expect(builder.getCharacterWidth(' ') == 1.0); // SPACE
    }

    // Test whitespace skipping after break
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const text = "hello   world";
        const break_point = 5; // After "hello"
        const next_pos = builder.skipWhitespaceAfterBreak(text, break_point);

        // Should skip the spaces and point to "world"
        try testing.expect(next_pos == 8); // Position of 'w' in "world"
    }

    // Test very long word that exceeds available width (force break)
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 5 }); // Very small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("superlongwordwithoutspaces", .normal, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithWrapMode(.wrap);

        // Should force break the long word across multiple lines
        try testing.expect(builder.lines.items.len >= 2);

        // Each line should have some content
        for (builder.lines.items) |line| {
            try testing.expect(line.fragments.items.len > 0);
            try testing.expect(line.fragments.items[0].length > 0);
        }
    }
}

test "LinesBuilder forced line break preservation" {
    const testing = std.testing;
    const AvailableSpace = mod.constants.AvailableSpace;

    // Test forced line break detection
    {
        try testing.expect(isForcedLineBreak(0x000A)); // LF
        try testing.expect(isForcedLineBreak(0x000D)); // CR
        try testing.expect(isForcedLineBreak(0x2028)); // LINE SEPARATOR
        try testing.expect(isForcedLineBreak(0x2029)); // PARAGRAPH SEPARATOR
        try testing.expect(!isForcedLineBreak(0x0020)); // SPACE (not forced)
        try testing.expect(!isForcedLineBreak(0x200B)); // ZWSP (soft break)
        try testing.expect(!isForcedLineBreak('a')); // Regular character
    }

    // Test forced break preservation in nowrap mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 5 }); // Very small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("line1\nline2\nline3", .pre, .nowrap);
        builder.finalizeText();

        try builder.buildLinesWithForcedBreakPreservation(.nowrap);

        // Should have 3 lines despite nowrap mode due to forced breaks
        try testing.expect(builder.lines.items.len == 3);

        // Verify each line has content
        if (builder.lines.items.len >= 3) {
            try testing.expect(builder.lines.items[0].fragments.items[0].length == 5); // "line1"
            try testing.expect(builder.lines.items[1].fragments.items[0].length == 5); // "line2"
            try testing.expect(builder.lines.items[2].fragments.items[0].length == 5); // "line3"
        }
    }

    // Test forced break preservation in wrap mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 }); // Large width
        defer builder.deinit();

        try builder.addTextWithWrapMode("line1\nline2", .pre, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithForcedBreakPreservation(.wrap);

        // Should have 2 lines due to forced break, not width constraint
        try testing.expect(builder.lines.items.len == 2);

        if (builder.lines.items.len >= 2) {
            try testing.expect(builder.lines.items[0].fragments.items[0].length == 5); // "line1"
            try testing.expect(builder.lines.items[1].fragments.items[0].length == 5); // "line2"
        }
    }

    // Test preserveForcedLineBreaks function directly
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const text = "a\nb\nc";
        try builder.preserveForcedLineBreaks(text);

        // Should create 3 lines
        try testing.expect(builder.lines.items.len == 3);

        if (builder.lines.items.len >= 3) {
            try testing.expect(builder.lines.items[0].fragments.items[0].length == 1); // "a"
            try testing.expect(builder.lines.items[1].fragments.items[0].length == 1); // "b"
            try testing.expect(builder.lines.items[2].fragments.items[0].length == 1); // "c"
        }
    }

    // Test mixed forced breaks and soft wrap opportunities in nowrap mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 8 }); // Small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("short text\nmore text", .pre, .nowrap);
        builder.finalizeText();

        try builder.buildLinesWithForcedBreakPreservation(.nowrap);

        // Should have 2 lines due to forced break
        // Width is small but nowrap prevents soft wrapping
        try testing.expect(builder.lines.items.len == 2);

        if (builder.lines.items.len >= 2) {
            try testing.expect(builder.lines.items[0].fragments.items[0].length == 10); // "short text"
            try testing.expect(builder.lines.items[1].fragments.items[0].length == 9); // "more text"
        }
    }

    // Test mixed forced breaks and soft wrap opportunities in wrap mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 8 }); // Small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("short text\nmore text", .normal, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithForcedBreakPreservation(.wrap);

        // Should have at least 2 lines due to forced break
        // May have more due to width constraints and wrapping
        try testing.expect(builder.lines.items.len >= 2);
    }

    // Test text without forced breaks falls back to wrap mode behavior
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 6 }); // Small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("hello world", .normal, .wrap);
        builder.finalizeText();

        try builder.buildLinesWithForcedBreakPreservation(.wrap);

        // Should wrap at space due to width constraint (no forced breaks)
        try testing.expect(builder.lines.items.len >= 2);
    }

    // Test text without forced breaks in nowrap mode
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 6 }); // Small width
        defer builder.deinit();

        try builder.addTextWithWrapMode("hello world", .normal, .nowrap);
        builder.finalizeText();

        try builder.buildLinesWithForcedBreakPreservation(.nowrap);

        // Should stay on one line despite small width (nowrap, no forced breaks)
        try testing.expect(builder.lines.items.len == 1);

        if (builder.lines.items.len > 0) {
            try testing.expect(builder.lines.items[0].fragments.items[0].length == 11); // "hello world"
        }
    }

    // Test empty text
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        try builder.buildLinesWithForcedBreakPreservation(.wrap);

        // Should have no lines for empty text
        try testing.expect(builder.lines.items.len == 0);
    }

    // Test multiple consecutive forced breaks
    {
        var builder = init(testing.allocator, AvailableSpace{ .definite = 100 });
        defer builder.deinit();

        const text = "a\n\n\nb";
        try builder.preserveForcedLineBreaks(text);

        // Should create lines for each break
        try testing.expect(builder.lines.items.len == 4);

        if (builder.lines.items.len >= 4) {
            // First line should have "a"
            try testing.expect(builder.lines.items[0].fragments.items.len > 0);
            try testing.expect(builder.lines.items[0].fragments.items[0].length == 1); // "a"

            // Middle lines should be empty (no fragments or empty fragments)
            // This is acceptable - empty lines for consecutive breaks

            // Last line should have "b"
            try testing.expect(builder.lines.items[3].fragments.items.len > 0);
            try testing.expect(builder.lines.items[3].fragments.items[0].length == 1); // "b"
        }
    }
}
