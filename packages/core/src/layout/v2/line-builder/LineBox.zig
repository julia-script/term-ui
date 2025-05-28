const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const LineBoxFragment = @import("./LineBoxFragment.zig");
const mod = @import("../mod.zig");

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
    
    pub fn appendLine(self: *@This(), line: Self) !void {
        try self.list.append(self.allocator, line);
    }
    
    pub fn getLinePtr(self: *@This(), index: usize) *Self {
        return &self.list.items[index];
    }
    
    pub fn appendFragmentToLastLine(self: *@This(), fragment: LineBoxFragment) !void {
        try self.getLinePtr(self.list.items.len - 1).fragments.append(self.allocator, fragment);
    }
};