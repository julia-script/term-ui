const std = @import("std");

pub const options = .{ .iterations = 10 };

test "simple bench" {
    var sum: usize = 0;
    for (0..1000) |i| sum += i;
    std.mem.doNotOptimizeAway(sum);
}
