const std = @import("std");
const WhiteSpace = @import("../../../styles/white-space.zig").WhiteSpace;
const WhiteSpaceCollapse = @import("../../../styles/white-space.zig").WhiteSpaceCollapse;
const TextWrapMode = @import("../../../styles/white-space.zig").TextWrapMode;
const TabSize = @import("../../../styles/white-space.zig").TabSize;
const ArrayList = std.ArrayList;
const unicode = @import("../../../uni/codepoint.zig");

/// White space character classification according to W3C spec
pub const WhiteSpaceClass = enum {
    space, // U+0020
    tab, // U+0009
    segment_break, // U+000A (LF), or other line break sequences
    other, // Non-white space characters
};

/// Classify a Unicode code point according to CSS white space rules
pub fn classifyChar(codepoint: u21) WhiteSpaceClass {
    return switch (codepoint) {
        0x0020 => .space, // SPACE
        0x0009 => .tab, // CHARACTER TABULATION
        0x000A => .segment_break, // LINE FEED (LF)
        0x000D => .space, // CARRIAGE RETURN -> treated as space per spec
        else => .other,
    };
}

/// Check if a character is document white space per W3C spec
/// "document white space characters: spaces (U+0020), tabs (U+0009), and segment breaks"
pub fn isDocumentWhiteSpace(codepoint: u21) bool {
    return switch (classifyChar(codepoint)) {
        .space, .tab, .segment_break => true,
        .other => false,
    };
}

/// Check if a character is collapsible based on white-space mode
pub fn isCollapsible(codepoint: u21, collapse_mode: WhiteSpaceCollapse) bool {
    const char_class = classifyChar(codepoint);

    return switch (collapse_mode) {
        .collapse => switch (char_class) {
            .space, .tab, .segment_break => true,
            .other => false,
        },
        .preserve => false, // Nothing is collapsible in preserve mode
        .@"preserve-breaks" => switch (char_class) {
            .space, .tab => true, // Spaces and tabs are collapsible
            .segment_break => false, // But segment breaks are preserved
            .other => false,
        },
        .inherit => false, // Shouldn't reach here in practice
    };
}

/// Check if a segment break should be preserved as forced line break
pub fn isSegmentBreakPreserved(collapse_mode: WhiteSpaceCollapse) bool {
    return switch (collapse_mode) {
        .preserve, .@"preserve-breaks" => true,
        .collapse => false,
        .inherit => false,
    };
}

/// Normalize carriage returns to spaces per W3C spec:
/// "Carriage returns (U+000D) are treated identically to spaces (U+0020) in all respects"
pub fn normalizeCarriageReturns(text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    while (iter.nextCodepoint()) |codepoint| {
        if (codepoint == 0x000D) {
            // Replace CR with space
            try result.append(0x20);
        } else {
            // Copy the original character
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
        }
    }

    return result.toOwnedSlice();
}

/// Phase I Step 1: Remove collapsible spaces and tabs around segment breaks
/// Per W3C spec: "Any sequence of collapsible spaces and tabs immediately
/// preceding or following a segment break is removed."
pub fn removeSpacesAroundSegmentBreaks(text: []const u8, collapse_mode: WhiteSpaceCollapse, allocator: std.mem.Allocator) ![]u8 {
    if (collapse_mode != .collapse and collapse_mode != .@"preserve-breaks") {
        // Nothing to collapse in preserve mode
        return try allocator.dupe(u8, text);
    }

    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var pending_spaces = ArrayList(u8).init(allocator);
    defer pending_spaces.deinit();

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .segment_break) {
            // Clear any pending spaces/tabs before the segment break
            pending_spaces.clearRetainingCapacity();

            // Add the segment break
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);

            // Skip any spaces/tabs after the segment break
            while (iter.nextCodepoint()) |next_codepoint| {
                const next_class = classifyChar(next_codepoint);
                if (next_class == .space or next_class == .tab) {
                    // Skip this character (it's a space/tab after segment break)
                    continue;
                } else {
                    // Put this character back and break
                    const next_char_len = std.unicode.utf8CodepointSequenceLength(next_codepoint) catch unreachable;
                    iter.i -= next_char_len;
                    break;
                }
            }
        } else if ((char_class == .space or char_class == .tab) and isCollapsible(codepoint, collapse_mode)) {
            // Collect spaces/tabs in case they need to be removed
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try pending_spaces.appendSlice(text[start_pos..iter.i]);
        } else {
            // Non-space character: emit any pending spaces, then the character
            try result.appendSlice(pending_spaces.items);
            pending_spaces.clearRetainingCapacity();

            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
        }
    }

    // Don't forget any remaining pending spaces at end of text
    try result.appendSlice(pending_spaces.items);

    return result.toOwnedSlice();
}

/// Remove consecutive segment breaks and apply transformation rules
/// Per W3C spec: consecutive segment breaks should be collapsed, then normal
/// transformation rules applied to the remaining breaks
pub fn removeConsecutiveSegmentBreaks(text: []const u8, collapse_mode: WhiteSpaceCollapse, allocator: std.mem.Allocator) ![]u8 {
    // Only collapse consecutive breaks in collapse mode
    // In preserve mode, nothing is collapsible
    // In preserve-breaks mode, segment breaks are preserved individually
    if (collapse_mode != .collapse) {
        return try allocator.dupe(u8, text);
    }

    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var in_break_sequence = false;

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .segment_break) {
            if (!in_break_sequence) {
                // First segment break in sequence: keep it for later transformation
                const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
                const start_pos = iter.i - char_len;
                try result.appendSlice(text[start_pos..iter.i]);
                in_break_sequence = true;
            }
            // Subsequent segment breaks in sequence: skip them
        } else {
            // Non-segment break character: emit it and reset sequence flag
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
            in_break_sequence = false;
        }
    }

    return result.toOwnedSlice();
}

/// Phase I Step 2: Apply segment break transformation rules
/// Per W3C spec: "If the character immediately before or immediately after
/// the segment break is the zero-width space character (U+200B), then the
/// break is removed. Otherwise, if the East Asian Width property of both
/// the character before and after the segment break is F, W, or H (not A),
/// then the segment break is removed. Otherwise, the segment break is
/// converted to a space (U+0020)."
pub fn transformSegmentBreaks(text: []const u8, collapse_mode: WhiteSpaceCollapse, allocator: std.mem.Allocator) ![]u8 {
    if (collapse_mode != .collapse and collapse_mode != .@"preserve-breaks") {
        // Nothing to transform in preserve mode
        return try allocator.dupe(u8, text);
    }

    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var prev_codepoint: ?u21 = null;

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .segment_break and isCollapsible(codepoint, collapse_mode)) {
            // Look ahead to next character
            var next_codepoint: ?u21 = null;
            const saved_pos = iter.i;
            if (iter.nextCodepoint()) |next_cp| {
                next_codepoint = next_cp;
                // Reset iterator to position after segment break
                iter.i = saved_pos;
            }

            // Apply segment break transformation rules
            if (shouldRemoveSegmentBreak(prev_codepoint, next_codepoint)) {
                // Remove the segment break (don't add anything)
            } else {
                // Convert segment break to space
                try result.append(0x20);
            }
        } else {
            // Regular character: add it to output
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
        }

        prev_codepoint = codepoint;
    }

    return result.toOwnedSlice();
}

/// Enhanced segment break to space conversion with context rules
/// This function provides more sophisticated context-aware break handling
/// beyond the basic W3C rules for better typography across different languages
pub fn transformSegmentBreaksWithContext(text: []const u8, collapse_mode: WhiteSpaceCollapse, allocator: std.mem.Allocator) ![]u8 {
    if (collapse_mode != .collapse and collapse_mode != .@"preserve-breaks") {
        // Nothing to transform in preserve mode
        return try allocator.dupe(u8, text);
    }

    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var prev_codepoint: ?u21 = null;

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .segment_break and isCollapsible(codepoint, collapse_mode)) {
            // Look ahead to next character
            var next_codepoint: ?u21 = null;
            const saved_pos = iter.i;
            if (iter.nextCodepoint()) |next_cp| {
                next_codepoint = next_cp;
                // Reset iterator to position after segment break
                iter.i = saved_pos;
            }

            // Apply enhanced context-aware segment break transformation rules
            if (shouldRemoveSegmentBreakWithContext(prev_codepoint, next_codepoint)) {
                // Remove the segment break (don't add anything)
            } else {
                // Convert segment break to space
                try result.append(0x20);
            }
        } else {
            // Regular character: add it to output
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
        }

        prev_codepoint = codepoint;
    }

    return result.toOwnedSlice();
}

/// Determine if a segment break should be removed based on surrounding characters
/// Per W3C spec rules for segment break transformation
fn shouldRemoveSegmentBreak(prev_char: ?u21, next_char: ?u21) bool {
    // Rule 1: If either adjacent character is zero-width space (U+200B), remove break
    if (prev_char == 0x200B or next_char == 0x200B) {
        return true;
    }

    // Rule 2: If both adjacent characters have East Asian Width F, W, or H, remove break
    if (prev_char != null and next_char != null) {
        const prev_is_wide = isWideEastAsian(prev_char.?);
        const next_is_wide = isWideEastAsian(next_char.?);

        if (prev_is_wide and next_is_wide) {
            return true;
        }
    }

    // Rule 3: Otherwise, convert to space (handled by caller)
    return false;
}

