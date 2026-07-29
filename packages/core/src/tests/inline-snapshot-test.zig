const std = @import("std");
const snapshot = @import("./utils/snapshot.zig");
const root = @import("root");

test "inlinesnapshot" {
    std.debug.print("aaa!\n", .{});
    try root.matchInlineSnapshot(
        @src(),
        \\ Hello, world!
        \\
    ,
        \\ Hello, world!
        \\
        ,
    );

    try root.matchInlineSnapshot(
        @src(),
        \\ Hello, world!
        \\
    ,
        \\ Hello, world!
        \\
        ,
    );

    try root.matchInlineSnapshot(@src(), "hello,\nworld!",
        \\hello,
        \\world!
    );

    try root.matchSnapshot(@src(), .{ .namespace = "hello" }, "hello,\nworld!");
}
