const std = @import("std");
const DocNodeId = @import("../../tree/Node.zig").NodeId;
const DocTree = @import("../../tree/Tree.zig");
const Array = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const mod = @import("mod.zig");

const docFromXml = @import("./doc-from-xml.zig").docFromXml;

nodes: HashMap(LayoutNode.Id, LayoutNode) = .{},
node_count: LayoutNode.Id = 0,
allocator: std.mem.Allocator,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .allocator = allocator };
}
pub fn deinit(self: *Self) void {
    var it = self.nodes.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.nodes.deinit(self.allocator);
}

pub fn createNode(self: *Self, data: LayoutNode.Data, ref: DocRef) !LayoutNode.Id {
    const id = self.node_count;
    try self.nodes.put(self.allocator, id, LayoutNode{ .id = id, .data = data, .ref = ref });
    self.node_count += 1;
    return id;
}
pub fn createTextNode(self: *Self, contents: []const u8, ref: DocRef) !LayoutNode.Id {
    const node_id = try self.createNode(.{ .text_node = .{} }, ref);
    var node = self.getNodePtr(node_id);
    try node.data.text_node.contents.appendSlice(self.allocator, contents);
    return node_id;
}
pub fn appendNode(self: *Self, parent_id: LayoutNode.Id, child_id: LayoutNode.Id) !void {
    const parent = self.getNodePtr(parent_id);
    var list: *Array(LayoutNode.Id) = switch (parent.data) {
        .inline_node => |*n| &n.children,
        .block_container_node => |*n| &n.children,
        .inline_container_node => |*n| &n.children,
        else => return error.InvalidParent,
    };
    try list.append(self.allocator, child_id);
    try self.setParent(child_id, parent_id);
}
pub fn setParent(self: *Self, child_id: LayoutNode.Id, parent_id: ?LayoutNode.Id) !void {
    const child = self.getNodePtr(child_id);
    child.parent = parent_id;
}

pub fn getNodePtr(self: *Self, id: LayoutNode.Id) *LayoutNode {
    return self.nodes.getPtr(id) orelse std.debug.panic("LayoutTree: Node {d} not found", .{id});
}

pub const LayoutNode = struct {
    id: Id,
    ref: DocRef,
    parent: ?Id = null,
    data: Data,
    box: mod.Box = .{},
    pub const Id = u32;
    pub const Data = union(enum) {
        text_node: TextNode,
        inline_node: InlineNode,
        block_container_node: BlockContainerNode,
        inline_container_node: InlineContainerNode,
    };
    pub fn deinit(self: *LayoutNode, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .text_node => |*node| node.deinit(allocator),
            .inline_node => |*node| node.deinit(allocator),
            .block_container_node => |*node| node.deinit(allocator),
            .inline_container_node => |*node| node.deinit(allocator),
        }
    }
};

pub const TextNode = struct {
    contents: Array(u8) = .{},
    pub fn deinit(self: *TextNode, allocator: std.mem.Allocator) void {
        self.contents.deinit(allocator);
    }
};

pub const InlineNode = struct {
    is_atomic: bool = false,
    children: Array(LayoutNode.Id) = .{},
    continuation: ?LayoutNode.Id = null,
    continuationOf: ?LayoutNode.Id = null,
    pub fn deinit(self: *InlineNode, allocator: std.mem.Allocator) void {
        self.children.deinit(allocator);
    }
};

pub const DocRef = union(enum) {
    anonymous,
    doc_node: DocNodeId,
};

pub const BlockContainerNode = struct {
    children: Array(LayoutNode.Id) = .{},
    pub fn deinit(self: *BlockContainerNode, allocator: std.mem.Allocator) void {
        self.children.deinit(allocator);
    }
    pub fn isAnonymous(self: *BlockContainerNode) bool {
        return self.ref == .anonymous;
    }
};

/// The same as a block container, but all children are inline, which enables inline formatting context.
/// this node also holds the LineBoxes
pub const InlineContainerNode = struct {
    children: Array(LayoutNode.Id) = .{},
    line_boxes: Array(LineBox) = .{},
    continuation: ?LayoutNode.Id = null,
    continuationOf: ?LayoutNode.Id = null,
    pub fn deinit(self: *InlineContainerNode, allocator: std.mem.Allocator) void {
        self.children.deinit(allocator);
        // Properly deallocate each LineBox's fragments before deallocating the array
        for (self.line_boxes.items) |*line_box| {
            line_box.deinit(allocator);
        }
        self.line_boxes.deinit(allocator);
    }
};

