pub const Node = @import("Node.zig");
const Point = @import("../layout/point.zig").Point;
const std = @import("std");
const xml = @import("../xml.zig");
pub const Style = @import("Style.zig");
const Color = @import("../colors/Color.zig");
const HashMap = std.AutoHashMap;
const Layout = @import("Layout.zig");
const Cache = @import("Cache.zig");
const ComputedText = @import("../layout/compute/text/ComputedText.zig");
const Rect = @import("../layout/rect.zig").Rect;
pub const AvailableSpace = @import("../layout/compute/compute_constants.zig").AvailableSpace;
const s = @import("../styles/styles.zig");
const ComputedStyleCache = s.computed_style.ComputedStyleCache;
const StyleError = s.computed_style.StyleError;
const StyleManager = s.style_manager.StyleManager;
const InputManager = @import("../cmd/input/manager.zig").AnyInputManager;
const Event = @import("../cmd/input/manager.zig").Event;
const String = @import("String.zig");
const Range = @import("Range.zig");
pub const BoundaryPoint = @import("BoundaryPoint.zig");
const NodeIterator = @import("NodeIterator.zig");
pub const Selection = @import("Selection.zig");
const traversal = @import("./traversal.zig");
const Canvas = @import("../renderer/Canvas.zig");
const GraphemeIterator = @import("../uni/GraphemeBreak.zig").Iterator;
const visible = @import("../uni/string-width.zig").visible;

node_map: std.AutoHashMapUnmanaged(Node.NodeId, Node) = .{},
allocator: std.mem.Allocator,
style_manager: StyleManager,
computed_style_cache: ComputedStyleCache,
input_manager: ?InputManager = null,
node_id_counter: Node.NodeId = 0,
selections: std.AutoHashMapUnmanaged(Node.NodeId, Selection) = .{},

live_ranges: std.AutoHashMapUnmanaged(u32, Range) = .{},
live_range_counter: u32 = 0,

const Self = @This();

usingnamespace @import("../layout/compute/compute_layout.zig");
pub const ROOT_NODE_ID: Node.NodeId = 0;
pub fn init(allocator: std.mem.Allocator) !Self {
    // Initialize style system and tree together
    return Self{
        .allocator = allocator,
        .style_manager = try StyleManager.init(allocator),
        .computed_style_cache = try ComputedStyleCache.init(allocator),
        // .selection = .{
        //     .allocator = allocator,
        // },
    };
}
pub fn getFirstSelectionId(self: *Self) ?Selection.Id {
    var it = self.selections.valueIterator();
    return if (it.next()) |selection| selection.range_id else null;
}
pub fn getFirstSelection(self: *Self) ?*Selection {
    var it = self.selections.valueIterator();
    return if (it.next()) |selection| selection else null;
}
pub fn getSelection(self: *Self, selection_id: Selection.Id) *Selection {
    return self.selections.getPtr(selection_id) orelse std.debug.panic("Selection {d} not found\n", .{selection_id});
}
pub fn getRange(self: *Self, range_id: Range.Id) *Range {
    return self.live_ranges.getPtr(range_id);
}

pub fn createSelection(self: *Self, start: BoundaryPoint, end: ?BoundaryPoint) !Selection.Id {
    const selection_id = try self.createLiveRange(.{
        .node_id = start.node_id,
        .offset = start.offset,
    }, .{
        .node_id = start.node_id,
        .offset = start.offset,
    });
    // if (end) |ennode_idd_point| {

    try self.selections.put(self.allocator, selection_id, Selection{
        .range_id = selection_id,
        .direction = .none,
    });

    try self.selections.getPtr(selection_id).?.setRange(self, start, end orelse start);
    // } else
    return selection_id;
}
pub fn removeSelection(self: *Self, selection_id: Selection.Id) void {
    _ = self.selections.remove(selection_id);
    _ = self.live_ranges.remove(selection_id);
}
pub fn createNodeIterator(self: *Self, root: Node.NodeId) NodeIterator {
    return NodeIterator{
        .reference_node = root,

        .tree = self,
    };
}
pub fn enableInputManager(self: *Self) !void {
    self.input_manager = .{
        .allocator = self.allocator,
    };
    try self.input_manager.?.subscribe(.{
        .context = @ptrCast(self),
        .emitFn = emitEventFn,
    });
}
pub fn disableInputManager(self: *Self) void {
    if (self.input_manager) |*manager| {
        manager.unsubscribe(@ptrCast(self));
    }
}
pub fn createLiveRange(self: *Self, start: BoundaryPoint, end: BoundaryPoint) !Range.Id {
    const id = self.live_range_counter;
    self.live_range_counter += 1;
    try self.live_ranges.put(
        self.allocator,
        id,
        try Range.init(self, id, start, end),
    );
    return id;
}
pub fn iterLiveRanges(self: *Self) std.AutoHashMapUnmanaged(Range.Id, Range).ValueIterator {
    return self.live_ranges.valueIterator();
}
pub fn getLiveRange(self: *Self, id: Range.Id) *Range {
    return self.live_ranges.getPtr(id) orelse std.debug.panic("Range {d} not found\n", .{id});
}
fn emitEventFn(context: *anyopaque, event: Event) void {
    _ = event; // autofix
    _ = context; // autofix
}
pub inline fn getNode(self: *Self, id: Node.NodeId) *Node {
    return self.node_map.getPtr(id) orelse std.debug.panic("Node {d} not found\n", .{id});
}
pub fn getNodeKind(self: *Self, id: Node.NodeId) Node.NodeKind {
    return self.getNode(id).kind;
}
pub inline fn getChildren(self: *Self, id: Node.NodeId) std.ArrayListUnmanaged(Node.NodeId) {
    return self.getNode(id).children;
}
pub inline fn isEmpty(self: *Self, id: Node.NodeId) bool {
    if (self.getNodeKind(id) == .text) {
        return self.getText(id).items.len == 0;
    }
    return self.getChildren(id).items.len == 0;
}
pub inline fn getStyle(self: *Self, id: Node.NodeId) *Style {
    return &self.getNode(id).styles;
}
pub inline fn getText(self: *Self, id: Node.NodeId) *String {
    return &self.getNode(id).text;
}
pub inline fn getParent(self: *Self, id: Node.NodeId) ?Node.NodeId {
    return self.getNode(id).parent;
}
pub inline fn getUnroundedLayout(self: *Self, id: Node.NodeId) *Layout {
    return &self.getNode(id).unrounded_layout;
}
pub inline fn getLayout(self: *Self, id: Node.NodeId) *Layout {
    return &self.getNode(id).layout;
}
pub inline fn getCache(self: *Self, id: Node.NodeId) *Cache {
    return &self.getNode(id).cache;
}
pub inline fn getComputedText(self: *Self, id: Node.NodeId) ?*ComputedText {
    if (self.getNode(id).computed_text) |*computed_text| {
        return computed_text;
    }
    return null;
}
pub fn unsafeGetComputedText(self: *Self, id: Node.NodeId) *ComputedText {
    return &(self.getNode(id).computed_text orelse std.debug.panic("No computed text for node {d}\n", .{id}));
}
pub inline fn getTextRootId(self: *Self, id: Node.NodeId) ?Node.NodeId {
    return self.getNode(id).text_root_id;
}
pub inline fn setTextRootId(self: *Self, id: Node.NodeId, text_root_id: ?Node.NodeId) void {
    self.getNode(id).text_root_id = text_root_id;
}

// node setters
pub fn setNodeKind(self: *Self, id: Node.NodeId, kind: Node.NodeKind) !void {
    self.getNode(id).kind = kind;
}
pub fn setChildren(self: *Self, id: Node.NodeId, children: []Node.NodeId) !void {
    const list = self.getNode(id).children;
    list.clearAndFree();
    try list.appendSlice(self.allocator, children);
}
pub fn setStyle(self: *Self, id: Node.NodeId, style: Style) void {
    self.getNode(id).styles = style;

    // Mark node dirty for layout
    self.markDirty(id);

    // Invalidate computed styles for this node and descendants
    self.invalidateStyles(id);
}
pub fn setText(self: *Self, id: Node.NodeId, text: []const u8) !void {
    var node = self.getNode(id);

    try node.text.replace(self.allocator, 0, node.text.length(), text);
    var dirty_node = id;
    while (self.getStyle(dirty_node).display.isInlineFlow() == false) {
        self.markDirty(dirty_node);
        dirty_node = self.getParent(dirty_node) orelse break;
    }
    self.markDirty(dirty_node);
}

pub fn setParent(self: *Self, id: Node.NodeId, parent: ?Node.NodeId) !void {
    var node = self.getNode(id);
    if (node.parent == parent) {
        return;
    }

    if (node.parent) |current_parent_id| {
        try self.removeChild(current_parent_id, id);
    }
    node.parent = parent;
}
pub fn removeNode(self: *Self, id: Node.NodeId) !void {
    const parent_id = self.getNode(id).parent orelse return;
    try self.removeChild(parent_id, id);
}
pub fn setUnroundedLayout(self: *Self, id: Node.NodeId, unrounded_layout: Layout) void {
    self.getNode(id).unrounded_layout = unrounded_layout;
}
pub fn setLayout(self: *Self, id: Node.NodeId, layout: Layout) void {
    self.getNode(id).layout = layout;
}
pub fn setCache(self: *Self, id: Node.NodeId, cache: Cache) void {
    self.getNode(id).cache = cache;
}
pub fn setComputedText(self: *Self, id: Node.NodeId, computed_text: ?ComputedText) void {
    if (self.getNode(id).computed_text) |*old_computed_text| {
        old_computed_text.deinit();
    }
    self.getNode(id).computed_text = computed_text;
}

pub inline fn createComputedText(self: *Self) !ComputedText {
    // const computed_text_list = self.getComputedTextList();
    // computed_text_list[node_id] = try ComputedText.init(self.allocator);
    return try ComputedText.init(self.allocator);
}
// fn isDirectChildOf(self: *Self, node_id: Node.NodeId, parent_id: Node.NodeId) bool {
//     const children = self.getChildren(parent_id);
//     for (children.items) |child| {
//         if (child == node_id) {
//             return true;
//         }
//     }
//     return false;

