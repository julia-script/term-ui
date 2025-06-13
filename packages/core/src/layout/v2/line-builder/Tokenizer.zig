const std = @import("std");
const mod = @import("../mod.zig");
const Token = @import("./Token.zig");
const LineBoxFragment = mod.LineBoxFragment;
const LineBreakStream = @import("../../../uni/LineBreakStream.zig");
const unicode = @import("../../../uni/codepoint.zig");
const WhiteSpaceCollapse = @import("../../../styles/white-space.zig").WhiteSpaceCollapse;

// pub fn tokenizeFragments(
//     allocator: std.mem.Allocator,
//     fragments: []const LineBoxFragment,
//     collapse_mode: WhiteSpaceCollapse,
// ) !std.ArrayList(Token) {
//     var tokens = std.ArrayList(Token).init(allocator);
//     var linebreak_iter = LineBreakStream.init(allocator);
//     defer linebreak_iter.deinit();

//     for (fragments) |fragment| {
//         if (fragment.is_atomic) {
//             // Atomic elements become single tokens with pre-computed size
//             try tokens.append(.{
//                 .l_node_id = fragment.l_node_id,
//                 .dom_range = .{ .start = fragment.dom_range.start, .end = fragment.dom_range.end },
//                 .text = fragment.text,
//                 .kind = .atomic,
//                 .break_after = .allowed,
//                 .size = fragment.size,
//             });
//             continue;
//         }

//         const last_buffer_i = linebreak_iter.i;
//         // Use line breaker to find segment boundaries
//         try linebreak_iter.append(fragment.text);

//         var last_break: usize = 0;
//         while (linebreak_iter.next()) |linebreak| {
//             const local_i = linebreak.i - last_buffer_i;
//             const segment = fragment.text[last_break..local_i];
//             std.debug.print("segment: {any}\n", .{segment});

//             try tokenizeAndAppend(
//                 &tokens,
//                 segment,
//                 fragment.l_node_id,
//                 .{ .start = @intCast(fragment.dom_range.start + last_break), .end = @intCast(fragment.dom_range.start + local_i) },
//                 linebreak.mandatory,
//                 collapse_mode,
//             );

//             last_break = local_i;
//         }

//         // Handle remaining text after last break
//         if (last_break < fragment.text.len) {
//             const segment = fragment.text[last_break..];
//             std.debug.print("segment: {any}\n", .{segment});
//             try tokenizeAndAppend(
//                 &tokens,
//                 segment,
//                 fragment.l_node_id,
//                 .{ .start = @intCast(fragment.dom_range.start + last_break), .end = @intCast(fragment.dom_range.start + fragment.text.len) },
//                 false, // No break at end
//                 collapse_mode,
//             );
//         }
//     }

