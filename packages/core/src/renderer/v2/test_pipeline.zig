const std = @import("std");
const pipeline = @import("../../testing/pipeline.zig");

test "pipeline: basic colored box" {
    const xml =
        \\<div style="width: 20px; height: 5px; background-color: #3b82f6;">
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "basic-colored-box",
        .{
            .available_space = .{ .x = .{ .definite = 30 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: nested boxes" {
    const xml =
        \\<div style="width: 30px; height: 10px; background-color: #1f2937;">
        \\  <div style="width: 10px; height: 3px; background-color: #3b82f6;"></div>
        \\  <div style="width: 15px; height: 4px; background-color: #10b981;"></div>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "nested-boxes",
        .{
            .available_space = .{ .x = .{ .definite = 40 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: text rendering" {
    const xml =
        \\<div style="width: 40px; height: 5px; background-color: #1e293b;">
        \\  <span style="color: #f59e0b;">Hello, World!</span>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-rendering",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: multi-width characters" {
    const xml =
        \\<div style="width: 30px; height: 5px; background-color: #1e293b;">
        \\  <span style="color: #f59e0b;">Hi 👋 World!</span>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "multi-width-characters",
        .{
            .available_space = .{ .x = .{ .definite = 40 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: text wrapping" {
    const xml =
        \\<div style="width: 20px; height: 10px; background-color: #1f2937;">
        \\  <span style="color: #fbbf24;">This is a long text that should wrap to multiple lines</span>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-wrapping",
        .{
            .available_space = .{ .x = .{ .definite = 25 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: inline and block mixing" {
    const xml =
        \\<div style="width: 40px; height: 15px; background-color: #f9fafb;">
        \\  <div style="background-color: #e5e7eb;">Block 1</div>
        \\  <span style="color: #dc2626;">Inline text</span>
        \\  <span style="color: #059669;"> with more text</span>
        \\  <div style="background-color: #d1d5db;">Block 2</div>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "inline-block-mixing",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: simple border" {
    const xml =
        \\<div style="width: 20px; height: 5px; background-color: #f3f4f6;">
        \\  <div style="width: 10px; height: 3px; background-color: #3b82f6; border-style: solid; border-color: #1e40af;"></div>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "simple-border",
        .{
            .available_space = .{ .x = .{ .definite = 30 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: text formatting" {
    const xml =
        \\<div style="width: 50px; height: 8px; background-color: #1e293b;">
        \\  <span style="font-weight: bold; color: #f59e0b;">Bold text</span>
        \\  <span style="font-style: italic; color: #10b981;"> Italic</span>
        \\  <span style="text-decoration: underline; color: #3b82f6;"> Underline</span>
        \\  <span style="text-decoration: line-through; color: #ef4444;"> Strike</span>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-formatting",
        .{
            .available_space = .{ .x = .{ .definite = 60 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: linear gradient background" {
    const xml =
        \\<div style="width: 30px; height: 10px; background-color: linear-gradient(to right, #3b82f6, #10b981);">
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "linear-gradient-bg",
        .{
            .available_space = .{ .x = .{ .definite = 40 }, .y = .max_content },
        },
        @src(),
    );
}

test "pipeline: radial gradient background" {
    const xml =
        \\<div style="width: 20px; height: 10px; background-color: radial-gradient(circle, #f59e0b, #dc2626);">
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "radial-gradient-bg",
        .{
            .available_space = .{ .x = .{ .definite = 30 }, .y = .{ .definite = 15 } },
        },
        @src(),
    );
}

test "pipeline: gradient border" {
    const xml =
        \\<div style="width: 20px; height: 8px; background-color: #1e293b; border-style: solid; border-width: 2px; border-color: linear-gradient(45deg, #3b82f6, #f59e0b);">
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "gradient-border",
        .{
            .available_space = .{ .x = .{ .definite = 30 }, .y = .{ .definite = 12 } },
        },
        @src(),
    );
}

test "pipeline: empty text node selection" {
    const xml =
        \\<div style="width: 40px; height: 10px; background-color: #1e293b;">
        \\  <div style="color: #f59e0b;">First<span>   </span>paragraph</div>
        \\</div>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "empty-text-node-selection",
        .{
            .available_space = .{ .x = .{ .definite = 50 }, .y = .{ .definite = 15 } },
        },
        @src(),
    );
}