// }

pub fn markDirty(self: *Self, id: Node.NodeId) void {
    const cache = self.getCache(id);
    const text_root_id = self.getTextRootId(id);
    if (cache.isEmpty() and text_root_id == null) {
        return;
    }

    // Clear layout cache
    cache.clear();
    self.setTextRootId(id, null);
    // if (self.getComputedText(id)) |computed_text| {

    // }
    self.setComputedText(id, null);

    // Also invalidate computed style for this specific node
    // We only invalidate this node, not descendants, since layout changes
    // don't necessarily affect cascaded styles of children
    self.computed_style_cache.invalidateNode(id);

    // Propagate to parent
    if (self.getParent(id)) |parent_id| {
        self.markDirty(parent_id);
    }
}

pub fn destroyNode(self: *Self, id: Node.NodeId) !void {
    const node = self.getNode(id);
    for (node.children.items) |child_id| {
        var child = self.getNode(child_id);
        child.parent = null;
    }
    try self.setParent(id, null);

    node.deinit(self.allocator);
    _ = self.node_map.remove(id);
}
pub fn destroyNodeRecursive(self: *Self, id: Node.NodeId) !void {
    try self.setParent(id, null);
    try self.destroyNodeRecursiveInner(id);
}
fn destroyNodeRecursiveInner(self: *Self, id: Node.NodeId) !void {
    const node = self.getNode(id);
    for (node.children.items) |child_id| {
        try self.destroyNodeRecursiveInner(child_id);
    }
    node.deinit(self.allocator);
    _ = self.node_map.remove(id);
}
// node creation
pub fn createNode(self: *Self) !Node.NodeId {
    const id = self.node_id_counter;
    self.node_id_counter += 1;

    try self.node_map.put(self.allocator, id, .{
        .id = id,
        .styles = .{},
    });

    return id;
}
pub fn validateTree(self: *Self, node_id: Node.NodeId, expected_parent: ?Node.NodeId) void {
    const node = self.getNode(node_id);
    if (node.kind == .text) {
        return;
    }
    if (node.parent != expected_parent) {
        std.debug.panic("Node {d} has parent {?d} but expected {?d}\n", .{ node_id, node.parent, expected_parent });
    }
    const children = node.children;
    for (children.items) |child_id| {
        self.validateTree(child_id, node_id);
    }
}

pub fn createTextNode(self: *Self, text: []const u8) !Node.NodeId {
    const id = self.node_id_counter;
    self.node_id_counter += 1;
    try self.node_map.put(self.allocator, id, .{
        .id = id,
        .kind = .text,
        .styles = .{
            .display = .{ .inside = .flow, .outside = .@"inline" },
        },
    });
    try self.setText(id, text);

    return id;
}
fn maybeRemoveNode(self: *Self, node_id: Node.NodeId) !void {
    if (self.getParent(node_id)) |parent_id| {
        try self.removeChild(parent_id, node_id);
    }
}
pub fn appendChildAtIndex(self: *Self, parent_id: Node.NodeId, child_id: Node.NodeId, index: usize) !Node.NodeId {
    const siblings = self.getNode(parent_id).children;
    const node_at_index = if (index >= siblings.items.len) null else siblings.items[index];

    return try self.insertBefore(parent_id, child_id, node_at_index);
}

pub fn appendChild(self: *Self, parent_id: Node.NodeId, child_id: Node.NodeId) !Node.NodeId {
    // self.setParent(child_id, parent_id);
    // var parent = self.getNode(parent_id);
    // try parent.children.append(self.allocator, child_id);
    // self.markDirty(parent_id);
    return try self.preInsert(parent_id, child_id, null);
}
// Helper function to implement ensure pre-insert validity
fn ensurePreInsertValidity(self: *Self, node: Node.NodeId, parent: Node.NodeId, child: ?Node.NodeId) !void {
    const parent_node = self.getNode(parent);
    const node_kind = self.getNode(node).kind;

    // 1. If parent is not a Document, DocumentFragment, or Element node, throw "HierarchyRequestError"
    if (parent_node.kind != .node) {
        std.debug.print("Parent {?d} is not a Document, DocumentFragment, or Element node\n", .{parent});
        // Adjust as needed if you add document or document fragment support
        return error.HierarchyRequestError;
    }

    // 2. If node is a host-including inclusive ancestor of parent, throw "HierarchyRequestError"
    if (self.isNodeAncestor(node, parent)) {
        return error.HierarchyRequestError;
    }

    // 3. If child is non-null and its parent is not parent, throw "NotFoundError"
    if (child != null and self.getParent(child.?) != parent) {
        return error.NotFoundError;
    }

    // 4. If node is not a DocumentFragment, DocumentType, Element, or CharacterData node, throw "HierarchyRequestError"
    if (node_kind != .node and node_kind != .text) {
        // Adjust as needed when you add document fragment support
        return error.HierarchyRequestError;
    }

    // The remaining checks (5 and 6) are primarily concerned with Document nodes
    // Since you don't have Document nodes, they can be omitted
}
pub fn preInsert(self: *Self, parent: Node.NodeId, node: Node.NodeId, child: ?Node.NodeId) !Node.NodeId {
    // 1. Ensure pre-insert validity of node into parent before child.
    try ensurePreInsertValidity(self, node, parent, child);

    // 2. Let referenceChild be child.
    var reference_child = child;

    // 3. If referenceChild is node, then set referenceChild to node's next sibling.
    if (reference_child == node) {
        reference_child = self.nextSibling(node);
    }

    // 4. Insert node into parent before referenceChild.
    try self.insertBeforeChecked(node, parent, reference_child);

    // 5. Return node.
    return node;
}

