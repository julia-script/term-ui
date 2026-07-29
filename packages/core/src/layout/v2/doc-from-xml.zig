// Helper functions to convert a small XML subset into the document tree used by
// the layout tests.  The parser is intentionally simple and exists only so the
// layout code can be tested without pulling in a full HTML parser.
const xml = @import("../../xml.zig");
const std = @import("std");
const Tree = @import("../../tree/Tree.zig");
const s = @import("../../styles/styles.zig");
const BoundaryPoint = @import("../../tree/BoundaryPoint.zig");

/// Simple configuration options used when converting XML into a test DOM tree.
pub const Options = struct {
    /// Discard text nodes that only contain whitespace.
    ignore_empty_text: bool = false,
    /// Remove leading and trailing whitespace from text nodes.
    trim_text: bool = false,
    /// Split text nodes on newline characters into multiple nodes.
    split_lines: bool = false,
};

/// Parse a string of XML into the document tree representation understood by
/// the layout code. The resulting DOM tree is independent of the XML parser
/// after this function returns.
pub fn docFromXml(allocator: std.mem.Allocator, xml_string: []const u8, options: Options) !Tree {
    _ = options; // autofix
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const doc = try xml.parse(arena_allocator, xml_string);
    var tree = try Tree.init(allocator);
    errdefer tree.deinit();
    var ctx = BuilderContext{
        .selection_start = null,
        .selection_end = null,
    };
    _ = try nodeFromXmlElement(&tree, doc.root, &ctx);
    if (ctx.selection_start) |start| {
        _ = try tree.createSelection(start, ctx.selection_end);
    }
    return tree;
}

const TreeFromXmlError = error{
    OutOfMemory,
    NotFound,
    HierarchyRequestError,
    NotFoundError,
    Overflow,
    InvalidCharacter,
    NotInTheSameTree,
    OutOfBounds,
    StartAfterEnd,
};

fn isEmpty(str: []const u8) bool {
    for (str) |c| {
        switch (c) {
            ' ', '\n', '\t' => continue,
            else => return false,
        }
    }
    return true;
}
fn trimText(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \n\t\r");
}

const SELECTION_START = "$S[";
const SELECTION_END = "$S]";

const BuilderContext = struct {
    selection_start: ?BoundaryPoint = null,
    selection_end: ?BoundaryPoint = null,
};
/// Recursively build the Tree representation from a parsed XML element.
fn nodeFromXmlElement(tree: *Tree, element: *xml.Element, ctx: *BuilderContext) TreeFromXmlError!Tree.Node.NodeId {
    // Create a DOM node corresponding to this element.
    const node_id = try tree.createNode();

    // Walk all children of the element and create corresponding DOM nodes.
    for (element.children) |child| {
        switch (child) {
            .char_data => {
                const text_node_id = try tree.createTextNode("");
                _ = try tree.appendChild(node_id, text_node_id);
                var str = std.array_list.Managed(u8).init(tree.allocator);
                defer str.deinit();

                var current_index: usize = 0;
                const text = child.char_data;

                // Find selection markers
                const selection_start_idx = std.mem.indexOf(u8, text, SELECTION_START);
                const selection_end_idx = std.mem.indexOf(u8, text, SELECTION_END);

                // Process text and markers in order
                if (selection_start_idx) |start_idx| {
                    // Add text before selection start marker
                    try str.appendSlice(text[current_index..start_idx]);
                    ctx.selection_start = .{ .node_id = text_node_id, .offset = @intCast(str.items.len) };
                    current_index = start_idx + SELECTION_START.len;

                    if (selection_end_idx) |end_idx| {
                        if (end_idx > start_idx) {
                            // Add text between markers
                            try str.appendSlice(text[current_index..end_idx]);
                            ctx.selection_end = .{ .node_id = text_node_id, .offset = @intCast(str.items.len) };
                            current_index = end_idx + SELECTION_END.len;
                        }
                    }
                } else if (selection_end_idx) |end_idx| {
                    // Only end marker present
                    try str.appendSlice(text[current_index..end_idx]);
                    ctx.selection_end = .{ .node_id = text_node_id, .offset = @intCast(str.items.len) };
                    current_index = end_idx + SELECTION_END.len;
                }

                // Add remaining text after all markers
                if (current_index < text.len) {
                    try str.appendSlice(text[current_index..]);
                }

                try tree.setText(text_node_id, str.items);
            },
            .comment => {
                // Comments are ignored entirely.
            },
            .element => {
                // Recursively build the subtree for the child element and
                // assign inline style hints for some HTML-like tags used in the
                // tests.
                const child_id = try nodeFromXmlElement(tree, child.element, ctx);
                _ = try tree.appendChild(node_id, child_id);
                var child_node = tree.getNode(child_id);
                if (std.mem.eql(u8, child.element.tag, "span")) {
                    child_node.styles.display = .{ .outside = .@"inline", .inside = .flow };
                } else if (std.mem.eql(u8, child.element.tag, "strong") or std.mem.eql(u8, child.element.tag, "b")) {
                    child_node.styles.display = .{ .outside = .@"inline", .inside = .flow };
                    child_node.styles.font_weight = .bold;
                } else if (std.mem.eql(u8, child.element.tag, "em") or std.mem.eql(u8, child.element.tag, "i")) {
                    child_node.styles.display = .{ .outside = .@"inline", .inside = .flow };
                    child_node.styles.font_style = .italic;
                } else if (std.mem.eql(u8, child.element.tag, "pre")) {
                    child_node.styles.white_space_collapse = .preserve;
                    child_node.styles.text_wrap_mode = .nowrap;
                }
            },
        }
    }

    // Parse simple inline attributes for styles, scrolling and selection.
    for (element.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "style")) {
            try s.parseStyleString(tree, node_id, attr.value);
            continue;
        }
        if (std.mem.eql(u8, attr.name, "scroll-top")) {
            tree.getNode(node_id).scroll_offset.y = std.fmt.parseFloat(f32, attr.value) catch unreachable;
            continue;
        }
        if (std.mem.eql(u8, attr.name, "scroll-left")) {
            tree.getNode(node_id).scroll_offset.x = std.fmt.parseFloat(f32, attr.value) catch unreachable;
            continue;
        }

        const node = tree.getNode(node_id);
        try node.setAttribute(attr.name, attr.value);
    }
    return node_id;
}