pub const LineBox = struct {
    fragments: Array(Fragment) = .{},
    pub const Fragment = struct {
        node: LayoutNode.Id,
        start: usize,
        end: usize,
        text: []u8,
        allocator: std.mem.Allocator,
        position: mod.CSSPoint,

        pub fn deinit(self: *@This()) void {
            self.allocator.free(self.text);
        }
    };
    pub fn deinit(self: *LineBox, allocator: std.mem.Allocator) void {
        for (self.fragments.items) |*fragment| {
            fragment.deinit();
        }
        self.fragments.deinit(allocator);
    }
};

pub fn fromTree(allocator: std.mem.Allocator, tree: *DocTree) !Self {
    var self = Self.init(allocator);
    // Start building the layout tree at the document root.
    _ = try self.build(tree, DocTree.ROOT_NODE_ID);
    return self;
}

fn nodeIsInline(tree: *DocTree, node_id: DocNodeId) bool {
    const kind = tree.getNodeKind(node_id);
    if (kind == .text) return true;
    return tree.getStyle(node_id).display.outside == .@"inline";
}
fn isOnlyInlineSubtree(tree: *DocTree, node_id: DocNodeId) bool {
    const kind = tree.getNodeKind(node_id);
    if (kind == .text) return true;
    const style = tree.getStyle(node_id);
    if (style.display.outside != .@"inline") return false;
    if (isAtomicInline(tree, node_id)) return true;
    for (tree.getNodeChildren(node_id)) |child| {
        if (!isOnlyInlineSubtree(tree, child)) return false;
    }
    return true;
}
pub fn isDisplayNone(tree: *DocTree, node_id: DocNodeId) bool {
    return tree.getStyle(node_id).display.outside == .none;
}
pub fn isInlineFlow(tree: *DocTree, node_id: DocNodeId) bool {
    const style = tree.getStyle(node_id);
    return style.display.outside == .@"inline" and style.display.inside == .flow;
}
pub fn isAtomicInline(tree: *DocTree, node_id: DocNodeId) bool {
    const style = tree.getStyle(node_id);
    return style.display.outside == .@"inline" and style.display.inside != .flow;
}

