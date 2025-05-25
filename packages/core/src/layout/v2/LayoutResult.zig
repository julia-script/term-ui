const mod = @import("mod.zig");
const LineBox = @import("./text/LineBox.zig");
const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

line_boxes: ?LineBox.LineBoxList = null,
size: mod.CSSPoint = .{ .x = 0, .y = 0 },
content_size: mod.CSSPoint = .{ .x = 0, .y = 0 },
first_baselines: mod.CSSMaybePoint = .{ .x = null, .y = null },
top_margin: mod.CollapsibleMarginSet = .{ .positive = 0, .negative = 0 },
bottom_margin: mod.CollapsibleMarginSet = .{ .positive = 0, .negative = 0 },
margins_can_collapse_through: bool = false,
