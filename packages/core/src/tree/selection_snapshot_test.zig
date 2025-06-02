const std = @import("std");
const pipeline = @import("../testing/pipeline.zig");

test "pipeline: selection basic movement" {
    const xml =
        \\<view style="display:flex; flex-direction: column; background-color: red; height:10px; width:50px;">
        \\  <view style="width:30px; background-color: blue; text-align: center; margin: auto;">
        \\    <text>Lorem ipsum dolor sit amet </text>
        \\    <text>Lorem ipsum dolor sit amet </text>
        \\    <text>Lorem ipsum dolor sit amet </text>
        \\  </view>
        \\</view>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "selection-basic-movement",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .max_content },
            .selections = &[_][3]u32{
                .{ 3, 4, 5 }, // Select one character in first text node
            },
        },
        @src(),
    );
}

test "pipeline: selection across text nodes" {
    const xml =
        \\<root style="width: 60px; background-color: #1e293b;">
        \\  <div style="color: #f59e0b;">
        \\    <span>First text </span>
        \\    <span>Second text </span>
        \\    <span>Third text</span>
        \\  </div>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "selection-across-nodes",
        .{
            .available_space = .{ .x = .{ .definite = 60 }, .y = .max_content },
            .selections = &[_][3]u32{
                .{ 3, 6, 11 }, // Select "text " from first span
                .{ 5, 0, 6 }, // Select "Second" from second span
            },
        },
        @src(),
    );
}

test "pipeline: selection with line movement" {
    const xml =
        \\<view style="display:flex; flex-direction: column; background-color: red; height:10px; width:50px;">
        \\  <view style="width:30px; background-color: blue; text-align: center; margin: auto;">
        \\    <text>First line</text>
        \\    <text>Second line</text>
        \\    <text>Third line</text>
        \\  </view>
        \\</view>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "selection-line-movement",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .max_content },
            .selections = &[_][3]u32{
                .{ 3, 0, 5 }, // Select "First" in first line
                .{ 5, 3, 7 }, // Select "ond " in second line
            },
        },
        @src(),
    );
}

test "pipeline: selection movement across boundaries" {
    const xml =
        \\<view style="display:flex; flex-direction: column; background-color: red; height:10px; width:50px;">
        \\  <view style="width:30px; background-color: blue; text-align: center; margin: auto;">
        \\    <text>First line</text>
        \\    <view>
        \\      <text>Second line</text>
        \\    </view>
        \\    <view>
        \\      <view>
        \\        <text>Third line</text>
        \\      </view>
        \\    </view>
        \\  </view>
        \\</view>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "selection-across-boundaries",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .max_content },
            .selections = &[_][3]u32{
                .{ 3, 0, 10 }, // Select entire "First line"
                .{ 6, 0, 11 }, // Select entire "Second line"
                .{ 10, 0, 10 }, // Select entire "Third line"
            },
        },
        @src(),
    );
}

test "pipeline: selection from long to short line" {
    const xml =
        \\<view style="display:flex; flex-direction: column; background-color: red; height:10px; width:50px;">
        \\  <view style="width:40px; background-color: blue; text-align: center; margin: auto;">
        \\    <text>This is a long paragraph of text.</text>
        \\    <text>short</text>
        \\    <text>This is another long paragraph of text.</text>
        \\  </view>
        \\</view>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "selection-long-to-short",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .max_content },
            .selections = &[_][3]u32{
                .{ 3, 20, 25 }, // Select portion of long line
                .{ 5, 0, 5 }, // Select entire short line
            },
        },
        @src(),
    );
}