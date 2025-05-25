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
        .content_size = root_layout.content_size,
        .location = .{ .x = 0, .y = 0 }, // Root is positioned at origin
        .margin = root_layout.resolved_margin,
        .padding = root_layout.resolved_padding,
        .border = root_layout.resolved_border,
        .scrollbar_size = root_layout.scrollbar_size,
    }, root_layout.line_boxes);
}
