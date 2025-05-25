const mod = @import("mod.zig");
const LayoutContext = mod.LayoutContext;

pub fn computeLayout(context: *LayoutContext, available_space: mod.PointOf(mod.constants.AvailableSpace), l_root_id: mod.LayoutNode.Id) mod.ComputeLayoutError!void {
    const root_layout = try mod.performChildLayout(
        context,
        l_root_id,
        mod.CSSMaybePoint.NULL,
        mod.CSSMaybePoint.NULL,
        available_space,
        .inherent_size,
        .{ .start = false, .end = false },
    );
    context.setBox(l_root_id, .{
        .size = root_layout.size,

        // .content_size = root_layout.content_size,
        // .first_baselines = root_layout.first_baselines,
        // .top_margin = root_layout.top_margin,
        // .bottom_margin = root_layout.bottom_margin,
        // .margins_can_collapse_through = root_layout.margins_can_collapse_through,
    }, root_layout.line_boxes);
}
