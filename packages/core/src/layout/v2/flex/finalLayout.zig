const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");
const computeContentSizeContribution = @import("computeContentSizeContribution.zig").computeContentSizeContribution;

/// Do a final layout pass and gather the resulting layouts
pub fn finalLayoutPass(
    context: *mod.LayoutContext,
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !mod.CSSPoint {
    var content_size = mod.CSSPoint{ .x = 0, .y = 0 };
    
    for (lines.items) |*line| {
        for (line.items) |*item| {
            const item_content_size = try calculateFlexItem(context, item, line, constants);
            content_size = mod.CSSPoint{
                .x = @max(content_size.x, item_content_size.x),
                .y = @max(content_size.y, item_content_size.y),
            };
        }
    }
    
    return content_size;
}

/// Calculate the final layout of a single flex item
pub fn calculateFlexItem(
    context: *mod.LayoutContext,
    item: *types.FlexItem,
    line: *types.FlexLine,
    constants: *types.AlgoConstants,
) !mod.CSSPoint {
    const dir = flexItems.DirectionHelper.init(constants.dir);
    
    // Perform final layout with determined size
    const final_layout = try mod.performChildLayout(
        context,
        item.node_id,
        item.target_size,
        constants.node_inner_size,
        .{ .x = .max_content, .y = .max_content },
        .inherent_size,
        .{ .start = false, .end = false },
    );
    
    // Calculate final position
    const location = mod.CSSPoint{
        .x = if (dir.is_row) 
            item.offset_main + constants.content_box_inset.left
        else 
            item.offset_cross + line.offset_cross + constants.content_box_inset.left,
        .y = if (dir.is_row) 
            item.offset_cross + line.offset_cross + constants.content_box_inset.top
        else 
            item.offset_main + constants.content_box_inset.top,
    };
    
    // Set the final layout
    context.setBox(item.node_id, .{
        .size = final_layout.size,
        .content_size = final_layout.content_size,
        .scrollbar_size = final_layout.scrollbar_size,
        .location = location,
        .padding = final_layout.resolved_padding,
        .border = final_layout.resolved_border,
        .margin = final_layout.resolved_margin,
    });
    
    // Calculate content size contribution
    return computeContentSizeContribution(
        location,
        final_layout.size,
        final_layout.content_size,
        item.overflow,
    );
}

/// Calculate baselines for flex items (simplified version)
pub fn calculateChildrenBaselines(
    context: *mod.LayoutContext,
    known_dimensions: mod.CSSMaybePoint,
    available_space: mod.constants.AvailableSpacePoint,
    lines: *std.ArrayList(types.FlexLine),
    constants: *types.AlgoConstants,
) !void {
    _ = context;
    _ = known_dimensions;
    _ = available_space;
    _ = constants;
    
    // Simplified baseline calculation - just set all baselines to 0
    for (lines.items) |*line| {
        for (line.items) |*item| {
            item.baseline = 0;
        }
    }
}

/// Perform absolute layout on absolutely positioned children
pub fn performAbsoluteLayoutOnAbsoluteChildren(
    context: *mod.LayoutContext,
    l_node_id: mod.LayoutNode.Id,
    constants: *types.AlgoConstants,
) !mod.CSSPoint {
    var absolute_content_size = mod.CSSPoint{ .x = 0, .y = 0 };
    const children = context.layout_tree.getChildren(l_node_id);
    
    for (children) |child_id| {
        const css_display = context.getStyleValue(css_types.Display, child_id, .display);
        const css_position = context.getStyleValue(css_types.Position, child_id, .position);
        
        if (css_display.outside == .none or css_position != .absolute) {
            continue;
        }
        
        // Simple absolute positioning - place at container origin
        const child_layout = try mod.performChildLayout(
            context,
            child_id,
            mod.CSSMaybePoint.NULL,
            constants.container_size,
            .{ .x = .max_content, .y = .max_content },
            .content_size,
            .{ .start = false, .end = false },
        );
        
        const location = mod.CSSPoint{
            .x = constants.content_box_inset.left,
            .y = constants.content_box_inset.top,
        };
        
        context.setBox(child_id, .{
            .size = child_layout.size,
            .content_size = child_layout.content_size,
            .scrollbar_size = child_layout.scrollbar_size,
            .location = location,
            .padding = child_layout.resolved_padding,
            .border = child_layout.resolved_border,
            .margin = child_layout.resolved_margin,
        });
        
        const contribution = computeContentSizeContribution(
            location,
            child_layout.size,
            child_layout.content_size,
            css_types.OverflowPoint{ .x = .visible, .y = .visible },
        );
        
        absolute_content_size = mod.CSSPoint{
            .x = @max(absolute_content_size.x, contribution.x),
            .y = @max(absolute_content_size.y, contribution.y),
        };
    }
    
    return absolute_content_size;
}