const std = @import("std");

pub const AttrValue = [:0]const u8;
const Attr = struct {
    value: AttrValue = "",

    pub fn setValue(self: *Attr, allocator: std.mem.Allocator, value: []const u8) !void {
        if (self.value.len > 0) {
            allocator.free(self.value);
        }
        self.value = try allocator.dupeSentinel(u8, value, 0);
    }

    pub fn getValue(self: *Attr) []const u8 {
        return self.value;
    }

    pub fn deinit(self: *Attr, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
    }
};

const Map = std.StringHashMapUnmanaged(Attr);
const Self = @This();
map: Map = .{},
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Map {
    return Map{
        .map = .{},
        .allocator = allocator,
    };
}
pub fn iterate(self: *Self) Map.Iterator {
    return self.map.iterator();
}
pub fn set(self: *Self, name: []const u8, value: []const u8) !void {
    var gop = try self.map.getOrPut(self.allocator, name);
    if (gop.found_existing) {
        try gop.value_ptr.setValue(self.allocator, value);
    } else {
        gop.value_ptr.* = Attr{};
        gop.key_ptr.* = try self.allocator.dupe(u8, name);
        try gop.value_ptr.setValue(self.allocator, value);
    }
}
pub fn remove(self: *Self, name: []const u8) void {
    if (self.map.getEntry(name)) |entry| {
        entry.value_ptr.deinit(self.allocator);
        self.allocator.free(entry.key_ptr.*);
        _ = self.map.remove(entry.key_ptr.*);
    }
}

pub fn get(self: *Self, name: []const u8) ?Attr {
    return self.map.get(name);
}
pub fn match(self: *Self, name: []const u8, value: []const u8) bool {
    if (self.map.get(name)) |attr| {
        return std.mem.eql(u8, attr.value, value);
    }
    return false;
}

pub fn deinit(self: *Self) void {
    var iter = self.map.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.deinit(self.allocator);
        self.allocator.free(entry.key_ptr.*);
    }
    self.map.deinit(self.allocator);
}