//     return tokens;
// }
pub const Error = error{ OutOfMemory, InvalidUtf8, FailedToComputeChildLayout };
pub fn tokenizeLayoutNode(
    allocator: std.mem.Allocator,
    context: *mod.LayoutContext,
    inputs: mod.ContainerContext,
    l_node_id: mod.LayoutNode.Id,
    collapse_mode: WhiteSpaceCollapse,
) Error!std.ArrayList(Token) {
    const l_node = context.layout_tree.getNodePtr(l_node_id);
    var linebreak_iter = LineBreakStream.init(allocator);
    defer linebreak_iter.deinit();
    var tokens = std.ArrayList(Token).init(allocator);

    switch (l_node.data) {
        .inline_container_node => |inline_container_node| {
            const children = inline_container_node.children;
            for (children.items) |child| {
                try tokenizeLayoutNodeInner(
                    allocator,
                    context,
                    inputs,
                    child,
                    collapse_mode,
                    &tokens,
                    &linebreak_iter,
                );
            }
        },
        else => std.debug.panic("Root node should be an inline container node", .{}),
    }
    return tokens;
}
pub fn tokenizeLayoutNodeInner(
    allocator: std.mem.Allocator,
    context: *mod.LayoutContext,
    inputs: mod.ContainerContext,
    l_node_id: mod.LayoutNode.Id,
    collapse_mode: WhiteSpaceCollapse,
    tokens: *std.ArrayList(Token),
    linebreak_iter: *LineBreakStream,
) Error!void {
    const l_node = context.layout_tree.getNodePtr(l_node_id);

    switch (l_node.data) {
        .text_node => |text_node| {
            _ = text_node; // autofix
            // const doc_node = context.doc_tree.getNode(l_node.ref.doc_node);
            // const text = doc_node.text.slice();
            const text = context.layout_tree.getNodeText(context.doc_tree, l_node_id);
            // special case: if the text is empty, we still need a token for it so every node has at least one token
            if (text.len == 0) {
                try tokens.append(.{
                    .l_node_id = l_node_id,
                    .dom_range = .{ .start = 0, .end = 0 },
                    .text = "",
                    .kind = .text,
                    .break_after = .prohibited,
                    .size = .{ .x = 0, .y = 0 },
                });
                return;
            }
            try linebreak_iter.append(text);
            const start_i = linebreak_iter.last_buffer_index;
            var last_break: usize = 0;
            while (linebreak_iter.next()) |linebreak| {
                const local_i = linebreak.i - start_i;
                const segment = text[last_break..local_i];

                try tokenizeAndAppend(
                    tokens,
                    segment,
                    l_node_id,
                    .{ .start = @intCast(last_break), .end = @intCast(local_i) },
                    linebreak.mandatory,
                    collapse_mode,
                );

                last_break = local_i;
            }

            // Handle remaining text after last break
            if (last_break < text.len) {
                const segment = text[last_break..];
                try tokenizeAndAppend(
                    tokens,
                    segment,
                    l_node_id,
                    .{ .start = @intCast(last_break), .end = @intCast(text.len) },
                    false, // No break at end
                    collapse_mode,
                );
            }
        },
        .inline_node => |inline_node| {
            if (inline_node.is_atomic) {
                var layout = try mod.performChildLayout(
                    context,

                    l_node_id,
                    inputs.known_dimensions,
                    inputs.parent_size,
                    inputs.available_space,
                    .inherent_size,
                    .{ .start = false, .end = false },
                );
                defer layout.deinit();
                try tokens.append(.{
                    .l_node_id = l_node_id,
                    .dom_range = .{ .start = 0, .end = 0 },
                    .text = "",
                    .kind = .atomic,
                    .break_after = .allowed,

                    .size = layout.size,
                });
                return;
            }
            const children = inline_node.children;
            for (children.items) |child| {
                try tokenizeLayoutNodeInner(
                    allocator,
                    context,
                    inputs,
                    child,
                    collapse_mode,
                    tokens,
                    linebreak_iter,
                );
            }
        },
        .block_container_node, .inline_container_node => unreachable,
    }
}