fn insertBeforeChecked(self: *Self, node_id: Node.NodeId, parent: Node.NodeId, child: ?Node.NodeId) !void {
    // 1.  Let nodes be node’s [children](#concept-tree-child), if node is a `[DocumentFragment](#documentfragment)` [node](#concept-node); otherwise « node ».
    // FIXME: add support for DocumentFragment once we have it
    const nodes = &[_]Node.NodeId{node_id};

    // 2.  Let count be nodes’s [size](https://infra.spec.whatwg.org/#list-size).
    const count = nodes.len;

    // 3.  If count is 0, then return.
    if (count == 0) {
        return;
    }

    // 4.  If node is a `[DocumentFragment](#documentfragment)` [node](#concept-node):

    //     1.  [Remove](#concept-node-remove) its [children](#concept-tree-child) with the _suppress observers flag_ set.

    //     2.  [Queue a tree mutation record](#queue-a-tree-mutation-record) for node with « », nodes, null, and null.

    //         This step intentionally does not pay attention to the _suppress observers flag_.

    // 5.  If child is non-null:
    if (child) |child_id| {

        //     1.  For each [live range](#concept-live-range) whose [start node](#concept-range-start-node) is parent and [start offset](#concept-range-start-offset) is greater than child’s [index](#concept-tree-index), increase its [start offset](#concept-range-start-offset) by count.
        {
            var it = self.iterLiveRanges();
            while (it.next()) |live_range| {
                if (live_range.start.node_id == parent and live_range.start.offset > child_id) {
                    live_range.start.offset += count;
                }
            }
        }

        //     2.  For each [live range](#concept-live-range) whose [end node](#concept-range-end-node) is parent and [end offset](#concept-range-end-offset) is greater than child’s [index](#concept-tree-index), increase its [end offset](#concept-range-end-offset) by count.
        {
            var it = self.iterLiveRanges();
            while (it.next()) |live_range| {
                if (live_range.end.node_id == parent and live_range.end.offset > child_id) {
                    live_range.end.offset += count;
                }
            }
        }
    }

    // 6.  Let previousSibling be child’s [previous sibling](#concept-tree-previous-sibling) or parent’s [last child](#concept-tree-last-child) if child is null.
    // const previous_sibling = if (child) |child_id| self.previousSibling(child_id) else self.lastChild(parent);

    // 7.  For each node in nodes, in [tree order](#concept-tree-order):
    for (nodes) |node| {

        //     1.  [Adopt](#concept-node-adopt) node into parent’s [node document](#concept-node-document).

        //     2.  If child is null, then [append](https://infra.spec.whatwg.org/#set-append) node to parent’s [children](#concept-tree-child).
        if (child) |child_id| {
            // 3.  Otherwise, [insert](https://infra.spec.whatwg.org/#list-insert) node into parent’s [children](#concept-tree-child) before child’s [index](#concept-tree-index).
            // To insert an item into a list before an index is to add the given item to the list between the given index − 1 and the given index. If the given index is 0, then prepend the given item to the list.
            // var siblings = self.getNode(parent).children;
            var parent_node = self.getNode(parent);
            const index = std.mem.indexOfScalar(Node.NodeId, parent_node.children.items, child_id);
            if (index) |i| {
                try self.maybeRemoveNode(node);
                try parent_node.children.insert(self.allocator, i, node);
            } else {
                try self.maybeRemoveNode(node);
                try parent_node.children.append(self.allocator, node);
            }
            var node_node = self.getNode(node);
            node_node.parent = parent;
        } else {
            try self.maybeRemoveNode(node);
            var parent_node = self.getNode(parent);
            try parent_node.children.append(self.allocator, node);
            var node_node = self.getNode(node);
            node_node.parent = parent;
        }

        //     4.  If parent is a [shadow host](#element-shadow-host) whose [shadow root](#concept-shadow-root)’s [slot assignment](#shadowroot-slot-assignment) is "`named`" and node is a [slottable](#concept-slotable), then [assign a slot](#assign-a-slot) for node.

        //     5.  If parent’s [root](#concept-tree-root) is a [shadow root](#concept-shadow-root), and parent is a [slot](#concept-slot) whose [assigned nodes](#slot-assigned-nodes) is the empty list, then run [signal a slot change](#signal-a-slot-change) for parent.

        //     6.  Run [assign slottables for a tree](#assign-slotables-for-a-tree) with node’s [root](#concept-tree-root).

        //     7.  For each [shadow-including inclusive descendant](#concept-shadow-including-inclusive-descendant) inclusiveDescendant of node, in [shadow-including tree order](#concept-shadow-including-tree-order):

        //         1.  Run the [insertion steps](#concept-node-insert-ext) with inclusiveDescendant.

        //         2.  If inclusiveDescendant is not [connected](#connected), then [continue](https://infra.spec.whatwg.org/#iteration-continue).

        //         3.  If inclusiveDescendant is an [element](#concept-element):

        //             1.  If inclusiveDescendant’s [custom element registry](#element-custom-element-registry) is null, then set inclusiveDescendant’s [custom element registry](#element-custom-element-registry) to the result of [looking up a custom element registry](https://html.spec.whatwg.org/multipage/custom-elements.html#look-up-a-custom-element-registry) given inclusiveDescendant’s [parent](#concept-tree-parent).

        //             2.  Otherwise, if inclusiveDescendant’s [custom element registry](#element-custom-element-registry)’s [is scoped](https://html.spec.whatwg.org/multipage/custom-elements.html#is-scoped) is true, [append](https://infra.spec.whatwg.org/#set-append) inclusiveDescendant’s [node document](#concept-node-document) to inclusiveDescendant’s [custom element registry](#element-custom-element-registry)’s [scoped document set](https://html.spec.whatwg.org/multipage/custom-elements.html#scoped-document-set).

        //             3.  If inclusiveDescendant is [custom](#concept-element-custom), then [enqueue a custom element callback reaction](https://html.spec.whatwg.org/multipage/custom-elements.html#enqueue-a-custom-element-callback-reaction) with inclusiveDescendant, callback name "`connectedCallback`", and « ».

        //             4.  Otherwise, [try to upgrade](https://html.spec.whatwg.org/multipage/custom-elements.html#concept-try-upgrade) inclusiveDescendant.

        //                 If this successfully upgrades inclusiveDescendant, its `connectedCallback` will be enqueued automatically during the [upgrade an element](https://html.spec.whatwg.org/multipage/custom-elements.html#concept-upgrade-an-element) algorithm.

        //         4.  Otherwise, if inclusiveDescendant is a [shadow root](#concept-shadow-root):

        //             1.  If inclusiveDescendant’s [custom element registry](#shadowroot-custom-element-registry) is null and inclusiveDescendant’s [keep custom element registry null](#shadowroot-keep-custom-element-registry-null) is false, then set inclusiveDescendant’s [custom element registry](#shadowroot-custom-element-registry) to the result of [looking up a custom element registry](https://html.spec.whatwg.org/multipage/custom-elements.html#look-up-a-custom-element-registry) given inclusiveDescendant’s [host](#concept-documentfragment-host).

        //             2.  Otherwise, if inclusiveDescendant’s [custom element registry](#shadowroot-custom-element-registry) is non-null and inclusiveDescendant’s [custom element registry](#shadowroot-custom-element-registry)’s [is scoped](https://html.spec.whatwg.org/multipage/custom-elements.html#is-scoped) is true, [append](https://infra.spec.whatwg.org/#set-append) inclusiveDescendant’s [node document](#concept-node-document) to inclusiveDescendant’s [custom element registry](#shadowroot-custom-element-registry)’s [scoped document set](https://html.spec.whatwg.org/multipage/custom-elements.html#scoped-document-set).
    }
    // 8.  If _suppress observers flag_ is unset, then [queue a tree mutation record](#queue-a-tree-mutation-record) for parent with nodes, « », previousSibling, and child.

    // 9.  Run the [children changed steps](#concept-node-children-changed-ext) for parent.

    // 10.  Let staticNodeList be a [list](https://infra.spec.whatwg.org/#list) of [nodes](#concept-node), initially « ».

    //     We collect all [nodes](#concept-node) _before_ calling the [post-connection steps](#concept-node-post-connection-ext) on any one of them, instead of calling the [post-connection steps](#concept-node-post-connection-ext) _while_ we’re traversing the [node tree](#concept-node-tree). This is because the [post-connection steps](#concept-node-post-connection-ext) can modify the tree’s structure, making live traversal unsafe, possibly leading to the [post-connection steps](#concept-node-post-connection-ext) being called multiple times on the same [node](#boundary-point-node).

    // 11.  For each node of nodes, in [tree order](#concept-tree-order):

    //     1.  For each [shadow-including inclusive descendant](#concept-shadow-including-inclusive-descendant) inclusiveDescendant of node, in [shadow-including tree order](#concept-shadow-including-tree-order), [append](https://infra.spec.whatwg.org/#list-append) inclusiveDescendant to staticNodeList.

    // 12.  [For each](https://infra.spec.whatwg.org/#list-iterate) node of staticNodeList, if node is [connected](#connected), then run the [post-connection steps](#concept-node-post-connection-ext) with node.
}

fn liveRangePreRemoveSteps(self: *Self, node_id: Node.NodeId) !void {
    // 1.  Let parent be node’s [parent](#concept-tree-parent).
    const parent = self.getNode(node_id).parent orelse unreachable;

    // 2.  [Assert](https://infra.spec.whatwg.org/#assert): parent is not null.

    // 3.  Let index be node’s [index](#concept-tree-index).
    const index: u32 = @intCast(self.nodeIndex(node_id) orelse unreachable);

    var it = self.iterLiveRanges();
    while (it.next()) |live_range| {
        // 4.  For each [live range](#concept-live-range) whose [start node](#concept-range-start-node) is an [inclusive descendant](#concept-tree-inclusive-descendant) of node, set its [start](#concept-range-start) to (parent, index).
        if (live_range.start.node_id == node_id) {
            live_range.start = .{ .node_id = parent, .offset = index };
        }

        // 5.  For each [live range](#concept-live-range) whose [end node](#concept-range-end-node) is an [inclusive descendant](#concept-tree-inclusive-descendant) of node, set its [end](#concept-range-end) to (parent, index).
        if (live_range.end.node_id == node_id) {
            live_range.end = .{ .node_id = parent, .offset = index };
        }

        // 6.  For each [live range](#concept-live-range) whose [start node](#concept-range-start-node) is parent and [start offset](#concept-range-start-offset) is greater than index, decrease its [start offset](#concept-range-start-offset) by 1.
        if (live_range.start.node_id == parent and live_range.start.offset > index) {
            live_range.start.offset -= 1;
        }

        // 7.  For each [live range](#concept-live-range) whose [end node](#concept-range-end-node) is parent and [end offset](#concept-range-end-offset) is greater than index, decrease its [end offset](#concept-range-end-offset) by 1.
        if (live_range.end.node_id == parent and live_range.end.offset > index) {
            live_range.end.offset -= 1;
        }
    }
}
const RemoveError = error{NotFound};
pub fn preRemove(self: *Self, parent_id: Node.NodeId, node_id: Node.NodeId) !void {
    // To pre-remove a child from a parent, run these steps:
    if (self.getNode(node_id).parent != parent_id) {
        return error.NotFound;
    }
    // If child’s parent is not parent, then throw a "NotFoundError" DOMException.

    // Remove child.

    // Return child.
    return self.removeChildChecked(node_id);
}
fn removeChildChecked(self: *Self, node_id: Node.NodeId) RemoveError!void {

    // 1.  Let parent be node’s [parent](#concept-tree-parent).
    const parent_id = self.getNode(node_id).parent orelse unreachable;

    // 2.  Assert: parent is non-null.

    // 3.  Run the [live range pre-remove steps](#live-range-pre-remove-steps), given node.
    try self.liveRangePreRemoveSteps(node_id);
    // 4.  For each `[NodeIterator](#nodeiterator)` object iterator whose [root](#concept-traversal-root)’s [node document](#concept-node-document) is node’s [node document](#concept-node-document), run the [`NodeIterator` pre-remove steps](#nodeiterator-pre-removing-steps) given node and iterator.
    // 5.  Let oldPreviousSibling be node’s [previous sibling](#concept-tree-previous-sibling).

    // 6.  Let oldNextSibling be node’s [next sibling](#concept-tree-next-sibling).
    // autofix
    // 7.  [Remove](https://infra.spec.whatwg.org/#list-remove) node from its parent’s [children](#concept-tree-child).
    var parent = self.getNode(parent_id);
    const index = std.mem.indexOfScalar(Node.NodeId, parent.children.items, node_id) orelse unreachable;
    _ = parent.children.orderedRemove(index);
    self.getNode(node_id).parent = null;
    self.markDirty(parent_id);

    // 8.  If node is [assigned](#slotable-assigned), then run [assign slottables](#assign-slotables) for node’s [assigned slot](#slotable-assigned-slot).

    // 9.  If parent’s [root](#concept-tree-root) is a [shadow root](#concept-shadow-root), and parent is a [slot](#concept-slot) whose [assigned nodes](#slot-assigned-nodes) is the empty list, then run [signal a slot change](#signal-a-slot-change) for parent.

    // 10.  If node has an [inclusive descendant](#concept-tree-inclusive-descendant) that is a [slot](#concept-slot):

    //     1.  Run [assign slottables for a tree](#assign-slotables-for-a-tree) with parent’s [root](#concept-tree-root).

    //     2.  Run [assign slottables for a tree](#assign-slotables-for-a-tree) with node.

    // 11.  Run the [removing steps](#concept-node-remove-ext) with node and parent.

    // 12.  Let isParentConnected be parent’s [connected](#connected).

    // 13.  If node is [custom](#concept-element-custom) and isParentConnected is true, then [enqueue a custom element callback reaction](https://html.spec.whatwg.org/multipage/custom-elements.html#enqueue-a-custom-element-callback-reaction) with node, callback name "`disconnectedCallback`", and « ».

    //     It is intentional for now that [custom](#concept-element-custom) [elements](#concept-element) do not get parent passed. This might change in the future if there is a need.

    // 14.  For each [shadow-including descendant](#concept-shadow-including-descendant) descendant of node, in [shadow-including tree order](#concept-shadow-including-tree-order):

    //     1.  Run the [removing steps](#concept-node-remove-ext) with descendant and null.

    //     2.  If descendant is [custom](#concept-element-custom) and isParentConnected is true, then [enqueue a custom element callback reaction](https://html.spec.whatwg.org/multipage/custom-elements.html#enqueue-a-custom-element-callback-reaction) with descendant, callback name "`disconnectedCallback`", and « ».

    // 15.  For each [inclusive ancestor](#concept-tree-inclusive-ancestor) inclusiveAncestor of parent, and then [for each](https://infra.spec.whatwg.org/#list-iterate) registered of inclusiveAncestor’s [registered observer list](#registered-observer-list), if registered’s [options](#registered-observer-options)\["`[subtree](#dom-mutationobserverinit-subtree)`"\] is true, then [append](https://infra.spec.whatwg.org/#list-append) a new [transient registered observer](#transient-registered-observer) whose [observer](#registered-observer-observer) is registered’s [observer](#registered-observer-observer), [options](#registered-observer-options) is registered’s [options](#registered-observer-options), and [source](#transient-registered-observer-source) is registered to node’s [registered observer list](#registered-observer-list).

    // 16.  If _suppress observers flag_ is unset, then [queue a tree mutation record](#queue-a-tree-mutation-record) for parent with « », « node », oldPreviousSibling, and oldNextSibling.

    // 17.  Run the [children changed steps](#concept-node-children-changed-ext) for parent.
}
pub fn removeChild(self: *Self, parent_id: Node.NodeId, child_id: Node.NodeId) !void {
    try self.preRemove(parent_id, child_id);
}

