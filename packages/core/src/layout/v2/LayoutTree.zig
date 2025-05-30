const std = @import("std");
const DocNodeId = @import("../../tree/Node.zig").NodeId;
const DocTree = @import("../../tree/Tree.zig");
const Styles = @import("../../tree/Style.zig");
const Array = std.ArrayListUnmanaged;
const HashMap = std.AutoHashMapUnmanaged;
const mod = @import("mod.zig");
const Cache = @import("Cache.zig");

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

pub fn createNodeWithDocTree(self: *Self, data: LayoutNode.Data, ref: DocRef, doc_tree: *DocTree) !LayoutNode.Id {
    const id = self.node_count;
    var node = LayoutNode{ .id = id, .data = data, .ref = ref };

    // Copy styles from doc node if available
    switch (ref) {
        .doc_node => |doc_node_id| {
            node.style = doc_tree.getComputedStyle(doc_node_id);
        },
        .anonymous => {
            // Anonymous nodes will inherit styles from parent later
        },
    }

    try self.nodes.put(self.allocator, id, node);
    self.node_count += 1;
    return id;
}
pub fn createTextNode(self: *Self, contents: []const u8, ref: DocRef) !LayoutNode.Id {
    const node_id = try self.createNode(.{ .text_node = .{} }, ref);
    var node = self.getNodePtr(node_id);
    try node.data.text_node.contents.appendSlice(self.allocator, contents);
    return node_id;
}

pub fn createTextNodeWithDocTree(self: *Self, contents: []const u8, ref: DocRef, doc_tree: *DocTree) !LayoutNode.Id {
    const node_id = try self.createNodeWithDocTree(.{ .text_node = .{} }, ref, doc_tree);
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

    // Handle style inheritance for anonymous nodes
    const child = self.getNodePtr(child_id);
    if (child.ref == .anonymous) {
        self.inheritStyles(child_id, parent_id);
    }
}

// Inherit specific style properties from parent to child
fn inheritStyles(self: *Self, child_id: LayoutNode.Id, parent_id: LayoutNode.Id) void {
    const parent = self.getNodePtr(parent_id);
    const child = self.getNodePtr(child_id);

    // Inherit text formatting properties
    child.style.text_align = parent.style.text_align;
    child.style.white_space_collapse = parent.style.white_space_collapse;
    child.style.text_wrap_mode = parent.style.text_wrap_mode;
    child.style.white_space_trim = parent.style.white_space_trim;
    child.style.tab_size = parent.style.tab_size;

    // Inherit font properties
    child.style.font_weight = parent.style.font_weight;
    child.style.font_style = parent.style.font_style;
    child.style.text_decoration = parent.style.text_decoration;

    // Inherit color
    child.style.foreground_color = parent.style.foreground_color;
}
pub fn setParent(self: *Self, child_id: LayoutNode.Id, parent_id: ?LayoutNode.Id) !void {
    const child = self.getNodePtr(child_id);
    child.parent = parent_id;
}

pub fn getNodePtr(self: *Self, id: LayoutNode.Id) *LayoutNode {
    return self.nodes.getPtr(id) orelse std.debug.panic("LayoutTree: Node {d} not found", .{id});
}

pub inline fn getCache(self: *Self, id: LayoutNode.Id) *Cache {
    return &self.getNodePtr(id).cache;
}

pub const LayoutNode = struct {
    id: Id,
    ref: DocRef,
    parent: ?Id = null,
    data: Data,
    box: mod.Box = .{},
    cache: Cache = .{},
    style: Styles = .{},
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
    line_boxes: mod.LineBox.LineBoxList,
    continuation: ?LayoutNode.Id = null,
    continuationOf: ?LayoutNode.Id = null,
    pub fn deinit(self: *InlineContainerNode, allocator: std.mem.Allocator) void {
        self.children.deinit(allocator);

        self.line_boxes.deinit();
    }
};

pub fn fromTree(allocator: std.mem.Allocator, tree: *DocTree) !Self {
    var self = Self.init(allocator);

    // Create an anonymous viewport node as the actual root
    const viewport_id = try self.createNode(.{ .block_container_node = .{} }, .anonymous);

    // Build the document tree and append it as a child of the viewport
    const doc_root_id = try self.build(tree, DocTree.ROOT_NODE_ID);
    try self.appendNode(viewport_id, doc_root_id);
    
    // Clear all invalidation flags after building
    tree.clearAllInvalidationFlags(DocTree.ROOT_NODE_ID);

    return self;
}

