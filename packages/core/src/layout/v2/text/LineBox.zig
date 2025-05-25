const mod = @import("../mod.zig");
const LineBoxFragment = @import("./LineBoxFragment.zig");
const LayoutNode = mod.LayoutNode;
const css_types = @import("../../../css/types.zig");
const std = @import("std");
const ArrayList = std.ArrayList;

size: mod.CSSPoint,
fragments: ArrayList(LineBoxFragment),
available_width: f32,

/// Free all fragment text memory and the fragments list
pub fn deinit(self: *@This()) void {
    for (self.fragments.items) |*fragment| {
        fragment.deinit();
    }
    self.fragments.deinit();
}
