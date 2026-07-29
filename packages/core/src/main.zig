pub const std_options: std.Options = .{
    .fmt_max_depth = 20,
};
const std = @import("std");

pub fn main() !void {}

test {
    _ = std_options;
    _ = @import("./cmd/input.zig");
    _ = @import("./cmd/Trie.zig");
    _ = @import("./cmd/terminfo/main.zig");
}