pub fn tokenizeAndAppend(
    tokens: *std.ArrayList(Token),
    segment: []const u8,
    l_node_id: mod.LayoutNode.Id,
    dom_range: struct { start: u32, end: u32 },
    mandatory_break_after: bool,
    collapse_mode: WhiteSpaceCollapse,
) !void {
    var i: usize = 0;

    while (i < segment.len) {
        const start = i;
        const start_char = segment[i];

        if (isWhitespace(start_char)) {
            // Check if this whitespace is collapsible
            if (isCollapsible(start_char, collapse_mode)) {
                // Collect run of collapsible whitespace (which may include spaces, tabs, and/or newlines)
                var has_newline = false;
                while (i < segment.len) {
                    const ch = segment[i];
                    if (!isWhitespace(ch) or !isCollapsible(ch, collapse_mode)) break;
                    if (ch == '\n') has_newline = true;
                    i += 1;
                }

                const ws_text = segment[start..i];
                const kind: Token.Kind = if (has_newline and collapse_mode != .collapse) .segment_break else .whitespace;
                const transformed = if (kind == .segment_break) "" else transformWhitespace(ws_text, collapse_mode);

                try tokens.append(.{
                    .l_node_id = l_node_id,
                    .dom_range = .{ .start = @intCast(dom_range.start + start), .end = @intCast(dom_range.start + i) },
                    .text = transformed,
                    .kind = kind,
                    .break_after = if (kind == .segment_break) .mandatory else .allowed,
                });
            } else {
                // Non-collapsible whitespace - create separate tokens
                if (isSegmentBreak(start_char)) {
                    i += 1;
                    // Segment breaks always have empty text
                    try tokens.append(.{
                        .l_node_id = l_node_id,
                        .dom_range = .{ .start = @intCast(dom_range.start + start), .end = @intCast(dom_range.start + i) },
                        .text = "",
                        .kind = .segment_break,
                        .break_after = .mandatory,
                    });
                } else {
                    // Non-collapsible spaces/tabs
                    while (i < segment.len and isWhitespace(segment[i]) and !isSegmentBreak(segment[i]) and !isCollapsible(segment[i], collapse_mode)) {
                        i += 1;
                    }

                    const ws_text = segment[start..i];
                    try tokens.append(.{
                        .l_node_id = l_node_id,
                        .dom_range = .{ .start = @intCast(dom_range.start + start), .end = @intCast(dom_range.start + i) },
                        .text = ws_text,
                        .kind = .whitespace,
                        .break_after = .allowed,
                    });
                }
            }
        } else {
            // Regular text
            while (i < segment.len and !isWhitespace(segment[i])) {
                i += 1;
            }

            const is_last_in_segment = (i == segment.len);
            try tokens.append(.{
                .l_node_id = l_node_id,
                .dom_range = .{ .start = @intCast(dom_range.start + start), .end = @intCast(dom_range.start + i) },
                .text = segment[start..i],
                .kind = .text,
                .break_after = if (is_last_in_segment and mandatory_break_after)
                    .mandatory
                else
                    .prohibited,
            });
        }
    }
}

fn transformWhitespace(text: []const u8, collapse_mode: WhiteSpaceCollapse) []const u8 {
    return switch (collapse_mode) {
        .preserve => text, // Keep as-is
        .@"preserve-breaks" => blk: {
            // Convert tabs to spaces, keep newlines
            for (text) |c| {
                if (c == '\t') break :blk " ";
            }
            break :blk text;
        },
        .@"preserve-spaces" => " ", // All collapsible chars (tabs, newlines) become single space
        .collapse => " ", // All whitespace becomes single space
        .@"break-spaces" => text, // Keep as-is like preserve
        .inherit => unreachable, // Should be resolved by now
    };
}

fn isSegmentBreak(c: u8) bool {
    return c == '\n';
}

fn isWhitespace(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n' => true,
        else => false,
    };
}

// Check if a codepoint is an "other space separator" (Unicode Zs excluding space and no-break space)
fn isOtherSpaceSeparator(codepoint: u21) bool {
    const cat = unicode.getCategory(codepoint);
    if (cat != .Zs) {
        return false;
    }
    if (codepoint == '\u{00A0}' or codepoint == '\u{0020}') {
        return false;
    }
    return true;
}

fn isCollapsible(codepoint: u21, collapse_mode: WhiteSpaceCollapse) bool {
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
        .@"break-spaces" => false, // Nothing is collapsible in break-spaces mode
        .inherit => std.debug.panic("inherit property should be resolved during style computation", .{}),
    };
}

// test "tokenize simple text" {
//     const allocator = std.testing.allocator;

//     const fragments = [_]LineBoxFragment{
//         .{
//             .l_node_id = 1,
//             .text = "hello world",
//             .dom_range = .{ .start = 0, .end = 11 },
//             .is_atomic = false,
//             .start = 0,
//             .length = 11,
//             .size = .{ .x = 0, .y = 0 },
//             .allocator = allocator,
//         },
//     };

//     // const tokens = try tokenizeFragments(allocator, fragments[0..], .collapse);
//     // defer tokens.deinit();

//     try std.testing.expectEqual(@as(usize, 3), tokens.items.len);
//     try std.testing.expectEqualStrings("hello", tokens.items[0].text);
//     try std.testing.expectEqual(Token.Kind.text, tokens.items[0].kind);
//     try std.testing.expectEqualStrings(" ", tokens.items[1].text);
//     try std.testing.expectEqual(Token.Kind.whitespace, tokens.items[1].kind);
//     try std.testing.expectEqualStrings("world", tokens.items[2].text);
//     try std.testing.expectEqual(Token.Kind.text, tokens.items[2].kind);
// }
