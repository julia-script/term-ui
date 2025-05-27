const std = @import("std");
const Canvas = @import("Canvas.zig");
const Color = @import("../../colors/Color.zig");
const Point = @import("../../layout/point.zig").Point;
const PointF32 = Point(f32);
const layout_v2 = @import("../../layout/v2/mod.zig");
const RenderList = layout_v2.RenderList;

canvas: Canvas,
allocator: std.mem.Allocator,
render_mode: RenderMode = .simple,

const Self = @This();

pub const RenderMode = enum {
    /// Simple mode: render sequentially with newlines, no cursor positioning
    simple,
    /// App mode: use cursor positioning and diffing for terminal apps
    app,
};

pub fn init(allocator: std.mem.Allocator) !Self {
    // Initialize with a default size, will be resized based on layout
    return Self{
        .canvas = try Canvas.init(
            allocator,
            .{ .x = 0, .y = 0 },
            Color.tw.black,
            Color.tw.white,
        ),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.canvas.deinit();
}

/// Render from a pre-built render list
pub fn render(self: *Self, render_list: *const RenderList, writer: std.io.AnyWriter) !void {
    // Infer canvas size from render list bounds
    var max_x: f32 = 0;
    var max_y: f32 = 0;

    for (render_list.items.items) |item| {
        const bounds = switch (item) {
            .box => |box| box.bounds,
            .text_fragment => |text| text.bounds,
            .push_clip => |clip| clip.rect,
            .pop_clip => continue,
        };

        max_x = @max(max_x, bounds.x + bounds.width);
        max_y = @max(max_y, bounds.y + bounds.height);
    }

    // Resize canvas to fit content (keep as floats)
    if (max_x > 0 and max_y > 0) {
        try self.canvas.resize(.{ .x = max_x, .y = max_y });
    } else {
        // No content in render list
        return;
    }

    // Paint from render list
    try self.canvas.paintFromRenderList(render_list);

    // Render to terminal based on mode
    switch (self.render_mode) {
        .simple => try self.renderSimple(writer),
        .app => try self.renderApp(writer),
    }
}

/// Resize the canvas if needed
pub fn resize(self: *Self, size: PointF32) !void {
    try self.canvas.resize(size);
}

/// Clear the canvas
pub fn clear(self: *Self) void {
    self.canvas.clear();
}

/// Set render mode
pub fn setRenderMode(self: *Self, mode: RenderMode) void {
    self.render_mode = mode;
}

/// Simple rendering: sequential output with newlines
fn renderSimple(self: *Self, writer: std.io.AnyWriter) !void {
    const cells = self.canvas.getCells();
    const dims = self.canvas.getDimensions();

    var last_bg: ?Color = null;
    var last_fg: ?Color = null;
    var last_format = Canvas.TextFormat{};

    for (0..dims.height) |y| {
        var skip_cells: u32 = 0;

        for (0..dims.width) |x| {
            const cell = &cells[y * dims.width + x];

            // Only write color sequences if they changed
            if (last_bg == null or !last_bg.?.equal(cell.bg)) {
                try writeBgSequence(writer, cell.bg);
                last_bg = cell.bg;
            }

            // Skip continuation cells
            if (skip_cells > 0) {
                skip_cells -= 1;
                continue;
            }

            if (last_fg == null or !last_fg.?.equal(cell.fg)) {
                try writeFgSequence(writer, cell.fg);
                last_fg = cell.fg;
            }

            // Apply text formatting if changed
            try writeFormattingSequence(writer, last_format, cell.format);
            last_format = cell.format;

            // Write character
            if (cell.width == 0) {
                // This is a continuation cell that wasn't properly skipped, write space
                try writer.writeAll(" ");
            } else {
                try writer.writeAll(cell.getChar());
                skip_cells = cell.width - 1;
            }
        }
        // Reset at end of line and add newline
        try writer.writeAll("\x1b[0m\n");
        last_bg = null;
        last_fg = null;
        last_format = .{};
    }
}

/// App mode rendering: use cursor positioning and diffing
fn renderApp(self: *Self, writer: std.io.AnyWriter) !void {
    const cells = self.canvas.getCells();
    const previous = self.canvas.getPreviousCells();
    const dims = self.canvas.getDimensions();

    // If no previous state or dimensions changed, do a full render
    if (previous.len == 0 or previous.len != cells.len) {
        try self.renderAppFull(writer);
        try self.canvas.savePreviousState();
        return;
    }

    var last_bg: ?Color = null;
    var last_fg: ?Color = null;
    var last_format = Canvas.TextFormat{};
    var last_x: i32 = -1;
    var last_y: i32 = 0;
    var any_changes = false;

    // Diff and render only changed cells
    for (0..dims.height) |y| {
        for (0..dims.width) |x| {
            const idx = y * dims.width + x;
            const cell = &cells[idx];
            const prev_cell = &previous[idx];

            // Skip if cell hasn't changed
            if (cell.equal(prev_cell)) {
                continue;
            }

            any_changes = true;

            // Calculate cursor movement
            const curr_x: i32 = @intCast(x);
            const curr_y: i32 = @intCast(y);
            const x_offset = curr_x - (last_x + 1);
            const y_offset = curr_y - last_y;

            try moveCursorBy(writer, x_offset, y_offset);
            last_x = curr_x;
            last_y = curr_y;

            // Apply colors if changed
            if (last_bg == null or !last_bg.?.equal(cell.bg)) {
                try writeBgSequence(writer, cell.bg);
                last_bg = cell.bg;
            }

            if (last_fg == null or !last_fg.?.equal(cell.fg)) {
                try writeFgSequence(writer, cell.fg);
                last_fg = cell.fg;
            }

            // Apply text formatting if changed
            try writeFormattingSequence(writer, last_format, cell.format);
            last_format = cell.format;

            // Write character
            try writer.writeAll(cell.getChar());

            // Skip continuation cells
            if (cell.width > 1) {
                last_x += @as(i32, @intCast(cell.width - 1));
            }
        }
    }

    // Only update if there were changes
    if (any_changes) {
        // Move cursor to bottom-left and reset
        const final_y: i32 = @intCast(dims.height);
        const y_offset = final_y - last_y;
        const x_offset = -last_x - 1;
        try moveCursorBy(writer, x_offset, y_offset);
        try writer.writeAll("\x1b[0m");

        // Save current state as previous
        try self.canvas.savePreviousState();
    }
}

/// Full render for app mode (no diffing)
fn renderAppFull(self: *Self, writer: std.io.AnyWriter) !void {
    const cells = self.canvas.getCells();
    const dims = self.canvas.getDimensions();

    // Move to home position
    try writer.writeAll("\x1b[H");

    var last_bg: ?Color = null;
    var last_fg: ?Color = null;
    var last_format = Canvas.TextFormat{};

    for (0..dims.height) |y| {
        var skip_cells: u32 = 0;

        for (0..dims.width) |x| {
            const cell = &cells[y * dims.width + x];

            // Apply colors if changed
            if (last_bg == null or !last_bg.?.equal(cell.bg)) {
                try writeBgSequence(writer, cell.bg);
                last_bg = cell.bg;
            }

            // Skip continuation cells
            if (skip_cells > 0) {
                skip_cells -= 1;
                continue;
            }

            if (last_fg == null or !last_fg.?.equal(cell.fg)) {
                try writeFgSequence(writer, cell.fg);
                last_fg = cell.fg;
            }

            // Apply text formatting if changed
            try writeFormattingSequence(writer, last_format, cell.format);
            last_format = cell.format;

            // Write character
            if (cell.width == 0) {
                try writer.writeAll(" ");
            } else {
                try writer.writeAll(cell.getChar());
                skip_cells = cell.width - 1;
            }
        }

        // Move to next line
        if (y < dims.height - 1) {
            const x_back: i32 = -@as(i32, @intCast(dims.width));
            try moveCursorBy(writer, x_back, 1);
        }
    }

    // Reset at end
    try writer.writeAll("\x1b[0m");
}

// Helper functions for escape sequences
fn writeFgSequence(writer: std.io.AnyWriter, fg: Color) !void {
    const r, const g, const b = fg.toU8RGB();
    try writer.print("\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
}

fn writeBgSequence(writer: std.io.AnyWriter, bg: Color) !void {
    const r, const g, const b = bg.toU8RGB();
    try writer.print("\x1b[48;2;{d};{d};{d}m", .{ r, g, b });
}

/// Move cursor by relative amount
fn moveCursorBy(writer: std.io.AnyWriter, x: i32, y: i32) !void {
    if (y > 0) {
        try writer.print("\x1b[{d}B", .{y});
    } else if (y < 0) {
        try writer.print("\x1b[{d}A", .{-y});
    }

    if (x > 0) {
        try writer.print("\x1b[{d}C", .{x});
    } else if (x < 0) {
        try writer.print("\x1b[{d}D", .{-x});
    }
}

/// Write text formatting escape sequences
fn writeFormattingSequence(writer: std.io.AnyWriter, current_format: Canvas.TextFormat, new_format: Canvas.TextFormat) !void {
    // Bold
    if (current_format.is_bold != new_format.is_bold) {
        if (new_format.is_bold) {
            try writer.print("\x1b[1m", .{}); // Enable bold
        } else {
            try writer.print("\x1b[22m", .{}); // Disable bold
        }
    }

    // Italic
    if (current_format.is_italic != new_format.is_italic) {
        if (new_format.is_italic) {
            try writer.print("\x1b[3m", .{}); // Enable italic
        } else {
            try writer.print("\x1b[23m", .{}); // Disable italic
        }
    }

    // Underline
    if ((current_format.decoration_line == .underline) != (new_format.decoration_line == .underline)) {
        if (new_format.decoration_line == .underline) {
            try writer.print("\x1b[4m", .{}); // Enable underline
        } else {
            try writer.print("\x1b[24m", .{}); // Disable underline
        }
    }

    // Strikethrough
    if ((current_format.decoration_line == .line_through) != (new_format.decoration_line == .line_through)) {
        if (new_format.decoration_line == .line_through) {
            try writer.print("\x1b[9m", .{}); // Enable strikethrough
        } else {
            try writer.print("\x1b[29m", .{}); // Disable strikethrough
        }
    }

    // TODO: Handle dim when added to TextFormat
}

test "Renderer v2 multi-width characters" {
    const LayoutTree = layout_v2.LayoutTree;
    const LayoutContext = layout_v2.LayoutContext;
    const computeLayout = layout_v2.computeLayout;
    const RenderListBuilder = layout_v2.RenderListBuilder;
    const docFromXml = layout_v2.docFromXml;

    const xml =
        \\<root style="width: 20px; height: 3px; background-color: #1f2937;">
        \\  <span>Hi👋🏼!</span>
        \\</root>
    ;

    var doc_tree = try docFromXml(std.testing.allocator, xml, .{});
    defer doc_tree.deinit();

    // Build layout tree
    var layout_tree = try LayoutTree.fromTree(std.testing.allocator, &doc_tree);
    defer layout_tree.deinit();

    // Create layout context
    var layout_context = LayoutContext{
        .layout_tree = &layout_tree,
        .doc_tree = &doc_tree,
        .allocator = std.testing.allocator,
    };

    // Compute layout
    const available_space = layout_v2.PointOf(layout_v2.constants.AvailableSpace){
        .x = .{ .definite = 20 },
        .y = .{ .definite = 3 },
    };

    try computeLayout(&layout_context, available_space);

    // Build render list
    var render_list = RenderList.init(std.testing.allocator);
    defer render_list.deinit();

    var builder = RenderListBuilder.init(&layout_tree, &doc_tree, &render_list);
    try builder.build();

    // Create renderer
    var renderer = try init(std.testing.allocator);
    defer renderer.deinit();

    // Render to a buffer
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try renderer.render(&render_list, buffer.writer().any());

    // Should have rendered something
    try std.testing.expect(buffer.items.len > 0);
}

test "Renderer v2 basic rendering" {
    const LayoutTree = layout_v2.LayoutTree;
    const LayoutContext = layout_v2.LayoutContext;
    const computeLayout = layout_v2.computeLayout;
    const RenderListBuilder = layout_v2.RenderListBuilder;
    const docFromXml = layout_v2.docFromXml;

    const xml =
        \\<root style="width: 80px; height: 24px; background-color: #1f2937;">
        \\  <div style="width: 20px; height: 10px; background-color: #3b82f6;"></div>
        \\</root>
    ;

    var doc_tree = try docFromXml(std.testing.allocator, xml, .{});
    defer doc_tree.deinit();

    // Build layout tree
    var layout_tree = try LayoutTree.fromTree(std.testing.allocator, &doc_tree);
    defer layout_tree.deinit();

    // Create layout context
    var layout_context = LayoutContext{
        .layout_tree = &layout_tree,
        .doc_tree = &doc_tree,
        .allocator = std.testing.allocator,
    };

    // Compute layout
    const available_space = layout_v2.PointOf(layout_v2.constants.AvailableSpace){
        .x = .{ .definite = 80 },
        .y = .{ .definite = 24 },
    };

    try computeLayout(&layout_context, available_space);

    // Build render list
    var render_list = RenderList.init(std.testing.allocator);
    defer render_list.deinit();

    var builder = RenderListBuilder.init(&layout_tree, &doc_tree, &render_list);
    try builder.build();

    // Create renderer (size will be inferred from render list)
    var renderer = try init(std.testing.allocator);
    defer renderer.deinit();

    // Render to a buffer
    var buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer buffer.deinit();

    try renderer.render(&render_list, buffer.writer().any());

    // Should have rendered something
    try std.testing.expect(buffer.items.len > 0);
}
