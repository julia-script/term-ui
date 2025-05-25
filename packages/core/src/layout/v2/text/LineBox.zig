const mod = @import("../mod.zig");
const LineBoxFragment = @import("./LineBoxFragment.zig");
const LayoutNode = mod.LayoutNode;
const css_types = @import("../../../css/types.zig");
const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

location: mod.CSSPoint = .{ .x = 0, .y = 0 },
size: mod.CSSPoint = .{ .x = 0, .y = 0 },
fragments: ArrayListUnmanaged(LineBoxFragment) = .{},
allocator: std.mem.Allocator,
available_width: f32,

const Self = @This();

/// Free all fragment text memory and the fragments list
pub fn deinit(self: *@This()) void {
    for (self.fragments.items) |*fragment| {
        fragment.deinit();
    }
    self.fragments.deinit(self.allocator);
}
pub fn dupe(self: *@This(), allocator: std.mem.Allocator) !Self {
    var new = @This(){
        .location = self.location,
        .size = self.size,
        .available_width = self.available_width,
        .fragments = .{},
        .allocator = allocator,
    };
    try new.fragments.ensureUnusedCapacity(allocator, self.fragments.items.len);
    for (self.fragments.items) |*fragment| {
        new.fragments.appendAssumeCapacity(try fragment.dupe(allocator));
    }
    return new;
}
pub fn endsWithWhitespace(self: *@This()) bool {
    var i = self.fragments.items.len - 1;
    while (i > 0) : (i -= 1) {
        if (self.fragment.items.len == 0) continue;
        if (self.fragments.items[i].endsWithWhitespace()) {
            return true;
        }
    }
    return false;
}
// pub fn toOwnedLineBox(self: *@This(), allocator: std.mem.Allocator) !Self {
//     var owned_fragments: ArrayListUnmanaged(LineBoxFragment) = .{};
//     try owned_fragments.ensureUnusedCapacity(allocator, self.fragments.items.len);

//     for (self.fragments.items) |*fragment| {
//         owned_fragments.appendAssumeCapacity(try fragment.dupe(allocator));
//         fragment.deinit();
//     }
//     self.fragments.clearAndFree(allocator);

//     return .{
//         .size = self.size,
//         .available_width = self.available_width,
//         .fragments = owned_fragments,
//     };
// }

pub const LineBoxList = struct {
    list: ArrayListUnmanaged(Self) = .{},
    allocator: std.mem.Allocator,
    pub fn items(self: *@This()) []Self {
        return self.list.items;
    }
    pub fn len(self: *const @This()) usize {
        return self.list.items.len;
    }

    pub fn deinit(
        self: *@This(),
    ) void {
        for (self.list.items) |*item| {
            item.deinit();
        }
        self.list.deinit(self.allocator);
    }
    pub fn dupe(self: *@This(), allocator: std.mem.Allocator) !@This() {
        var new = @This(){
            .allocator = allocator,
        };
        try new.list.ensureUnusedCapacity(allocator, self.list.items.len);
        for (self.list.items) |*item| {
            new.list.appendAssumeCapacity(try item.dupe(allocator));
        }
        return new;
    }
};
