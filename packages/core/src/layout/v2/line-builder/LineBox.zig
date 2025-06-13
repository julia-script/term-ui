const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const LineBoxFragment = @import("./LineBoxFragment.zig");
const mod = @import("../mod.zig");

location: mod.CSSPoint = .{ .x = 0, .y = 0 },
size: mod.CSSPoint = .{ .x = 0, .y = 0 },
fragments: ArrayListUnmanaged(LineBoxFragment) = .{},
allocator: std.mem.Allocator,
available_width: f32 = 0,

const Self = @This();

/// Free all fragment text memory and the fragments list
pub fn deinit(self: *@This()) void {
    for (self.fragments.items) |*fragment| {
        fragment.deinit();
    }
    self.fragments.deinit(self.allocator);
}
pub fn append(self: *@This(), fragment: LineBoxFragment) !void {
    self.size.x += fragment.size.x;
    self.size.y = @max(self.size.y, fragment.size.y);
    try self.fragments.append(self.allocator, fragment);
}

pub fn dupe(self: *const @This(), allocator: std.mem.Allocator) !Self {
    var new = @This(){
        .location = self.location,
        .size = self.size,
        .available_width = self.available_width,
        .fragments = .{},
        .allocator = allocator,
    };
    // try new.fragments.ensureUnusedCapacity(allocator, self.fragments.items.len);
    for (self.fragments.items) |*fragment| {
        const duped = try fragment.dupe(allocator);
        try new.fragments.append(allocator, duped);
    }
    return new;
}

pub fn endsWithWhitespace(self: *@This()) bool {
    if (self.fragments.items.len == 0) return false;

    var i = self.fragments.items.len - 1;
    while (true) : (i -= 1) {
        if (self.fragments.items[i].text.len > 0) {
            return self.fragments.items[i].endsWithWhitespace();
        }
        if (i == 0) break;
    }
    return false;
}

pub const LineBoxList = struct {
    list: ArrayListUnmanaged(Self) = .{},
    allocator: std.mem.Allocator,

    pub fn items(self: *@This()) []Self {
        return self.list.items;
    }

    pub fn len(self: *const @This()) usize {
        return self.list.items.len;
    }

    pub fn deinit(self: *@This()) void {
        for (self.list.items) |*item| {
            item.deinit();
        }
        // self.list.clearAndFree(self.allocator);
        self.list.deinit(self.allocator);
    }
    pub fn clear(self: *@This()) void {
        for (self.list.items) |*item| {
            item.deinit();
        }
        self.list.clearAndFree(self.allocator);
    }

    pub fn dupe(self: @This(), allocator: std.mem.Allocator) !@This() {
        var new = @This(){
            .allocator = allocator,
        };
        // try new.list.ensureUnusedCapacity(allocator, self.list.items.len);
        for (self.list.items) |*item| {
            const duped = try item.dupe(allocator);
            try new.list.append(allocator, duped);
        }
        return new;
    }

    pub fn appendLine(self: *@This(), line: Self) !void {
        try self.list.append(self.allocator, line);
    }

    pub fn getLinePtr(self: *@This(), index: usize) *Self {
        return &self.list.items[index];
    }
    pub fn breakLine(self: *@This()) !void {
        if (self.list.items.len == 0) {
            try self.appendLine(.{
                .allocator = self.allocator,
            });
        }
        const last_line = self.getLinePtr(self.list.items.len - 1);
        try self.appendLine(.{
            .allocator = self.allocator,
            .location = .{ .x = 0, .y = last_line.location.y + last_line.size.y },
        });
    }

    pub fn appendFragmentToLastLine(self: *@This(), fragment: LineBoxFragment) !void {
        if (self.list.items.len == 0) {
            try self.appendLine(.{
                .allocator = self.allocator,
            });
        }

        try self.getLinePtr(self.list.items.len - 1).append(fragment);
    }
};
