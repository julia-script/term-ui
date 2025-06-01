const mod = @import("mod.zig");
const LayoutContext = mod.LayoutContext;
const css_types = @import("../../css/types.zig");
const std = @import("std");

pub fn computeChildLayout(context: *LayoutContext, inputs: mod.ContainerContext, l_node_id: mod.LayoutNode.Id) mod.ComputeLayoutError!mod.LayoutResult {
    const cache = context.layout_tree.getCache(l_node_id);
    if (cache.get(inputs.known_dimensions, inputs.available_space, inputs.run_mode)) |cached| {
        return cached;
    }

    const l_node = context.layout_tree.getNodePtr(l_node_id);
    const computed: mod.LayoutResult = blk: {
        switch (l_node.data) {
            .block_container_node => {
                const display = context.getStyleValue(css_types.Display, l_node_id, .display);
                break :blk switch (display.inside) {
                    .flow_root => try mod.computeBlockLayout(context, inputs, l_node_id),
                    .flex => try mod.computeFlexboxLayout(context, inputs, l_node_id),
                    .flow => try mod.computeBlockLayout(context, inputs, l_node_id), // fallback to block layout
                };
            },
            .inline_container_node => break :blk try mod.computeInlineContextLayout(context, inputs, l_node_id),
            .inline_node => {
                const display = context.getStyleValue(css_types.Display, l_node_id, .display);
                break :blk switch (display.inside) {
                    .flow_root => try mod.computeBlockLayout(context, inputs, l_node_id),
                    .flex => try mod.computeFlexboxLayout(context, inputs, l_node_id),
                    .flow => std.debug.panic("unreachable: inline_node should be handled by it's inline container parent", .{}),
                };
            },
            else => std.debug.panic("unimplemented: {s}\n", .{@tagName(l_node.data)}),
        }
    };
    cache.store(inputs.known_dimensions, inputs.available_space, inputs.run_mode, computed);
    
    // Clear DOM invalidation status only after final layout is computed
    if (inputs.run_mode == .perform_layout) {
        switch (l_node.ref) {
            .doc_node => |doc_node_id| {
                context.doc_tree.getNode(doc_node_id).regenerate_level = .repaint;
            },
            .anonymous => {
                // Anonymous nodes don't have DOM counterparts, nothing to clear
            },
        }
    }
    
    return computed;
}