const BuildError = error{
    OutOfMemory,
    InvalidParent,
};
const MixedContextBuilder = struct {
    layout_tree: *Self,
    doc_tree: *DocTree,
    root_container_id: LayoutNode.Id,
    current_container_id: LayoutNode.Id,
    allocator: std.mem.Allocator,
    stack: Array(LayoutNode.Id) = .{},
    pub fn isCurrentContainerInline(self: *MixedContextBuilder) bool {
        const current_container = self.layout_tree.getNodePtr(self.current_container_id);
        return switch (current_container.data) {
            .inline_container_node => true,
            .block_container_node => false,
            else => unreachable,
        };
    }
    pub fn init(allocator: std.mem.Allocator, layout_tree: *Self, doc_tree: *DocTree, root_container_id: LayoutNode.Id) !MixedContextBuilder {
        return MixedContextBuilder{
            .allocator = allocator,
            .layout_tree = layout_tree,
            .doc_tree = doc_tree,
            .root_container_id = root_container_id,
            .current_container_id = root_container_id,
        };
    }
    pub fn getCurrentParent(self: *MixedContextBuilder) LayoutNode.Id {
        return if (self.stack.items.len > 0) self.stack.items[self.stack.items.len - 1] else self.current_container_id;
    }
    pub fn createBlockContainer(self: *MixedContextBuilder) !LayoutNode.Id {
        const id = try self.layout_tree.createNode(.{ .block_container_node = .{} }, .anonymous);
        try self.layout_tree.appendNode(self.root_container_id, id);
        self.current_container_id = id;
        return id;
    }
    pub fn createInlineContainer(self: *MixedContextBuilder, parent_id: LayoutNode.Id) !LayoutNode.Id {
        const id = try self.layout_tree.createNode(.{ .inline_container_node = .{} }, .anonymous);
        try self.layout_tree.appendNode(parent_id, id);
        self.current_container_id = id;
        return id;
    }
    pub fn appendNode(self: *MixedContextBuilder, child_id: LayoutNode.Id) !void {
        if (!self.isCurrentContainerInline()) {
            try self.splitStack();
        }
        try self.layout_tree.appendNode(self.getCurrentParent(), child_id);
    }
    pub fn splitStack(self: *MixedContextBuilder) !void {
        var parent = try self.createInlineContainer(self.root_container_id);
        for (0..self.stack.items.len) |i| {
            const id = self.stack.items[i];
            var node = self.layout_tree.getNodePtr(id);
            switch (node.data) {
                .inline_container_node => {
                    const clone_inline_container_node_id = try self.layout_tree.createNode(.{ .inline_container_node = .{} }, .anonymous);
                    node = self.layout_tree.getNodePtr(id);
                    node.data.inline_container_node.continuation = clone_inline_container_node_id;
                    const clone_node = self.layout_tree.getNodePtr(clone_inline_container_node_id);
                    clone_node.data.inline_container_node.continuationOf = id;

                    try self.layout_tree.appendNode(parent, clone_inline_container_node_id);
                    parent = clone_inline_container_node_id;
                    self.stack.items[i] = clone_inline_container_node_id;
                },
                .inline_node => {
                    const clone_inline_node_id = try self.layout_tree.createNode(.{ .inline_node = .{} }, node.ref);
                    node = self.layout_tree.getNodePtr(id);
                    node.data.inline_node.continuation = clone_inline_node_id;
                    const clone_node = self.layout_tree.getNodePtr(clone_inline_node_id);
                    clone_node.data.inline_node.continuationOf = id;
                    try self.layout_tree.appendNode(parent, clone_inline_node_id);
                    parent = clone_inline_node_id;
                    self.stack.items[i] = clone_inline_node_id;
                },
                else => unreachable,
            }
        }
    }

    pub fn build(self: *MixedContextBuilder) BuildError!void {
        const children = self.doc_tree.getNodeChildren(self.root_container_id);
        for (children) |child| {
            if (isDisplayNone(self.doc_tree, child)) continue;
            try self.buildFromNode(child);
        }
    }
    pub fn buildFromNode(self: *MixedContextBuilder, node_id: DocNodeId) BuildError!void {
        const kind = self.doc_tree.getNodeKind(node_id);
        if (kind == .text) {
            const text = self.doc_tree.getText(node_id).bytes.items;
            const id = try self.layout_tree.createTextNode(text, .{ .doc_node = node_id });
            try self.appendNode(id);

            // return id;
            return;
        }
        if (isAtomicInline(self.doc_tree, node_id)) {
            const id = try self.layout_tree.buildInsideBlock(self.doc_tree, node_id);
            try self.appendNode(id);
            return;
        }
        if (isInlineFlow(self.doc_tree, node_id)) {
            const id = try self.layout_tree.createNode(.{ .inline_node = .{} }, .{ .doc_node = node_id });
            try self.layout_tree.appendNode(self.getCurrentParent(), id);
            // push to the stack
            try self.stack.append(self.allocator, id);
            defer _ = self.stack.pop();
            const children = self.doc_tree.getNodeChildren(node_id);
            for (children) |child| {
                if (isDisplayNone(self.doc_tree, child)) continue;
                try self.buildFromNode(child);
            }
            return;
        }

        // otherwise it's a block
        const block_container_id = if (self.isCurrentContainerInline()) try self.createBlockContainer() else self.current_container_id;
        const block_node = try self.layout_tree.buildInsideBlock(self.doc_tree, node_id);
        try self.layout_tree.appendNode(block_container_id, block_node);
    }

    pub fn deinit(self: *MixedContextBuilder) void {
        self.stack.deinit(self.allocator);
    }
};
/// Recursively convert the DOM starting at `node_id` into layout nodes.
/// Returns the id of the created layout node or `null` if the DOM node should
/// not produce a layout representation.
fn build(self: *Self, tree: *DocTree, node_id: DocNodeId) BuildError!LayoutNode.Id {
    const kind = tree.getNodeKind(node_id);

    // 1. Text DOM nodes map directly to layout text nodes.
    if (kind == .text) {
        const text = tree.getText(node_id).bytes.items;
        const id = try self.createTextNode(text, .{ .doc_node = node_id });
        return id;
    }
    const style = tree.getStyle(node_id);
    if (style.display.inside != .flow) {
        return self.buildInsideBlock(tree, node_id);
    }

    // 2. Atomic inline elements produce an `InlineNode`, right now we dont have other types of atomic inline elements besides inline-block or inline-flex
    if (isInlineFlow(tree, node_id)) {
        const id = try self.createNode(.{ .inline_node = .{} }, .{ .doc_node = node_id });
        for (tree.getNodeChildren(node_id)) |child| {
            if (isDisplayNone(tree, child)) continue;
            const child_layout_node_id = try self.build(tree, child);
            try self.appendNode(id, child_layout_node_id);
        }
        return id;
    }
    unreachable;
}
pub fn buildInsideBlock(self: *Self, tree: *DocTree, node_id: DocNodeId) !LayoutNode.Id {
    const children = tree.getNodeChildren(node_id);
    var only_inline_children = true;
    for (children) |child| {
        if (isDisplayNone(tree, child)) continue;
        if (!isOnlyInlineSubtree(tree, child)) {
            only_inline_children = false;
        }
    }
    if (only_inline_children) {
        const inline_container_id = try self.createNode(.{ .inline_container_node = .{} }, .{ .doc_node = node_id });
        for (children) |child| {
            if (isDisplayNone(tree, child)) continue;
            const child_layout_node_id = try self.build(tree, child);
            try self.appendNode(inline_container_id, child_layout_node_id);
        }
        return inline_container_id;
    }

    const container_id = try self.createNode(.{ .block_container_node = .{} }, .{ .doc_node = node_id });
    var mixed_context_builder = try MixedContextBuilder.init(self.allocator, self, tree, container_id);
    defer mixed_context_builder.deinit();
    try mixed_context_builder.build();
    return container_id;
}