pub fn replaceChild(self: *Self, new_node_id: Node.NodeId, old_child_id: Node.NodeId) !Node.NodeId {
    // Find the parent of the node being replaced
    const parent_id = self.getNode(old_child_id).parent orelse return error.NotFound;

    // 3. If child's parent is not parent, then throw a "NotFoundError" DOMException.
    // (This is already handled by getting the parent above)

    // Check for hierarchical issues (node being a host-including ancestor of parent)
    // (Implementation dependent on your tree structure)

    // 7. Let referenceChild be child's next sibling
    var reference_child = traversal.nextSibling(self, old_child_id);

    // 8. If referenceChild is node, then set referenceChild to node's next sibling
    if (reference_child == new_node_id) {
        reference_child = traversal.nextSibling(self, new_node_id);
    }

    // 11. Remove the old child
    try self.removeChild(parent_id, old_child_id);

    // 12. Let nodes be node's children if node is a DocumentFragment node; otherwise « node ».
    // FIXME: uncomment this once we have a document fragment
    // const nodes: []const Node.NodeId = if (self.getNodeKind(new_node_id) == .document_fragment) self.getChildren(new_node_id).items else &.{new_node_id};
    const nodes: []const Node.NodeId = &.{new_node_id};

    // 13. Insert each node before the reference child
    for (nodes) |node_to_insert| {
        _ = try self.insertBefore(parent_id, node_to_insert, reference_child);
        // std.debug.print("replaceChild {d} {d}\n", .{ old_child_id, new_node_id });
    }

    // 15. Return the removed child
    return old_child_id;
}
test "Tree.replaceChild" {
    var tree = try init(std.testing.allocator);
    defer tree.deinit();

    const root = try tree.createNode();
    defer tree.validateTree(root, null);
    for (0..5) |i| {
        _ = i; // autofix
        const child = try tree.createNode();
        _ = try tree.appendChild(root, child);
    }
    const to_replace = try tree.createNode();
    try tree.expectNodes(0, "<0><1></1><2></2><3></3><4></4><5></5></0>", null);
    _ = try tree.replaceChild(to_replace, 3);
    try tree.expectNodes(0, "<0><1></1><2></2><6></6><4></4><5></5></0>", null);
}

pub fn insertBefore(self: *Self, parent_id: Node.NodeId, node_id: Node.NodeId, child_id: ?Node.NodeId) !Node.NodeId {
    // const parent = self.getNode(child orelse return error.NotFound).parent orelse return error.NotFound;
    return try self.preInsert(parent_id, node_id, child_id);
}
test "Tree.insertBefore" {
    var tree = try parseTree(std.testing.allocator, "<element><text>World</text></element>");
    defer tree.deinit();
    defer tree.validateTree(0, null);
    try tree.expectNodes(0, "<0><1><text#2>'World'</text#2></1></0>", null);
    const hello_node = try tree.createTextNode("Hello ");
    _ = try tree.insertBefore(1, hello_node, 2);
    try tree.expectNodes(0, "<0><1><text#3>'Hello '</text#3><text#2>'World'</text#2></1></0>", null);
}

test "Tree.removeChild" {
    {
        var tree = try parseTree(std.testing.allocator, "<element><text>World</text></element>");
        defer tree.deinit();
        defer tree.validateTree(0, null);

        try tree.expectNodes(0, "<0><1><text#2>'World'</text#2></1></0>", null);
        try tree.removeChild(0, 1);
        try tree.expectNodes(0, "<0></0>", null);
    }
    {
        var tree = try parseTree(std.testing.allocator, "<element><text>World</text></element>");

        defer tree.deinit();
        defer tree.validateTree(0, null);
        try tree.expectNodes(0, "<0><1><text#2>'World'</text#2></1></0>", null);
        try tree.removeChild(1, 2);
        try tree.expectNodes(0, "<0><1></1></0>", null);
    }

    {
        var tree = try init(std.testing.allocator);

        defer tree.deinit();
        defer tree.validateTree(0, null);
        const root = try tree.createNode();
        for (0..5) |i| {
            _ = i; // autofix
            const child = try tree.createNode();
            _ = try tree.appendChild(root, child);
        }
        try tree.expectNodes(0, "<0><1></1><2></2><3></3><4></4><5></5></0>", null);
        try tree.removeChild(0, 2);
        try tree.expectNodes(0, "<0><1></1><3></3><4></4><5></5></0>", null);
        try tree.removeChild(0, 5);
        try tree.expectNodes(0, "<0><1></1><3></3><4></4></0>", null);
        try tree.removeChild(0, 4);
        try tree.expectNodes(0, "<0><1></1><3></3></0>", null);
        try tree.removeChild(0, 3);
        try tree.expectNodes(0, "<0><1></1></0>", null);
        try tree.removeChild(0, 1);
        try tree.expectNodes(0, "<0></0>", null);
    }
}
pub fn removeChildren(self: *Self, parent_id: Node.NodeId) void {
    var node = self.getNode(parent_id);
    if (node.children.items.len == 0) {
        return;
    }
    for (node.children.items) |child_id| {
        self.getNode(child_id).parent = null;
    }
    node.children.clearRetainingCapacity();
    self.markDirty(parent_id);
}
pub fn normalize(self: *Self, node_id: Node.NodeId) !void {
    // Process each child node
    var current_index: usize = 0;

    // Don't store children outside the loop - always access it directly
    while (current_index < self.getNode(node_id).children.items.len) {
        // Get child_id directly from the current tree state
        const child_id = self.getNode(node_id).children.items[current_index];

        // If not a text node, normalize its children and move on
        if (self.getNodeKind(child_id) != .text) {
            try self.normalize(child_id);
            current_index += 1;
            continue;
        }

        // Handle empty text nodes - step 2
        if (self.getNode(child_id).length() == 0) {
            try self.removeChild(node_id, child_id);
            // Don't increment current_index as the array has shifted
            continue;
        }

        // Look for contiguous text nodes - steps 3-7
        var next_index = current_index + 1;
        var has_adjacent_text = false;

        // Check if there are adjacent text nodes - always use the current state
        while (next_index < self.getNode(node_id).children.items.len) {
            const next_child = self.getNode(node_id).children.items[next_index];
            if (self.getNodeKind(next_child) != .text) break;
            has_adjacent_text = true;
            next_index += 1;
        }

        // If we have adjacent text nodes, merge them
        if (has_adjacent_text) {
            var data = std.ArrayList(u8).init(self.allocator);
            defer data.deinit();

            // Get the first text node's content
            try data.appendSlice(self.getText(child_id).bytes.items);
            var length: u32 = @intCast(self.getNode(child_id).length());

            // Store the IDs of text nodes to remove in a separate array
            var to_remove = std.ArrayList(Node.NodeId).init(self.allocator);
            defer to_remove.deinit();

            // Process adjacent text nodes - step 6
            var node_to_process = current_index + 1;
            while (node_to_process < next_index) {
                // Always get the current state
                const text_node = self.getNode(node_id).children.items[node_to_process];
                try to_remove.append(text_node);

                // Update live ranges - steps 6.1-6.4
                var it = self.iterLiveRanges();
                while (it.next()) |live_range| {
                    // 6.1: If start node is this text node
                    if (live_range.start.node_id == text_node) {
                        live_range.start.node_id = child_id;
                        live_range.start.offset += length;
                    }

                    // 6.2: If end node is this text node
                    if (live_range.end.node_id == text_node) {
                        live_range.end.node_id = child_id;
                        live_range.end.offset += length;
                    }

                    // 6.3 & 6.4: Handle ranges that point to the parent at this index
                    if (live_range.start.node_id == node_id and
                        live_range.start.offset == node_to_process)
                    {
                        live_range.start.node_id = child_id;
                        live_range.start.offset = length;
                    }

                    if (live_range.end.node_id == node_id and
                        live_range.end.offset == node_to_process)
                    {
                        live_range.end.node_id = child_id;
                        live_range.end.offset = length;
                    }
                }

                // 6.5: Add this node's text to our buffer
                try data.appendSlice(self.getText(text_node).bytes.items);
                length += @intCast(self.getNode(text_node).length());

                // Move to the next node
                node_to_process += 1;
            }

            // 4: Replace the data in the first text node
            try self.setText(child_id, data.items);

            // 7: Remove all the other text nodes in reverse order
            var i = to_remove.items.len;
            while (i > 0) {
                i -= 1;
                try self.removeChild(node_id, to_remove.items[i]);
            }
        }

        // Move to the next child
        current_index += 1;
    }
}
test "Tree.normalize" {
    var tree = try init(std.testing.allocator);
    defer tree.deinit();
    defer tree.validateTree(0, null);
    const root = try tree.createNode();
    const text1 = try tree.createTextNode("Hello ");
    const text2 = try tree.createTextNode("World");
    const child3 = try tree.createNode();
    const text3 = try tree.createTextNode("!");
    const text4 = try tree.createTextNode("!");

    _ = try tree.appendChild(root, text1);
    _ = try tree.appendChild(root, text2);
    _ = try tree.appendChild(root, child3);
    _ = try tree.appendChild(child3, text3);
    _ = try tree.appendChild(child3, text4);

    try tree.expectNodes(0, "<0><text#1>'Hello '</text#1><text#2>'World'</text#2><3><text#4>'!'</text#4><text#5>'!'</text#5></3></0>", null);
    try tree.normalize(0);
    try tree.expectNodes(0, "<0><text#1>'Hello World'</text#1><3><text#4>'!!'</text#4></3></0>", null);
    tree.validateTree(0, null);
}

