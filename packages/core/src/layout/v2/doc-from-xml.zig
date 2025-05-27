// Helper functions to convert a small XML subset into the document tree used by
// the layout tests.  The parser is intentionally simple and exists only so the
// layout code can be tested without pulling in a full HTML parser.
const xml = @import("../../xml.zig");
const std = @import("std");
const Tree = @import("../../tree/Tree.zig");
const s = @import("../../styles/styles.zig");

/// Simple configuration options used when converting XML into a test DOM tree.
pub const Options = struct {
    /// Discard text nodes that only contain whitespace.
    ignore_empty_text: bool = true,
    /// Remove leading and trailing whitespace from text nodes.
    trim_text: bool = false,
    /// Split text nodes on newline characters into multiple nodes.
    split_lines: bool = true,
};

/// Parse a string of XML into the document tree representation understood by
/// the layout code. The resulting DOM tree is independent of the XML parser
/// after this function returns.
pub fn docFromXml(allocator: std.mem.Allocator, xml_string: []const u8, options: Options) !Tree {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const doc = try xml.parse(arena_allocator, xml_string);
    var tree = try Tree.init(allocator);
    errdefer tree.deinit();
    _ = try nodeFromXmlElement(&tree, doc.root, options);
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

/// Recursively build the Tree representation from a parsed XML element.
fn nodeFromXmlElement(tree: *Tree, element: *xml.Element, options: Options) TreeFromXmlError!Tree.Node.NodeId {
    // Create a DOM node corresponding to this element.
    const node_id = try tree.createNode();

    // Walk all children of the element and create corresponding DOM nodes.
    for (element.children) |child| {
        switch (child) {
            .char_data => {
                // Text nodes may be dropped or split according to the options.
                if (options.ignore_empty_text and isEmpty(child.char_data)) {
                    continue;
                }
                if (options.split_lines) {
                    var iter = std.mem.splitScalar(u8, child.char_data, '\n');

                    while (iter.next()) |line| {
                        const text = if (options.trim_text) trimText(line) else line;
                        if (text.len == 0) continue;
                        const text_node_id = try tree.createTextNode(text);
                        _ = try tree.appendChild(node_id, text_node_id);
                    }
                } else {
                    const text_node_id = try tree.createTextNode(if (options.trim_text) trimText(child.char_data) else child.char_data);
                    _ = try tree.appendChild(node_id, text_node_id);
                }
            },
            .comment => {
                // Comments are ignored entirely.
            },
            .element => {
                // Recursively build the subtree for the child element and
                // assign inline style hints for some HTML-like tags used in the
                // tests.
                const child_id = try nodeFromXmlElement(tree, child.element, options);
                var child_node = tree.getNode(child_id);
                if (std.mem.eql(u8, child.element.tag, "span")) {
                    child_node.styles.display = .{ .outside = .@"inline", .inside = .flow };
                } else if (std.mem.eql(u8, child.element.tag, "strong") or std.mem.eql(u8, child.element.tag, "b")) {
                    child_node.styles.display = .{ .outside = .@"inline", .inside = .flow };
                    child_node.styles.font_weight = .bold;
                } else if (std.mem.eql(u8, child.element.tag, "em") or std.mem.eql(u8, child.element.tag, "i")) {
                    child_node.styles.display = .{ .outside = .@"inline", .inside = .flow };
                    child_node.styles.font_style = .italic;
                }
                _ = try tree.appendChild(node_id, child_id);
            },
        }
    }

    // Parse simple inline attributes for styles, scrolling and selection.
    for (element.attributes) |attr| {
        if (std.mem.eql(u8, attr.name, "style")) {
            try s.parseStyleString(tree, node_id, attr.value);
            continue;
        }
        if (std.mem.eql(u8, attr.name, "scroll-y")) {
            tree.getNode(node_id).scroll_offset.y = std.fmt.parseFloat(f32, attr.value) catch unreachable;
            continue;
        }
        if (std.mem.eql(u8, attr.name, "scroll-x")) {
            tree.getNode(node_id).scroll_offset.x = std.fmt.parseFloat(f32, attr.value) catch unreachable;
            continue;
        }
        if (std.mem.eql(u8, attr.name, "selectionStart")) {
            const offset: u32 = try std.fmt.parseInt(u32, attr.value, 10);
            if (tree.getFirstSelection()) |selection| {
                try selection.setAnchor(tree, .{ .node_id = node_id, .offset = offset });
            } else {
                _ = try tree.createSelection(.{ .node_id = node_id, .offset = offset }, null);
            }
            continue;
        }
        if (std.mem.eql(u8, attr.name, "selectionEnd")) {
            const offset: u32 = try std.fmt.parseInt(u32, attr.value, 10);
            if (tree.getFirstSelection()) |selection| {
                try selection.setFocus(tree, .{ .node_id = node_id, .offset = offset });
            } else {
                _ = try tree.createSelection(.{ .node_id = node_id, .offset = offset }, null);
            }
            continue;
        }
    }
    return node_id;
}