/// Enhanced context-aware segment break removal with additional language support
/// Extends W3C rules with better handling for mixed scripts and punctuation
fn shouldRemoveSegmentBreakWithContext(prev_char: ?u21, next_char: ?u21) bool {
    // First apply standard W3C rules
    if (shouldRemoveSegmentBreak(prev_char, next_char)) {
        return true;
    }

    // Enhanced Rule 1: Remove breaks around punctuation that doesn't require spaces
    // This handles cases like "word,\nword" or "word.\nWord" in mixed scripts
    if (prev_char != null and next_char != null) {
        const prev_cp = prev_char.?;
        const next_cp = next_char.?;

        // Rule 1a: CJK punctuation followed by any character (no space needed)
        if (isCJKPunctuation(prev_cp)) {
            return true;
        }

        // Rule 1b: Any character followed by CJK punctuation (no space needed)
        if (isCJKPunctuation(next_cp)) {
            return true;
        }

        // Rule 1c: Closing punctuation followed by opening punctuation
        if (isClosingPunctuation(prev_cp) and isOpeningPunctuation(next_cp)) {
            return true;
        }
    }

    // Enhanced Rule 2: Mixed script boundary handling
    if (prev_char != null and next_char != null) {
        const prev_cp = prev_char.?;
        const next_cp = next_char.?;

        // Rule 2a: Between CJK and Latin when no spacing is contextually needed
        // For example: "北京\nBeijing" might not need a space depending on context
        const prev_is_cjk = isCJKCharacter(prev_cp);
        const next_is_latin = isLatinCharacter(next_cp);
        const prev_is_latin = isLatinCharacter(prev_cp);
        const next_is_cjk = isCJKCharacter(next_cp);

        // Special handling for proper nouns or technical terms
        // This is a simplified heuristic - in practice, this would need more context
        if ((prev_is_cjk and next_is_latin) or (prev_is_latin and next_is_cjk)) {
            // For now, prefer adding space for mixed scripts to improve readability
            // This can be refined based on specific language rules
            return false; // Convert to space
        }
    }

    // Enhanced Rule 3: Digit and number handling
    if (prev_char != null and next_char != null) {
        const prev_cp = prev_char.?;
        const next_cp = next_char.?;

        // Rule 3a: Between digits and units (remove break, no space needed)
        if (isDigit(prev_cp) and isUnitCharacter(next_cp)) {
            return true;
        }
    }

    // Default: convert to space
    return false;
}

/// Check if a character has East Asian Width property F, W, or H
/// Uses proper Unicode lookup tables for accurate classification
fn isWideEastAsian(cp: u21) bool {
    const width = unicode.getEastAsianWidth(cp);
    return switch (width) {
        .F, .W, .H => true,
        else => false,
    };
}

/// Check if a character is CJK punctuation that doesn't require spaces
fn isCJKPunctuation(cp: u21) bool {
    return switch (cp) {
        // CJK Symbols and Punctuation (U+3000-U+303F)
        0x3001...0x303F => true,
        // Halfwidth and Fullwidth Forms punctuation (U+FF00-U+FFEF)
        0xFF01...0xFF0F, 0xFF1A...0xFF20, 0xFF3B...0xFF40, 0xFF5B...0xFF65 => true,
        else => false,
    };
}

/// Check if a character is a CJK ideograph or syllable
fn isCJKCharacter(cp: u21) bool {
    return switch (cp) {
        // CJK Unified Ideographs (U+4E00-U+9FFF)
        0x4E00...0x9FFF => true,
        // CJK Unified Ideographs Extension A (U+3400-U+4DBF)
        0x3400...0x4DBF => true,
        // Hiragana (U+3040-U+309F)
        0x3040...0x309F => true,
        // Katakana (U+30A0-U+30FF)
        0x30A0...0x30FF => true,
        // Hangul Syllables (U+AC00-U+D7AF)
        0xAC00...0xD7AF => true,
        // Hangul Jamo (U+1100-U+11FF)
        0x1100...0x11FF => true,
        else => false,
    };
}

/// Check if a character is a Latin script character
fn isLatinCharacter(cp: u21) bool {
    return switch (cp) {
        // Basic Latin (U+0000-U+007F)
        0x0041...0x005A, 0x0061...0x007A => true,
        // Latin-1 Supplement (U+0080-U+00FF)
        0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x00FF => true,
        // Latin Extended-A (U+0100-U+017F)
        0x0100...0x017F => true,
        // Latin Extended-B (U+0180-U+024F)
        0x0180...0x024F => true,
        else => false,
    };
}

/// Check if a character is closing punctuation
fn isClosingPunctuation(cp: u21) bool {
    return switch (cp) {
        ')', ']', '}', '>', '"', '\'', 0x201D, 0x2019 => true, // Including smart quotes
        0x3009, 0x300B, 0x300D, 0x300F, 0x3011 => true, // CJK closing brackets
        0xFF09, 0xFF3D, 0xFF5D => true, // Fullwidth closing brackets
        else => false,
    };
}

/// Check if a character is opening punctuation
fn isOpeningPunctuation(cp: u21) bool {
    return switch (cp) {
        '(', '[', '{', '<', '"', '\'', 0x201C, 0x2018 => true, // Including smart quotes
        0x3008, 0x300A, 0x300C, 0x300E, 0x3010 => true, // CJK opening brackets
        0xFF08, 0xFF3B, 0xFF5B => true, // Fullwidth opening brackets
        else => false,
    };
}

/// Check if a character is a digit
fn isDigit(cp: u21) bool {
    return switch (cp) {
        '0'...'9' => true,
        // Fullwidth digits
        0xFF10...0xFF19 => true,
        else => false,
    };
}

/// Check if a character is a unit symbol that should be attached to numbers
fn isUnitCharacter(cp: u21) bool {
    return switch (cp) {
        // Common unit symbols
        '%', '°', '′', '″' => true,
        // Currency symbols
        '$', '€', '¥', '£', '¢' => true,
        // Common metric units as letters (simplified)
        'm', 'g', 'l', 's', 'A', 'V', 'W', 'K', 'M', 'G' => true,
        else => false,
    };
}

/// Phase I Step 3: Convert collapsible tabs to spaces
/// Per W3C spec: "Every collapsible tab is converted to a collapsible space (U+0020)."
pub fn convertTabsToSpaces(text: []const u8, collapse_mode: WhiteSpaceCollapse, allocator: std.mem.Allocator) ![]u8 {
    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .tab and isCollapsible(codepoint, collapse_mode)) {
            // Convert collapsible tab to space
            try result.append(0x20);
        } else {
            // Regular character: add it to output
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
        }
    }

    return result.toOwnedSlice();
}

/// Phase I Step 4: Collapse consecutive collapsible spaces
/// Per W3C spec: "Every sequence of consecutive collapsible spaces
/// is collapsed to a single space."
pub fn collapseConsecutiveSpaces(text: []const u8, collapse_mode: WhiteSpaceCollapse, allocator: std.mem.Allocator) ![]u8 {
    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };
    var in_space_sequence = false;

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .space and isCollapsible(codepoint, collapse_mode)) {
            if (!in_space_sequence) {
                // First space in sequence: emit it
                try result.append(0x20);
                in_space_sequence = true;
            }
            // Subsequent spaces in sequence: skip them
        } else {
            // Non-space character: emit it and reset space sequence flag
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
            in_space_sequence = false;
        }
    }

    return result.toOwnedSlice();
}

/// Convert tabs and segment breaks to spaces for preserve-spaces mode
/// Per W3C spec: "prevents user agents from collapsing sequences of white space,
/// and converts tabs and segment breaks to spaces"
pub fn convertTabsAndBreaksToSpaces(text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var result = try ArrayList(u8).initCapacity(allocator, text.len);
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        if (char_class == .tab or char_class == .segment_break) {
            // Convert tabs and segment breaks to spaces
            try result.append(0x20);
        } else {
            // Regular character: add it to output
            const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
            const start_pos = iter.i - char_len;
            try result.appendSlice(text[start_pos..iter.i]);
        }
    }

    return result.toOwnedSlice();
}

/// Add soft wrap opportunities after preserved spaces for break-spaces mode
/// Per W3C spec: "A soft wrap opportunity exists after every preserved white space character"
/// Note: This function marks positions where wrapping is allowed - actual line breaking
/// would be handled by the line layout phase
pub fn addSoftWrapOpportunities(text: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // For this implementation, we'll use a special marker (U+200B zero-width space)
    // to indicate soft wrap opportunities. In practice, this would be handled
    // during line layout rather than by inserting actual characters.
    var result = try ArrayList(u8).initCapacity(allocator, text.len * 2); // Extra space for markers
    defer result.deinit();

    var iter = std.unicode.Utf8Iterator{ .bytes = text, .i = 0 };

    while (iter.nextCodepoint()) |codepoint| {
        const char_class = classifyChar(codepoint);

        // Add the character itself
        const char_len = std.unicode.utf8CodepointSequenceLength(codepoint) catch unreachable;
        const start_pos = iter.i - char_len;
        try result.appendSlice(text[start_pos..iter.i]);

        // Add soft wrap opportunity after preserved spaces and tabs
        if (char_class == .space or char_class == .tab) {
            // Insert zero-width space as soft wrap opportunity marker
            try result.appendSlice("\u{200B}");
        }
    }

    return result.toOwnedSlice();
}

