const std = @import("std");
const pipeline = @import("../../testing/pipeline.zig");

test "pipeline: basic colored box" {
    const xml =
        \\<root style="width: 20px; height: 5px; background-color: #3b82f6;">
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "basic-colored-box",
        .{
            .available_space = .{ .width = 30, .height = 10 },
        },
        @src(),
    );
}

test "pipeline: nested boxes" {
    const xml =
        \\<root style="width: 30px; height: 10px; background-color: #1f2937;">
        \\  <div style="width: 10px; height: 3px; background-color: #3b82f6;"></div>
        \\  <div style="width: 15px; height: 4px; background-color: #10b981;"></div>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "nested-boxes",
        .{
            .available_space = .{ .width = 40, .height = 15 },
        },
        @src(),
    );
}

test "pipeline: text rendering" {
    const xml =
        \\<root style="width: 40px; height: 5px; background-color: #1e293b;">
        \\  <span style="color: #f59e0b;">Hello, World!</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-rendering",
        .{
            .available_space = .{ .width = 50, .height = 10 },
        },
        @src(),
    );
}

test "pipeline: multi-width characters" {
    const xml =
        \\<root style="width: 30px; height: 5px; background-color: #1e293b;">
        \\  <span style="color: #f59e0b;">Hi 👋 World!</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "multi-width-characters",
        .{
            .available_space = .{ .width = 40, .height = 8 },
        },
        @src(),
    );
}

test "pipeline: z-index ordering" {
    const xml =
        \\<root style="width: 30px; height: 10px; background-color: #f3f4f6;">
        \\  <div style="position: absolute; left: 5px; top: 2px; width: 10px; height: 4px; background-color: #ef4444; z-index: 2;"></div>
        \\  <div style="position: absolute; left: 8px; top: 3px; width: 10px; height: 4px; background-color: #3b82f6; z-index: 1;"></div>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "z-index-ordering",
        .{
            .available_space = .{ .width = 40, .height = 15 },
        },
        @src(),
    );
}

test "pipeline: text wrapping" {
    const xml =
        \\<root style="width: 20px; height: 10px; background-color: #1f2937;">
        \\  <span style="color: #fbbf24;">This is a long text that should wrap to multiple lines</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-wrapping",
        .{
            .available_space = .{ .width = 25, .height = 15 },
        },
        @src(),
    );
}

test "pipeline: inline and block mixing" {
    const xml =
        \\<root style="width: 40px; height: 15px; background-color: #f9fafb;">
        \\  <div style="background-color: #e5e7eb;">Block 1</div>
        \\  <span style="color: #dc2626;">Inline text</span>
        \\  <span style="color: #059669;"> with more text</span>
        \\  <div style="background-color: #d1d5db;">Block 2</div>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "inline-block-mixing",
        .{
            .available_space = .{ .width = 50, .height = 20 },
        },
        @src(),
    );
}

test "pipeline: simple border" {
    const xml =
        \\<root style="width: 20px; height: 5px; background-color: #f3f4f6;">
        \\  <div style="width: 10px; height: 3px; background-color: #3b82f6; border-style: solid; border-color: #1e40af;"></div>
        \\</root>
    ;
    
    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "simple-border",
        .{
            .available_space = .{ .width = 30, .height = 10 },
        },
        @src(),
    );
}

test "pipeline: text formatting" {
    const xml =
        \\<root style="width: 50px; height: 8px; background-color: #1e293b;">
        \\  <span style="font-weight: bold; color: #f59e0b;">Bold text</span>
        \\  <span style="font-style: italic; color: #10b981;"> Italic</span>
        \\  <span style="text-decoration: underline; color: #3b82f6;"> Underline</span>
        \\  <span style="text-decoration: line-through; color: #ef4444;"> Strike</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-formatting",
        .{
            .available_space = .{ .width = 60, .height = 10 },
        },
        @src(),
    );
}

test "pipeline: linear gradient background" {
    const xml =
        \\<root style="width: 30px; height: 10px; background-color: linear-gradient(to right, #3b82f6, #10b981);">
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "linear-gradient-bg",
        .{
            .available_space = .{ .width = 40, .height = 15 },
        },
        @src(),
    );
}

test "pipeline: radial gradient background" {
    const xml =
        \\<root style="width: 20px; height: 10px; background-color: radial-gradient(circle, #f59e0b, #dc2626);">
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "radial-gradient-bg",
        .{
            .available_space = .{ .width = 30, .height = 15 },
        },
        @src(),
    );
}

test "pipeline: gradient border" {
    const xml =
        \\<root style="width: 20px; height: 8px; background-color: #1e293b; border-style: solid; border-width: 2px; border-color: linear-gradient(45deg, #3b82f6, #f59e0b);">
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "gradient-border",
        .{
            .available_space = .{ .width = 30, .height = 12 },
        },
        @src(),
    );
}

test "pipeline: text selection" {
    const xml =
        \\<root style="width: 40px; height: 5px; background-color: #1e293b;">
        \\  <span style="color: #f59e0b;">Hello, World!</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "text-selection",
        .{
            .available_space = .{ .width = 50, .height = 10 },
            // Select "World" - text node is typically node 2 (root=0, span=1, text=2)
            .selections = &[_][3]u32{
                .{ 2, 7, 12 }, // node_id=2, start=7, end=12
            },
        },
        @src(),
    );
}

test "pipeline: multiple selections" {
    const xml =
        \\<root style="width: 50px; height: 8px; background-color: #1e293b;">
        \\  <span style="color: #10b981;">The quick brown fox jumps over the lazy dog</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "multiple-selections",
        .{
            .available_space = .{ .width = 60, .height = 10 },
            // Select "quick" and "lazy"
            .selections = &[_][3]u32{
                .{ 2, 4, 9 },   // "quick"
                .{ 2, 35, 39 }, // "lazy"
            },
        },
        @src(),
    );
}

test "pipeline: selection spanning wrapped text" {
    const xml =
        \\<root style="width: 20px; height: 10px; background-color: #1f2937;">
        \\  <span style="color: #fbbf24;">This is a long text that should wrap to multiple lines</span>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "selection-wrapped-text",
        .{
            .available_space = .{ .width = 25, .height = 15 },
            // Select from "long" to "should"
            .selections = &[_][3]u32{
                .{ 2, 10, 30 }, // "long text that should"
            },
        },
        @src(),
    );
}

test "pipeline: empty text node selection" {
    const xml =
        \\<root style="width: 40px; height: 10px; background-color: #1e293b;">
        \\  <div style="color: #f59e0b;">First<span>   </span>paragraph</div>
        \\</root>
    ;

    try pipeline.expectPipeline(
        std.testing.allocator,
        xml,
        "empty-text-node-selection",
        .{
            .available_space = .{ .width = 50, .height = 15 },
            // Select the whitespace-only span content
            // Text nodes: root=0, div=1, text1=2, span=3, text2=4, text3=5
            .selections = &[_][3]u32{
                .{ 4, 0, 3 }, // The three spaces in the span
            },
        },
        @src(),
    );
}
