const std = @import("std");
const mod = @import("mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutTree = mod.LayoutTree;
const LayoutNode = mod.LayoutNode;
const ContainerContext = mod.ContainerContext;

pub fn performChildLayout(
    context: *LayoutContext,
    l_node_id: LayoutNode.Id,
    known_dimensions: mod.CSSMaybePoint,
    parent_size: mod.CSSMaybePoint,
    available_space: mod.PointOf(mod.constants.AvailableSpace),
    sizing_mode: mod.constants.SizingMode,
    vertical_margins_are_collapsible: mod.Line(bool),
) mod.ComputeLayoutError!mod.LayoutResult {
    context.info(l_node_id, "performChildLayout", .{});
    const result = try mod.computeChildLayout(
        context,
        .{
            .available_space = available_space,
            .known_dimensions = known_dimensions,
            .parent_size = parent_size,
            .sizing_mode = sizing_mode,
            .axis = .both,
            .run_mode = .perform_layout,
            .vertical_margins_are_collapsible = vertical_margins_are_collapsible,
        },
        l_node_id,
    );
    context.info(l_node_id, "Result {any}", .{result});
    return result;
}
