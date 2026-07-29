const std = @import("std");
const assertDocumentSnapshotFromXml = @import("utils/assert-document-snapshot.zig").assertDocumentSnapshotFromXml;

test "whites-pace: normal" {
    try assertDocumentSnapshotFromXml(
        @src(),
        std.testing.allocator,
        \\<div style="border-style: solid;color: white;background-color: black;">
        \\  <p>When the sunlight strikes raindrops in the air, they act like a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon.</p>
        \\  <p>There is, according to legend, a boiling pot of gold at one end. People look but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow</p>
        \\</div>
        \\
    ,
        null,
    );
}
test "whites-pace: normal: text-align: center" {
    try assertDocumentSnapshotFromXml(
        @src(),
        std.testing.allocator,
        \\<div style="border-style: solid;text-align: center;color: white;background-color: black;">
        \\  <p>When the sunlight strikes raindrops in the air, they act like a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon.</p>
        \\  <p>There is, according to legend, a boiling pot of gold at one end. People look but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow</p>
        \\</div>
        \\
    ,
        null,
    );
}

test "whites-pace: normal: text-align: right" {
    try assertDocumentSnapshotFromXml(
        @src(),
        std.testing.allocator,
        \\<div style="border-style: solid;text-align: right;color: white;background-color: black;">
        \\  <p>When the sunlight strikes raindrops in the air, they act like a prism and form a rainbow. The rainbow is a division of white light into many beautiful colors. These take the shape of a long round arch, with its path high above, and its two ends apparently beyond the horizon.</p>
        \\  <p>There is, according to legend, a boiling pot of gold at one end. People look but no one ever finds it. When a man looks for something beyond his reach, his friends say he is looking for the pot of gold at the end of the rainbow</p>
        \\</div>
        \\
    ,
        null,
    );
}
test "whites-pace: pre" {
    try assertDocumentSnapshotFromXml(
        @src(),
        std.testing.allocator,
        \\<div style="border-style: solid;color: white;background-color: black;">
        \\  <pre>
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello, world!\n", .{});
        \\}
        \\  </pre>
        \\</div>
        \\
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
    );
}

test "whitespace: pre-wrap" {
    try assertDocumentSnapshotFromXml(
        @src(),
        std.testing.allocator,
        \\<div style="border-style: solid;color: white;background-color: black;">
        \\  <pre style="white-space: pre-wrap;">
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello, world!\n", .{});
        \\}
        \\  </pre>
        \\</div>
        \\
    ,
    // .{ .x = .{ .definite = 50 }, .y = .max_content },
        null,
    );
}

test "whites-pace: pre, overflow" {
    try assertDocumentSnapshotFromXml(
        @src(),
        std.testing.allocator,
        \\<div style="color: white;background-color: black;">
        \\
        \\  <pre style="white-space: pre;width: 28;border-style: solid;overflow: hidden;padding: 1;">
        \\const std = @import("std");
        \\
        \\pub fn main() void {
        \\    std.debug.print("Hello, world!\n", .{});
        \\}
        \\  </pre>
        \\</div>
        \\
    ,
        .{ .x = .{ .definite = 50 }, .y = .max_content },
    );
}