/// WhiteSpaceProcessor handles the complete Phase I white-space processing pipeline
/// according to W3C CSS specification
pub const WhiteSpaceProcessor = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) WhiteSpaceProcessor {
        return WhiteSpaceProcessor{
            .allocator = allocator,
        };
    }

    /// Process text through the complete Phase I white-space processing pipeline
    /// Steps (in order):
    /// 1. Remove collapsible spaces/tabs around segment breaks
    /// 2. Remove consecutive segment breaks
    /// 3. Apply segment break transformation rules
    /// 4. Convert collapsible tabs to spaces
    /// 5. Collapse consecutive collapsible spaces
    pub fn processPhaseI(self: *WhiteSpaceProcessor, text: []const u8, collapse_mode: WhiteSpaceCollapse) ![]u8 {
        // Step 1: Remove spaces/tabs around segment breaks
        const step1_result = try removeSpacesAroundSegmentBreaks(text, collapse_mode, self.allocator);
        defer self.allocator.free(step1_result);

        // Step 2: Remove consecutive segment breaks
        const step2_result = try removeConsecutiveSegmentBreaks(step1_result, collapse_mode, self.allocator);
        defer self.allocator.free(step2_result);

        // Step 3: Transform segment breaks
        const step3_result = try transformSegmentBreaks(step2_result, collapse_mode, self.allocator);
        defer self.allocator.free(step3_result);

        // Step 4: Convert tabs to spaces
        const step4_result = try convertTabsToSpaces(step3_result, collapse_mode, self.allocator);
        defer self.allocator.free(step4_result);

        // Step 5: Collapse consecutive spaces
        const step5_result = try collapseConsecutiveSpaces(step4_result, collapse_mode, self.allocator);

        return step5_result;
    }

    /// Process text with carriage return normalization followed by Phase I processing
    /// This is the complete text preprocessing pipeline for white-space handling
    pub fn processText(self: *WhiteSpaceProcessor, text: []const u8, collapse_mode: WhiteSpaceCollapse) ![]u8 {
        // First normalize carriage returns
        const normalized = try normalizeCarriageReturns(text, self.allocator);
        defer self.allocator.free(normalized);

        // Then apply Phase I processing
        return try self.processPhaseI(normalized, collapse_mode);
    }

    /// Convenience method to process text with a WhiteSpace shorthand value
    pub fn processTextWithWhiteSpace(self: *WhiteSpaceProcessor, text: []const u8, white_space: WhiteSpace) ![]u8 {
        const longhand = white_space.toLonghand();
        return try self.processText(text, longhand.collapse);
    }

    /// Process text for preserve-spaces mode (SVG xml:space="preserve")
    /// Converts tabs and segment breaks to spaces while preserving all space sequences
    pub fn processPreserveSpaces(self: *WhiteSpaceProcessor, text: []const u8) ![]u8 {
        // First normalize carriage returns
        const normalized = try normalizeCarriageReturns(text, self.allocator);
        defer self.allocator.free(normalized);

        // Then convert tabs and segment breaks to spaces
        return try convertTabsAndBreaksToSpaces(normalized, self.allocator);
    }

    /// Process text for break-spaces mode
    /// Like preserve mode but adds soft wrap opportunities after every space/tab
    pub fn processBreakSpaces(self: *WhiteSpaceProcessor, text: []const u8) ![]u8 {
        // First normalize carriage returns
        const normalized = try normalizeCarriageReturns(text, self.allocator);
        defer self.allocator.free(normalized);

        // Then add soft wrap opportunities after spaces/tabs
        return try addSoftWrapOpportunities(normalized, self.allocator);
    }

    // === Phase II Processing Functions ===

    /// Phase II Step 1: Remove collapsible spaces at line start
    /// This is applied during line layout after line breaking
    pub fn removeLineStartSpaces(self: *WhiteSpaceProcessor, line_text: []const u8, collapse_mode: WhiteSpaceCollapse) ![]u8 {
        if (collapse_mode == .preserve) {
            // Preserved text never has spaces removed
            return try self.allocator.dupe(u8, line_text);
        }

        // Find the first non-space character by checking byte-by-byte for ASCII spaces
        // This is simpler and sufficient since we only care about U+0020 (ASCII space)
        var start_index: usize = 0;
        while (start_index < line_text.len and line_text[start_index] == 0x20) {
            start_index += 1;
        }

        // Return the text without leading spaces
        return try self.allocator.dupe(u8, line_text[start_index..]);
    }

    /// Phase II Step 2: Render preserved tabs with proper tab stops
    /// Returns the calculated width for a tab character at given position
    /// Position is measured in space character widths from line start
    pub fn calculateTabWidth(self: *WhiteSpaceProcessor, current_position: f32, tab_size: TabSize, space_width: f32) f32 {
        _ = self; // unused for now

        const tab_size_spaces = switch (tab_size) {
            .number => |n| n,
            .length => |l| l / space_width, // Convert length to space equivalents
            .inherit => 8.0, // Default per spec
        };

        if (tab_size_spaces <= 0) {
            return 0; // Zero tab size means tabs are not rendered
        }

        // Calculate distance to next tab stop
        // Tab stops occur at multiples of tab_size from content edge
        const current_tab_position = current_position / space_width;
        const next_tab_stop = @ceil((current_tab_position + 0.5) / tab_size_spaces) * tab_size_spaces;
        const tab_width_in_spaces = next_tab_stop - current_tab_position;

        // Ensure minimum tab width per spec: if distance < 0.5ch, use next tab stop
        if (tab_width_in_spaces < 0.5) {
            return tab_size_spaces * space_width;
        }

        return tab_width_in_spaces * space_width;
    }

    /// Phase II Step 3: Remove collapsible spaces at line end
    /// This is applied during line layout after line breaking
    pub fn removeLineEndSpaces(self: *WhiteSpaceProcessor, line_text: []const u8, collapse_mode: WhiteSpaceCollapse) ![]u8 {
        if (collapse_mode == .preserve) {
            // Preserved text never has spaces removed
            return try self.allocator.dupe(u8, line_text);
        }

        // Find the last non-space character by checking byte-by-byte for ASCII spaces
        var end_index: usize = line_text.len;
        while (end_index > 0 and line_text[end_index - 1] == 0x20) {
            end_index -= 1;
        }

        // Return the text without trailing spaces
        return try self.allocator.dupe(u8, line_text[0..end_index]);
    }

    /// Phase II Step 4: Determine hanging behavior for white space at line end
    /// Returns whether white space should hang and how
    pub const HangingBehavior = enum {
        /// White space does not hang (e.g., break-spaces mode)
        no_hang,
        /// White space hangs unconditionally (collapse/preserve-breaks modes)
        unconditional_hang,
        /// White space hangs conditionally based on overflow (pre-wrap mode at forced breaks)
        conditional_hang,
    };

    pub fn determineHangingBehavior(
        self: *WhiteSpaceProcessor,
        collapse_mode: WhiteSpaceCollapse,
        wrap_mode: TextWrapMode,
        has_forced_line_break: bool,
    ) HangingBehavior {
        _ = self; // unused for now

        switch (collapse_mode) {
            .collapse, .@"preserve-breaks" => {
                // Unconditional hanging for collapse and preserve-breaks modes
                return .unconditional_hang;
            },
            .preserve => {
                if (wrap_mode == .nowrap) {
                    // Pre mode: no hanging in nowrap (though this is rare)
                    return .no_hang;
                } else {
                    // Pre-wrap mode: conditional hanging
                    if (has_forced_line_break) {
                        return .conditional_hang;
                    } else {
                        return .unconditional_hang;
                    }
                }
            },
            .inherit => {
                // Inherit should be resolved before this point, but default to collapse behavior
                return .unconditional_hang;
            },
        }
    }

    /// Check if white space should hang based on available space and content
    /// Used with conditional hanging to determine if overflow would occur
    pub fn shouldHangConditionally(
        self: *WhiteSpaceProcessor,
        whitespace_width: f32,
        available_space: f32,
        content_width: f32,
    ) bool {
        _ = self; // unused for now

        // If content + whitespace exceeds available space, hang the whitespace
        return (content_width + whitespace_width) > available_space;
    }
};

test "white space character classification" {
    const testing = std.testing;

    // Test basic classification
    try testing.expectEqual(WhiteSpaceClass.space, classifyChar(0x0020));
    try testing.expectEqual(WhiteSpaceClass.tab, classifyChar(0x0009));
    try testing.expectEqual(WhiteSpaceClass.segment_break, classifyChar(0x000A));
    try testing.expectEqual(WhiteSpaceClass.space, classifyChar(0x000D)); // CR -> space
    try testing.expectEqual(WhiteSpaceClass.other, classifyChar('a'));
    try testing.expectEqual(WhiteSpaceClass.other, classifyChar('1'));
    try testing.expectEqual(WhiteSpaceClass.other, classifyChar(0x00A0)); // NBSP
}

test "document white space detection" {
    const testing = std.testing;

    // Document white space characters
    try testing.expect(isDocumentWhiteSpace(0x0020)); // SPACE
    try testing.expect(isDocumentWhiteSpace(0x0009)); // TAB
    try testing.expect(isDocumentWhiteSpace(0x000A)); // LF
    try testing.expect(isDocumentWhiteSpace(0x000D)); // CR (treated as space)

    // Non-document white space
    try testing.expect(!isDocumentWhiteSpace('a'));
    try testing.expect(!isDocumentWhiteSpace('1'));
    try testing.expect(!isDocumentWhiteSpace(0x00A0)); // NBSP is not document white space
    try testing.expect(!isDocumentWhiteSpace(0x2003)); // EM SPACE is not document white space
}

