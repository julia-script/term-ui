const std = @import("std");
const Node = @import("../tree/Node.zig");
const Tree = @import("../tree/Tree.zig");
const NodeId = Node.NodeId;

/// The type of selector for matching elements
pub const SelectorType = enum {
    /// Matches any element ("*")
    universal,

    /// Matches elements by tag name ("div", "span")
    tag,

    /// Matches elements with the specified class (".className")
    class,

    /// Matches element by ID ("#elementId")
    id,

    /// Matches elements that are descendants of specified parent ("div p")
    descendant,

    /// Matches elements that are direct children of specified parent ("div > p")
    child,

    /// Matches elements that come immediately after specified element ("div + p")
    adjacent_sibling,

    /// Matches elements that come after specified element ("div ~ p")
    general_sibling,

    /// Combines multiple selectors (compound selector)
    compound,
};

/// A CSS selector that can match nodes in the tree
pub const Selector = struct {
    allocator: std.mem.Allocator,
    type: SelectorType,
    value: union {
        tag: []const u8,
        class: []const u8,
        id: []const u8,
        compound: []Selector,
        universal: void,
        relationship: struct {
            parent: *Selector,
            child: *Selector,
        },
    },

    pub fn init(allocator: std.mem.Allocator) Selector {
        return .{
            .allocator = allocator,
            .type = .universal,
            .value = .{ .universal = {} },
        };
    }

    pub fn deinit(self: *Selector) void {
        switch (self.type) {
            .tag => {
                self.allocator.free(self.value.tag);
            },
            .class => {
                self.allocator.free(self.value.class);
            },
            .id => {
                self.allocator.free(self.value.id);
            },
            .compound => {
                for (self.value.compound) |*sel| {
                    sel.deinit();
                }
                self.allocator.free(self.value.compound);
            },
            .descendant, .child, .adjacent_sibling, .general_sibling => {
                self.value.relationship.parent.deinit();
                self.value.relationship.child.deinit();
                self.allocator.destroy(self.value.relationship.parent);
                self.allocator.destroy(self.value.relationship.child);
            },
            .universal => {},
        }
    }

    pub fn matches(self: *const Selector, tree: *Tree, node_id: NodeId) bool {
        // For now, only implement simple matching
        // This will be expanded later for complex selectors
        switch (self.type) {
            .universal => return true,
            .tag => {
                // Tag matching would need a way to get the element's tag name
                // For now, just return false as placeholder
                return false;
            },
            .class => {
                // Class matching would need a way to get the element's classes
                // For now, just return false as placeholder
                return false;
            },
            .id => {
                // ID matching would need a way to get the element's ID
                // For now, just return false as placeholder
                return false;
            },
            .compound => {
                // All selectors in a compound selector must match
                for (self.value.compound) |sel| {
                    if (!sel.matches(tree, node_id)) {
                        return false;
                    }
                }
                return true;
            },
            .descendant, .child, .adjacent_sibling, .general_sibling => {
                // Complex relationship selectors will be implemented later
                return false;
            },
        }
    }
};
