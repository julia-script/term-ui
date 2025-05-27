const mod = @import("../mod.zig");
const LineBox = @import("./LineBox.zig");
const LineBoxFragment = @import("./LineBoxFragment.zig");
const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;
const LineBreakStream = @import("../../../uni/LineBreakStream.zig");
const WhiteSpaceProcessor = @import("./white-space-processor.zig").WhiteSpaceProcessor;
const WhiteSpace = @import("../../../styles/white-space.zig").WhiteSpace;
const WhiteSpaceLonghand = @import("../../../styles/white-space.zig").WhiteSpaceLonghand;
const css_types = @import("../../../css/types.zig");
const TextWrapMode = @import("../../../styles/white-space.zig").TextWrapMode;
const TabSize = @import("../../../styles/white-space.zig").TabSize;
const snapshot = @import("../../../testing/snapshot.zig");

lines: LineBox.LineBoxList,
available_width: mod.constants.AvailableSpace,
white_space_processor: WhiteSpaceProcessor,
allocator: std.mem.Allocator,
/// Layout context for accessing DOM tree
context: *mod.LayoutContext,

const Self = @This();

/// Track text inputs and their corresponding node IDs for proper fragment creation
const TextInput = struct {
    node_id: u32,
    start_offset: u32, // Offset in the segmenter buffer where this text starts
    length: u32, // Length of the processed text
};

pub fn init(allocator: std.mem.Allocator, available_width: mod.constants.AvailableSpace, context: *mod.LayoutContext) Self {
    return Self{
        .available_width = available_width,
        .white_space_processor = WhiteSpaceProcessor.init(allocator),
        .allocator = allocator,
        .lines = LineBox.LineBoxList{
            .allocator = allocator,
        },
        .context = context,
    };
}

pub fn deinit(self: *Self) void {
    // Deinitialize all lines (which will deinitialize their fragments and text)
    self.lines.deinit();
}