pub fn fromTreeIncremental(allocator: std.mem.Allocator, tree: *DocTree, existing: ?*Self) !Self {
    // If no existing tree or root needs full regeneration, build from scratch
    if (existing == null or tree.getNode(DocTree.ROOT_NODE_ID).needs_regenerate) {
        return fromTree(allocator, tree);
    }
    
    var self = Self.init(allocator);
    
    // Create an anonymous viewport node as the actual root
    const viewport_id = try self.createNode(.{ .block_container_node = .{} }, .anonymous);
    
    // Build incrementally, reusing existing nodes where possible
    const doc_root_id = try self.buildIncremental(tree, DocTree.ROOT_NODE_ID, existing.?);
    try self.appendNode(viewport_id, doc_root_id);
    
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
    doc_node_id: DocNodeId,
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
    pub fn init(allocator: std.mem.Allocator, layout_tree: *Self, doc_tree: *DocTree, root_container_id: LayoutNode.Id, doc_node_id: DocNodeId) !MixedContextBuilder {
        return MixedContextBuilder{
            .allocator = allocator,
            .layout_tree = layout_tree,
            .doc_tree = doc_tree,
            .doc_node_id = doc_node_id,
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
        const id = try self.layout_tree.createNode(.{ .inline_container_node = .{
            .line_boxes = .{
                .allocator = self.allocator,
            },
        } }, .anonymous);
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
                    const clone_inline_container_node_id = try self.layout_tree.createNode(.{ .inline_container_node = .{
                        .line_boxes = .{
                            .allocator = self.allocator,
                        },
                    } }, .anonymous);
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
        const children = self.doc_tree.getNodeChildren(self.doc_node_id);
        for (children) |child| {
            if (isDisplayNone(self.doc_tree, child)) continue;
            try self.buildFromNode(child);
        }
    }
    pub fn buildFromNode(self: *MixedContextBuilder, node_id: DocNodeId) BuildError!void {
        const kind = self.doc_tree.getNodeKind(node_id);
        if (kind == .text) {
            const text = self.doc_tree.getText(node_id).bytes.items;
            const id = try self.layout_tree.createTextNodeWithDocTree(text, .{ .doc_node = node_id }, self.doc_tree);
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
            const id = try self.layout_tree.createNodeWithDocTree(.{ .inline_node = .{} }, .{ .doc_node = node_id }, self.doc_tree);
            try self.appendNode(id);
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
fn findExistingLayoutNode(existing_tree: *Self, doc_node_id: DocNodeId) ?LayoutNode.Id {
    // Search through existing tree for a node with matching doc reference
    var it = existing_tree.nodes.iterator();
    while (it.next()) |entry| {
        const node = entry.value_ptr;
        switch (node.ref) {
            .doc_node => |id| {
                if (id == doc_node_id) return node.id;
            },
            .anonymous => {},
        }
    }
    return null;
}

fn buildIncremental(self: *Self, tree: *DocTree, node_id: DocNodeId, existing: *Self) BuildError!LayoutNode.Id {
    const doc_node = tree.getNode(node_id);
    
    // If this node needs regeneration, build fresh subtree and clear flags
    if (doc_node.needs_regenerate) {
        const result = try self.build(tree, node_id);
        // Clear all flags since we rebuilt the entire subtree
        tree.clearInvalidationFlags(node_id);
        return result;
    }
    
    // If no invalidation flags are set, we can potentially reuse the entire subtree
    if (!doc_node.needs_recompute and !doc_node.needs_repaint) {
        // Try to find and reuse existing layout subtree
        if (findExistingLayoutNode(existing, node_id)) |existing_layout_id| {
            return self.cloneSubtree(existing, existing_layout_id, tree);
        }
    }
    
    // Try to find existing layout node for partial reuse
    if (findExistingLayoutNode(existing, node_id)) |existing_layout_id| {
        const existing_node = existing.getNodePtr(existing_layout_id);
        
        // Clone the existing node structure
        const new_id = try self.cloneNode(existing_node, tree);
        
        // If needs recompute, clear the cache
        if (doc_node.needs_recompute) {
            const new_node = self.getNodePtr(new_id);
            new_node.cache.clear();
        }
        
        // Clear the flags we've processed
        doc_node.needs_recompute = false;
        doc_node.needs_repaint = false;
        
        // Process children incrementally
        switch (existing_node.data) {
            .inline_node => |*n| {
                for (n.children.items) |child_id| {
                    const child_node = existing.getNodePtr(child_id);
                    if (child_node.ref == .doc_node) {
                        const child_doc_id = child_node.ref.doc_node;
                        const new_child_id = try self.buildIncremental(tree, child_doc_id, existing);
                        try self.appendNode(new_id, new_child_id);
                    }
                }
            },
            .block_container_node => |*n| {
                for (n.children.items) |child_id| {
                    const child_node = existing.getNodePtr(child_id);
                    if (child_node.ref == .doc_node) {
                        const child_doc_id = child_node.ref.doc_node;
                        const new_child_id = try self.buildIncremental(tree, child_doc_id, existing);
                        try self.appendNode(new_id, new_child_id);
                    }
                }
            },
            .inline_container_node => |*n| {
                for (n.children.items) |child_id| {
                    const child_node = existing.getNodePtr(child_id);
                    if (child_node.ref == .doc_node) {
                        const child_doc_id = child_node.ref.doc_node;
                        const new_child_id = try self.buildIncremental(tree, child_doc_id, existing);
                        try self.appendNode(new_id, new_child_id);
                    }
                }
            },
            .text_node => {
                // Text nodes are leaf nodes, no children to process
            },
        }
        
        return new_id;
    }
    
    // No existing node found, build fresh and clear flags
    const result = try self.build(tree, node_id);
    tree.clearInvalidationFlags(node_id);
    return result;
}

fn cloneSubtree(self: *Self, existing_tree: *Self, existing_id: LayoutNode.Id, tree: *DocTree) !LayoutNode.Id {
    const existing_node = existing_tree.getNodePtr(existing_id);
    
    // Clone the node
    const new_id = try self.cloneNode(existing_node, tree);
    
    // Clone all children recursively
    switch (existing_node.data) {
        .inline_node => |*n| {
            for (n.children.items) |child_id| {
                const new_child_id = try self.cloneSubtree(existing_tree, child_id, tree);
                try self.appendNode(new_id, new_child_id);
            }
        },
        .block_container_node => |*n| {
            for (n.children.items) |child_id| {
                const new_child_id = try self.cloneSubtree(existing_tree, child_id, tree);
                try self.appendNode(new_id, new_child_id);
            }
        },
        .inline_container_node => |*n| {
            for (n.children.items) |child_id| {
                const new_child_id = try self.cloneSubtree(existing_tree, child_id, tree);
                try self.appendNode(new_id, new_child_id);
            }
        },
        .text_node => {
            // Text nodes have no children
        },
    }
    
    return new_id;
}

fn cloneNode(self: *Self, existing: *LayoutNode, tree: *DocTree) !LayoutNode.Id {
    // Create a new node with the same data structure
    const new_id = self.node_count;
    var new_node = LayoutNode{
        .id = new_id,
        .data = undefined,
        .ref = existing.ref,
        .parent = null,
        .style = existing.style,
        .cache = .{},
    };
    
    // Clone the data based on type
    switch (existing.data) {
        .text_node => |*tn| {
            new_node.data = .{ .text_node = .{} };
            // For text nodes, get fresh text from the DOM tree
            switch (existing.ref) {
                .doc_node => |doc_id| {
                    const text = tree.getText(doc_id).bytes.items;
                    try new_node.data.text_node.contents.appendSlice(self.allocator, text);
                },
                .anonymous => {
                    // Anonymous text nodes shouldn't exist, but if they do, copy existing
                    try new_node.data.text_node.contents.appendSlice(self.allocator, tn.contents.items);
                },
            }
        },
        .inline_node => {
            new_node.data = .{ .inline_node = .{} };
        },
        .block_container_node => {
            new_node.data = .{ .block_container_node = .{} };
        },
        .inline_container_node => {
            new_node.data = .{ .inline_container_node = .{
                .line_boxes = .{ .allocator = self.allocator },
            } };
        },
    }
    
    // Update style from doc tree if this is a doc node
    switch (existing.ref) {
        .doc_node => |doc_id| {
            new_node.style = tree.getComputedStyle(doc_id);
        },
        .anonymous => {},
    }
    
    try self.nodes.put(self.allocator, new_id, new_node);
    self.node_count += 1;
    return new_id;
}

/// Returns the id of the created layout node or `null` if the DOM node should
/// not produce a layout representation.
fn build(self: *Self, tree: *DocTree, node_id: DocNodeId) BuildError!LayoutNode.Id {
    const kind = tree.getNodeKind(node_id);

    // 1. Text DOM nodes map directly to layout text nodes.
    if (kind == .text) {
        const text = tree.getText(node_id).bytes.items;
        const id = try self.createTextNodeWithDocTree(text, .{ .doc_node = node_id }, tree);
        return id;
    }
    const style = tree.getStyle(node_id);
    if (style.display.inside != .flow) {
        return self.buildInsideBlock(tree, node_id);
    }

    // 2. Atomic inline elements produce an `InlineNode`, right now we dont have other types of atomic inline elements besides inline-block or inline-flex
    if (isInlineFlow(tree, node_id)) {
        const id = try self.createNodeWithDocTree(.{ .inline_node = .{} }, .{ .doc_node = node_id }, tree);
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
        const inline_container_id = try self.createNodeWithDocTree(.{ .inline_container_node = .{
            .line_boxes = .{
                .allocator = self.allocator,
            },
        } }, .{ .doc_node = node_id }, tree);
        for (children) |child| {
            if (isDisplayNone(tree, child)) continue;
            const child_layout_node_id = try self.build(tree, child);
            try self.appendNode(inline_container_id, child_layout_node_id);
        }
        return inline_container_id;
    }

    const container_id = try self.createNodeWithDocTree(.{ .block_container_node = .{} }, .{ .doc_node = node_id }, tree);
    var mixed_context_builder = try MixedContextBuilder.init(self.allocator, self, tree, container_id, node_id);
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
            try writer.print("[{s} #{d}] \"", .{ @tagName(node.data), node.id });
            for (text.contents.items) |c| {
                switch (c) {
                    '\n' => try writer.writeAll("\\n"),
                    '\t' => try writer.writeAll("\\t"),
                    '\r' => try writer.writeAll("\\r"),
                    else => try writer.writeByte(c),
                }
            }

            try writer.print("\"", .{});
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
            try writer.print(" children={{{d}}} lines={{{d}}} box={{{any}}}]", .{ container.children.items.len, container.line_boxes.len(), node.box });
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
        total_items += node.data.inline_container_node.line_boxes.len();
    }
    const children = self.getChildren(node_id);
    total_items += children.len;

    var item_idx: usize = 0;

    if (node.data == .inline_container_node) {
        const line_boxes = node.data.inline_container_node.line_boxes.items();
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

fn printLineBox(_: *Self, line_box: *const mod.LineBox, index: usize, writer: std.io.AnyWriter, prefix: []const u8, is_last: bool) !void {
    try writer.writeAll(prefix);
    if (is_last)
        try writer.writeAll("└── ")
    else
        try writer.writeAll("├── ");

    try writer.print("[line_box #{d} fragments={d} size={{{any}}}]", .{ index, line_box.fragments.items.len, line_box.size });

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
        try writer.print("[fragment node={{#{d}}} range={d}-{d} pos={{{any}}} size={{{any}}} text=\"", .{ fragment.l_node_id, fragment.start, fragment.start + fragment.length, fragment.position, fragment.size });
        for (fragment.text) |c| {
            switch (c) {
                '\n' => try writer.writeAll("\\n"),
                '\t' => try writer.writeAll("\\t"),
                '\r' => try writer.writeAll("\\r"),
                else => try writer.writeByte(c),
            }
        }
        try writer.print("\"]\n", .{});
    }
}

pub fn printNode(self: *Self, node_id: LayoutNode.Id, writer: std.io.AnyWriter) !void {
    try self.printNodeInternal(node_id, writer, "", true, true);
}
pub fn printRoot(self: *Self, writer: std.io.AnyWriter) !void {
    try self.printNode(0, writer);
}

pub fn expectLayoutTree(description: []const u8, docXml: []const u8, comptime loc: std.builtin.SourceLocation) !void {
    const snapshot = @import("../../testing/snapshot.zig");

    var tree = try docFromXml(std.testing.allocator, docXml, .{});
    defer tree.deinit();

    var lt = try fromTree(std.testing.allocator, &tree);
    defer lt.deinit();

    var buf = std.ArrayList(u8).init(std.testing.allocator);
    defer buf.deinit();
    const writer = buf.writer().any();
    try writer.print("DocTree:\n", .{});
    try tree.print(writer);
    try writer.print("LayoutTree:\n", .{});

    try lt.printRoot(writer);

    try snapshot.expectMatchSnapshot(loc, std.testing.allocator, description, buf.items);
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
    , @src());
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
    , @src());

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
    , @src());
}

test "inline and block mixing" {
    try expectLayoutTree("inline and block mixing",
        \\<root style="width: 40px; height: 15px; background-color: #f9fafb;">
        \\  <div style="background-color: #e5e7eb;">Block 1</div>
        \\  <span style="color: #dc2626;">Inline text</span>
        \\  <span style="color: #059669;"> with more text</span>
        \\  <div style="background-color: #d1d5db;">Block 2</div>
        \\</root>
    , @src());
}