fn writeDocRef(writer: std.io.AnyWriter, ref: DocRef) !void {
    switch (ref) {
        .anonymous => try writer.writeAll("{anon}"),
        .doc_node => |id| try writer.print("{{doc#{d}}}", .{id}),
    }
}

pub fn getChildren(self: *Self, node_id: LayoutNode.Id) []const LayoutNode.Id {
    const node = self.getNodePtr(node_id);
    return switch (node.data) {
        .inline_node => |*n| n.children.items,
        .block_container_node => |*n| n.children.items,
        .inline_container_node => |*n| n.children.items,
        else => &[_]LayoutNode.Id{},
    };
}

fn printNodeInternal(self: *Self, node_id: LayoutNode.Id, writer: std.io.AnyWriter, prefix: []const u8, is_root: bool, is_last: bool) !void {
    const node = self.getNodePtr(node_id);

    if (!is_root) {
        try writer.writeAll(prefix);
        if (is_last)
            try writer.writeAll("└── ")
        else
            try writer.writeAll("├── ");
    }

    switch (node.data) {
        .text_node => |text| {
            if (is_root) {
                // root has no prefix
            }
            try writer.print("[{s} #{d}] \"{s}\"", .{ @tagName(node.data), node.id, text.contents.items });
        },
        .inline_node => |inline_node| {
            try writer.print("[{s} #{d}", .{ @tagName(node.data), node.id });
            if (inline_node.is_atomic) {
                try writer.print(" atomic", .{});
            }
            if (inline_node.continuationOf) |continuation_of| {
                try writer.print(" continuationOf={{#{d}}}", .{continuation_of});
            }
            if (inline_node.continuation) |continuation| {
                try writer.print(" continuation={{#{d}}}", .{continuation});
            }

            try writer.print(" ref=", .{});
            try writeDocRef(writer, node.ref);
            try writer.print(" children={{{d}}} box={{{any}}}]", .{ inline_node.children.items.len, node.box });
        },
        .block_container_node => |block| {
            try writer.print("[{s} #{d} ref=", .{ @tagName(node.data), node.id });
            try writeDocRef(writer, node.ref);

            try writer.print(" children={{{d}}} box={{{any}}}]", .{ block.children.items.len, node.box });
        },
        .inline_container_node => |container| {
            try writer.print("[{s} #{d} ref=", .{ @tagName(node.data), node.id });
            try writeDocRef(writer, node.ref);
            if (container.continuationOf) |continuation_of| {
                try writer.print(" continuationOf={{#{d}}}", .{continuation_of});
            }
            if (container.continuation) |continuation| {
                try writer.print(" continuation={{#{d}}}", .{continuation});
            }
            try writer.print(" children={{{d}}} lines={{{d}}} box={{{any}}}]", .{ container.children.items.len, container.line_boxes.items.len, node.box });
        },
    }

    try writer.writeByte('\n');

    var new_prefix_buf: [256]u8 = undefined;
    var new_prefix_len: usize = 0;
    if (!is_root) {
        std.mem.copyForwards(u8, new_prefix_buf[0..prefix.len], prefix);
        const segment = if (is_last) "    " else "│   ";
        new_prefix_len = prefix.len + segment.len;
        std.mem.copyForwards(u8, new_prefix_buf[prefix.len .. prefix.len + segment.len], segment);
    } else {
        new_prefix_len = 0;
    }
    const new_prefix = new_prefix_buf[0..new_prefix_len];

    var total_items: usize = 0;
    if (node.data == .inline_container_node) {
        total_items += node.data.inline_container_node.line_boxes.items.len;
    }
    const children = self.getChildren(node_id);
    total_items += children.len;

    var item_idx: usize = 0;

    if (node.data == .inline_container_node) {
        const line_boxes = node.data.inline_container_node.line_boxes.items;
        for (line_boxes, 0..) |line_box, i| {
            const last_item = item_idx == total_items - 1;
            try self.printLineBox(&line_box, i, writer, new_prefix, last_item and children.len == 0);
            item_idx += 1;
        }
    }

    for (children) |child| {
        const last_item = item_idx == total_items - 1;
        try self.printNodeInternal(child, writer, new_prefix, false, last_item);
        item_idx += 1;
    }
}

