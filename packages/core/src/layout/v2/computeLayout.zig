const mod = @import("mod.zig");
const LayoutContext = mod.LayoutContext;

pub fn computeLayout(context: *LayoutContext, available_space: mod.PointOf(mod.constants.AvailableSpace)) mod.ComputeLayoutError!void {
    const viewport_id: mod.LayoutNode.Id = context.layout_tree.root_id;

    // For viewport node, use definite dimensions if available
    const viewport_size = mod.CSSMaybePoint{
        .x = switch (available_space.x) {
            .definite => |size| size,
            else => null,
        },
        .y = switch (available_space.y) {
            .definite => |size| size,
            else => null,
        },
    };

    const root_layout = try mod.performChildLayout(
        context,
        viewport_id,
        viewport_size,
        viewport_size,
        available_space,
        .inherent_size,
        .{ .start = false, .end = false },
    );

    // If available space is not definite, size should be based on the child
    const final_size = mod.CSSPoint{
        .x = if (viewport_size.x) |x| x else root_layout.size.x,
        .y = if (viewport_size.y) |y| y else root_layout.size.y,
    };

    context.setBox(viewport_id, .{
        .size = final_size,
        .content_size = final_size,
        .location = .{ .x = 0, .y = 0 },
        .margin = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
        .padding = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
        .border = .{ .top = 0, .right = 0, .bottom = 0, .left = 0 },
        .scrollbar_size = .{ .x = 0, .y = 0 },
    }, root_layout.line_boxes);
}
