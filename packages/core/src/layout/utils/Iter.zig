const std = @import("std");

pub fn SliceType(T: type) type {
    switch (@typeInfo(T)) {
        .array => |array| {
            return array.child;
        },
        // .Pointer => |pointer| return SliceType(pointer.child),
        .pointer => |pointer| switch (@typeInfo(pointer.child)) {
            .array => |array| {
                return SliceType(array.child);
            },
            else => return pointer.child,
        },

        else => @compileError("SliceType: T must be a slice, found" ++ @typeName(T)),
    }
}

pub fn Iter(comptime T: type) type {
    return struct {
        slice: T,
        index: usize = 0,

        const Self = @This();
        pub fn next(self: *Self) ?*SliceType(T) {
            if (self.index < self.slice.len) {
                const index = self.index;
                self.index += 1;
                return &self.slice[index];
            }
            return null;
        }
        pub fn reverse(self: Self) RevIter(T) {
            return RevIter(T){
                .slice = self.slice,
                .index = self.slice.len,
            };
        }
    };
}

pub fn RevIter(comptime T: type) type {
    return struct {
        slice: T,
        index: usize,

        const Self = @This();
        pub fn next(self: *Self) ?*SliceType(T) {
            if (self.index > 0) {
                self.index -= 1;
                return &self.slice[self.index];
            }
            return null;
        }
    };
}

pub fn slice(s: anytype) Iter(@TypeOf(s)) {
    return Iter(@TypeOf(s)){ .slice = s };
}
pub fn sliceReverse(s: anytype) RevIter(@TypeOf(s)) {
    return RevIter(@TypeOf(s)){ .slice = s, .index = s.len };
}

test "List.SliceType" {
    var list = std.array_list.Managed(f32).init(std.testing.allocator);
    defer list.deinit();
    try list.append(1.0);

    var iter = slice(list.items);
    while (iter.next()) |item| {
        item.* *= 2;
        // item.* = 0;
        // item = 10;
    }

    //
    // std.debug.print("{any}\n", .{@typeInfo(@TypeOf(list.items))});
    // _ = SliceType(@TypeOf(list));
    // std.debug.print("{any}", .{SliceType(@TypeOf(list))});
}
