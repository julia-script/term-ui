const Node = @import("./Node.zig");
const Tree = @import("./Tree.zig");
const std = @import("std");
const Order = std.math.Order;
const BoundaryPoint = @import("./BoundaryPoint.zig");

pub const Id = u32;
id: Id,
start: BoundaryPoint = .{ .node_id = 0, .offset = 0 },
end: BoundaryPoint = .{ .node_id = 0, .offset = 0 },
const Self = @This();

pub const Direction = enum {
    forward,
    backward,
    none,
};
pub fn init(tree: *Tree, id: u32, start: BoundaryPoint, end: BoundaryPoint) !Self {
    var range = Self{ .id = id, .start = start, .end = end };
    try range.validate(tree);
    return range;
}

fn validate(self: *Self, tree: *Tree) !void {
    // Its start and end are in the same node tree.
    if (tree.getNodeRoot(self.start.node_id) != tree.getNodeRoot(self.end.node_id)) {
        return error.NotInTheSameTree;
    }

    // Its start offset is between 0 and its start node's length, inclusive.
    if (self.start.offset > tree.getNode(self.start.node_id).length()) {
        return error.OutOfBounds;
    }
    // Its end offset is between 0 and its end node's length, inclusive.
    if (self.end.offset > tree.getNode(self.end.node_id).length()) {
        return error.OutOfBounds;
    }
    // Its start is before or equal to its end.
    if (try boundaryPointTreeOrder(tree, self.start, self.end) == .gt) {
        return error.StartAfterEnd;
    }
}
pub fn getCommonAncestorContainer(self: *Self, tree: *Tree) !Node.NodeId {
    return tree.getLowestCommonAncestorAndFirstDistinctAncestor(self.start.node_id, self.end.node_id).ancestor orelse error.NotInTheSameTree;
}
/// https://dom.spec.whatwg.org/#dom-range-setstart
pub fn setStart(self: *Self, tree: *Tree, node_id: Node.NodeId, offset: u32) !void {
    // If offset is greater than node's length, then throw an "IndexSizeError" DOMException.
    const node_length = tree.getNode(node_id).length();
    if (offset > node_length) {
        return error.OutOfBounds;
    }

    // Let bp be the boundary point (node, offset).
    const bp = BoundaryPoint{ .node_id = node_id, .offset = offset };
    // If range's root is not equal to node's root
    if (tree.getNodeRoot(node_id) != self.getRoot(tree)) {
        self.end = bp;
    } else if (try boundaryPointTreeOrder(tree, bp, self.end) == .gt) {
        // or if bp is after the range's end, set range's end to bp.
        self.end = bp;
    }
    // Set range's start to bp.
    self.start = bp;
}
/// https://dom.spec.whatwg.org/#dom-range-setend
pub fn setEnd(self: *Self, tree: *Tree, node_id: Node.NodeId, offset: u32) !void {
    // If offset is greater than node's length, then throw an "IndexSizeError" DOMException.
    const node_length = tree.getNode(node_id).length();
    if (offset > node_length) {
        return error.OutOfBounds;
    }

    // Let bp be the boundary point (node, offset).
    const bp = BoundaryPoint{ .node_id = node_id, .offset = offset };
    // If range's root is not equal to node's root
    if (tree.getNodeRoot(node_id) != self.getRoot(tree)) {
        self.start = bp;
        // or if bp is before the range's start, set range's start to bp.
    } else if (try boundaryPointTreeOrder(tree, bp, self.start) == .lt) {
        self.start = bp;
    }
    // Set range's end to bp.
    self.end = bp;
}