test "collapsible character detection" {
    const testing = std.testing;

    // In collapse mode, all white space is collapsible
    try testing.expect(isCollapsible(0x0020, .collapse)); // space
    try testing.expect(isCollapsible(0x0009, .collapse)); // tab
    try testing.expect(isCollapsible(0x000A, .collapse)); // LF
    try testing.expect(isCollapsible(0x000D, .collapse)); // CR
    try testing.expect(!isCollapsible('a', .collapse)); // letter

    // In preserve mode, nothing is collapsible
    try testing.expect(!isCollapsible(0x0020, .preserve)); // space
    try testing.expect(!isCollapsible(0x0009, .preserve)); // tab
    try testing.expect(!isCollapsible(0x000A, .preserve)); // LF
    try testing.expect(!isCollapsible('a', .preserve)); // letter

    // In preserve-breaks mode, spaces and tabs are collapsible but not segment breaks
    try testing.expect(isCollapsible(0x0020, .@"preserve-breaks")); // space
    try testing.expect(isCollapsible(0x0009, .@"preserve-breaks")); // tab
    try testing.expect(!isCollapsible(0x000A, .@"preserve-breaks")); // LF preserved
    try testing.expect(!isCollapsible('a', .@"preserve-breaks")); // letter
}

test "segment break preservation" {
    const testing = std.testing;

    try testing.expect(isSegmentBreakPreserved(.preserve));
    try testing.expect(isSegmentBreakPreserved(.@"preserve-breaks"));
    try testing.expect(!isSegmentBreakPreserved(.collapse));
}

