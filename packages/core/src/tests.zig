const std = @import("std");
const builtin = @import("builtin");
const options = @import("test_options");

test {
    std.debug.print("Hello, world!\n", .{});
    _ = @import("./tests/mod.zig");
}
