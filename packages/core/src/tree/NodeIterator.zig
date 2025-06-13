const Node = @import("./Node.zig");
const Tree = @import("./Tree.zig");
const traversal = @import("./traversal.zig");
const std = @import("std");
const docFromXml = @import("../layout/v2/doc-from-xml.zig").docFromXml;

tree: *Tree,
reference_node: Node.NodeId,
pointer_before_reference_node: bool = false,
what_to_show: u32 = whatToShow.SHOW_ALL,
// filter: ?NodeFilter,

pub const whatToShow = struct {
    pub const SHOW_ALL: u32 = 0xFFFFFFFF;
    pub const SHOW_ELEMENT: u32 = 1;

    // pub const SHOW_ATTRIBUTE: u32 = 2; (not applicable)

    pub const SHOW_TEXT: u32 = 4;
    // pub const SHOW_CDATA_SECTION: u32 = 8; (not applicable)
    // pub const SHOW_PROCESSING_INSTRUCTION: u32 = 64; (not applicable)
    // pub const SHOW_COMMENT: u32 = 128; (not applicable)
    // pub const SHOW_DOCUMENT: u32 = 256; (not applicable)

    // pub const SHOW_DOCUMENT_FRAGMENT: u32 = 1024; (FIXME: not implemented)
};
const NodeFilter = enum(u32) {
    accept = 1,
    reject = 2,
    skip = 3,
    pub fn acceptNode(tree: *Tree, node_id: Node.NodeId, what_to_show: u32) NodeFilter {
        switch (tree.getNodeKind(node_id)) {
            .element => {
                if (what_to_show & whatToShow.SHOW_ELEMENT != 0) {
                    return .accept;
                }
                return .skip;
            },
            .text => {
                if (what_to_show & whatToShow.SHOW_TEXT != 0) {
                    return .accept;
                }
                return .skip;
            },
        }
        return .skip;
    }
};
const Self = @This();

pub const FilterResult = enum(u32) {
    accept = 1,
    reject = 2,
    skip = 3,
};

fn filterNode(self: *Self, node_id: Node.NodeId) FilterResult {
    // Apply what_to_show filter
    const kind = self.tree.getNodeKind(node_id);
    switch (kind) {
        .node => {
            if ((self.what_to_show & whatToShow.SHOW_ELEMENT) != 0) {
                return .accept;
            }
            return .reject;
        },
        .text => {
            if ((self.what_to_show & whatToShow.SHOW_TEXT) != 0) {
                return .accept;
            }
            return .reject;
        },
        // Add other node types as needed
    }

    // if (!show) return .reject;

    // Apply custom filter if provided
    // if (self.filter) |filter| {
    //     return filter.acceptNode(self.tree, node_id);
    // }

}

pub fn offsetNode(self: *Self, comptime forward: bool) ?Node.NodeId {
    // 1. Let node be iterator's reference
    var node_id = self.reference_node;

    // 2. Let beforeNode be iterator's pointer before reference
    var before_node = self.pointer_before_reference_node;

    // 3. While true:
    while (true) {
        // 3.1. Branch on direction
        if (comptime forward) {
            // next
            if (before_node == false) {
                // If beforeNode is false, set node to the first node following node
                // in iterator's iterator collection. If there is no such node, return null.
                node_id = traversal.nextNode(self.tree, node_id) orelse return null;
            } else {
                // If beforeNode is true, then set it to false.
                before_node = false;
            }
        } else {
            // previous
            if (before_node == true) {
                // If beforeNode is true, set node to the first node preceding node
                // in iterator's iterator collection. If there is no such node, return null.
                node_id = traversal.previousNode(self.tree, node_id) orelse return null;
            } else {
                // If beforeNode is false, then set it to true.
                before_node = true;
            }
        }

        // 3.2. Let result be the result of filtering node within iterator.
        const result = self.filterNode(node_id);

        // 3.3. If result is FILTER_ACCEPT, then break.
        if (result == .accept) {
            break;
        }
        // For FILTER_REJECT and FILTER_SKIP, we continue the loop
    }

    // 4. Set iterator's reference to node.
    self.reference_node = node_id;

    // 5. Set iterator's pointer before reference to beforeNode.
    self.pointer_before_reference_node = before_node;

    // 6. Return node.
    return node_id;
}

pub fn nextNode(self: *Self) ?Node.NodeId {
    return self.offsetNode(true);
}

pub fn previousNode(self: *Self) ?Node.NodeId {
    return self.offsetNode(false);
}

test "NodeIterator" {
    const allocator = std.testing.allocator;
    var tree = try docFromXml(allocator,
        \\<view>
        \\  <view>
        \\    <view>
        \\      <view></view>
        \\    </view>
        \\    <view>
        \\      <view></view>
        \\    </view>
        \\  </view>
        \\  <view>
        \\    <view><text>Hello</text></view>
        \\    <view></view>
        \\  </view>
        \\</view>
    , .{});

    defer tree.deinit();

    {
        var node_iter = tree.createNodeIterator(1);
        var i: Node.NodeId = 2;
        while (node_iter.nextNode()) |node_id| {
            try std.testing.expectEqual(node_id, i);
            i += 1;
        }
    }
    {
        var node_iter = tree.createNodeIterator(tree.node_map.count() - 1);
        var i: Node.NodeId = tree.node_map.count();
        while (node_iter.previousNode()) |node_id| {
            i -= 1;

            try std.testing.expectEqual(node_id, i);
        }
    }
}