pub fn getNodeContains(self: *Self, parent_id: Node.NodeId, maybe_child_id: Node.NodeId) bool {
    var parent = self.getNode(maybe_child_id).parent;
    while (parent) |p| {
        if (p == parent_id) {
            return true;
        }
        parent = self.getNode(p).parent;
    }
    return false;
}
pub fn deinit(self: *Self) void {
    var node_iter = self.node_map.iterator();
    if (self.input_manager) |*manager| {
        manager.deinit();
    }
    while (node_iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
    }
    self.node_map.deinit(self.allocator);

    self.live_ranges.deinit(self.allocator);
    self.selections.deinit(self.allocator);
    // Clean up style system
    self.style_manager.deinit();
    self.computed_style_cache.deinit();
}
pub fn getNodeCount(self: *Self) usize {
    return self.node_map.count();
}
fn printNode(self: *Self, writer: std.io.AnyWriter, node_id: Node.NodeId, indent: usize) !void {
    // const node = self.getNode(node_id);
    try writer.writeByteNTimes(' ', indent * 4);
    const layout = self.getLayout(node_id);
    const kind = self.getNodeKind(node_id);
    if (kind == .text) {
        try writer.print("[{s} #{d}] \"{s}\"\n", .{ @tagName(kind), node_id, self.getText(node_id).bytes.items });
    } else {
        const display = self.getStyle(node_id).display;
        const has_computed_text = self.getComputedText(node_id) != null;

        try writer.print("[{s}#{d} {s} {s} {any} #{d} pos=[{d},{d}] size=[{d},{d}] content_size=[{d},{d}] border=[{d}, {d}, {d}, {d}]]\n", .{
            @tagName(kind),
            node_id,
            @tagName(display.outside),
            @tagName(display.inside),
            has_computed_text,
            node_id,
            layout.location.x,
            layout.location.y,
            layout.size.x,
            layout.size.y,
            layout.content_size.x,
            layout.content_size.y,
            layout.border.top,
            layout.border.right,
            layout.border.bottom,
            layout.border.left,
        });

        // } else {
        //     try writer.print("[{s} {s} {s}  #{d} x={d} y={d} width={d} height={d}]\n", .{
        //         @tagName(kind),
        //         @tagName(display.outside),
        //         @tagName(display.inside),
        //         node_id,
        //         layout.location.x,
        //         layout.location.y,
        //         layout.size.x,
        //         layout.size.y,
        //     });
        // }
    }

    for (self.getChildren(node_id).items) |child_id| {
        try self.printNode(writer, child_id, indent + 1);
    }
}
pub fn print(self: *Self, writer: std.io.AnyWriter) !void {
    try self.printNode(writer, 0, 0);
}

