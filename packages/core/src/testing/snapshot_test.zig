const std = @import("std");
const snapshot = @import("snapshot.zig");

test "expectMatchSnapshot basic" {
    const allocator = std.testing.allocator;
    const content = "hello snapshot";
    try snapshot.expectMatchSnapshot(allocator, "basic snapshot", content);
}
