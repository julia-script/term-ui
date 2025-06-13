const std = @import("std");
const mod = @import("../mod.zig");
const css_types = @import("../../../css/types.zig");
const types = @import("types.zig");
const flexItems = @import("flexItems.zig");

pub fn collectFlexLines(
    allocator: std.mem.Allocator,
    constants: *types.AlgoConstants,
    available_space: mod.constants.AvailableSpacePoint,
    flex_items: *std.ArrayList(types.FlexItem),
) !std.ArrayList(types.FlexLine) {
    const dir = flexItems.DirectionHelper.init(constants.dir);

    if (!constants.is_wrap) {
        var lines = try std.ArrayList(types.FlexLine).initCapacity(allocator, 1);
        lines.appendAssumeCapacity(.{ .items = flex_items.items.ptr[0..flex_items.items.len], .cross_size = 0.0, .offset_cross = 0.0 });
        return lines;
    }

    const main_available_space = if (dir.is_row) available_space.x else available_space.y;

    switch (main_available_space) {
        // If we're sizing under a max-content constraint then the flex items will never wrap
        .max_content => {
            var lines = try std.ArrayList(types.FlexLine).initCapacity(allocator, 1);
            lines.appendAssumeCapacity(.{ .items = flex_items.items.ptr[0..flex_items.items.len], .cross_size = 0.0, .offset_cross = 0.0 });
            return lines;
        },

        // If flex-wrap is wrap and we're sizing under a min-content constraint, then we take every possible wrapping opportunity
        .min_content => {
            var lines = try std.ArrayList(types.FlexLine).initCapacity(allocator, flex_items.items.len);
            for (0..flex_items.items.len) |index| {
                lines.appendAssumeCapacity(.{ .items = flex_items.items.ptr[index .. index + 1], .cross_size = 0.0, .offset_cross = 0.0 });
            }
            return lines;
        },

        .definite => |definite| {
            var lines = std.ArrayList(types.FlexLine).init(allocator);
            var start_range_index: usize = 0;
            var line_length: f32 = 0.0;
            const main_axis_gap = dir.getMain(constants.gap);
            var is_new_row = true;
            var index: usize = 0;

            while (index < flex_items.items.len) {
                const current_item = flex_items.items.ptr[index];
                // Find index of the first item in the next line
                const gap_contribution = if (is_new_row) 0.0 else main_axis_gap;
                const item_main_size = dir.getMain(current_item.hypothetical_outer_size);
                line_length += item_main_size + gap_contribution;

                if (line_length > definite and !is_new_row) {
                    try lines.append(.{ .items = flex_items.items.ptr[start_range_index..index], .cross_size = 0.0, .offset_cross = 0.0 });
                    start_range_index = index;
                    is_new_row = true;
                    line_length = 0;
                } else {
                    is_new_row = false;
                    index += 1;
                }
            }

            if (start_range_index < flex_items.items.len) {
                try lines.append(.{ .items = flex_items.items.ptr[start_range_index..flex_items.items.len], .cross_size = 0.0, .offset_cross = 0.0 });
            }

            return lines;
        },
    }
}