pub inline fn parseTree(allocator: std.mem.Allocator, tree_string: []const u8) !Self {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    const doc = try xml.parse(arena_allocator, tree_string);
    var tree = try init(allocator);
    errdefer tree.deinit();
    _ = try fromXmlElement(&tree, doc.root, null);

    return tree;
}
fn printFunctionErrors(comptime func: anytype) void {
    const type_info: std.builtin.Type = @typeInfo(@TypeOf(func));
    switch (type_info) {
        .@"fn" => |func_info| {
            const ReturnType = func_info.return_type orelse @compileError("No return type");
            const ret_type_info: std.builtin.Type = @typeInfo(ReturnType);
            switch (ret_type_info) {
                .error_union => |error_union_info| {
                    const error_type: std.builtin.Type = @typeInfo(error_union_info.error_set);
                    switch (error_type) {
                        .error_set => |error_set_info| {
                            inline for (error_set_info.?) |field| {
                                std.debug.print("{s}\n", .{field.name});
                            }
                        },
                        else => @compileError("No error type"),
                    }
                },
                else => @compileError("No error type"),
            }
        },
        else => unreachable,
    }
}
const PrintTreeError = error{
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
inline fn textNodeFromXmlElement(
    tree: *Self,
    xml_node: *xml.Element,
    parent_id: ?Node.NodeId,
) PrintTreeError!void {
    // const node_id = try tree.createTextNode("");
    const node_id = try tree.createNode();
    if (parent_id) |parent| {
        _ = try tree.appendChild(parent, node_id);
    }
    var node = tree.getNode(node_id);
    node.styles.display = .{ .inside = .flow, .outside = .@"inline" };

    var it = xml_node.iterator();
    var curr_offset: usize = 0;
    while (it.next()) |content| {
        switch (content.*) {
            .char_data => |text| {
                const text_node_id = try tree.createTextNode(text);
                _ = try tree.appendChild(node_id, text_node_id);
                try tree.setText(text_node_id, text);

                for (xml_node.attributes) |attr| {
                    if (std.mem.eql(u8, attr.name, "selectionStart")) {
                        const offset: u32 = try std.fmt.parseInt(u32, attr.value, 10);
                        if (offset >= curr_offset and offset < curr_offset + text.len) {
                            if (tree.getFirstSelection()) |selection| {
                                try selection.setAnchor(tree, .{ .node_id = text_node_id, .offset = offset });
                            } else {
                                _ = try tree.createSelection(.{ .node_id = text_node_id, .offset = offset }, null);
                            }
                        }

                        continue;
                    }
                    if (std.mem.eql(u8, attr.name, "selectionEnd")) {
                        const offset: u32 = try std.fmt.parseInt(u32, attr.value, 10);
                        if (offset >= curr_offset and offset < curr_offset + text.len) {
                            if (tree.getFirstSelection()) |selection| {
                                try selection.setFocus(tree, .{ .node_id = text_node_id, .offset = offset });
                            } else {
                                _ = try tree.createSelection(.{ .node_id = text_node_id, .offset = offset }, null);
                            }
                        }
                        continue;
                    }
                }
                curr_offset += text.len;
            },
            .element => |el| {
                // errorFromFunction(fromXmlElement);
                const child_id = try fromXmlElement(tree, el, node_id);
                _ = child_id; // autofix
                // _ = try tree.appendChild(node_id, child_id);
            },
            else => {
                std.debug.print("unknown content {s}\n", .{@tagName(content.*)});
            },
        }
    }

    // return node_id;
}
fn fromXmlElement(
    tree: *Self,
    xml_node: *xml.Element,
    parent_id: ?Node.NodeId,
) PrintTreeError!void {
    const is_text_node = std.mem.eql(u8, xml_node.tag, "text");
    if (is_text_node) {
        return textNodeFromXmlElement(
            tree,
            xml_node,
            parent_id,
        );
    }
    const node_id = try tree.createNode();
    if (parent_id) |parent| {
        _ = try tree.appendChild(parent, node_id);
    }

    // // var style = Style.init(tree.allocator);
    // // errdefer style.deinit();
    // const node_id = try tree.createNode();
    // var style = &tree.getNode(node_id).styles;
    // if (is_text_node) {
    //     style.display = .{ .inside = .flow, .outside = .@"inline" };
    // }

    for (xml_node.children) |child| {
        switch (child) {
            .element => |el| {
                const child_id = try fromXmlElement(tree, el, node_id);
                _ = child_id; // autofix
                // _ = try tree.appendChild(node_id, child_id);
            },
            // .char_data => |text| {
            //     if (!is_text_node) continue;
            //     const child_id = try tree.createTextNode(text);
            //     _ = try tree.appendChild(node_id, child_id);
            // },
            else => {},
        }
    }

    for (xml_node.attributes) |attr| {
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
    // return node_id;
}

/// Get the computed style for a node, accounting for inheritance and cascading
pub fn getComputedStyle(self: *Self, node_id: Node.NodeId) Style {
    return self.computed_style_cache.getComputedStyle(self, node_id);
}

/// Invalidate computed styles for a node and its descendants
pub fn invalidateStyles(self: *Self, node_id: Node.NodeId) void {
    // Invalidate all computed styles for this node and its descendants
    self.computed_style_cache.invalidateTree(self, node_id);

    // Mark the node as dirty to trigger layout recalculation
    self.markDirty(node_id);
}

//         // \\  <div display="block" width="100%" height="100%">
//         \\    <span><div display="block" width="1" height="1"></div>Lorem ipsum dolor sit am <div display="inline-block"></div>et<div display="block" width="1" height="1"></div></span>
//         // \\    <span>Lorem ipsum dolor sit am<span>et, cons</span>ec<span>tetur adipiscing elit. </span></span>
//         // \\    <span>Lorem ipsum dolor sit am<span>et, cons</span>ec<span>tetur adipiscing elit. </span></span>
//         // \\  </div>
//         \\</div>
//     );
//     defer tree.deinit();
//     // const root = tree.getNode(0);
//     const writer = std.io.getStdErr().writer().any();
//     try tree.print(writer);

//     const testing_allocator = std.testing.allocator;

//     var arena = std.heap.ArenaAllocator.init(testing_allocator);
//     defer arena.deinit();

//     const layout = tree.getLayout(0);
//     std.debug.print("\n\nlayout:\n{any}\n", .{(layout)});
//     try tree.print(writer);
// }

pub fn getNodeChildren(self: *Self, node_id: Node.NodeId) []const Node.NodeId {
    switch (self.getNode(node_id).kind) {
        .text => return &[_]Node.NodeId{},
        .node => return self.getNode(node_id).children.items,
    }
}

/// https://dom.spec.whatwg.org/#concept-tree-root
/// The root of an object is itself, if its parent is null, or else it is the root of its parent. The root of a tree is any object participating in that tree whose parent is null.
pub fn getNodeRoot(self: *Self, node_id: Node.NodeId) Node.NodeId {
    var current: Node.NodeId = node_id;
    while (self.getNode(current).parent) |parent| {
        current = parent;
    }
    return current;
}

/// https://dom.spec.whatwg.org/#trees
/// An object A is called a descendant of an object B, if either A is a child of B or A is a child of an object C that is a descendant of B.
pub fn isNodeDescendant(self: *Self, node_id: Node.NodeId, maybe_ancestor_id: Node.NodeId) bool {
    if (maybe_ancestor_id == node_id) return false;
    var current: Node.NodeId = node_id;
    while (self.getNode(current).parent) |parent| {
        if (parent == maybe_ancestor_id) return true;
        current = parent;
    }
    return false;
}

pub fn isNodeAncestor(self: *Self, node_id: Node.NodeId, maybe_descendant_id: Node.NodeId) bool {
    return self.isNodeDescendant(maybe_descendant_id, node_id);
}
pub const LCA = struct {
    ancestor: ?Node.NodeId,
    distinct_a_child: ?Node.NodeId,
    distinct_b_child: ?Node.NodeId,
    a: Node.NodeId,
    b: Node.NodeId,
    pub fn aIsAncestorOfB(self: LCA) bool {
        return self.distinct_a_child == null and self.distinct_b_child != null;
    }
    pub fn bIsAncestorOfA(self: LCA) bool {
        return self.distinct_b_child == null and self.distinct_a_child != null;
    }
    pub fn getOrder(self: LCA, tree: *Self) !Order {
        if (self.ancestor == null) return error.NotInTheSameTree;
        if (self.aIsAncestorOfB()) return .lt;
        if (self.bIsAncestorOfA()) return .gt;
        const a_index = tree.nodeIndex(self.a) orelse unreachable;
        const b_index = tree.nodeIndex(self.b) orelse unreachable;
        if (a_index < b_index) return .lt;
        return .gt;
    }
};
pub fn getLowestCommonAncestorAndFirstDistinctAncestor(self: *Self, a: Node.NodeId, b: Node.NodeId) LCA {
    // Same node check
    if (a == b)
        return .{ .a = a, .b = b, .ancestor = a, .distinct_a_child = null, .distinct_b_child = null };

    // Find depths
    var depth_a: usize = 0;
    var depth_b: usize = 0;
    var current = a;
    while (self.getNode(current).parent) |parent| {
        depth_a += 1;
        current = parent;
    }
    current = b;
    while (self.getNode(current).parent) |parent| {
        depth_b += 1;
        current = parent;
    }

    // Set x to deeper node, y to shallower node
    var x, var y, const difference = if (depth_a >= depth_b) .{ a, b, depth_a - depth_b } else .{ b, a, depth_b - depth_a };

    // Track child on deeper node's path
    var distinctAncestorA: ?Node.NodeId = null;

    // Move up from deeper node to equalize depths
    for (0..difference) |_| {
        distinctAncestorA = x;
        x = self.getNode(x).parent orelse return .{ .a = a, .b = b, .ancestor = null, .distinct_a_child = null, .distinct_b_child = null };
    }

    // Track child on shallower node's path
    var distinctAncestorB: ?Node.NodeId = null;

    // Find LCA by moving up both nodes
    while (x != y) {
        distinctAncestorA = x;
        distinctAncestorB = y;
        x = self.getNode(x).parent orelse return .{ .a = a, .b = b, .ancestor = null, .distinct_a_child = null, .distinct_b_child = null };
        y = self.getNode(y).parent orelse return .{ .a = a, .b = b, .ancestor = null, .distinct_a_child = null, .distinct_b_child = null };
    }

    // Swap back to ensure children match original a and b
    if (depth_a < depth_b) {
        std.mem.swap(?Node.NodeId, &distinctAncestorA, &distinctAncestorB);
    }

    return .{ .a = a, .b = b, .ancestor = x, .distinct_a_child = distinctAncestorA, .distinct_b_child = distinctAncestorB };
}
test "getLowestCommonAncestorAndFirstDistinctAncestor" {
    var tree = try init(std.testing.allocator);
    defer tree.deinit();
    defer tree.validateTree(0, null);
    const root = try tree.createNode();
    const child_a = try tree.createNode();
    const child_b = try tree.createNode();
    _ = try tree.appendChild(root, child_a);
    _ = try tree.appendChild(root, child_b);
    {
        const lca = tree.getLowestCommonAncestorAndFirstDistinctAncestor(child_a, child_b);
        try std.testing.expectEqual(lca.ancestor, root);
        try std.testing.expectEqual(lca.distinct_a_child, child_a);
        try std.testing.expectEqual(lca.distinct_b_child, child_b);
    }

    {
        const lca = tree.getLowestCommonAncestorAndFirstDistinctAncestor(child_a, root);
        try std.testing.expectEqual(lca.ancestor, root);
        try std.testing.expectEqual(lca.bIsAncestorOfA(), true);
    }
    {
        const lca = tree.getLowestCommonAncestorAndFirstDistinctAncestor(root, child_a);
        try std.testing.expectEqual(lca.ancestor, root);
        try std.testing.expectEqual(lca.aIsAncestorOfB(), true);
    }
}

/// An object A is called a sibling of an object B, if and only if B and A share the same non-null parent.
pub fn isNodeSibling(self: *Self, node_id: Node.NodeId, maybe_sibling_id: Node.NodeId) bool {
    if (node_id == maybe_sibling_id) return false;
    const node_parent = self.getNode(node_id).parent;
    if (node_parent == null) return false;

    return self.getNode(maybe_sibling_id).parent == node_parent;
}

pub fn firstChild(self: *Self, node_id: Node.NodeId) ?Node.NodeId {
    return traversal.firstChild(self, node_id);
}

pub fn lastChild(self: *Self, node_id: Node.NodeId) ?Node.NodeId {
    return traversal.lastChild(self, node_id);
}

pub fn nodeIndex(self: *Self, node_id: Node.NodeId) ?u32 {
    return traversal.nodeIndex(self, node_id);
}

pub fn nextSibling(self: *Self, node_id: Node.NodeId) ?Node.NodeId {
    return traversal.nextSibling(self, node_id);
}
pub fn previousSibling(self: *Self, node_id: Node.NodeId) ?Node.NodeId {
    return traversal.previousSibling(self, node_id);
}
pub fn isSubsequentSibling(self: *Self, node_a: Node.NodeId, node_b: Node.NodeId) bool {
    if (node_a == node_b) return false;
    const a_parent = self.getNode(node_a).parent orelse return false;
    const b_parent = self.getNode(node_b).parent orelse return false;
    if (a_parent != b_parent) return false;
    const siblings = self.getNodeChildren(a_parent);
    const a_index = std.mem.indexOfScalar(Node.NodeId, siblings, node_a) orelse unreachable;
    if (a_index == siblings.len - 1) return false;
    for (siblings[a_index + 1 ..]) |child| {
        if (child == node_b) return true;
    }
    return false;
}
const Order = std.math.Order;
/// In tree order is preorder, depth-first traversal of a tree.
pub fn treeOrder(self: *Self, node_a: Node.NodeId, node_b: Node.NodeId) !Order {
    if (node_a == node_b) return .eq;
    const lca = self.getLowestCommonAncestorAndFirstDistinctAncestor(node_a, node_b);
    if (lca.ancestor == null) return error.NotInTheSameTree;
    // if no distinct child a, that means that a is an ancestor of b, therefore a is before b
    const distinct_a_child = lca.distinct_a_child orelse return .lt;
    // if no distinct child b, that means that b is an ancestor of a, therefore b is before a
    const distinct_b_child = lca.distinct_b_child orelse return .gt;
    const a_index = self.nodeIndex(distinct_a_child) orelse unreachable;
    const b_index = self.nodeIndex(distinct_b_child) orelse unreachable;
    if (a_index < b_index) return .lt;
    return .gt;
}

test "treeOrder - comprehensive" {
    var tree = try init(std.testing.allocator);
    defer tree.deinit();
    defer tree.validateTree(0, null);
    // Create a more complex tree structure
    //                    root
    //                   /    \
    //                child_a  child_b
    //               /  |  \    /   \
    //     child_a_a child_a_b child_b_a child_b_b
    //                 |
    //             child_a_b_a

    const root = try tree.createNode();
    const child_a = try tree.createNode();
    const child_b = try tree.createNode();
    _ = try tree.appendChild(root, child_a);
    _ = try tree.appendChild(root, child_b);

    const child_a_a = try tree.createNode();
    const child_a_b = try tree.createNode();
    const child_a_c = try tree.createNode();
    _ = try tree.appendChild(child_a, child_a_a);
    _ = try tree.appendChild(child_a, child_a_b);
    _ = try tree.appendChild(child_a, child_a_c);

    const child_b_a = try tree.createNode();
    const child_b_b = try tree.createNode();
    _ = try tree.appendChild(child_b, child_b_a);
    _ = try tree.appendChild(child_b, child_b_b);

    const child_a_b_a = try tree.createNode();
    _ = try tree.appendChild(child_a_b, child_a_b_a);

    // Let's add some deeper nodes for more complex testing
    const child_b_b_a = try tree.createNode();
    _ = try tree.appendChild(child_b_b, child_b_b_a);

    const child_a_c_a = try tree.createNode();
    const child_a_c_b = try tree.createNode();
    _ = try tree.appendChild(child_a_c, child_a_c_a);
    _ = try tree.appendChild(child_a_c, child_a_c_b);

    // 1. Self comparison
    try std.testing.expectEqual(try tree.treeOrder(root, root), .eq);
    try std.testing.expectEqual(try tree.treeOrder(child_a, child_a), .eq);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_a_b_a), .eq);

    // 2. Basic sibling order tests
    try std.testing.expectEqual(try tree.treeOrder(child_a, child_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b, child_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_a, child_a_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b, child_a_c), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c, child_a_a), .gt);

    // 3. Parent-child relationships
    try std.testing.expectEqual(try tree.treeOrder(root, child_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a, root), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a, child_a_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b, child_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b, child_a_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_a_b), .gt);

    // 4. Cross-branch comparisons
    try std.testing.expectEqual(try tree.treeOrder(child_a_a, child_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b_a, child_a_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c, child_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b_a, child_a_c), .gt);

    // 5. Deep cross-branch comparisons
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_b_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b_b_a, child_a_b_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c_a, child_b_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b_b_a, child_a_c_b), .gt);

    // 6. Uncle/aunt to niece/nephew comparisons
    try std.testing.expectEqual(try tree.treeOrder(child_a, child_b_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b_b_a, child_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c, child_a_b_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_a_c), .lt);

    // 7. Nodes at different depths
    try std.testing.expectEqual(try tree.treeOrder(child_a_a, child_a_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_a_c), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_a_c_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b_a, child_b_b_a), .lt);

    // 8. Root comparisons
    try std.testing.expectEqual(try tree.treeOrder(root, child_a_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(root, child_b_b_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c_b, root), .gt);

    // 9. Test complex ancestor relationships
    try std.testing.expectEqual(try tree.treeOrder(child_a_c_a, child_a_c_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c_b, child_a_c_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_a_c_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_c_a, child_a_b_a), .gt);

    // 10. Test modified tree structure
    // Let's move a subtree and test the new relationships
    try tree.removeChild(child_a, child_a_b);
    _ = try tree.appendChild(child_b_a, child_a_b);

    // Now child_a_b is under child_b_a
    try std.testing.expectEqual(try tree.treeOrder(child_b_a, child_a_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b, child_b_a), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_a, child_a_b), .lt); // different branches now
    try std.testing.expectEqual(try tree.treeOrder(child_a_b, child_b_b), .lt); // now child_a_b comes before child_b_b
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, child_b_b), .lt); // child_a_b_a follows its parent

    // 11. Test disconnected nodes
    const disconnected1 = try tree.createNode();
    const disconnected2 = try tree.createNode();

    // Create a separate tree
    const other_root = try tree.createNode();
    const other_child = try tree.createNode();
    _ = try tree.appendChild(other_root, other_child);

    // Test that comparing disconnected nodes returns an error
    try std.testing.expectError(error.NotInTheSameTree, tree.treeOrder(disconnected1, disconnected2));
    try std.testing.expectError(error.NotInTheSameTree, tree.treeOrder(root, disconnected1));
    try std.testing.expectError(error.NotInTheSameTree, tree.treeOrder(disconnected1, root));

    // Test that comparing nodes in separate trees returns an error
    try std.testing.expectError(error.NotInTheSameTree, tree.treeOrder(root, other_root));
    try std.testing.expectError(error.NotInTheSameTree, tree.treeOrder(other_child, child_a));
    try std.testing.expectError(error.NotInTheSameTree, tree.treeOrder(child_b_b_a, other_child));

    // 12. Test edge cases with root and direct children
    try std.testing.expectEqual(try tree.treeOrder(root, child_a), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a, root), .gt);
    try std.testing.expectEqual(try tree.treeOrder(root, child_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_b, root), .gt);

    // 13. Create a very deep tree to test performance with nodes at many different levels

    var deep_node = child_b_b_a;
    var deep_nodes = [_]Node.NodeId{undefined} ** 10;

    for (0..10) |i| {
        deep_nodes[i] = try tree.createNode();
        _ = try tree.appendChild(deep_node, deep_nodes[i]);
        deep_node = deep_nodes[i];
    }

    // Test deep ancestor relationship
    try std.testing.expectEqual(try tree.treeOrder(child_b_b, deep_nodes[9]), .lt);
    try std.testing.expectEqual(try tree.treeOrder(deep_nodes[9], child_b_b), .gt);
    try std.testing.expectEqual(try tree.treeOrder(deep_nodes[0], deep_nodes[9]), .lt);
    try std.testing.expectEqual(try tree.treeOrder(deep_nodes[9], deep_nodes[0]), .gt);

    // 14. Test after more complex tree modifications
    // Move a subtree to another part of the tree
    try tree.removeChild(child_b_a, child_a_b);
    _ = try tree.appendChild(deep_nodes[5], child_a_b);

    try std.testing.expectEqual(try tree.treeOrder(deep_nodes[4], child_a_b), .lt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b, deep_nodes[6]), .gt);
    try std.testing.expectEqual(try tree.treeOrder(child_a_b_a, deep_nodes[9]), .gt);
}
pub fn splitTextNode(self: *Self, text_node_id: Node.NodeId, offset: u32) !Node.NodeId {
    // 1. Let length be node's [length](#concept-node-length).
    const text_node = self.getNode(text_node_id);
    if (text_node.kind != .text) return error.NotATextNode;
    const length = text_node.length();

    // 2. If offset is greater than length, then [throw](https://webidl.spec.whatwg.org/#dfn-throw) an "`[IndexSizeError](https://webidl.spec.whatwg.org/#indexsizeerror)`" `[DOMException](https://webidl.spec.whatwg.org/#idl-DOMException)`.
    if (offset > length) return error.OffsetOutOfBounds;

    // 3. Let count be length minus offset.
    const count = length - offset;

    // 4. Let new data be the result of [substringing data](#concept-cd-substring) with node node, offset offset, and count count.
    const new_data = text_node.text.slice()[offset..];

    // 5. Let new node be a new `[Text](#text)` [node](#concept-node), with the same [node document](#concept-node-document) as node. Set new node's [data](#concept-cd-data) to new data.
    const new_node_id = try self.createTextNode(new_data);

    // 6. Let parent be node's [parent](#concept-tree-parent).
    const parent = text_node.parent;

    // 7. If parent is not null:
    if (parent) |parent_id| {
        // Get the next sibling of the text node
        const next_sibling = self.nextSibling(text_node_id);

        // 7.1. [Insert](#concept-node-insert) new node into parent before node's [next sibling](#concept-tree-next-sibling).
        _ = try self.insertBefore(parent_id, new_node_id, next_sibling);

        var iter = self.live_ranges.iterator();
        // Live range adjustments
        while (iter.next()) |entry| {
            var range = entry.value_ptr;
            // 7.2. For each [live range](#concept-live-range) whose [start node](#concept-range-start-node) is node
            // and [start offset](#concept-range-start-offset) is greater than offset,
            // set its [start node](#concept-range-start-node) to new node and decrease its [start offset](#concept-range-start-offset) by offset.
            if (range.start.node_id == text_node_id and range.start.offset > offset) {
                try range.setStart(self, new_node_id, range.start.offset - offset);
            }

            // 7.3. For each [live range](#concept-live-range) whose [end node](#concept-range-end-node) is node
            // and [end offset](#concept-range-end-offset) is greater than offset,
            // set its [end node](#concept-range-end-node) to new node and decrease its [end offset](#concept-range-end-offset) by offset.
            if (range.end.node_id == text_node_id and range.end.offset > offset) {
                try range.setEnd(self, new_node_id, range.end.offset - offset);
            }

            // 7.4. For each [live range](#concept-live-range) whose [start node](#concept-range-start-node) is parent and
            // [start offset](#concept-range-start-offset) is equal to the [index](#concept-tree-index) of node plus 1,
            // increase its [start offset](#concept-range-start-offset) by 1.
            const index = self.nodeIndex(text_node_id) orelse unreachable;
            if (range.start.node_id == parent_id and range.start.offset == index + 1) {
                try range.setStart(self, parent_id, range.start.offset + 1);
            }

            // 7.5. For each [live range](#concept-live-range) whose [end node](#concept-range-end-node) is parent and
            // [end offset](#concept-range-end-offset) is equal to the [index](#concept-tree-index) of node plus 1,
            // increase its [end offset](#concept-range-end-offset) by 1.
            if (range.end.node_id == parent_id and range.end.offset == index + 1) {
                try range.setEnd(self, parent_id, range.end.offset + 1);
            }
        }
    }

    // 8. [Replace data](#concept-cd-replace) with node node, offset offset, count count, and data the empty string.
    try text_node.replaceData(self, offset, @intCast(count), "");

    // 9. Return new node.
    return new_node_id;
}
const DumpNodesOptions = struct {
    collapsed_caret: []const u8 = "\x1b[31m|\x1b[0m",
    range_open: []const u8 = "\x1b[7m",
    range_close: []const u8 = "\x1b[0m",
};
pub fn dumpNodes(tree: *Self, node_id: Node.NodeId, writer: std.io.AnyWriter, maybe_range: ?Range, comptime options: DumpNodesOptions) !void {
    const node = tree.getNode(node_id);
    if (maybe_range) |range| {
        const is_collapsed = range.isCollapsed();
        const range_open = options.range_open;
        const range_close = options.range_close;
        const collapsed_caret = options.collapsed_caret;

        switch (node.kind) {
            .text => {
                try writer.print("<text#{d}>", .{node_id});
                const bytes = tree.getText(node_id).bytes.items;

                if (is_collapsed and node_id == range.start.node_id) {
                    // For collapsed ranges in text nodes, insert caret at the offset
                    // if (self.start.offset == 0) {
                    //     try writer.print("\x1b[31m|\x1b[0m{s}", .{bytes}); // Red caret at beginning
                    // } else if (self.start.offset >= bytes.len) {
                    //     try writer.print("{s}\x1b[31m|\x1b[0m", .{bytes}); // Red caret at end
                    // } else {
                    // Caret in the middle of text
                    try writer.print("'{s}" ++ collapsed_caret ++ "{s}'", .{ bytes[0..range.start.offset], bytes[range.start.offset..] });
                    // }
                } else if (!is_collapsed and node_id == range.start.node_id and range.end.node_id == node_id) {
                    try writer.print("'{s}", .{bytes[0..range.start.offset]});
                    try writer.print(range_open ++ "{s}" ++ range_close, .{bytes[range.start.offset..range.end.offset]});
                    try writer.print("{s}'", .{bytes[range.end.offset..]});
                } else if (!is_collapsed and node_id == range.start.node_id) {
                    try writer.print("'{s}" ++ range_open ++ "{s}'", .{ bytes[0..range.start.offset], bytes[range.start.offset..bytes.len] });
                } else if (!is_collapsed and node_id == range.end.node_id) {
                    try writer.print("'{s}" ++ range_close ++ "{s}'", .{ bytes[0..range.end.offset], bytes[range.end.offset..] });
                } else {
                    try writer.print("'{s}'", .{bytes});
                }
                try writer.print("</text#{d}>", .{node_id});
            },
            else => {
                if (is_collapsed and node_id == range.start.node_id) {
                    // For collapsed ranges in element nodes
                    try writer.print("<{d}>", .{node_id});

                    if (node.children.items.len > 0) {
                        var caret_shown = false;

                        // Insert caret at the appropriate offset between children
                        for (node.children.items, 0..) |child_id, i| {
                            if (i == range.start.offset and !caret_shown) {
                                try writer.print(collapsed_caret, .{}); // Red caret
                                caret_shown = true;
                            }

                            try dumpNodes(tree, child_id, writer, range, options);
                        }

                        // Handle case where caret is after all children
                        if (range.start.offset >= node.children.items.len) {
                            try writer.print(collapsed_caret, .{});
                        }
                    } else if (range.start.offset == 0) {
                        // Empty node with caret
                        try writer.print(collapsed_caret, .{});
                    }

                    try writer.print("</{d}>", .{node_id});
                } else if (!is_collapsed and node_id == range.start.node_id and range.start.offset == 0) {
                    try writer.writeAll(range_open);
                    if (node.children.items.len > 0) {
                        try writer.print("<{d}>", .{node_id});
                        for (node.children.items, 0..) |child_id, i| {
                            if (!is_collapsed and i > 0 and node_id == range.start.node_id and i == range.start.offset) {
                                try writer.writeAll(range_open);
                            }
                            try dumpNodes(tree, child_id, writer, range, options);
                            if (!is_collapsed and i < node.children.items.len - 1 and node_id == range.end.node_id and i == range.end.offset) {
                                try writer.writeAll(range_close);
                            }
                        }
                        try writer.print("</{d}>", .{node_id});
                    } else {
                        try writer.print("<{d}/>", .{node_id});
                    }
                    if (!is_collapsed and node_id == range.end.node_id and range.end.offset >= node.length() - 1) {
                        try writer.writeAll(range_close);
                    }
                } else {
                    if (node.children.items.len > 0) {
                        try writer.print("<{d}>", .{node_id});
                        for (node.children.items, 0..) |child_id, i| {
                            if (!is_collapsed and i > 0 and node_id == range.start.node_id and i == range.start.offset) {
                                try writer.writeAll(range_open);
                            }
                            try dumpNodes(tree, child_id, writer, range, options);
                            if (!is_collapsed and i < node.children.items.len - 1 and node_id == range.end.node_id and i == range.end.offset) {
                                try writer.writeAll(range_close);
                            }
                        }
                        try writer.print("</{d}>", .{node_id});
                    } else {
                        try writer.print("<{d}/>", .{node_id});
                    }
                    if (!is_collapsed and node_id == range.end.node_id and range.end.offset >= node.length() - 1) {
                        try writer.writeAll(range_close);
                    }
                }
            },
        }
    } else {
        switch (node.kind) {
            .text => {
                try writer.print("<text#{d}>'{s}'</text#{d}>", .{ node_id, node.text.slice(), node_id });
            },
            else => {
                try writer.print("<{d}>", .{node_id});
                for (node.children.items) |child_id| {
                    try dumpNodes(tree, child_id, writer, null, options);
                }
                try writer.print("</{d}>", .{node_id});
            },
        }
    }
}