fn printLineBox(_: *Self, line_box: *const LineBox, index: usize, writer: std.io.AnyWriter, prefix: []const u8, is_last: bool) !void {
    try writer.writeAll(prefix);
    if (is_last)
        try writer.writeAll("└── ")
    else
        try writer.writeAll("├── ");

    try writer.print("[line_box #{d} fragments={d}]", .{ index, line_box.fragments.items.len });
    try writer.writeByte('\n');

    var new_prefix_buf: [256]u8 = undefined;
    std.mem.copyForwards(u8, new_prefix_buf[0..prefix.len], prefix);
    const segment = if (is_last) "    " else "│   ";
    std.mem.copyForwards(u8, new_prefix_buf[prefix.len .. prefix.len + segment.len], segment);
    const new_prefix = new_prefix_buf[0 .. prefix.len + segment.len];

    for (line_box.fragments.items, 0..) |fragment, frag_idx| {
        const last_frag = frag_idx == line_box.fragments.items.len - 1;
        try writer.writeAll(new_prefix);
        if (last_frag)
            try writer.writeAll("└── ")
        else
            try writer.writeAll("├── ");
        try writer.print("[fragment node={{#{d}}} range={d}-{d} pos=({:.2}, {:.2}) text=\"{s}\"]", .{ fragment.node, fragment.start, fragment.end, fragment.position.x, fragment.position.y, fragment.text });
        try writer.writeByte('\n');
    }
}

pub fn printNode(self: *Self, node_id: LayoutNode.Id, writer: std.io.AnyWriter) !void {
    try self.printNodeInternal(node_id, writer, "", true, true);
}
pub fn printRoot(self: *Self, writer: std.io.AnyWriter) !void {
    try self.printNode(0, writer);
}