/// Transfer ownership of line boxes to caller, preventing deallocation when LineBuilder is destroyed
/// Caller becomes responsible for deallocating the returned ArrayList and all fragment ArrayLists within each LineBox
pub fn toOwnedLineBoxes(self: *Self, allocator: std.mem.Allocator) !LineBox.LineBoxList {
    const copy = try self.lines.dupe(allocator);
    self.lines.deinit();
    self.lines = .{
        .allocator = self.allocator,
    };
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
pub fn appendNodeSlice(self: *Self, text: []const u8, white_space_mode: WhiteSpaceLonghand, node_id: u32) !void {
    // Check if we should collapse initial whitespace based on the last non-empty fragment
    // const should_collapse_initial = self.shouldCollapseInitialWhitespace(white_space_mode);
    // const resolved_white_space = if (white_space_mode == .inherit) WhiteSpace.normal else white_space_mode;
    // const longhand = resolved_white_space.toLonghand();

    // Process text according to white-space rules (Phase I) with initial collapse support
    // The processor will handle whitespace-only text and return empty string if needed
    const processed_text = try self.white_space_processor.processTextWithWhiteSpace(text, longhand, should_collapse_initial);
    defer self.allocator.free(processed_text);

    // Create a single fragment for this text node
    // DOM range is always 0 to original text length since we're processing the whole node
    const dom_start: u32 = 0;
    const dom_end: u32 = @intCast(text.len);

    // Even if processed text is empty, create a zero-width fragment for selection support
    try self.createFragment(processed_text, white_space_mode, node_id, 0, dom_start, dom_end);
}

/// Create a fragment with owned text and add it to the current or new line
fn createFragment(self: *Self, text_slice: []const u8, white_space_mode: WhiteSpace, node_id: u32, start_offset: u32, dom_start: u32, dom_end: u32) !void {
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
        .dom_range = .{ .start = dom_start, .end = dom_end },
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

// /// Add text with full preprocessing pipeline
// /// This demonstrates the complete text preprocessing before LineBreakStream
// pub fn addTextWithFullPreprocessing(self: *Self, text: []const u8, white_space: WhiteSpaceLonghand, tab_size: TabSize) !void {
//     // TODO: .inherit should be resolved during style computation
//     const resolved_white_space = if (white_space == .inherit) WhiteSpace.normal else white_space;
//     const longhand = resolved_white_space.toLonghand();

//     // Phase I: White-space processing (collapsing/transformation)
//     const phase1_text = try self.white_space_processor.processTextWithWhiteSpace(text, longhand, false);
//     defer self.allocator.free(phase1_text);

//     // Store metadata about processing for potential Phase II usage
//     // In a real implementation, this would be associated with text fragments
//     _ = tab_size; // Will be used in Phase II during actual rendering

//     // Add processed text to line break segmenter
//     try self.segmenter.append(phase1_text);
// }

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

/// Build lines based on CSS white-space properties using a multi-pass approach:
/// Pass 1: Split on preserved line breaks (for pre, pre-wrap)
/// Pass 2: Word wrapping (for normal, pre-wrap when text-wrap: wrap)
/// Pass 3: End-of-line space handling (remove/hang based on white-space mode)
pub fn buildLines(self: *Self, white_space: WhiteSpace) !void {
    // TODO: white_space should be resolved during style computation, not here
    const resolved_white_space = if (white_space == .inherit) WhiteSpace.normal else white_space;
    const properties = resolved_white_space.toLonghand();

    // If there are no lines/fragments, nothing to do
    if (self.lines.len() == 0) return;

    // For modes that wrap, we always need to run word wrapping
    // (even if we also preserve line breaks)
    if (properties.wrap_mode == .wrap) {
        switch (self.available_width) {
            .definite => |width| try self.wrapLinesAtWordBoundaries(width),
            .min_content => {
                // For min-content, we need to find the minimum width first
                const min_width = try self.calculateMinContentWidth();
                try self.wrapLinesAtWordBoundaries(min_width);
            },
            .max_content => {}, // No wrapping for max-content
        }
    } else if (shouldPreserveLineBreaks(white_space)) {
        // Only split on line breaks if we're not wrapping
        // (wrapping will handle line breaks too)
        try self.splitOnPreservedLineBreaks();
    }

    // Pass 3: Handle end-of-line spaces (remove or mark as hanging)
    try self.handleEndOfLineSpaces(white_space);
}

/// Pass 1: Split fragments on preserved line breaks (simpler than using segmenter)
fn splitOnPreservedLineBreaks(self: *Self) !void {
    // Take ownership of current lines to rebuild them
    var prev_lines = try self.toOwnedLineBoxes(self.allocator);
    defer prev_lines.deinit();

    for (prev_lines.list.items) |*line| {
        const available_width = switch (self.available_width) {
            .definite => |w| w,
            else => 999999.0, // Large value for content-based sizing
        };
        try self.addNewLine(available_width);

        for (line.fragments.items) |*fragment| {
            // Check if this fragment contains line breaks
            if (std.mem.indexOf(u8, fragment.text, "\n")) |_| {
                try self.splitFragmentOnLineBreaks(fragment);
            } else {
                // No line breaks - just clone and add the fragment
                const owned_text = try self.allocator.dupe(u8, fragment.text);
                var cloned_fragment = fragment.*;
                cloned_fragment.text = owned_text;
                try self.appendFragment(cloned_fragment);
            }
        }
    }
}

/// Pass 2: Wrap lines at word boundaries using LineBreakStream
fn wrapLinesAtWordBoundaries(self: *Self, available_width: f32) !void {
    // Take ownership of current lines to rebuild them with wrapping
    var prev_lines = try self.toOwnedLineBoxes(self.allocator);
    defer prev_lines.deinit();

    for (prev_lines.list.items) |*line| {
        try self.addNewLine(available_width);
        try self.wrapLineAtWords(line, available_width);
    }
}

/// Check if line breaks should be preserved for this white-space mode
fn shouldPreserveLineBreaks(white_space_mode: WhiteSpace) bool {
    return switch (white_space_mode) {
        .pre, .@"pre-wrap" => true,
        .normal, .nowrap => false,
        .inherit => false, // TODO: Should be resolved during style computation
    };
}

/// Pass 3: Handle end-of-line spaces based on CSS white-space rules
/// This removes trailing spaces for modes that collapse spaces, or marks them as hanging
fn handleEndOfLineSpaces(self: *Self, white_space: WhiteSpace) !void {
    const properties = white_space.toLonghand();

    // Only process if we collapse spaces
    if (properties.collapse == .preserve) return;

    // Process each line
    for (self.lines.items()) |*line| {
        if (line.fragments.items.len == 0) continue;

        // Find the last fragment with content
        var last_fragment_idx = line.fragments.items.len - 1;
        while (last_fragment_idx > 0 and line.fragments.items[last_fragment_idx].text.len == 0) {
            last_fragment_idx -= 1;
        }

        var last_fragment = &line.fragments.items[last_fragment_idx];

        // For collapsing modes, remove trailing spaces
        const trimmed = std.mem.trimRight(u8, last_fragment.text, " \t");
        if (trimmed.len < last_fragment.text.len) {
            // We have trailing spaces to remove
            const old_text = last_fragment.text;
            const old_width = last_fragment.size.x;

            // Create new trimmed text
            const new_text = try self.allocator.dupe(u8, trimmed);
            self.allocator.free(old_text);

            // Update fragment
            last_fragment.text = new_text;
            last_fragment.length = @intCast(new_text.len);
            last_fragment.size.x = self.measureTextWidth(new_text);

            // Update line width
            line.size.x = line.size.x - old_width + last_fragment.size.x;
        }
    }
}

/// Split a fragment on preserved line breaks
fn splitFragmentOnLineBreaks(self: *Self, fragment: *const LineBoxFragment) !void {
    // Get the original DOM text for proper offset mapping
    const dom_text = self.getDomText(fragment.l_node_id);
    const dom_text_slice = dom_text[fragment.dom_range.start..fragment.dom_range.end];

    // Find line breaks in the fragment text
    var line_start: usize = 0;

    while (std.mem.indexOf(u8, fragment.text[line_start..], "\n")) |lf_offset| {
        const lf_index = line_start + lf_offset;
        const line_text = fragment.text[line_start..lf_index];

        // Map processed text offsets to DOM offsets
        const dom_start = mapProcessedOffsetWithinRange(
            line_start,
            fragment.dom_range.start,
            dom_text_slice,
            fragment.text,
        );
        // +1 to include the line break itself
        const dom_end = mapProcessedOffsetWithinRange(
            lf_index + 1,
            fragment.dom_range.start,
            dom_text_slice,
            fragment.text,
        );

        // Create fragment for this line
        const owned_text = try self.allocator.dupe(u8, line_text);
        try self.appendFragment(.{
            .l_node_id = fragment.l_node_id,
            .allocator = self.allocator,
            .start = @intCast(line_start),
            .length = @intCast(line_text.len),
            .size = mod.CSSPoint{ .x = self.measureTextWidth(line_text), .y = fragment.size.y },
            .is_atomic = fragment.is_atomic,
            .white_space_info = fragment.white_space_info,
            .text = owned_text,
            .dom_range = .{ .start = dom_start, .end = dom_end },
        });

        // Move to next line
        line_start = lf_index + 1;
        try self.ensureNewLine();
    }

    // Handle remaining text after last line break
    if (line_start < fragment.text.len) {
        const remaining_text = fragment.text[line_start..];

        // Map the start of the remaining text
        const dom_start = mapProcessedOffsetWithinRange(
            line_start,
            fragment.dom_range.start,
            dom_text_slice,
            fragment.text,
        );

        const owned_text = try self.allocator.dupe(u8, remaining_text);
        try self.appendFragment(.{
            .l_node_id = fragment.l_node_id,
            .allocator = self.allocator,
            .start = @intCast(line_start),
            .length = @intCast(remaining_text.len),
            .size = mod.CSSPoint{ .x = self.measureTextWidth(remaining_text), .y = fragment.size.y },
            .is_atomic = fragment.is_atomic,
            .white_space_info = fragment.white_space_info,
            .text = owned_text,
            .dom_range = .{ .start = dom_start, .end = fragment.dom_range.end },
        });
    }
}

/// Get the original DOM text for a layout node
/// Text nodes should always have a DOM node reference, panics if anonymous
fn getDomText(self: *Self, l_node_id: mod.LayoutNode.Id) []const u8 {
    const l_node = self.context.layout_tree.getNodePtr(l_node_id);
    switch (l_node.ref) {
        .doc_node => |doc_node_id| {
            const kind = self.context.doc_tree.getNodeKind(doc_node_id);
            if (kind == .text) {
                return self.context.doc_tree.getText(doc_node_id).bytes.items;
            }
            std.debug.panic("Layout node {d} has doc_node ref but is not a text node", .{l_node_id});
        },
        .anonymous => std.debug.panic("Text layout node {d} should not be anonymous", .{l_node_id}),
    }
}

/// Map a processed text offset to the corresponding offset within the fragment's DOM range
/// @param processed_offset: offset in the processed text
/// @param dom_range_start: start of the fragment's range in the DOM text
/// @param dom_text_slice: the portion of DOM text that this fragment represents
/// @param processed_text: the processed version of dom_text_slice
fn mapProcessedOffsetWithinRange(
    processed_offset: usize,
    dom_range_start: u32,
    dom_text_slice: []const u8,
    processed_text: []const u8,
) u32 {
    if (processed_offset == 0) return dom_range_start;
    if (processed_offset >= processed_text.len) return dom_range_start + @as(u32, @intCast(dom_text_slice.len));

    var dom_pos: usize = 0;
    var processed_pos: usize = 0;

    while (processed_pos < processed_offset and dom_pos < dom_text_slice.len) {
        // If we're at whitespace in the DOM text
        if (std.ascii.isWhitespace(dom_text_slice[dom_pos])) {
            // Skip the entire whitespace sequence in DOM
            while (dom_pos < dom_text_slice.len and std.ascii.isWhitespace(dom_text_slice[dom_pos])) {
                dom_pos += 1;
            }

            // If this whitespace sequence produced a space in processed text, advance processed position
            if (processed_pos < processed_text.len and processed_text[processed_pos] == ' ') {
                processed_pos += 1;
            }
        } else {
            // Non-whitespace character - these map 1:1
            dom_pos += 1;
            processed_pos += 1;
        }
    }

    return dom_range_start + @as(u32, @intCast(dom_pos));
}

/// Wrap a single line at word boundaries using LineBreakStream
fn wrapLineAtWords(self: *Self, line: *LineBox, available_width: f32) !void {
    var current_line_width: f32 = 0;

    for (line.fragments.items) |*fragment| {
        // Always use LineBreakStream - it knows best about word boundaries
        var segmenter = LineBreakStream.init(self.allocator);
        defer segmenter.deinit();

        try segmenter.append(fragment.text);

        // Get the original DOM text once for this fragment
        const dom_text = self.getDomText(fragment.l_node_id);
        const dom_text_slice = dom_text[fragment.dom_range.start..fragment.dom_range.end];

        var segment_start: usize = 0;

        while (segmenter.next()) |break_point| {
            const segment_text = fragment.text[segment_start..break_point.i];
            const measurements = self.trimAndMeasureText(segment_text);

            // Use trimmed width for overflow check - trailing whitespace can overflow
            if (current_line_width + measurements.trimmed_width > available_width and current_line_width > 0) {
                try self.ensureNewLine();
                current_line_width = 0;
            }

            // Map the processed text offsets to DOM offsets
            const dom_segment_start = mapProcessedOffsetWithinRange(
                segment_start,
                fragment.dom_range.start,
                dom_text_slice,
                fragment.text,
            );
            const dom_segment_end = mapProcessedOffsetWithinRange(
                break_point.i,
                fragment.dom_range.start,
                dom_text_slice,
                fragment.text,
            );

            try self.appendFragment(.{
                .l_node_id = fragment.l_node_id,
                .allocator = self.allocator,
                .start = @intCast(segment_start),
                .length = @intCast(segment_text.len),
                .size = mod.CSSPoint{ .x = measurements.full_width, .y = fragment.size.y },
                .is_atomic = fragment.is_atomic,
                .white_space_info = fragment.white_space_info,
                .text = try self.allocator.dupe(u8, segment_text),
                .dom_range = .{
                    .start = dom_segment_start,
                    .end = dom_segment_end,
                },
            });

            current_line_width += measurements.full_width;
            segment_start = break_point.i;
        }

        // Handle the remaining text after the last break point
        if (segment_start < fragment.text.len) {
            const remaining_text = fragment.text[segment_start..];
            const measurements = self.trimAndMeasureText(remaining_text);

            if (current_line_width + measurements.trimmed_width > available_width and current_line_width > 0) {
                try self.ensureNewLine();
                current_line_width = 0;
            }

            // Map the final segment's DOM range
            const dom_segment_start = mapProcessedOffsetWithinRange(
                segment_start,
                fragment.dom_range.start,
                dom_text_slice,
                fragment.text,
            );

            try self.appendFragment(.{
                .l_node_id = fragment.l_node_id,
                .allocator = self.allocator,
                .start = @intCast(segment_start),
                .length = @intCast(remaining_text.len),
                .size = mod.CSSPoint{ .x = measurements.full_width, .y = fragment.size.y },
                .is_atomic = fragment.is_atomic,
                .white_space_info = fragment.white_space_info,
                .text = try self.allocator.dupe(u8, remaining_text),
                .dom_range = .{
                    .start = dom_segment_start,
                    .end = fragment.dom_range.end,
                },
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

pub fn expectBuilderSnapshot(description: []const u8, lb: *Self) !void {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    const writer = buffer.writer().any();
    defer buffer.deinit();
    try lb.print(writer);
    try writer.writeAll("\n");
    try lb.printText(writer, false);
    try writer.writeAll("\n");
    try snapshot.expectMatchSnapshot(@src(), std.testing.allocator, description, buffer.items);
}

/// Helper to test layout computation with snapshot matching
fn expectComputedLayoutSnapshot(description: []const u8, doc_xml: []const u8, available_space: mod.constants.AvailableSpacePoint, comptime loc: std.builtin.SourceLocation) !void {
    const allocator = std.testing.allocator;

    var tree = try mod.docFromXml(allocator, doc_xml, .{});
    defer tree.deinit();

    var lt = try mod.LayoutTree.fromTree(allocator, &tree);
    defer lt.deinit();

    var context = mod.LayoutContext{
        .layout_tree = &lt,
        .doc_tree = &tree,
        .allocator = allocator,
    };

    // Compute the layout
    try mod.computeLayout(&context, available_space);

    // Generate snapshot
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    try writer.print("=== {s} ===\n", .{description});
    try writer.writeAll("DocTree:\n");
    try tree.print(writer.any());
    try writer.writeAll("\nLayoutTree after compute:\n");
    try lt.printRoot(writer.any());

    try snapshot.expectMatchSnapshot(loc, allocator, description, buffer.items);
}

test "reorganizeFragmentsWithWrapping" {
    const doc_xml =
        \\<div style="width: 100px;"><span>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed </span><span>   do eiusmod tempor incididunt ut labore et dolore magna aliqua.</span></div>
    ;
    try expectComputedLayoutSnapshot("wrapping multiple nodes", doc_xml, .{ .x = .{ .definite = 100 }, .y = .max_content }, @src());
}

test "cross-boundary whitespace collapsing" {
    // Multiple text nodes created by having text in different elements
    const doc_xml =
        \\<div style="width: 200px;"><span>Hello </span><span>   world</span></div>
    ;
    try expectComputedLayoutSnapshot("whitespace collapsing between spans", doc_xml, .{ .x = .{ .definite = 200 }, .y = .max_content }, @src());
}

test "preserve mode keeps trailing whitespace" {
    const doc_xml =
        \\<div style="width: 50px; white-space: pre-wrap;">Hello world   </div>
    ;
    try expectComputedLayoutSnapshot("pre-wrap preserves trailing spaces", doc_xml, .{ .x = .{ .definite = 50 }, .y = .max_content }, @src());
}

test "min-content wrapping" {
    const doc_xml =
        \\<div>Lorem ipsum dolor sit amet, consectetur adipiscing elit.</div>
    ;
    try expectComputedLayoutSnapshot("min-content wrapping", doc_xml, .{ .x = .min_content, .y = .max_content }, @src());
}

test "max-content layout" {
    const doc_xml =
        \\<div>This is a very long line that would normally wrap but in max-content mode it stays on one line</div>
    ;
    try expectComputedLayoutSnapshot("max-content single line", doc_xml, .{ .x = .max_content, .y = .max_content }, @src());
}

/// Check if we should collapse initial whitespace based on the last non-empty fragment in the current line
fn shouldCollapseInitialWhitespace(self: *Self, white_space_mode: WhiteSpace) bool {
    // TODO: .inherit should be resolved during style computation
    const resolved_mode = if (white_space_mode == .inherit) WhiteSpace.normal else white_space_mode;

    // In preserve mode, never collapse whitespace
    if (resolved_mode.toLonghand().collapse == .preserve) return false;

    // If no lines yet, this is the first content - remove all leading whitespace
    if (self.lines.len() == 0) return true;

    // Get the current line (the last line)
    const current_line = &self.lines.items()[self.lines.len() - 1];

    // Find the last non-empty fragment in the current line
    var frag_idx = current_line.fragments.items.len;
    while (frag_idx > 0) {
        frag_idx -= 1;
        const fragment = &current_line.fragments.items[frag_idx];

        // Skip empty fragments
        if (fragment.text.len == 0) continue;

        // Found a non-empty fragment - check if it ends with whitespace
        return std.ascii.isWhitespace(fragment.text[fragment.text.len - 1]);
    }

    // No previous non-empty fragment in this line - this is the first content of the line
    // Remove all leading whitespace
    return true;
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
            .min_content => {
                const min_content_width = try self.calculateMinContentWidth();
                var current_size = self.measureTextWidth(fba.slice());
                while (current_size < min_content_width) {
                    try fba_writer.writeByte(' ');
                    current_size += 1;
                }
            },
            .max_content => {
                try fba_writer.writeAll("|");
            },
        }
        const slice = fba.slice();
        try writer.print("|{s}", .{slice});
        try writer.print("|\n", .{});

        fba.clear();
    }
}