pub fn caretPositionFromPoint(self: *Self, viewport_size: Point(f32), position: Point(f32)) ?BoundaryPoint {
    const maybe_hit = hitTest(self, viewport_size, position, .{});
    if (maybe_hit) |hit| {
        // TODO: for now, we only return if the caret is exactly on a text node
        // we will handle a more flexible model once we introduce the render tree

        if (self.getNode(hit.node_id).kind == .text) {
            return hit;
        }
    }
    return null;
}

pub fn expectNodes(tree: *Self, node_id: Node.NodeId, expected: []const u8, range: ?Range) !void {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    try tree.dumpNodes(node_id, buffer.writer().any(), range, .{});
    try std.testing.expectEqualStrings(expected, buffer.items);
}

const HitTestOptions = struct {
    whatToShow: u8 = 0,
    include_margin: bool = true,
};
pub fn hitTest(self: *Self, viewport_size: Point(f32), position: Point(f32), comptime options: HitTestOptions) ?BoundaryPoint {
    return hitTestInner(self, viewport_size, .{ .pos = .{ .x = 0, .y = 0 }, .size = viewport_size }, 0, .{ .x = 0, .y = 0 }, position, options);
}

fn hitTestInner(
    self: *Self,
    viewport_size: Point(f32),
    mask: Canvas.Rect,
    node_id: Node.NodeId,
    offset: Point(f32),
    hit_position: Point(f32),
    comptime options: HitTestOptions,
) ?BoundaryPoint {
    const layout = self.getLayout(node_id);
    var absolute_position = layout.location.add(offset);
    const style = self.getComputedStyle(node_id);
    const node = self.getNode(node_id);
    const is_scrollable = style.overflow.y == .scroll or style.overflow.x == .scroll or style.overflow.y == .hidden or style.overflow.x == .hidden;
    if (is_scrollable) {
        absolute_position = absolute_position.sub(node.scroll_offset);
    }

    var node_rect = Canvas.Rect{ .pos = absolute_position, .size = layout.size };
    if (comptime options.include_margin) {
        node_rect.pos = node_rect.pos.sub(.{ .x = layout.margin.left, .y = layout.margin.top });
        node_rect.size = node_rect.size.sub(.{ .x = layout.margin.left + layout.margin.right, .y = layout.margin.top + layout.margin.bottom });
    }

    node_rect = node_rect.intersect(mask);

    var hit: ?BoundaryPoint = if (node_rect.isPointWithin(f32, hit_position)) .{ .node_id = node_id, .offset = 0 } else null;

    const is_text_root = style.display.isInlineFlow();
    if (is_text_root) {
        const computed_text = self.getComputedText(node_id) orelse return null;
        for (computed_text.lines.items) |line| {
            const line_position = absolute_position.add(line.position);
            const line_rect = Canvas.Rect{ .pos = line_position, .size = line.size };

            if (!line_rect.isPointWithin(f32, hit_position)) {
                if (hit_position.y > line_rect.pos.y) {
                    if (line.parts.getLastOrNull()) |last_part| {
                        hit = .{ .node_id = last_part.node_id, .offset = @intCast(last_part.node_offset + last_part.length) };
                    } else {
                        hit = .{ .node_id = node_id, .offset = 0 };
                    }
                } else {
                    break;
                }

                continue;
            }

            if (line.parts.items.len == 0) {
                return .{ .node_id = node_id, .offset = 0 };
            }
            const first_part: ComputedText.TextPart = line.parts.items[0];

            const first_part_pos = line_position.add(first_part.position);
            if (hit_position.x < first_part_pos.x) {
                return .{ .node_id = first_part.node_id, .offset = @intCast(first_part.node_offset) };
            }
            const last_part: ComputedText.TextPart = line.parts.items[line.parts.items.len - 1];
            const last_part_pos = line_position.add(last_part.position);
            const last_part_end = last_part_pos.add(.{ .x = last_part.size.x, .y = 0 });
            if (hit_position.x >= last_part_end.x) {
                return .{ .node_id = last_part.node_id, .offset = @intCast(last_part.node_offset + last_part.length) };
            }

            for (line.parts.items) |part| {
                const part_rect = Canvas.Rect{ .pos = line_position.add(part.position), .size = .{
                    .x = part.size.x,
                    .y = line.size.y,
                } };

                if (part_rect.isPointWithin(f32, hit_position)) {
                    hit = .{ .node_id = part.node_id, .offset = @intCast(part.node_offset) };
                    var x: f32 = part_rect.pos.x;

                    if (x >= hit_position.x) {
                        return .{ .node_id = part.node_id, .offset = @intCast(part.node_offset) };
                    }

                    const str = computed_text.slice(part.start, part.start + part.length);
                    var grapheme_iterator = GraphemeIterator.init(str);

                    while (grapheme_iterator.next()) |grapheme| {
                        if (x >= hit_position.x) {
                            return .{ .node_id = part.node_id, .offset = @intCast(part.node_offset + grapheme.offset) };
                        }
                        x += @floatFromInt(visible.width.exclude_ansi_colors.utf8(grapheme.bytes(str)));
                    }

                    return .{ .node_id = part.node_id, .offset = @intCast(part.node_offset + part.length) };
                }
            }
        }
        return hit;
    }

    const children = self.getChildren(node_id);

    for (children.items) |child_id| {
        const child_hit = hitTestInner(
            self,
            viewport_size,
            mask,
            child_id,
            absolute_position,
            hit_position,
            options,
        );
        hit = child_hit orelse hit;
    }

    return hit;
}
fn getBoundaryEnd(tree: *Self, node_id: Node.NodeId) BoundaryPoint {
    const length = tree.getNode(node_id).length();
    return .{ .node_id = node_id, .offset = length };
}