pub fn expectLayoutTree(description: []const u8, docXml: []const u8, expected: []const u8) !void {
    var tree = try docFromXml(std.testing.allocator, docXml, .{});
    defer tree.deinit();

    var lt = try fromTree(std.testing.allocator, &tree);
    defer lt.deinit();

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    const writer = buf.writer().any();
    try lt.printRoot(writer);
    if (std.mem.eql(u8, expected, buf.items)) {
        std.debug.print("\x1b[32m✓\x1b[0m {s}\n", .{description});
    } else {
        std.debug.print("\x1b[31m✗\x1b[0m {s}\n", .{description});
    }

    try std.testing.expectEqualStrings(expected, buf.items);
}
test "LayoutTree" {
    try expectLayoutTree("inline only",
        \\<span>
        \\  <span>
        \\    abc
        \\    def
        \\  </span>
        \\  zzz
        \\</span>
    ,
        \\[inline_container_node #0 ref={doc#0} children={2} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\├── [inline_node #1 ref={doc#1} children={2} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   ├── [text_node #2] "abc"
        \\│   └── [text_node #3] "def"
        \\└── [text_node #4] "zzz"
        \\
    );
}

test "deep formatting context break" {
    // example from https://webkit.org/blog/115/webcore-rendering-ii-blocks-and-inlines/
    // should output this structure
    // <anonymous pre block>
    // <i>Italic only <b>italic and bold</b></i>
    // </anonymous pre block>
    // <anonymous middle block>
    // <div>
    // Wow, a block!
    // </div>
    // <div>
    // Wow, another block!
    // </div>
    // </anonymous middle block>
    // <anonymous post block>
    // <i><b>More italic and bold text</b> More italic text</i>
    // </anonymous post block>
    try expectLayoutTree("deep formatting context break",
        \\<i>
        \\  Italic only
        \\  <b>
        \\  italic and bold
        \\    <div>Wow, a block!</div>
        \\    <div>Wow, another block!</div>
        \\    More italic and bold text
        \\  </b> 
        \\  More italic text
        \\</i>
        \\
    ,
        \\[block_container_node #0 ref={doc#0} children={3} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\├── [inline_container_node #2 ref={anon} children={2} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   ├── [text_node #1] "Italic only"
        \\│   └── [inline_node #3 continuation={#12} ref={doc#2} children={1} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│       └── [text_node #4] "italic and bold"
        \\├── [block_container_node #5 ref={anon} children={2} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   ├── [inline_container_node #6 ref={doc#4} children={1} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   │   └── [text_node #7] "Wow, a block!"
        \\│   └── [inline_container_node #8 ref={doc#6} children={1} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│       └── [text_node #9] "Wow, another block!"
        \\└── [inline_container_node #11 ref={anon} children={2} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\    ├── [inline_node #12 continuationOf={#3} ref={doc#2} children={1} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\    │   └── [text_node #10] "More italic and bold text"
        \\    └── [text_node #13] "More italic text"
        \\
    );

    try expectLayoutTree("deep formatting context break 2",
        \\<i>
        \\  Italic only
        \\  <b>
        \\  italic and bold
        \\    <div>Wow, a block!</div>
        \\    <span>
        \\      <div>Wow, another block!</div>
        \\      More italic and bold text
        \\    </span>
        \\  </b> 
        \\  More italic text
        \\</i>
        \\
    ,
        \\[block_container_node #0 ref={doc#0} children={3} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\├── [inline_container_node #2 ref={anon} children={2} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   ├── [text_node #1] "Italic only"
        \\│   └── [inline_node #3 continuation={#13} ref={doc#2} children={2} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│       ├── [text_node #4] "italic and bold"
        \\│       └── [inline_node #8 continuation={#14} ref={doc#6} children={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\├── [block_container_node #5 ref={anon} children={2} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   ├── [inline_container_node #6 ref={doc#4} children={1} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│   │   └── [text_node #7] "Wow, a block!"
        \\│   └── [inline_container_node #9 ref={doc#7} children={1} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\│       └── [text_node #10] "Wow, another block!"
        \\└── [inline_container_node #12 ref={anon} children={2} lines={0} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\    ├── [inline_node #13 continuationOf={#3} ref={doc#2} children={1} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\    │   └── [inline_node #14 continuationOf={#8} ref={doc#6} children={1} box={[loc: (0.00, 0.00) size: (0.00, 0.00) content: (0.00, 0.00)]}]
        \\    │       └── [text_node #11] "More italic and bold text"
        \\    └── [text_node #15] "More italic text"
        \\
    );
}
