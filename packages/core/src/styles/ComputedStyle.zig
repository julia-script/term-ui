const std = @import("std");
const Style = @import("../tree/Style.zig");
const Tree = @import("../tree/Tree.zig");
const Node = @import("../tree/Node.zig");
const StyleManager = @import("StyleManager.zig");
const CascadeTypes = @import("CascadeTypes.zig");
const NodeId = Node.NodeId;

/// Manages computed styles for nodes
/// Error types that can occur during style operations
pub const StyleError = error{
    OutOfMemory,
    KeyNotFound,
    StyleComputationError,
};

pub const ComputedStyleCache = struct {
    allocator: std.mem.Allocator,
    styles: std.AutoHashMap(NodeId, Style),
    inheritance: CascadeTypes.PropertyInheritance,

    pub fn init(allocator: std.mem.Allocator) !ComputedStyleCache {
        return ComputedStyleCache{
            .allocator = allocator,
            .styles = std.AutoHashMap(NodeId, Style).init(allocator),
            .inheritance = CascadeTypes.DEFAULT_INHERITANCE,
        };
    }

    pub fn deinit(self: *ComputedStyleCache) void {
        self.styles.deinit();
    }

    pub fn computeStyle(self: *ComputedStyleCache, tree: *Tree, node_id: NodeId, parent_style: Style) StyleError!void {
        // const style = self.styles.get(node_id) orelse return;
        // _ = style; // autofix
        const children = tree.getChildren(node_id);

        // First, apply the node's own style properties
        const node = tree.getNode(node_id);
        var node_style = try self.applyInheritedProperties(tree, parent_style, node.styles);

        if (node_style.border_style.top.style != .none) {
            node_style.border.top = .{ .length = 1 };
        }
        if (node_style.border_style.bottom.style != .none) {
            node_style.border.bottom = .{ .length = 1 };
        }
        if (node_style.border_style.left.style != .none) {
            node_style.border.left = .{ .length = 1 };
        }
        if (node_style.border_style.right.style != .none) {
            node_style.border.right = .{ .length = 1 };
        }

        // Store in cache and return
        try self.styles.put(node_id, node_style);
        for (children.items) |child_id| {
            try self.computeStyle(tree, child_id, node_style);
        }
        // return style;
    }
    /// Get a node's computed style, calculating it if not cached
    pub fn getComputedStyle(self: *ComputedStyleCache, tree: *Tree, node_id: NodeId) Style {
        _ = tree; // autofix
        // Return cached style if available
        if (self.styles.get(node_id)) |style| {
            return style;
        }
        std.debug.panic("computeStyle\n", .{});
        // return try self.computeStyle(tree, node_id);

        //     // Create new style for this node
        //     var style = try self.allocator.create(Style);
        //     style.* = Style.init(self.allocator);
        //     errdefer {
        //         style.deinit();
        //         self.allocator.destroy(style);
        //     }

        //     // First, apply the node's own style properties
        //     const node_style = tree.getStyle(node_id);
        //     self.copyStyleProperties(node_style, style);

        //     // Then apply inherited properties from parent
        //     if (tree.getParent(node_id)) |parent_id| {
        //         try self.applyInheritedProperties(tree, parent_id, style);
        //     }

        //     // Store in cache and return
        //     try self.styles.put(node_id, style);
        //     return style;
    }

    /// Copy all style properties from source to destination
    fn copyStyleProperties(self: *ComputedStyleCache, source: *Style, dest: *Style) void {
        _ = self; // Not used yet

        inline for (std.meta.fields(Style)) |field| {
            @field(dest, field.name) = @field(source, field.name);
        }

        // Copy all properties from source to destination
        // Text properties
        // dest.text_align = source.text_align;
        // dest.text_wrap = source.text_wrap;
        // dest.foreground_color = source.foreground_color;
        // dest.line_height = source.line_height;

        // // Text formatting properties
        // dest.font_weight = source.font_weight;
        // dest.font_style = source.font_style;
        // dest.text_decoration = source.text_decoration;

        // // Background properties
        // dest.background_color = source.background_color;

        // Other properties can be copied similarly
        // For now, just copying the most commonly used properties
    }

    /// Apply inherited properties based on inheritance rules
    fn applyInheritedProperties(self: *ComputedStyleCache, tree: *Tree, parent_style: Style, style: Style) StyleError!Style {
        var new_style = style;
        _ = self; // autofix
        _ = tree; // autofix
        // Apply text_align inheritance
        // Apply text_align inheritance
        if (style.text_align == .inherit) {
            new_style.text_align = parent_style.text_align;
        }

        // Apply white_space inheritance
        if (style.white_space == .inherit) {
            new_style.white_space = parent_style.white_space;
        }

        // Apply foreground_color inheritance
        if (style.foreground_color == null) {
            new_style.foreground_color = parent_style.foreground_color;
        }

        // Apply line_height inheritance
        if (style.line_height == 1) { // Default value check
            new_style.line_height = parent_style.line_height;
        }

        // Apply text formatting properties inheritance

        // Font weight
        if (style.font_weight == .inherit) {
            new_style.font_weight = parent_style.font_weight;
        }

        // Font style
        if (style.font_style == .inherit) {
            new_style.font_style = parent_style.font_style;
        }

        // Text decoration - only inherit if explicitly set to inherit
        if (style.text_decoration.line == .inherit) {
            new_style.text_decoration = parent_style.text_decoration;
        }

        // Other inherited properties would be handled similarly
        return new_style;
    }

    /// Invalidate a node's computed style
    pub fn invalidateNode(self: *ComputedStyleCache, node_id: NodeId) void {
        _ = self.styles.remove(node_id);
    }

    /// Invalidate a node and all its descendants
    pub fn invalidateTree(self: *ComputedStyleCache, tree: *Tree, node_id: NodeId) void {
        self.invalidateNode(node_id);

        // Invalidate all child nodes recursively
        const children = tree.getChildren(node_id);
        for (children.items) |child_id| {
            self.invalidateTree(tree, child_id);
        }
    }
};
