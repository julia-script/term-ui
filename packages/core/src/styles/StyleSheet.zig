const std = @import("std");
const Style = @import("../tree/Style.zig");
const Tree = @import("../tree/Tree.zig");
const Node = @import("../tree/Node.zig");
const Selector = @import("Selector.zig");
const StyleManager = @import("StyleManager.zig");
const NodeId = Node.NodeId;

/// A collection of style rules that can be applied to elements
pub const StyleSheet = struct {
    allocator: std.mem.Allocator,
    rules: std.array_list.Managed(StyleRule),

    pub fn init(allocator: std.mem.Allocator) StyleSheet {
        return .{
            .allocator = allocator,
            .rules = std.array_list.Managed(StyleRule).init(allocator),
        };
    }

    pub fn deinit(self: *StyleSheet) void {
        for (self.rules.items) |*rule| {
            rule.deinit();
        }
        self.rules.deinit();
    }

    pub fn addRule(self: *StyleSheet, selector: Selector, style: Style) !void {
        try self.rules.append(.{
            .selector = selector,
            .style = style,
        });
    }

    /// Get all rules that match a specific node
    pub fn getMatchingRules(self: *StyleSheet, tree: *Tree, node_id: NodeId, allocator: std.mem.Allocator) ![]StyleRule {
        var matching = std.array_list.Managed(StyleRule).init(allocator);
        errdefer matching.deinit();

        for (self.rules.items) |rule| {
            if (rule.selector.matches(tree, node_id)) {
                try matching.append(rule);
            }
        }

        return matching.toOwnedSlice();
    }
};

/// A rule combining a selector and style declaration
pub const StyleRule = struct {
    selector: Selector,
    style: Style,

    pub fn deinit(self: *StyleRule) void {
        self.selector.deinit();
        self.style.deinit();
    }
};