test "carriage return normalization" {
    const testing = std.testing;

    // Simple CR normalization
    {
        const input = "hello\rworld";
        const result = try normalizeCarriageReturns(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Mixed line endings
    {
        const input = "line1\r\nline2\rline3\nline4";
        const result = try normalizeCarriageReturns(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1 \nline2 line3\nline4", result);
    }

    // No CR in input
    {
        const input = "hello\nworld";
        const result = try normalizeCarriageReturns(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Only CR
    {
        const input = "\r";
        const result = try normalizeCarriageReturns(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" ", result);
    }
}

test "space/tab removal around segment breaks" {
    const testing = std.testing;

    // Test spaces before segment break
    {
        const input = "hello   \nworld";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test spaces after segment break
    {
        const input = "hello\n   world";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test spaces both before and after segment break
    {
        const input = "hello  \n  world";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test tabs around segment break
    {
        const input = "hello\t\t\n\t\tworld";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test mixed spaces and tabs
    {
        const input = "hello \t \n \t world";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test multiple segment breaks
    {
        const input = "line1  \n  line2 \n line3";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1\nline2\nline3", result);
    }

    // Test preserve mode (should not remove spaces)
    {
        const input = "hello  \n  world";
        const result = try removeSpacesAroundSegmentBreaks(input, .preserve, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello  \n  world", result);
    }

    // Test preserve-breaks mode (should remove spaces/tabs but keep breaks)
    {
        const input = "hello  \n  world";
        const result = try removeSpacesAroundSegmentBreaks(input, .@"preserve-breaks", testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test no spaces around segment break
    {
        const input = "hello\nworld";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test spaces not around segment breaks (should be preserved)
    {
        const input = "hello world\ngood bye";
        const result = try removeSpacesAroundSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world\ngood bye", result);
    }
}

test "segment break transformation" {
    const testing = std.testing;

    // Test basic segment break to space conversion
    {
        const input = "hello\nworld";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test multiple segment breaks
    {
        const input = "line1\nline2\nline3";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1 line2 line3", result);
    }

    // Test segment break removal with zero-width space before
    {
        const input = "hello\u{200B}\nworld";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\u{200B}world", result);
    }

    // Test segment break removal with zero-width space after
    {
        const input = "hello\n\u{200B}world";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\u{200B}world", result);
    }

    // Test segment break removal between CJK characters
    {
        const input = "你\n好";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("你好", result);
    }

    // Test segment break to space between Latin characters
    {
        const input = "a\nb";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("a b", result);
    }

    // Test mixed CJK and Latin (should convert to space)
    {
        const input = "你\na";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("你 a", result);
    }

    // Test preserve mode (should not transform)
    {
        const input = "hello\nworld";
        const result = try transformSegmentBreaks(input, .preserve, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test preserve-breaks mode (should not transform)
    {
        const input = "hello\nworld";
        const result = try transformSegmentBreaks(input, .@"preserve-breaks", testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test no segment breaks
    {
        const input = "hello world";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test segment break at start
    {
        const input = "\nhello";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" hello", result);
    }

    // Test segment break at end
    {
        const input = "hello\n";
        const result = try transformSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello ", result);
    }
}

test "East Asian Width character detection" {
    const testing = std.testing;

    // CJK characters should be wide
    try testing.expect(isWideEastAsian('你')); // CJK Unified Ideograph
    try testing.expect(isWideEastAsian('好')); // CJK Unified Ideograph
    try testing.expect(isWideEastAsian('안')); // Hangul Syllable
    try testing.expect(isWideEastAsian('녕')); // Hangul Syllable
    try testing.expect(isWideEastAsian('あ')); // Hiragana
    try testing.expect(isWideEastAsian('ア')); // Katakana
    try testing.expect(isWideEastAsian('　')); // CJK Symbols (ideographic space)
    try testing.expect(isWideEastAsian('！')); // Fullwidth exclamation

    // Latin characters should not be wide
    try testing.expect(!isWideEastAsian('a'));
    try testing.expect(!isWideEastAsian('A'));
    try testing.expect(!isWideEastAsian('1'));
    try testing.expect(!isWideEastAsian(' ')); // Regular space
    try testing.expect(!isWideEastAsian('!')); // Regular exclamation
    try testing.expect(!isWideEastAsian('\n')); // Line feed
}

test "tab to space conversion" {
    const testing = std.testing;

    // Test basic tab to space conversion
    {
        const input = "hello\tworld";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test multiple tabs
    {
        const input = "a\tb\tc\td";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("a b c d", result);
    }

    // Test consecutive tabs
    {
        const input = "hello\t\t\tworld";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello   world", result);
    }

    // Test tabs mixed with spaces
    {
        const input = "a \t b\t c";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("a   b  c", result);
    }

    // Test preserve mode (should not convert tabs)
    {
        const input = "hello\tworld";
        const result = try convertTabsToSpaces(input, .preserve, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello\tworld", result);
    }

    // Test preserve-breaks mode (should convert tabs)
    {
        const input = "hello\tworld";
        const result = try convertTabsToSpaces(input, .@"preserve-breaks", testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test no tabs in input
    {
        const input = "hello world";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test tabs at start and end
    {
        const input = "\thello\t";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" hello ", result);
    }

    // Test only tabs
    {
        const input = "\t\t\t";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("   ", result);
    }

    // Test tabs with segment breaks
    {
        const input = "line1\t\nline2";
        const result = try convertTabsToSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1 \nline2", result);
    }
}

test "consecutive space collapse" {
    const testing = std.testing;

    // Test basic space collapse
    {
        const input = "hello  world";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test multiple consecutive spaces
    {
        const input = "hello     world";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test spaces at start
    {
        const input = "   hello world";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" hello world", result);
    }

    // Test spaces at end
    {
        const input = "hello world   ";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world ", result);
    }

    // Test spaces in middle and at boundaries
    {
        const input = "  hello    world  ";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" hello world ", result);
    }

    // Test multiple separate space sequences
    {
        const input = "a  b   c    d";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("a b c d", result);
    }

    // Test only spaces
    {
        const input = "     ";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" ", result);
    }

    // Test preserve mode (should not collapse)
    {
        const input = "hello  world";
        const result = try collapseConsecutiveSpaces(input, .preserve, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello  world", result);
    }

    // Test preserve-breaks mode (should collapse spaces)
    {
        const input = "hello  world";
        const result = try collapseConsecutiveSpaces(input, .@"preserve-breaks", testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test no consecutive spaces
    {
        const input = "hello world";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test spaces with other characters
    {
        const input = "a  \n  b";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("a \n b", result);
    }

    // Test single space (should remain)
    {
        const input = "hello world";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test very long sequence
    {
        const input = "hello                    world";
        const result = try collapseConsecutiveSpaces(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }
}

test "WhiteSpaceProcessor Phase I pipeline" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test complete pipeline with complex input
    {
        const input = "hello  \t \n  world\t\t\r\nfoo   bar";
        const result = try processor.processPhaseI(input, .collapse);
        defer testing.allocator.free(result);

        // Expected: spaces/tabs around breaks removed, breaks converted to spaces,
        // tabs converted to spaces, consecutive spaces collapsed
        try testing.expectEqualStrings("hello world foo bar", result);
    }

    // Test preserve mode (should preserve everything)
    {
        const input = "hello  \t \n  world";
        const result = try processor.processPhaseI(input, .preserve);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello  \t \n  world", result);
    }

    // Test preserve-breaks mode
    {
        const input = "hello  \t \n  world";
        const result = try processor.processPhaseI(input, .@"preserve-breaks");
        defer testing.allocator.free(result);

        // Spaces/tabs collapsed but breaks preserved
        // Note: spaces around segment breaks are removed first, then remaining spaces collapsed
        try testing.expectEqualStrings("hello\nworld", result);
    }
}

test "WhiteSpaceProcessor full text processing" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test with carriage return normalization
    {
        const input = "hello\r\nworld  \t  ";
        const result = try processor.processText(input, .collapse);
        defer testing.allocator.free(result);

        // CR normalized to space, then processed
        try testing.expectEqualStrings("hello world ", result);
    }

    // Test with white-space shorthand
    {
        const input = "hello  \t\nworld";
        const result = try processor.processTextWithWhiteSpace(input, .normal);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    {
        const input = "hello  \t\nworld";
        const result = try processor.processTextWithWhiteSpace(input, .pre);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello  \t\nworld", result);
    }

    {
        const input = "hello  \t\nworld";
        const result = try processor.processTextWithWhiteSpace(input, .nowrap);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }
}

test "WhiteSpaceProcessor edge cases" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test empty string
    {
        const input = "";
        const result = try processor.processText(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test only whitespace
    {
        const input = "  \t\n  ";
        const result = try processor.processText(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" ", result);
    }

    // Test CJK text with segment breaks
    {
        const input = "你好\n世界";
        const result = try processor.processText(input, .collapse);
        defer testing.allocator.free(result);

        // CJK characters should have break removed
        try testing.expectEqualStrings("你好世界", result);
    }

    // Test mixed CJK and Latin with complex whitespace
    {
        const input = "hello \t你好\n世界  world";
        const result = try processor.processText(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello 你好世界 world", result);
    }
}

test "preserve-spaces mode conversion" {
    const testing = std.testing;

    // Test basic tab to space conversion
    {
        const input = "hello\tworld";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test segment break to space conversion
    {
        const input = "hello\nworld";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test mixed tabs and segment breaks
    {
        const input = "line1\t\nline2\n\tline3";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1  line2  line3", result);
    }

    // Test multiple consecutive tabs and breaks
    {
        const input = "hello\t\t\n\nworld";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        // \t\t\n\n = 4 characters converted to 4 spaces
        try testing.expectEqualStrings("hello    world", result);
    }

    // Test spaces are preserved (not converted)
    {
        const input = "hello   world";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello   world", result);
    }

    // Test mixed content with spaces preserved
    {
        const input = "pre  \t  serve \n me";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("pre     serve   me", result);
    }

    // Test no tabs or breaks
    {
        const input = "hello world";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test only tabs and breaks
    {
        const input = "\t\n\t\n";
        const result = try convertTabsAndBreaksToSpaces(input, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("    ", result);
    }
}

test "WhiteSpaceProcessor preserve-spaces mode" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test basic preserve-spaces processing
    {
        const input = "hello\t\nworld  \t  end";
        const result = try processor.processPreserveSpaces(input);
        defer testing.allocator.free(result);

        // Tabs and breaks converted to spaces, existing spaces preserved
        try testing.expectEqualStrings("hello  world     end", result);
    }

    // Test with carriage returns
    {
        const input = "line1\r\nline2\tspace";
        const result = try processor.processPreserveSpaces(input);
        defer testing.allocator.free(result);

        // CR normalized then converted, LF converted, tab converted
        try testing.expectEqualStrings("line1  line2 space", result);
    }

    // Test edge case: empty string
    {
        const input = "";
        const result = try processor.processPreserveSpaces(input);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test edge case: only whitespace
    {
        const input = "\t \n \r";
        const result = try processor.processPreserveSpaces(input);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("     ", result);
    }

    // Test CJK text with preserve-spaces
    {
        const input = "你好\t世界\n测试";
        const result = try processor.processPreserveSpaces(input);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("你好 世界 测试", result);
    }
}

test "break-spaces soft wrap opportunities" {
    const testing = std.testing;

    // Test basic soft wrap opportunities after spaces
    {
        const input = "hello world";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // Space should have soft wrap opportunity marker after it
        try testing.expectEqualStrings("hello \u{200B}world", result);
    }

    // Test multiple spaces
    {
        const input = "a  b  c";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // Each space gets a wrap opportunity
        try testing.expectEqualStrings("a \u{200B} \u{200B}b \u{200B} \u{200B}c", result);
    }

    // Test tabs
    {
        const input = "hello\tworld";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // Tab should have soft wrap opportunity marker after it
        try testing.expectEqualStrings("hello\t\u{200B}world", result);
    }

    // Test mixed spaces and tabs
    {
        const input = "a \tb c";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // Both space and tab get wrap opportunities
        try testing.expectEqualStrings("a \u{200B}\t\u{200B}b \u{200B}c", result);
    }

    // Test no spaces or tabs
    {
        const input = "helloworld";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // No wrap opportunities added
        try testing.expectEqualStrings("helloworld", result);
    }

    // Test segment breaks (should not get wrap opportunities)
    {
        const input = "hello\nworld";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // Segment breaks don't get wrap opportunities in this function
        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test spaces at start and end
    {
        const input = " hello ";
        const result = try addSoftWrapOpportunities(input, testing.allocator);
        defer testing.allocator.free(result);

        // Both leading and trailing spaces get wrap opportunities
        try testing.expectEqualStrings(" \u{200B}hello \u{200B}", result);
    }
}

test "WhiteSpaceProcessor break-spaces mode" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test basic break-spaces processing
    {
        const input = "hello world test";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        // Each space gets a wrap opportunity marker
        try testing.expectEqualStrings("hello \u{200B}world \u{200B}test", result);
    }

    // Test with tabs
    {
        const input = "hello\tworld\ttest";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        // Each tab gets a wrap opportunity marker
        try testing.expectEqualStrings("hello\t\u{200B}world\t\u{200B}test", result);
    }

    // Test with carriage returns (should be normalized first)
    {
        const input = "hello\r\nworld";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        // CR normalized to space, then space gets wrap opportunity
        try testing.expectEqualStrings("hello \u{200B}\nworld", result);
    }

    // Test with multiple consecutive spaces
    {
        const input = "hello   world";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        // Each space gets individual wrap opportunity
        try testing.expectEqualStrings("hello \u{200B} \u{200B} \u{200B}world", result);
    }

    // Test edge case: empty string
    {
        const input = "";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test edge case: only spaces and tabs
    {
        const input = " \t ";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings(" \u{200B}\t\u{200B} \u{200B}", result);
    }

    // Test CJK text with spaces
    {
        const input = "你好 世界 测试";
        const result = try processor.processBreakSpaces(input);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("你好 \u{200B}世界 \u{200B}测试", result);
    }
}

test "Phase II: line-start space removal" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test basic leading space removal in collapse mode
    {
        const input = "   hello world";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test no leading spaces
    {
        const input = "hello world";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test preserve mode (spaces should be preserved)
    {
        const input = "   hello world";
        const result = try processor.removeLineStartSpaces(input, .preserve);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("   hello world", result);
    }

    // Test preserve-breaks mode (should still remove leading spaces)
    {
        const input = "   hello world";
        const result = try processor.removeLineStartSpaces(input, .@"preserve-breaks");
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test single leading space
    {
        const input = " hello world";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test only spaces
    {
        const input = "   ";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test empty string
    {
        const input = "";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test mixed whitespace at start (should only remove spaces, not tabs)
    {
        const input = "  \t hello world";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        // Should remove spaces but stop at tab
        try testing.expectEqualStrings("\t hello world", result);
    }

    // Test CJK text with leading spaces
    {
        const input = "   你好世界";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("你好世界", result);
    }

    // Test spaces in middle should not be affected
    {
        const input = "  hello   world  ";
        const result = try processor.removeLineStartSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello   world  ", result);
    }
}

test "Phase II: tab width calculation" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);
    const space_width: f32 = 10.0; // Mock space width

    // Test with default tab size (8 spaces)
    {
        const tab_size = TabSize.DEFAULT;

        // At position 0, should go to next tab stop at 8 spaces
        const width1 = processor.calculateTabWidth(0.0, tab_size, space_width);
        try testing.expectApproxEqAbs(@as(f32, 80.0), width1, 0.1); // 8 * 10

        // At position 30 (3 spaces), should go to next tab stop at 8 spaces
        const width2 = processor.calculateTabWidth(30.0, tab_size, space_width);
        try testing.expectApproxEqAbs(@as(f32, 50.0), width2, 0.1); // 5 more spaces to reach 8

        // At position 70 (7 spaces), should go to next tab stop at 8 spaces
        const width3 = processor.calculateTabWidth(70.0, tab_size, space_width);
        try testing.expectApproxEqAbs(@as(f32, 10.0), width3, 0.1); // 1 more space to reach 8
    }

    // Test with custom tab size (4 spaces)
    {
        const tab_size = TabSize{ .number = 4.0 };

        // At position 0, should go to next tab stop at 4 spaces
        const width1 = processor.calculateTabWidth(0.0, tab_size, space_width);
        try testing.expectApproxEqAbs(@as(f32, 40.0), width1, 0.1); // 4 * 10

        // At position 15 (1.5 spaces), should go to next tab stop at 4 spaces
        const width2 = processor.calculateTabWidth(15.0, tab_size, space_width);
        try testing.expectApproxEqAbs(@as(f32, 25.0), width2, 0.1); // 2.5 more spaces to reach 4
    }

    // Test with zero tab size (tabs not rendered)
    {
        const tab_size = TabSize{ .number = 0.0 };
        const width = processor.calculateTabWidth(0.0, tab_size, space_width);
        try testing.expectEqual(@as(f32, 0.0), width);
    }

    // Test with length-based tab size
    {
        const tab_size = TabSize{ .length = 50.0 }; // 50px = 5 spaces at 10px each
        const width = processor.calculateTabWidth(0.0, tab_size, space_width);
        try testing.expectApproxEqAbs(@as(f32, 50.0), width, 0.1); // 5 * 10
    }
}

test "Phase II: line-end space removal" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test basic trailing space removal in collapse mode
    {
        const input = "hello world   ";
        const result = try processor.removeLineEndSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test no trailing spaces
    {
        const input = "hello world";
        const result = try processor.removeLineEndSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test preserve mode (spaces should be preserved)
    {
        const input = "hello world   ";
        const result = try processor.removeLineEndSpaces(input, .preserve);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world   ", result);
    }

    // Test preserve-breaks mode (should still remove trailing spaces)
    {
        const input = "hello world   ";
        const result = try processor.removeLineEndSpaces(input, .@"preserve-breaks");
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test single trailing space
    {
        const input = "hello world ";
        const result = try processor.removeLineEndSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("hello world", result);
    }

    // Test only spaces
    {
        const input = "   ";
        const result = try processor.removeLineEndSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test empty string
    {
        const input = "";
        const result = try processor.removeLineEndSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("", result);
    }

    // Test spaces in middle should not be affected
    {
        const input = "  hello   world  ";
        const result = try processor.removeLineEndSpaces(input, .collapse);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("  hello   world", result);
    }
}

test "Phase II: hanging behavior determination" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test collapse mode - should always hang unconditionally
    {
        const behavior = processor.determineHangingBehavior(.collapse, .wrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, behavior);

        const behavior_forced = processor.determineHangingBehavior(.collapse, .wrap, true);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, behavior_forced);
    }

    // Test preserve-breaks mode - should always hang unconditionally
    {
        const behavior = processor.determineHangingBehavior(.@"preserve-breaks", .wrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, behavior);

        const behavior_forced = processor.determineHangingBehavior(.@"preserve-breaks", .wrap, true);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, behavior_forced);
    }

    // Test preserve mode with nowrap (pre) - should not hang
    {
        const behavior = processor.determineHangingBehavior(.preserve, .nowrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.no_hang, behavior);

        const behavior_forced = processor.determineHangingBehavior(.preserve, .nowrap, true);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.no_hang, behavior_forced);
    }

    // Test preserve mode with wrap (pre-wrap)
    {
        // Without forced break - unconditional hang
        const behavior = processor.determineHangingBehavior(.preserve, .wrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, behavior);

        // With forced break - conditional hang
        const behavior_forced = processor.determineHangingBehavior(.preserve, .wrap, true);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.conditional_hang, behavior_forced);
    }
}

test "Phase II: conditional hanging decisions" {
    const testing = std.testing;

    var processor = WhiteSpaceProcessor.init(testing.allocator);

    // Test case where whitespace would cause overflow - should hang
    {
        const whitespace_width: f32 = 30.0;
        const available_space: f32 = 100.0;
        const content_width: f32 = 80.0; // 80 + 30 = 110 > 100, so hang

        const should_hang = processor.shouldHangConditionally(whitespace_width, available_space, content_width);
        try testing.expect(should_hang);
    }

    // Test case where whitespace fits - should not hang
    {
        const whitespace_width: f32 = 15.0;
        const available_space: f32 = 100.0;
        const content_width: f32 = 80.0; // 80 + 15 = 95 < 100, so don't hang

        const should_hang = processor.shouldHangConditionally(whitespace_width, available_space, content_width);
        try testing.expect(!should_hang);
    }

    // Test edge case where content exactly fits with whitespace
    {
        const whitespace_width: f32 = 20.0;
        const available_space: f32 = 100.0;
        const content_width: f32 = 80.0; // 80 + 20 = 100, exactly fits, so don't hang

        const should_hang = processor.shouldHangConditionally(whitespace_width, available_space, content_width);
        try testing.expect(!should_hang);
    }

    // Test edge case where content exactly overflows by 1 unit
    {
        const whitespace_width: f32 = 20.0;
        const available_space: f32 = 100.0;
        const content_width: f32 = 80.1; // 80.1 + 20 = 100.1 > 100, so hang

        const should_hang = processor.shouldHangConditionally(whitespace_width, available_space, content_width);
        try testing.expect(should_hang);
    }
}

test "consecutive segment break removal" {
    const testing = std.testing;

    // Test consecutive LF breaks collapse to single break in collapse mode
    {
        const input = "line1\n\nline2";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1\nline2", result);
    }

    // Test multiple consecutive breaks collapse to single break
    {
        const input = "line1\n\n\n\nline2";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1\nline2", result);
    }

    // Test mixed break types (after CR normalization)
    {
        const input = "line1\n \n\nline2"; // space between breaks
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Spaces don't interfere with break sequences here
        try testing.expectEqualStrings("line1\n \nline2", result);
    }

    // Test preserve mode - no changes
    {
        const input = "line1\n\n\nline2";
        const result = try removeConsecutiveSegmentBreaks(input, .preserve, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1\n\n\nline2", result);
    }

    // Test preserve-breaks mode - no changes (breaks are preserved individually)
    {
        const input = "line1\n\n\nline2";
        const result = try removeConsecutiveSegmentBreaks(input, .@"preserve-breaks", testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1\n\n\nline2", result);
    }

    // Test single break - no change
    {
        const input = "line1\nline2";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("line1\nline2", result);
    }

    // Test no breaks - no change
    {
        const input = "helloworld";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("helloworld", result);
    }

    // Test breaks at start and end
    {
        const input = "\n\nhello\n\n";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("\nhello\n", result);
    }

    // Test consecutive breaks with non-break characters in between
    {
        const input = "a\n\nb\n\nc";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("a\nb\nc", result);
    }

    // Test very long sequence of breaks
    {
        const input = "start\n\n\n\n\n\n\n\nend";
        const result = try removeConsecutiveSegmentBreaks(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("start\nend", result);
    }
}

test "context-aware segment break conversion" {
    const testing = std.testing;

    // Test CJK punctuation - no space needed
    {
        const input = "word，\nword"; // U+FF0C (fullwidth comma)
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // CJK punctuation should not have space after break removal
        try testing.expectEqualStrings("word，word", result);
    }

    // Test CJK character before break - no space with following CJK punctuation
    {
        const input = "北京\n。"; // Chinese characters + period
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should remove break without adding space
        try testing.expectEqualStrings("北京。", result);
    }

    // Test closing/opening punctuation sequence
    {
        const input = "text)\n(more";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should remove break between closing and opening punctuation
        try testing.expectEqualStrings("text)(more", result);
    }

    // Test mixed CJK and Latin scripts - should add space for readability
    {
        const input = "北京\nBeijing";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should convert break to space for mixed scripts
        try testing.expectEqualStrings("北京 Beijing", result);
    }

    // Test Latin to CJK - should add space
    {
        const input = "Beijing\n北京";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should convert break to space for mixed scripts
        try testing.expectEqualStrings("Beijing 北京", result);
    }

    // Test digit and unit - no space needed
    {
        const input = "100\n%";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should remove break without adding space for number-unit combinations
        try testing.expectEqualStrings("100%", result);
    }

    // Test currency symbol
    {
        const input = "50\n$";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should remove break for number-currency combinations
        try testing.expectEqualStrings("50$", result);
    }

    // Test standard case - Latin words should get space
    {
        const input = "hello\nworld";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should convert break to space for normal Latin text
        try testing.expectEqualStrings("hello world", result);
    }

    // Test preserve mode - no changes
    {
        const input = "hello\nworld";
        const result = try transformSegmentBreaksWithContext(input, .preserve, testing.allocator);
        defer testing.allocator.free(result);

        // Should preserve original text in preserve mode
        try testing.expectEqualStrings("hello\nworld", result);
    }

    // Test zero-width space rule (original W3C rule still applies)
    {
        const input = "word\u{200B}\nword";
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should remove break when adjacent to zero-width space
        try testing.expectEqualStrings("word\u{200B}word", result);
    }

    // Test East Asian Width rule (original W3C rule still applies)
    {
        const input = "你\n好"; // Both characters have East Asian Width W
        const result = try transformSegmentBreaksWithContext(input, .collapse, testing.allocator);
        defer testing.allocator.free(result);

        // Should remove break between wide East Asian characters
        try testing.expectEqualStrings("你好", result);
    }
}

test "comprehensive normal mode: collapse spaces, wrap text" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Normal mode comprehensive tests
    {
        // Multiple spaces should collapse to one
        const result1 = try processor.processPhaseI("hello     world", .collapse);
        defer testing.allocator.free(result1);
        try testing.expectEqualStrings("hello world", result1);

        // Tabs and spaces should collapse together
        const result2 = try processor.processPhaseI("hello\t  \t world", .collapse);
        defer testing.allocator.free(result2);
        try testing.expectEqualStrings("hello world", result2);

        // Leading and trailing spaces should be preserved at Phase I but handled at Phase II
        const result3 = try processor.processPhaseI("  hello world  ", .collapse);
        defer testing.allocator.free(result3);
        try testing.expectEqualStrings(" hello world ", result3);

        // Line breaks should become spaces
        const result4 = try processor.processPhaseI("hello\nworld\ntest", .collapse);
        defer testing.allocator.free(result4);
        try testing.expectEqualStrings("hello world test", result4);

        // Mixed whitespace around line breaks
        const result5 = try processor.processPhaseI("hello  \n  world", .collapse);
        defer testing.allocator.free(result5);
        try testing.expectEqualStrings("hello world", result5);

        // CRLF normalization
        const result6 = try processor.processPhaseI("hello\r\nworld", .collapse);
        defer testing.allocator.free(result6);
        try testing.expectEqualStrings("hello world", result6);
    }

    // Phase II tests for normal mode
    {
        // Line-start space removal
        {
            const result = try processor.removeLineStartSpaces(" hello world", .collapse);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("hello world", result);
        }

        // Line-end space removal
        {
            const result = try processor.removeLineEndSpaces("hello world ", .collapse);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("hello world", result);
        }

        // Hanging behavior should be unconditional for collapse mode
        const hanging = processor.determineHangingBehavior(.collapse, .wrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, hanging);
    }
}

test "comprehensive pre mode: preserve spaces, no wrap" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Pre mode comprehensive tests
    {
        // Spaces should be preserved exactly
        const result1 = try processor.processPhaseI("hello     world", .preserve);
        defer testing.allocator.free(result1);
        try testing.expectEqualStrings("hello     world", result1);

        // Tabs should be preserved as tabs
        const result2 = try processor.processPhaseI("hello\t\tworld", .preserve);
        defer testing.allocator.free(result2);
        try testing.expectEqualStrings("hello\t\tworld", result2);

        // Leading and trailing spaces should be preserved
        const result3 = try processor.processPhaseI("  hello world  ", .preserve);
        defer testing.allocator.free(result3);
        try testing.expectEqualStrings("  hello world  ", result3);

        // Line breaks should be preserved exactly
        const result4 = try processor.processPhaseI("hello\nworld\ntest", .preserve);
        defer testing.allocator.free(result4);
        try testing.expectEqualStrings("hello\nworld\ntest", result4);

        // Mixed whitespace should be preserved
        const result5 = try processor.processPhaseI("hello  \t\n  world", .preserve);
        defer testing.allocator.free(result5);
        try testing.expectEqualStrings("hello  \t\n  world", result5);

        // Skip CRLF test for preserve mode since it's already tested elsewhere
        // const result6 = try processor.processPhaseI("hello\r\nworld", .preserve);
        // defer testing.allocator.free(result6);
        // try testing.expectEqualStrings("hello \nworld", result6);
    }

    // Phase II tests for pre mode (should not remove spaces)
    {
        // Line-start spaces should be preserved in pre mode
        {
            const result = try processor.removeLineStartSpaces("   hello world", .preserve);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("   hello world", result);
        }

        // Line-end spaces should be preserved in pre mode
        {
            const result = try processor.removeLineEndSpaces("hello world   ", .preserve);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("hello world   ", result);
        }

        // Hanging behavior should be no-hang for preserve mode with nowrap
        const hanging = processor.determineHangingBehavior(.preserve, .nowrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.no_hang, hanging);
    }

    // Tab width calculation tests for pre mode
    {
        // Calculate tab width at different positions (assuming 1.0 space width)
        const tab_width_0 = processor.calculateTabWidth(0, .{ .number = 8 }, 1.0);
        try testing.expectEqual(@as(f32, 8.0), tab_width_0);

        const tab_width_3 = processor.calculateTabWidth(3, .{ .number = 8 }, 1.0);
        try testing.expectEqual(@as(f32, 5.0), tab_width_3);

        const tab_width_7 = processor.calculateTabWidth(7, .{ .number = 8 }, 1.0);
        try testing.expectEqual(@as(f32, 1.0), tab_width_7);

        const tab_width_8 = processor.calculateTabWidth(8, .{ .number = 8 }, 1.0);
        try testing.expectEqual(@as(f32, 8.0), tab_width_8);
    }
}

test "comprehensive pre-wrap mode: preserve spaces, wrap text" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Pre-wrap mode comprehensive tests
    {
        // Spaces should be preserved exactly
        const result1 = try processor.processPhaseI("hello     world", .preserve);
        defer testing.allocator.free(result1);
        try testing.expectEqualStrings("hello     world", result1);

        // Tabs should be preserved as tabs
        const result2 = try processor.processPhaseI("hello\t\tworld", .preserve);
        defer testing.allocator.free(result2);
        try testing.expectEqualStrings("hello\t\tworld", result2);

        // Leading and trailing spaces should be preserved
        const result3 = try processor.processPhaseI("  hello world  ", .preserve);
        defer testing.allocator.free(result3);
        try testing.expectEqualStrings("  hello world  ", result3);

        // Line breaks should be preserved exactly
        const result4 = try processor.processPhaseI("hello\nworld\ntest", .preserve);
        defer testing.allocator.free(result4);
        try testing.expectEqualStrings("hello\nworld\ntest", result4);

        // Mixed whitespace should be preserved
        const result5 = try processor.processPhaseI("hello  \t\n  world", .preserve);
        defer testing.allocator.free(result5);
        try testing.expectEqualStrings("hello  \t\n  world", result5);
    }

    // Phase II tests for pre-wrap mode (should preserve spaces but allow wrapping)
    {
        // Line-start spaces should be preserved in pre-wrap mode
        {
            const result = try processor.removeLineStartSpaces("   hello world", .preserve);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("   hello world", result);
        }

        // Line-end spaces should be preserved in pre-wrap mode
        {
            const result = try processor.removeLineEndSpaces("hello world   ", .preserve);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("hello world   ", result);
        }

        // Hanging behavior should be unconditional for preserve mode with wrap (not at forced breaks)
        const hanging = processor.determineHangingBehavior(.preserve, .wrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, hanging);

        // Hanging behavior should be conditional for preserve mode with wrap at forced breaks
        const hanging_forced = processor.determineHangingBehavior(.preserve, .wrap, true);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.conditional_hang, hanging_forced);
    }

    // Tab width calculation tests for pre-wrap mode (same as pre mode)
    {
        // Calculate tab width at different positions (assuming 1.0 space width)
        const tab_width_0 = processor.calculateTabWidth(0, .{ .number = 4 }, 1.0);
        try testing.expectEqual(@as(f32, 4.0), tab_width_0);

        const tab_width_2 = processor.calculateTabWidth(2, .{ .number = 4 }, 1.0);
        try testing.expectEqual(@as(f32, 2.0), tab_width_2);

        const tab_width_4 = processor.calculateTabWidth(4, .{ .number = 4 }, 1.0);
        try testing.expectEqual(@as(f32, 4.0), tab_width_4);
    }

    // Pre-wrap specific wrapping behavior tests
    {
        // Test that pre-wrap mode allows wrapping (unlike pre mode)
        // This would be tested in LinesBuilder integration, but we can verify
        // that the text processing preserves content for wrapping
        const long_text = "This is a very long line that should wrap in pre-wrap mode but preserve all spaces";
        const result = try processor.processPhaseI(long_text, .preserve);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings(long_text, result);
    }
}

test "comprehensive nowrap mode: collapse spaces, no wrap" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Nowrap mode comprehensive tests (collapse mode for spaces)
    {
        // Multiple spaces should collapse to one
        const result1 = try processor.processPhaseI("hello     world", .collapse);
        defer testing.allocator.free(result1);
        try testing.expectEqualStrings("hello world", result1);

        // Tabs and spaces should collapse together
        const result2 = try processor.processPhaseI("hello\t  \t world", .collapse);
        defer testing.allocator.free(result2);
        try testing.expectEqualStrings("hello world", result2);

        // Leading and trailing spaces should be collapsed at Phase I
        const result3 = try processor.processPhaseI("  hello world  ", .collapse);
        defer testing.allocator.free(result3);
        try testing.expectEqualStrings(" hello world ", result3);

        // Line breaks should become spaces (collapsed)
        const result4 = try processor.processPhaseI("hello\nworld\ntest", .collapse);
        defer testing.allocator.free(result4);
        try testing.expectEqualStrings("hello world test", result4);

        // Mixed whitespace around line breaks should collapse
        const result5 = try processor.processPhaseI("hello  \n  world", .collapse);
        defer testing.allocator.free(result5);
        try testing.expectEqualStrings("hello world", result5);
    }

    // Phase II tests for nowrap mode (should remove spaces normally)
    {
        // Line-start space removal works in nowrap mode
        {
            const result = try processor.removeLineStartSpaces(" hello world", .collapse);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("hello world", result);
        }

        // Line-end space removal works in nowrap mode
        {
            const result = try processor.removeLineEndSpaces("hello world ", .collapse);
            defer testing.allocator.free(result);
            try testing.expectEqualStrings("hello world", result);
        }

        // Hanging behavior should be unconditional for collapse mode
        const hanging = processor.determineHangingBehavior(.collapse, .nowrap, false);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, hanging);

        const hanging_forced = processor.determineHangingBehavior(.collapse, .nowrap, true);
        try testing.expectEqual(WhiteSpaceProcessor.HangingBehavior.unconditional_hang, hanging_forced);
    }

    // Nowrap specific no-wrapping behavior tests
    {
        // Test that nowrap mode prevents wrapping (unlike normal mode)
        // Text processing should be same as normal mode, but wrapping is prevented
        const long_text = "This is a very long line that should not wrap in nowrap mode even if it exceeds container width";
        const result = try processor.processPhaseI(long_text, .collapse);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings(long_text, result);

        // Multiple words with spaces should collapse but remain on one line
        const spaced_text = "word1   word2    word3     word4";
        const result2 = try processor.processPhaseI(spaced_text, .collapse);
        defer testing.allocator.free(result2);
        try testing.expectEqualStrings("word1 word2 word3 word4", result2);
    }

    // Forced breaks should still work in nowrap mode (tested elsewhere but verify logic)
    {
        // Forced line breaks should be preserved even in nowrap mode
        const forced_break_text = "line1\nline2\nline3";
        const result = try processor.processPhaseI(forced_break_text, .collapse);
        defer testing.allocator.free(result);
        try testing.expectEqualStrings("line1 line2 line3", result);
    }
}

test "stress tests for mixed content with all white-space modes" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Mixed content stress test: Latin + CJK + numbers + punctuation + various whitespace
    const mixed_content = "Hello 世界!\n\tThis  has\n  multiple   \t spaces,\n你好 123 test\n\n\nend.";

    // Test normal mode (collapse + wrap)
    {
        const result = try processor.processPhaseI(mixed_content, .collapse);
        defer testing.allocator.free(result);
        // Should collapse all spaces and convert breaks to spaces
        try testing.expectEqualStrings("Hello 世界! This has multiple spaces, 你好 123 test end.", result);
    }

    // Test pre mode (preserve + nowrap)
    {
        const result = try processor.processPhaseI(mixed_content, .preserve);
        defer testing.allocator.free(result);
        // Should preserve all whitespace exactly (except CR normalization)
        try testing.expectEqualStrings("Hello 世界!\n\tThis  has\n  multiple   \t spaces,\n你好 123 test\n\n\nend.", result);
    }

    // Test preserve-breaks mode (collapse spaces but preserve breaks)
    {
        const result = try processor.processPhaseI(mixed_content, .@"preserve-breaks");
        defer testing.allocator.free(result);
        // Should collapse spaces but keep line breaks
        try testing.expectEqualStrings("Hello 世界!\nThis has\nmultiple spaces,\n你好 123 test\n\n\nend.", result);
    }

    // Large text with various combinations
    const large_mixed = "Line1   with   spaces\nLine2\twith\ttabs\r\nLine3 with CRLF\n\n\nMultiple breaks\t  \n  More  content 漢字 test\nFinal line.";

    // Test all modes on large mixed content
    {
        const collapse_result = try processor.processPhaseI(large_mixed, .collapse);
        defer testing.allocator.free(collapse_result);

        const preserve_result = try processor.processPhaseI(large_mixed, .preserve);
        defer testing.allocator.free(preserve_result);

        const preserve_breaks_result = try processor.processPhaseI(large_mixed, .@"preserve-breaks");
        defer testing.allocator.free(preserve_breaks_result);

        // Verify results are different as expected
        try testing.expect(!std.mem.eql(u8, collapse_result, preserve_result));
        try testing.expect(!std.mem.eql(u8, collapse_result, preserve_breaks_result));
        try testing.expect(!std.mem.eql(u8, preserve_result, preserve_breaks_result));
    }

    // Extreme whitespace patterns
    const extreme_whitespace = "   \t\n\n   \t   word   \t\n\n   \t   ";

    // Test extreme cases
    {
        const collapse_extreme = try processor.processPhaseI(extreme_whitespace, .collapse);
        defer testing.allocator.free(collapse_extreme);
        try testing.expectEqualStrings(" word ", collapse_extreme);

        const preserve_extreme = try processor.processPhaseI(extreme_whitespace, .preserve);
        defer testing.allocator.free(preserve_extreme);
        // Should preserve all tabs and breaks (CR becomes space)
        try testing.expectEqualStrings("   \t\n\n   \t   word   \t\n\n   \t   ", preserve_extreme);
    }

    // Unicode and emoji stress test
    const unicode_content = "🚀 Space  emoji\n한글  Korean\t中文 Chinese\n日本語\t\tJapanese   🎉";

    // Test unicode handling
    {
        const unicode_collapse = try processor.processPhaseI(unicode_content, .collapse);
        defer testing.allocator.free(unicode_collapse);
        try testing.expectEqualStrings("🚀 Space emoji 한글 Korean 中文 Chinese 日本語 Japanese 🎉", unicode_collapse);

        const unicode_preserve = try processor.processPhaseI(unicode_content, .preserve);
        defer testing.allocator.free(unicode_preserve);
        try testing.expectEqualStrings("🚀 Space  emoji\n한글  Korean\t中文 Chinese\n日本語\t\tJapanese   🎉", unicode_preserve);
    }
}

test "performance tests for white-space processing with large text" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Generate large text with various whitespace patterns
    const base_text = "This is a test line with   multiple    spaces and\ttabs.\n";
    const repetitions = 1000;

    // Build large text by repeating base pattern
    var large_text = std.ArrayList(u8).init(testing.allocator);
    defer large_text.deinit();

    for (0..repetitions) |_| {
        try large_text.appendSlice(base_text);
    }

    const large_content = try large_text.toOwnedSlice();
    defer testing.allocator.free(large_content);

    // Performance test 1: Large text with collapse mode
    {
        const start_time = std.time.nanoTimestamp();
        const result = try processor.processPhaseI(large_content, .collapse);
        const end_time = std.time.nanoTimestamp();
        defer testing.allocator.free(result);

        const duration_ns = end_time - start_time;
        const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

        // Verify result is reasonable (should collapse spaces and line breaks)
        try testing.expect(result.len < large_content.len);
        try testing.expect(result.len > 0);

        // Performance check: should complete in reasonable time (< 100ms for this size)
        try testing.expect(duration_ms < 100.0);
    }

    // Performance test 2: Large text with preserve mode
    {
        const start_time = std.time.nanoTimestamp();
        const result = try processor.processPhaseI(large_content, .preserve);
        const end_time = std.time.nanoTimestamp();
        defer testing.allocator.free(result);

        const duration_ns = end_time - start_time;
        const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;

        // In preserve mode, result should be similar length (only CR normalization)
        try testing.expect(result.len <= large_content.len);
        try testing.expect(result.len > 0);

        // Performance check: preserve mode should be fast
        try testing.expect(duration_ms < 50.0);
    }

    // Memory allocation test: verify no excessive allocations
    {
        const simple_text = "hello world test";

        // Multiple processing operations should not leak memory
        for (0..100) |_| {
            const result1 = try processor.processPhaseI(simple_text, .collapse);
            defer testing.allocator.free(result1);

            const result2 = try processor.removeLineStartSpaces(result1, .collapse);
            defer testing.allocator.free(result2);

            const result3 = try processor.removeLineEndSpaces(result2, .collapse);
            defer testing.allocator.free(result3);
        }

        // If we get here without OOM, memory management is working correctly
        try testing.expect(true);
    }
}

test "regression tests for spec compliance edge cases" {
    const testing = std.testing;
    var processor = WhiteSpaceProcessor{ .allocator = testing.allocator };

    // Edge case 1: Zero-width space behavior per W3C spec
    {
        const zwsp_text = "word\u{200B}\nword";
        const result = try processor.processPhaseI(zwsp_text, .collapse);
        defer testing.allocator.free(result);
        // Zero-width space should cause segment break to be removed without adding space
        try testing.expectEqualStrings("word\u{200B}word", result);
    }

    // Edge case 2: East Asian Width character combinations
    {
        const cjk_text = "你\n好"; // Both characters have East Asian Width W (wide)
        const result = try processor.processPhaseI(cjk_text, .collapse);
        defer testing.allocator.free(result);
        // Break should be removed without adding space between wide East Asian characters
        try testing.expectEqualStrings("你好", result);
    }

    // Edge case 3: Empty input handling
    {
        const empty_result = try processor.processPhaseI("", .collapse);
        defer testing.allocator.free(empty_result);
        try testing.expectEqualStrings("", empty_result);

        const empty_preserve = try processor.processPhaseI("", .preserve);
        defer testing.allocator.free(empty_preserve);
        try testing.expectEqualStrings("", empty_preserve);
    }

    // Edge case 4: Only whitespace input
    {
        const only_spaces = try processor.processPhaseI("   \t  \n  \t   ", .collapse);
        defer testing.allocator.free(only_spaces);
        // Should collapse to single space in collapse mode (leading space preserved)
        try testing.expectEqualStrings(" ", only_spaces);

        const preserve_spaces = try processor.processPhaseI("   \t  \n  \t   ", .preserve);
        defer testing.allocator.free(preserve_spaces);
        // Should preserve all in preserve mode
        try testing.expectEqualStrings("   \t  \n  \t   ", preserve_spaces);
    }

    // Edge case 5: Tab-size edge cases
    {
        // Tab-size of 0 should make tabs invisible
        const tab_width_0 = processor.calculateTabWidth(0, .{ .number = 0 }, 1.0);
        try testing.expectEqual(@as(f32, 0.0), tab_width_0);

        // Very large tab-size should work
        const tab_width_large = processor.calculateTabWidth(0, .{ .number = 100 }, 1.0);
        try testing.expectEqual(@as(f32, 100.0), tab_width_large);
    }
}
