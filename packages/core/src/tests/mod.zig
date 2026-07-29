const std = @import("std");

test {
    _ = @import("./whitespace.zig");
    _ = @import("./scroll.zig");
    _ = @import("./inline-snapshot-test.zig");
    _ = @import("./borders.zig");
    _ = @import("./cache.zig");
}