pub fn setStartBefore(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {

    // Let parent be node's parent.
    const parent = tree.getNode(node_id).parent orelse return error.InvalidNodeType;
    // If parent is null, then throw an "InvalidNodeTypeError" DOMException.

    // Set the start of this to boundary point (parent, node's index).
    try self.setStart(tree, parent, tree.nodeIndex(node_id) orelse unreachable);
}

pub fn setStartAfter(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {

    // Let parent be node's parent.

    // If parent is null, then throw an "InvalidNodeTypeError" DOMException.
    const parent = tree.getNode(node_id).parent orelse return error.InvalidNodeType;

    // Set the start of this to boundary point (parent, node's index plus 1).
    try self.setStart(tree, parent, (tree.nodeIndex(node_id) orelse unreachable) + 1);
}

pub fn setEndBefore(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {
    // Let parent be node's parent.
    const parent = tree.getNode(node_id).parent orelse return error.InvalidNodeType;

    // Set the end of this to boundary point (parent, node's index).
    try self.setEnd(tree, parent, tree.nodeIndex(node_id) orelse unreachable);
}

pub fn setEndAfter(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {
    // Let parent be node's parent.
    const parent = tree.getNode(node_id).parent orelse return error.InvalidNodeType;

    // Set the end of this to boundary point (parent, node's index plus 1).
    try self.setEnd(tree, parent, (tree.nodeIndex(node_id) orelse unreachable) + 1);
}
pub fn collapse(self: *Self, tree: *Tree, to_start: bool) !void {
    // The collapse(toStart) method steps are to, if toStart is true, set end to start; otherwise set start to end.

    if (to_start) {
        try self.setEnd(tree, self.start.node_id, self.start.offset);
    } else {
        try self.setStart(tree, self.end.node_id, self.end.offset);
    }
}

pub fn isCollapsed(self: Self) bool {
    return self.start.node_id == self.end.node_id and self.start.offset == self.end.offset;
}
/// The root of a live range is the root of its start node.
pub fn getRoot(self: *Self, tree: *Tree) Node.NodeId {
    return tree.getNodeRoot(self.start.node_id);
}
/// https://dom.spec.whatwg.org/#dom-range-selectnode
pub fn selectNode(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {

    // Let parent be node's parent.

    // If parent is null, then throw an "InvalidNodeTypeError" DOMException.
    const parent = tree.getNode(node_id).parent orelse return error.InvalidNodeType;

    // Let index be node's index.
    const index = tree.nodeIndex(node_id) orelse unreachable;
    // Set range's start to boundary point (parent, index).
    try self.setStart(tree, parent, index);

    // Set range's end to boundary point (parent, index plus 1).
    try self.setEnd(tree, parent, index + 1);
}

/// https://dom.spec.whatwg.org/#dom-range-selectnodecontents
pub fn selectNodeContents(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {
    // Let length be the length of node.
    const length = tree.getNode(node_id).length;
    // Set start to the boundary point (node, 0).
    try self.setStart(tree, node_id, 0);
    // Set end to the boundary point (node, length).
    try self.setEnd(tree, node_id, length);
}
pub const CompareBoundariesMode = enum {
    start_to_start,
    start_to_end,
    end_to_start,
    end_to_end,
};
/// The compareBoundaryPoints(how, sourceRange) method steps are:
pub fn compareBoundaryPoints(self: Self, tree: *Tree, how: CompareBoundariesMode, source_range: Self) !Order {
    // If this's root is not the same as sourceRange's root, then throw a "WrongDocumentError" DOMException.
    const this_point, const other_point = switch (how) {
        // Let this point be this's start. Let other point be sourceRange's start.
        .start_to_start => .{ self.start, source_range.start },
        // Let this point be this's end. Let other point be sourceRange's start.
        .start_to_end => .{ self.end, source_range.start },
        // Let this point be this's end. Let other point be sourceRange's end.
        .end_to_end => .{ self.end, source_range.end },
        // Let this point be this's start. Let other point be sourceRange's end.
        .end_to_start => .{ self.start, source_range.end },
    };
    return boundaryPointTreeOrder(tree, this_point, other_point);
}
fn deleteBetweenOffsets(self: *Self, tree: *Tree, node_id: Node.NodeId, start_offset: u32, end_offset: u32) !void {
    _ = self; // autofix
    var node = tree.getNode(node_id);
    switch (tree.getNodeKind(node_id)) {
        .text => {
            try node.replaceData(tree, start_offset, end_offset - start_offset, "");
        },
        else => {
            for (node.children.items[start_offset..end_offset]) |child_id| {
                try tree.removeChild(node_id, child_id);
            }
            // try node.children.replaceRange(tree.allocator, start_offset, end_offset - start_offset, &[_]Node.NodeId{});
        },
    }
}

fn traverseNodeAndCollect(self: *Self, tree: *Tree, node_id: Node.NodeId, nodes_to_remove: *std.AutoArrayHashMap(Node.NodeId, void)) !void {
    // Check if this node is contained in the range
    if (try self.containsNode(tree, node_id)) {
        // Skip if any ancestor is already in the removal list
        var has_contained_ancestor = false;
        var current = node_id;

        while (tree.getParent(current)) |parent| {
            if (nodes_to_remove.contains(parent)) {
                has_contained_ancestor = true;
                break;
            }
            current = parent;
        }

        if (!has_contained_ancestor) {
            try nodes_to_remove.put(node_id, {});
        }

        // Since this node is fully contained, we don't need to process its children
        return;
    }

    // If the node isn't contained, process its children in tree order
    const node = tree.getNode(node_id);
    for (node.children.items) |child_id| {
        try traverseNodeAndCollect(self, tree, child_id, nodes_to_remove);
    }
}

// this is a version of the function above without recursion..might be handy if we have deep trees but I think it's unlikely it will become a problem
// I prefer the recursive version above cause it's easier to understand and to avoid allocating a stack
// fn collectNodesToRemove(self: *Self, tree: *Tree, nodes_to_remove: *std.AutoArrayHashMap(Node.NodeId, void), lca: Tree.LCA) !void {
//     // Get the LCA (lowest common ancestor)
//     const common_ancestor = lca.ancestor orelse return;

//     // Start from common ancestor and traverse in tree order
//     var to_visit = std.ArrayList(Node.NodeId).init(tree.allocator);
//     defer to_visit.deinit();

//     // Start with the common ancestor's children
//     try to_visit.append(common_ancestor);

//     while (to_visit.items.len > 0) {
//         const node_id = to_visit.pop() orelse break;

//         // Check if this node is contained in the range
//         if (try self.containsNode(tree, node_id)) {
//             // Skip if any ancestor is already in the removal list
//             var has_contained_ancestor = false;
//             var current = node_id;

//             while (tree.getParent(current)) |parent| {
//                 if (nodes_to_remove.contains(parent)) {
//                     has_contained_ancestor = true;
//                     break;
//                 }
//                 current = parent;
//             }

//             if (!has_contained_ancestor) {
//                 try nodes_to_remove.put(node_id, {});
//             }
//         } else {
//             // If not contained, check its children (in reverse order to maintain tree order when popped)
//             const node = tree.getNode(node_id);
//             var i = node.children.items.len;
//             while (i > 0) {
//                 i -= 1;
//                 try to_visit.append(node.children.items[i]);
//             }
//         }
//     }
// }

pub fn deleteContents(self: *Self, tree: *Tree) !void {
    // Step 1: If range is collapsed, return
    if (self.isCollapsed()) {
        return;
    }

    // Step 2: Get original boundary points
    const original_start_node = self.start.node_id;
    const original_start_offset = self.start.offset;
    const original_end_node = self.end.node_id;
    const original_end_offset = self.end.offset;

    // Step 3: If start and end are in same character data node
    if (original_start_node == original_end_node) {
        try deleteBetweenOffsets(
            self,
            tree,
            original_start_node,
            original_start_offset,
            original_end_offset,
        );

        // Collapse range
        self.end = self.start;
        return;
    }

    // Get LCA and relationship information
    const lca = tree.getLowestCommonAncestorAndFirstDistinctAncestor(original_start_node, original_end_node);

    // Step 4: Collect nodes to remove
    var nodes_to_remove = std.AutoArrayHashMap(Node.NodeId, void).init(tree.allocator);
    defer nodes_to_remove.deinit();

    // Collect all nodes contained in the range
    try traverseNodeAndCollect(self, tree, lca.ancestor.?, &nodes_to_remove);

    // Steps 5-6: Determine new node and offset based on ancestral relationship
    var new_node: Node.NodeId = undefined;
    var new_offset: u32 = undefined;

    // Add debug output to see ancestral relationships

    if (lca.distinct_a_child == null) {
        // Step 5: start node is an inclusive ancestor of end node
        new_node = original_start_node;
        new_offset = original_start_offset;
    } else {
        // Step 6: Otherwise
        const reference_node = lca.distinct_a_child.?;

        // Set new node to the parent of reference node
        new_node = lca.ancestor.?;

        // Get index of reference_node and check if it's valid
        const index_opt = tree.nodeIndex(reference_node);
        if (index_opt) |index| {
            new_offset = @intCast(index + 1);
        } else {
            // Handle the case where nodeIndex returns null
            new_offset = 0; // Default to 0 if index is not found
        }
    }
    // Step 7: If original start node is a CharacterData node
    if (tree.getNodeKind(original_start_node) == .text) {
        try deleteBetweenOffsets(
            self,
            tree,
            original_start_node,
            original_start_offset,
            @intCast(tree.getNode(original_start_node).length()),
        );
    }

    // Step 8: Remove each node in nodes to remove
    for (nodes_to_remove.keys()) |node_id| {
        try tree.removeNode(node_id);
    }

    // Step 9: If original end node is a CharacterData node
    if (tree.getNodeKind(original_end_node) == .text) {
        try deleteBetweenOffsets(
            self,
            tree,
            original_end_node,
            0,
            original_end_offset,
        );
    }

    // Step 10: Set start and end to (new node, new offset)
    self.start.node_id = new_node;
    self.start.offset = new_offset;
    self.end = self.start;
}
/// A node node is contained in a live range range if node's root is range's root, and (node, 0) is after range's start, and (node, node's length) is before range's end.
pub fn containsNode(self: *Self, tree: *Tree, node_id: Node.NodeId) !bool {
    if (tree.getNodeRoot(node_id) != self.getRoot(tree)) {
        return false;
    }
    const node_length = tree.getNode(node_id).length();
    const start_order = try boundaryPointTreeOrder(tree, self.start, BoundaryPoint{ .node_id = node_id, .offset = 0 });
    const end_order = try boundaryPointTreeOrder(tree, self.end, BoundaryPoint{ .node_id = node_id, .offset = @intCast(node_length) });
    return start_order == .lt and end_order == .gt;
}
/// A node is partially contained in a live range if it's an inclusive ancestor of the live range's start node but not its end node, or vice versa.
pub fn partiallyContainsNode(self: *Self, tree: *Tree, node_id: Node.NodeId) !bool {
    // Check if the node's root is the range's root
    if (tree.getNodeRoot(node_id) != self.getRoot(tree)) {
        return false;
    }

    // Check if node_id is an inclusive ancestor of start.node_id
    const is_inclusive_ancestor_of_start = (node_id == self.start.node_id) or tree.isNodeAncestor(node_id, self.start.node_id);

    // Check if node_id is an inclusive ancestor of end.node_id
    const is_inclusive_ancestor_of_end = (node_id == self.end.node_id) or tree.isNodeAncestor(node_id, self.end.node_id);

    // Node partially contains the range if it's an inclusive ancestor of one endpoint but not the other
    return (is_inclusive_ancestor_of_start and !is_inclusive_ancestor_of_end) or
        (!is_inclusive_ancestor_of_start and is_inclusive_ancestor_of_end);
}
pub fn insertNode(self: *Self, tree: *Tree, node_id: Node.NodeId) !void {
    //  1.  If range's [start node](#concept-range-start-node) is a `[ProcessingInstruction](#processinginstruction)` or `[Comment](#comment)` [node](#concept-node), is a `[Text](#text)` [node](#concept-node) whose [parent](#concept-tree-parent) is null, or is node, then [throw](https://webidl.spec.whatwg.org/#dfn-throw) a "`[HierarchyRequestError](https://webidl.spec.whatwg.org/#hierarchyrequesterror)`" `[DOMException](https://webidl.spec.whatwg.org/#idl-DOMException)`.
    const start_node = tree.getNode(self.start.node_id);
    if ((start_node.kind == .text and start_node.parent == null) or
        self.start.node_id == node_id)
    {
        return error.HierarchyRequestError;
    }

    // 2.  Let referenceNode be null.
    var reference_node: ?Node.NodeId = null;

    // 3.  If range's [start node](#concept-range-start-node) is a `[Text](#text)` [node](#concept-node), set referenceNode to that `[Text](#text)` [node](#concept-node).
    if (start_node.kind == .text) {
        reference_node = self.start.node_id;
    } else if (start_node.children.items.len > self.start.offset) {
        // 4.  Otherwise, set referenceNode to the [child](#concept-tree-child) of [start node](#concept-range-start-node) whose [index](#concept-tree-index) is [start offset](#concept-range-start-offset), and null if there is no such [child](#concept-tree-child).
        reference_node = start_node.children.items[self.start.offset];
    }

    // 5.  Let parent be range's [start node](#concept-range-start-node) if referenceNode is null, and referenceNode's [parent](#concept-tree-parent) otherwise.
    const parent = if (reference_node) |reference_node_id|
        tree.getParent(reference_node_id) orelse return error.InvalidState
    else
        self.start.node_id;

    // 6.  [Ensure pre-insert validity](#concept-node-ensure-pre-insertion-validity) of node into parent before referenceNode.
    try ensurePreInsertValidity(tree, node_id, parent, reference_node);

    // 7.  If range's [start node](#concept-range-start-node) is a `[Text](#text)` [node](#concept-node), set referenceNode to the result of [splitting](#concept-text-split) it with offset range's [start offset](#concept-range-start-offset).
    if (start_node.kind == .text) {
        reference_node = try tree.splitTextNode(self.start.node_id, self.start.offset);
    }

    // 8.  If node is referenceNode, set referenceNode to its [next sibling](#concept-tree-next-sibling).
    if (node_id == reference_node) {
        reference_node = tree.nextSibling(node_id);
    }

    // 9.  If node's [parent](#concept-tree-parent) is non-null, then [remove](#concept-node-remove) node.
    if (tree.getParent(node_id) != null) {
        try tree.removeNode(node_id);
    }

    // 10.  Let newOffset be parent's [length](#concept-node-length) if referenceNode is null; otherwise referenceNode's [index](#concept-tree-index).
    var new_offset: u32 = undefined;
    if (reference_node) |reference_node_id| {
        new_offset = @intCast(tree.nodeIndex(reference_node_id) orelse return error.InvalidState);
    } else {
        new_offset = @intCast(tree.getNode(parent).length());
    }

    // 11.  Increase newOffset by node's [length](#concept-node-length) if node is a `[DocumentFragment](#documentfragment)` [node](#concept-node); otherwise 1.
    const node = tree.getNode(node_id);
    _ = node; // autofix
    // Will be implemented when document fragments are added
    // if (node.kind == .document_fragment) {
    //     new_offset += node.length();
    // } else {
    new_offset += 1;
    // }

    // 12.  [Pre-insert](#concept-node-pre-insert) node into parent before referenceNode.
    _ = try tree.insertBefore(parent, node_id, reference_node);

    // 13.  If range is [collapsed](#range-collapsed), then set range's [end](#concept-range-end) to (parent, newOffset).
    if (self.isCollapsed()) {
        self.end = BoundaryPoint{ .node_id = parent, .offset = new_offset };
    }
}

// // Helper function to implement the pre-insert operation
// fn preInsert(tree: *Tree, node: Node.NodeId, parent: Node.NodeId, child: ?Node.NodeId) !Node.NodeId {
//     // 1. Ensure pre-insert validity of node into parent before child.
//     try ensurePreInsertValidity(tree, node, parent, child);

//     // 2. Let referenceChild be child.
//     var reference_child = child;

//     // 3. If referenceChild is node, then set referenceChild to node's next sibling.
//     if (reference_child != null and reference_child.? == node) {
//         reference_child = tree.nextSibling(node);
//     }

//     // 4. Insert node into parent before referenceChild.
//     if (reference_child) |ref_child| {
//         _ = try tree.insertBefore(parent, node, ref_child);
//     } else {
//         try tree.appendChild(parent, node);
//     }

//     // 5. Return node.
//     return node;
// }

// Helper function to implement ensure pre-insert validity
fn ensurePreInsertValidity(tree: *Tree, node: Node.NodeId, parent: Node.NodeId, child: ?Node.NodeId) !void {
    const parent_node = tree.getNode(parent);
    const node_kind = tree.getNode(node).kind;

    // 1. If parent is not a Document, DocumentFragment, or Element node, throw "HierarchyRequestError"
    if (parent_node.kind != .node) {
        // Adjust as needed if you add document or document fragment support
        return error.HierarchyRequestError;
    }

    // 2. If node is a host-including inclusive ancestor of parent, throw "HierarchyRequestError"
    if (tree.isNodeAncestor(node, parent)) {
        return error.HierarchyRequestError;
    }

    // 3. If child is non-null and its parent is not parent, throw "NotFoundError"
    if (child != null and tree.getParent(child.?) != parent) {
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
test "insertNode" {
    // W3C spec examples: <P>Abcd efgh XY blah ijkl</P> with range from Y to i

    // Test 1: Insert before the 'X' (at position 10)
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode(); // Represents <P>
        const text = try tree.createTextNode("Abcd efgh XY blah ijkl");
        _ = try tree.appendChild(root, text);

        const range_id = try tree.createLiveRange(.{
            .node_id = text,
            .offset = 11, // Position of Y
        }, .{
            .node_id = text,
            .offset = 19, // Position after i
        });
        var range = tree.getLiveRange(range_id);

        try range.testRange(&tree, root, "<element#1><text#2>'Abcd efgh X[Y blah i]jkl'</text#2></element#1>");

        // Insert before X (at position 10)
        const insert_text = try tree.createTextNode("inserted text");
        try range.setStart(&tree, text, 10); // Position before 'X'
        try range.insertNode(&tree, insert_text);

        try range.testRange(&tree, root, "<element#1><text#2>'Abcd efgh ['</text#2><text#3>'inserted text'</text#3><text#4>'XY blah i]jkl'</text#4></element#1>");
    }

    // Test 2: Insert at start of range (after X)
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const text = try tree.createTextNode("Abcd efgh XY blah ijkl");
        _ = try tree.appendChild(root, text);

        const range_id = try tree.createLiveRange(.{
            .node_id = text,
            .offset = 11, // Position of Y (start of range)
        }, .{
            .node_id = text,
            .offset = 19, // Position after i (end of range)
        });
        var range = tree.getLiveRange(range_id);

        const insert_text = try tree.createTextNode("inserted text");
        try range.insertNode(&tree, insert_text);

        try range.testRange(&tree, root, "<element#1><text#2>'Abcd efgh X['</text#2><text#3>'inserted text'</text#3><text#4>'Y blah i]jkl'</text#4></element#1>");
    }

    // Test 3: Insert after Y
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const text = try tree.createTextNode("Abcd efgh XY blah ijkl");
        _ = try tree.appendChild(root, text);

        const range_id = try tree.createLiveRange(.{
            .node_id = text,
            .offset = 11, // Position of Y
        }, .{
            .node_id = text,
            .offset = 19, // Position after i
        });
        var range = tree.getLiveRange(range_id);

        try range.setStart(&tree, text, 12); // Position after 'Y'
        const insert_text = try tree.createTextNode("inserted text");
        try range.insertNode(&tree, insert_text);

        try range.testRange(&tree, root, "<element#1><text#2>'Abcd efgh XY['</text#2><text#3>'inserted text'</text#3><text#4>' blah i]jkl'</text#4></element#1>");
    }
}
pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;
    try writer.print("Self({}, {})", .{ self.start, self.end });
}
const FormatTreeOptions = struct {
    collapsed_caret: []const u8 = "\x1b[31m|\x1b[0m",
    range_open: []const u8 = "\x1b[7m",
    range_close: []const u8 = "\x1b[0m",
};
pub fn formatTreeInner(self: *Self, tree: *Tree, node_id: Node.NodeId, writer: std.io.AnyWriter, comptime options: FormatTreeOptions) !void {
    const node = tree.getNode(node_id);
    const is_collapsed = self.isCollapsed();
    const range_open = options.range_open;
    const range_close = options.range_close;
    const collapsed_caret = options.collapsed_caret;

    switch (node.kind) {
        .text => {
            try writer.print("<text#{d}>", .{node_id});
            const bytes = tree.getText(node_id).bytes.items;

            if (is_collapsed and node_id == self.start.node_id) {
                // For collapsed ranges in text nodes, insert caret at the offset
                // if (self.start.offset == 0) {
                //     try writer.print("\x1b[31m|\x1b[0m{s}", .{bytes}); // Red caret at beginning
                // } else if (self.start.offset >= bytes.len) {
                //     try writer.print("{s}\x1b[31m|\x1b[0m", .{bytes}); // Red caret at end
                // } else {
                // Caret in the middle of text
                try writer.print("'{s}" ++ collapsed_caret ++ "{s}'", .{ bytes[0..self.start.offset], bytes[self.start.offset..] });
                // }
            } else if (!is_collapsed and node_id == self.start.node_id and self.end.node_id == node_id) {
                try writer.print("'{s}", .{bytes[0..self.start.offset]});
                try writer.print(range_open ++ "{s}" ++ range_close, .{bytes[self.start.offset..self.end.offset]});
                try writer.print("{s}'", .{bytes[self.end.offset..]});
            } else if (!is_collapsed and node_id == self.start.node_id) {
                try writer.print("'{s}" ++ range_open ++ "{s}'", .{ bytes[0..self.start.offset], bytes[self.start.offset..bytes.len] });
            } else if (!is_collapsed and node_id == self.end.node_id) {
                try writer.print("'{s}" ++ range_close ++ "{s}'", .{ bytes[0..self.end.offset], bytes[self.end.offset..] });
            } else {
                try writer.print("'{s}'", .{bytes});
            }
            try writer.print("</text#{d}>", .{node_id});
        },
        else => {
            if (is_collapsed and node_id == self.start.node_id) {
                // For collapsed ranges in element nodes
                try writer.print("<element#{d}>", .{node_id});

                if (node.children.items.len > 0) {
                    var caret_shown = false;

                    // Insert caret at the appropriate offset between children
                    for (node.children.items, 0..) |child_id, i| {
                        if (i == self.start.offset and !caret_shown) {
                            try writer.print(collapsed_caret, .{}); // Red caret
                            caret_shown = true;
                        }

                        try self.formatTreeInner(tree, child_id, writer, options);
                    }

                    // Handle case where caret is after all children
                    if (self.start.offset >= node.children.items.len) {
                        try writer.print(collapsed_caret, .{});
                    }
                } else if (self.start.offset == 0) {
                    // Empty node with caret
                    try writer.print(collapsed_caret, .{});
                }

                try writer.print("</element#{d}>", .{node_id});
            } else if (!is_collapsed and node_id == self.start.node_id and self.start.offset == 0) {
                try writer.writeAll(range_open);
                if (node.children.items.len > 0) {
                    try writer.print("<element#{d}>", .{node_id});
                    for (node.children.items, 0..) |child_id, i| {
                        if (!is_collapsed and i > 0 and node_id == self.start.node_id and i == self.start.offset) {
                            try writer.writeAll(range_open);
                        }
                        try self.formatTreeInner(tree, child_id, writer, options);
                        if (!is_collapsed and i < node.children.items.len - 1 and node_id == self.end.node_id and i == self.end.offset) {
                            try writer.writeAll(range_close);
                        }
                    }
                    try writer.print("</element#{d}>", .{node_id});
                } else {
                    try writer.print("<element#{d}/>", .{node_id});
                }
                if (!is_collapsed and node_id == self.end.node_id and self.end.offset >= node.length() - 1) {
                    try writer.writeAll(range_close);
                }
            } else {
                if (node.children.items.len > 0) {
                    try writer.print("<element#{d}>", .{node_id});
                    for (node.children.items, 0..) |child_id, i| {
                        if (!is_collapsed and i > 0 and node_id == self.start.node_id and i == self.start.offset) {
                            try writer.writeAll(range_open);
                        }
                        try self.formatTreeInner(tree, child_id, writer, options);
                        if (!is_collapsed and i < node.children.items.len - 1 and node_id == self.end.node_id and i == self.end.offset) {
                            try writer.writeAll(range_close);
                        }
                    }
                    try writer.print("</element#{d}>", .{node_id});
                } else {
                    try writer.print("<element#{d}/>", .{node_id});
                }
                if (!is_collapsed and node_id == self.end.node_id and self.end.offset >= node.length() - 1) {
                    try writer.writeAll(range_close);
                }
            }
        },
    }
}
pub fn formatTree(self: *Self, tree: *Tree, node_id: Node.NodeId, writer: std.io.AnyWriter, comptime options: FormatTreeOptions) !void {
    try self.formatTreeInner(tree, node_id, writer, options);
    try writer.writeAll("\n");
}
fn testRange(range: *Self, tree: *Tree, node_id: Node.NodeId, expected: []const u8) !void {
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();
    const writer = buffer.writer();

    try range.formatTreeInner(tree, node_id, writer.any(), .{
        .collapsed_caret = "|",
        .range_open = "[",
        .range_close = "]",
    });
    try std.testing.expectEqualStrings(
        expected,
        buffer.items,
    );
}

fn order(T: type, a: T, b: T) Order {
    if (a < b) {
        return .lt;
    } else if (a > b) {
        return .gt;
    }
    return .eq;
}
pub fn boundaryPointTreeOrder(tree: *Tree, boundary_point: BoundaryPoint, other: BoundaryPoint) !Order {
    // 1. Assert: same root
    if (tree.getNodeRoot(boundary_point.node_id) != tree.getNodeRoot(other.node_id)) {
        return error.NotInTheSameTree;
    }

    // 2. Same node case - compare offsets
    if (boundary_point.node_id == other.node_id) {
        return order(usize, boundary_point.offset, other.offset);
    }

    // return try tree.treeOrder(boundary_point.node_id, other.node_id);
    // 3. If nodeA is following nodeB in tree order
    const lca = tree.getLowestCommonAncestorAndFirstDistinctAncestor(boundary_point.node_id, other.node_id);
    if (lca.distinct_a_child != null and lca.distinct_b_child != null) {
        const distinct_a_child_index = tree.nodeIndex(lca.distinct_a_child.?) orelse 0;
        const distinct_b_child_index = tree.nodeIndex(lca.distinct_b_child.?) orelse 0;

        return order(usize, distinct_a_child_index, distinct_b_child_index);
    }

    // If nodeA is ancestor of nodeB
    if (lca.distinct_b_child) |distinct_b_child| {
        const distinct_b_child_index = tree.nodeIndex(distinct_b_child) orelse 0;
        if (distinct_b_child_index < boundary_point.offset) {
            return .gt;
        }
        return .lt;
    }

    // // If nodeB is ancestor of nodeA
    if (lca.distinct_a_child) |distinct_a_child| {
        const distinct_a_child_index = tree.nodeIndex(distinct_a_child) orelse 0;
        if (distinct_a_child_index < other.offset) {
            return .lt;
        }
        return .gt;
    }

    std.debug.panic("Shouldn't happen", .{});
}
test "boundaryPointTreeOrder - comprehensive" {
    var tree = try Tree.init(std.testing.allocator);
    defer tree.deinit();

    //                     root 0
    //                   /      \
    //              child_a 1     child_b 5
    //             /  |            \
    //    text_a_a 2  child_a_b 3      text_b_b 6
    //                |
    //            text_a_b_a 4

    // Create the base structure
    const root = try tree.createNode();
    const child_a = try tree.createNode();
    const text_a_a = try tree.createTextNode("First text node");
    const child_a_b = try tree.createNode();
    const text_a_b_a = try tree.createTextNode("Second text node");
    const child_b = try tree.createNode();
    const text_b_b = try tree.createTextNode("Third text node");

    _ = try tree.appendChild(root, child_a);
    std.debug.assert(tree.nodeIndex(root) == null);

    // Create text nodes and regular nodes
    _ = try tree.appendChild(child_a, text_a_a);
    _ = try tree.appendChild(child_a, child_a_b);

    std.debug.assert(tree.nodeIndex(text_a_a) == 0);
    std.debug.assert(tree.nodeIndex(child_a_b) == 1);

    _ = try tree.appendChild(child_a_b, text_a_b_a);
    std.debug.assert(tree.nodeIndex(text_a_b_a) == 0);

    _ = try tree.appendChild(root, child_b);
    _ = try tree.appendChild(child_b, text_b_b);

    // Create a separate tree for testing error cases
    const other_root = try tree.createNode();
    const other_child = try tree.createTextNode("Text in other tree");
    _ = try tree.appendChild(other_root, other_child);

    // 1. Test same node, different offsets (step 2)
    {
        // Test same node, before
        const bp1 = BoundaryPoint{ .node_id = text_a_a, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = text_a_a, .offset = 1 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp2, bp1), .gt);
    }

    // 2. Test one node following another in tree order (step 3)
    {
        const bp1 = BoundaryPoint{ .node_id = child_a, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = child_a_b, .offset = 0 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp2, bp1), .gt);
    }

    // 3. Test one node being an ancestor of another (step 4)
    {
        // nodeA is ancestor of nodeB and child index < offsetA
        const bp1 = BoundaryPoint{ .node_id = child_a, .offset = 1 };
        const bp2 = BoundaryPoint{ .node_id = text_a_a, .offset = 3 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .gt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp2, bp1), .lt);
    }

    {
        // nodeA is ancestor of nodeB and child index >= offsetA
        const bp1 = BoundaryPoint{ .node_id = child_a, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = text_a_b_a, .offset = 4 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp2, bp1), .gt);
    }
    //     // Root as ancestor
    {
        const bp1 = BoundaryPoint{ .node_id = root, .offset = 1 };
        const bp2 = BoundaryPoint{ .node_id = child_b, .offset = 0 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
    }

    {
        const bp1 = BoundaryPoint{ .node_id = root, .offset = 2 };
        const bp2 = BoundaryPoint{ .node_id = child_b, .offset = 0 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .gt);
    }

    // // 4. Test nodes in different branches (step 5 - default case)
    {
        // nodes in different branches where neither is ancestor of the other
        const bp1 = BoundaryPoint{ .node_id = text_a_a, .offset = 5 };
        const bp2 = BoundaryPoint{ .node_id = text_b_b, .offset = 2 };
        const ord = try boundaryPointTreeOrder(&tree, bp1, bp2);

        try std.testing.expectEqual(ord, .lt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp2, bp1), .gt);
    }

    // 5. Test error case - nodes not in same tree
    {
        const bp1 = BoundaryPoint{ .node_id = root, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = other_root, .offset = 0 };
        try std.testing.expectError(error.NotInTheSameTree, boundaryPointTreeOrder(&tree, bp1, bp2));
    }

    // // 6. Test complex scenario with deeply nested nodes
    {
        const bp1 = BoundaryPoint{ .node_id = root, .offset = 1 };
        const bp2 = BoundaryPoint{ .node_id = text_a_b_a, .offset = 5 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .gt);
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp2, bp1), .lt);
    }
    {
        const bp1 = BoundaryPoint{ .node_id = child_a_b, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = text_a_b_a, .offset = 10 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
    }

    // 7. Test with text node offsets representing positions in the text
    const text_content = tree.getText(text_a_a);
    const text_length = text_content.length();
    {
        const bp1 = BoundaryPoint{ .node_id = text_a_a, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = text_a_a, .offset = 2 };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
    }
    {
        const bp1 = BoundaryPoint{ .node_id = child_a, .offset = 0 };
        const bp2 = BoundaryPoint{ .node_id = text_a_a, .offset = @intCast(text_length / 2) };
        try std.testing.expectEqual(try boundaryPointTreeOrder(&tree, bp1, bp2), .lt);
    }
}
test "deleteContents" {
    // Test 1: Delete within a text node
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const hello = "Hello";
        const world = ", world!";
        const text = try tree.createTextNode(hello ++ world);
        _ = try tree.appendChild(root, text);
        const range_id = try tree.createLiveRange(.{
            .node_id = text,
            .offset = hello.len,
        }, .{
            .node_id = text,
            .offset = hello.len + world.len,
        });
        var range = tree.getLiveRange(range_id);
        try range.testRange(&tree, root, "<element#1><text#2>'Hello[, world!]'</text#2></element#1>");
        try range.deleteContents(&tree);
        try range.testRange(&tree, root, "<element#1><text#2>'Hello|'</text#2></element#1>");
    }

    // Test 2: Delete across multiple nodes
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();

        const node1 = try tree.createTextNode("First node");
        const node2 = try tree.createTextNode("Second node");
        const node3 = try tree.createTextNode("Third node");
        _ = try tree.appendChild(root, node1);
        _ = try tree.appendChild(root, node2);
        _ = try tree.appendChild(root, node3);

        // Delete from middle of first node to middle of third node
        const range_id = try tree.createLiveRange(.{
            .node_id = node1,
            .offset = 6, // "First [node"
        }, .{
            .node_id = node3,
            .offset = 5, // "Third" ]
        });
        var range = tree.getLiveRange(range_id);

        try range.testRange(&tree, root, "<element#1><text#2>'First [node'</text#2><text#3>'Second node'</text#3><text#4>'Third] node'</text#4></element#1>");
        try range.deleteContents(&tree);
        try range.testRange(&tree, root, "<element#1><text#2>'First '</text#2>|<text#4>' node'</text#4></element#1>");
    }

    // Test 3: Delete where start node is ancestor of end node
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const parent = try tree.createNode();
        const child1 = try tree.createTextNode("Child one");
        const child2 = try tree.createTextNode("Child two");
        _ = try tree.appendChild(root, parent);
        _ = try tree.appendChild(parent, child1);
        _ = try tree.appendChild(parent, child2);

        // Delete from parent (after child1) to middle of child2
        const range_id = try tree.createLiveRange(.{
            .node_id = parent,
            .offset = 1, // After child1
        }, .{
            .node_id = child2,
            .offset = 5, // "Child" ]
        });
        var range = tree.getLiveRange(range_id);
        try range.testRange(&tree, root, "<element#1><element#2><text#3>'Child one'</text#3>[<text#4>'Child] two'</text#4></element#2></element#1>");
        try range.deleteContents(&tree);
        try range.testRange(&tree, root, "<element#1><element#2><text#3>'Child one'</text#3>|<text#4>' two'</text#4></element#2></element#1>");
    }

    // Test 4: Delete where end node is ancestor of start node
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const parent = try tree.createNode();
        const child1 = try tree.createTextNode("Child one");
        const child2 = try tree.createTextNode("Child two");
        _ = try tree.appendChild(root, parent);
        _ = try tree.appendChild(parent, child1);
        _ = try tree.appendChild(parent, child2);

        // Delete from middle of child1 to parent (after child1)
        const range_id = try tree.createLiveRange(.{
            .node_id = child1,
            .offset = 6, // "Child " [one
        }, .{
            .node_id = parent,
            .offset = 2, // After child1 and child2
        });
        var range = tree.getLiveRange(range_id);
        try range.testRange(&tree, root, "<element#1><element#2><text#3>'Child [one'</text#3><text#4>'Child two'</text#4></element#2>]</element#1>");
        try range.deleteContents(&tree);
        try range.testRange(&tree, root, "<element#1><element#2><text#3>'Child '</text#3>|</element#2></element#1>");
    }

    // Test 5: Complex case with nodes in different branches
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const branch1 = try tree.createNode();
        const branch2 = try tree.createNode();
        const leaf1 = try tree.createTextNode("Leaf one");
        const leaf2 = try tree.createTextNode("Leaf two");
        _ = try tree.appendChild(root, branch1);
        _ = try tree.appendChild(root, branch2);
        _ = try tree.appendChild(branch1, leaf1);
        _ = try tree.appendChild(branch2, leaf2);

        // Delete from middle of leaf1 to middle of leaf2
        const range_id = try tree.createLiveRange(.{
            .node_id = leaf1,
            .offset = 5, // "Leaf " [one
        }, .{
            .node_id = leaf2,
            .offset = 5, // "Leaf " [two
        });
        var range = tree.getLiveRange(range_id);
        try range.testRange(&tree, root, "<element#1><element#2><text#4>'Leaf [one'</text#4></element#2><element#3><text#5>'Leaf ]two'</text#5></element#3></element#1>");
        try range.deleteContents(&tree);
        try range.testRange(&tree, root, "<element#1><element#2><text#4>'Leaf '</text#4></element#2>|<element#3><text#5>'two'</text#5></element#3></element#1>");
    }

    // Test 6: Empty range (collapsed)
    {
        var tree = try Tree.init(std.testing.allocator);
        defer tree.deinit();
        const root = try tree.createNode();
        const text = try tree.createTextNode("Test text");
        _ = try tree.appendChild(root, text);

        // Create collapsed range
        const range_id = try tree.createLiveRange(.{
            .node_id = text,
            .offset = 5,
        }, .{
            .node_id = text,
            .offset = 5,
        });
        var range = tree.getLiveRange(range_id);
        try range.testRange(&tree, root, "<element#1><text#2>'Test |text'</text#2></element#1>");
        try range.deleteContents(&tree);
        try range.testRange(&tree, root, "<element#1><text#2>'Test |text'</text#2></element#1>");
    }
}
