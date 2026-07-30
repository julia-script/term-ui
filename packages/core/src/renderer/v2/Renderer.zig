const std = @import("std");
const Canvas = @import("Canvas.zig");
const Color = @import("../../colors/Color.zig");
const Point = @import("../../layout/point.zig").Point;
const PointF32 = Point(f32);
const layout_v2 = @import("../../layout/v2/mod.zig");
const RenderList = layout_v2.RenderList;

canvas: Canvas,
allocator: std.mem.Allocator,
render_buffer: std.ArrayListUnmanaged(u8) = .empty,

const Self = @This();

const BufferWriter = struct {
    buffer: *std.ArrayListUnmanaged(u8),
    allocator: std.mem.Allocator,

    pub const Error = error{OutOfMemory};

    pub fn print(self: BufferWriter, comptime format_str: []const u8, args: anytype) Error!void {
        var buf: [1024]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, format_str, args) catch return error.OutOfMemory;
        try self.writeAll(formatted);
    }

    pub fn writeAll(self: BufferWriter, bytes: []const u8) Error!void {
        self.buffer.appendSlice(self.allocator, bytes) catch return error.OutOfMemory;
    }

    pub fn writeByte(self: BufferWriter, byte: u8) Error!void {
        self.buffer.append(self.allocator, byte) catch return error.OutOfMemory;
    }

    pub fn splatByteAll(self: BufferWriter, byte: u8, n: usize) Error!void {
        try self.writeByteNTimes(byte, n);
    }

    pub fn writeByteNTimes(self: BufferWriter, byte: u8, n: usize) Error!void {
        for (0..n) |_| {
            try self.writeByte(byte);
        }
    }
};

pub const RenderMode = enum(u8) {
    /// Simple mode: render sequentially with newlines, no cursor positioning
    simple = 0,
    /// App mode: use cursor positioning and diffing for terminal apps
    app = 1,
    svg = 2,
};

pub fn init(allocator: std.mem.Allocator) !Self {
    // Initialize with a default size, will be resized based on layout
    return Self{
        .canvas = try Canvas.init(
            allocator,
            .{ .x = 0, .y = 0 },
            Color.tw.transparent,
            Color.tw.transparent,
        ),
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.canvas.deinit();
    self.render_buffer.deinit(self.allocator);
}

/// Render from a pre-built render list
pub fn render(self: *Self, render_list: *const RenderList, writer: anytype, mode: RenderMode) !void {
    // Get canvas size from the first element (viewport)
    if (render_list.items.items.len == 0) {
        // No content in render list
        return;
    }

    const first_item = render_list.items.items[0];
    const viewport_bounds = switch (first_item) {
        .box => |box| box.bounds,
        .push_clip => |clip| clip.rect,
        else => std.debug.panic("First render list item must be a box or push_clip for the viewport", .{}),
    };

    // Size canvas to viewport dimensions
    if (viewport_bounds.width > 0 and viewport_bounds.height > 0) {
        try self.canvas.resize(.{ .x = viewport_bounds.x + viewport_bounds.width, .y = viewport_bounds.y + viewport_bounds.height });
    } else {
        // No valid viewport dimensions
        return;
    }

    // Paint from render list
    try self.canvas.paintFromRenderList(render_list);

    // Render to terminal based on mode
    switch (mode) {
        .simple => try self.renderSimple(writer),
        .app => try self.renderApp(writer),
        .svg => try self.renderSvg(writer),
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

// /// Set render mode
// pub fn setRenderMode(self: *Self, mode: RenderMode) void {
//     self.render_mode = mode;
// }

/// Simple rendering: sequential output with newlines
fn renderSimple(self: *Self, writer: anytype) !void {
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

fn renderSvg(self: *Self, writer: anytype) !void {
    const cell_height: f32 = 12;
    const cell_width: f32 = 7;
    const font_size: f32 = 11;
    // TODO:
    const min_contrast_ratio: f32 = 4.5; // default vscode integrated terminal settings

    const cells = self.canvas.getCells();
    const dims = self.canvas.getDimensions();
    var color_buf: [7]u8 = undefined;

    const width = @as(f32, @floatFromInt(dims.width)) * cell_width;
    const height = @as(f32, @floatFromInt(dims.height)) * cell_height;

    try writer.print("<svg width=\"{d}\" height=\"{d}\" xmlns=\"http://www.w3.org/2000/svg\">\n", .{ width, height });

    try writer.writeAll(
        \\<style>
        \\  text {
    );
    try writer.print(
        \\    font-family: Menlo, Monaco, 'Courier New', monospace;
        \\    font-size: {d}px;
        \\    line-height: {d}px;
        \\
        \\
    , .{ font_size, cell_height });
    try writer.writeAll(
        \\  }
        \\</style>
        \\
    );
    try writer.print("<rect width=\"{d}\" height=\"{d}\" fill=\"{s}\" style=\"margin: auto;\" />", .{ width, height, try Color.tw.black.toHexString(color_buf[0..]) });
    for (0..dims.height) |y_index| {
        for (0..dims.width) |x_index| {
            const x: f32 = @floatFromInt(x_index);
            const y: f32 = @floatFromInt(y_index);
            const cell = &cells[y_index * dims.width + x_index];
            const x_pos = x * cell_width;
            const y_pos = y * cell_height;
            try writer.print("<g transform=\"translate({d}, {d})\">\n", .{ x_pos, y_pos });

            // background
            if (cell.bg.a > 0) {
                try writer.print("  <rect x=\"0\" y=\"0\" width=\"{d}\" height=\"{d}\" fill=\"{s}\" />\n", .{ cell_width, cell_height, try cell.bg.toHexString(color_buf[0..]) });
            }
            // text
            const text = cell.getChar();
            if (text.len > 0) {
                try writer.print("  <text x=\"{d}\" y=\"{d}\" fill=\"{s}\" text-anchor=\"middle\" dominant-baseline=\"middle\"", .{
                    cell_width / 2,
                    cell_height / 2,
                    try cell.fg.contrastedColor(cell.bg, min_contrast_ratio).toHexString(color_buf[0..]),
                });
                if (cell.format.is_bold) {
                    try writer.print(" font-weight=\"bold\"", .{});
                }
                if (cell.format.is_italic) {
                    try writer.print(" font-style=\"italic\"", .{});
                }
                // TODO: add other text decorations

                try writer.print(">{s}</text>\n", .{text});
            }
            try writer.print("</g>\n", .{});
        }
    }
    try writer.print("</svg>", .{});
}

/// App mode rendering: use cursor positioning and diffing
fn renderApp(self: *Self, writer: anytype) !void {
    const cells = self.canvas.getCells();
    const previous = self.canvas.getPreviousCells();
    const dims = self.canvas.getDimensions();

    self.render_buffer.clearRetainingCapacity();
    var buf_writer = BufferWriter{ .buffer = &self.render_buffer, .allocator = self.allocator };
    try buf_writer.writeAll("\x1b[H");

    // If there is no previous state (first frame) or dimensions changed,
    // force a full render: every cell is treated as dirty
    const force_full = previous.len == 0 or previous.len != cells.len;

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

            // Skip if cell hasn't changed (unless doing a full render)
            if (!force_full) {
                const prev_cell = &previous[idx];
                if (cell.equal(prev_cell)) {
                    continue;
                }
            }

            any_changes = true;

            // Calculate cursor movement
            const curr_x: i32 = @intCast(x);
            const curr_y: i32 = @intCast(y);
            const x_offset = curr_x - (last_x + 1);
            const y_offset = curr_y - last_y;

            try moveCursorBy(buf_writer, x_offset, y_offset);

            last_x = curr_x;
            last_y = curr_y;

            // Apply colors if changed
            if (last_bg == null or !last_bg.?.equal(cell.bg)) {
                try writeBgSequence(buf_writer, cell.bg);
                last_bg = cell.bg;
            }

            if (last_fg == null or !last_fg.?.equal(cell.fg)) {
                try writeFgSequence(buf_writer, cell.fg);
                last_fg = cell.fg;
            }

            // Apply text formatting if changed
            try writeFormattingSequence(buf_writer, last_format, cell.format);
            last_format = cell.format;

            // Write character
            const char = cell.getChar();
            try buf_writer.writeAll(if (char.len == 0) " " else char);

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
        try moveCursorBy(buf_writer, x_offset, y_offset);
        try buf_writer.writeAll("\x1b[0m");

        // Save current state so the next frame diffs against this one
        try self.canvas.savePreviousState();
        try writer.writeAll(self.render_buffer.items);
    }
}

// /// Full render for app mode (no diffing)
// fn renderAppFull(self: *Self, writer: anytype) !void {
//     const cells = self.canvas.getCells();
//     const dims = self.canvas.getDimensions();

//     // Move to home position
//     try writer.writeAll("\x1b[H");

//     var last_bg: ?Color = null;
//     var last_fg: ?Color = null;
//     var last_format = Canvas.TextFormat{};

//     for (0..dims.height) |y| {
//         var skip_cells: u32 = 0;

//         for (0..dims.width) |x| {
//             const cell = &cells[y * dims.width + x];

//             // Apply colors if changed
//             if (last_bg == null or !last_bg.?.equal(cell.bg)) {
//                 try writeBgSequence(writer, cell.bg);
//                 last_bg = cell.bg;
//             }

//             // Skip continuation cells
//             if (skip_cells > 0) {
//                 skip_cells -= 1;
//                 continue;
//             }

//             if (last_fg == null or !last_fg.?.equal(cell.fg)) {
//                 try writeFgSequence(writer, cell.fg);
//                 last_fg = cell.fg;
//             }

//             // Apply text formatting if changed
//             try writeFormattingSequence(writer, last_format, cell.format);
//             last_format = cell.format;

//             // Write character
//             if (cell.width == 0) {
//                 try writer.writeAll(" ");
//             } else {
//                 try writer.writeAll(cell.getChar());
//                 skip_cells = cell.width - 1;
//             }
//         }

//         // Move to next line
//         if (y < dims.height - 1) {
//             const x_back: i32 = -@as(i32, @intCast(dims.width));
//             try moveCursorBy(writer, x_back, 1);
//         }
//     }

//     // Reset at end
//     try writer.writeAll("\x1b[0m");
// }

// Helper functions for escape sequences
fn writeFgSequence(writer: anytype, fg: Color) !void {
    const r, const g, const b = fg.toU8RGB();
    try writer.print("\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
}

fn writeBgSequence(writer: anytype, bg: Color) !void {
    if (bg.a == 0) {
        try writer.print("\x1b[49m", .{});
        return;
    }
    const r, const g, const b = bg.toU8RGB();
    try writer.print("\x1b[48;2;{d};{d};{d}m", .{ r, g, b });
}

/// Move cursor by relative amount
fn moveCursorBy(writer: anytype, x: i32, y: i32) !void {
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
fn writeFormattingSequence(writer: anytype, current_format: Canvas.TextFormat, new_format: Canvas.TextFormat) !void {
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
    const docFromXml = layout_v2.docFromXml;

    const xml =
        \\<root style="width: 20px; height: 3px; background-color: #1f2937;">
        \\  <span>Hi👋🏼!</span>
        \\</root>
    ;

    const available_space = layout_v2.constants.AvailableSpacePoint{
        .x = .{ .definite = 20 },
        .y = .{ .definite = 3 },
    };
    var doc_tree = try docFromXml(std.testing.allocator, xml, .{});
    defer doc_tree.deinit();
    try doc_tree.computeStyles();
    try doc_tree.buildLayoutTree();

    try doc_tree.computeLayout(std.testing.allocator, available_space);

    var renderer = try init(std.testing.allocator);
    defer renderer.deinit();

    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();

    try doc_tree.paint(&renderer, &aw.writer, .app);

    try std.testing.expect(aw.writer.buffered().len > 0);
}

test "Renderer v2 basic rendering" {
    const docFromXml = layout_v2.docFromXml;

    const available_space = layout_v2.constants.AvailableSpacePoint{
        .x = .{ .definite = 80 },
        .y = .{ .definite = 24 },
    };
    const xml =
        \\<root style="width: 80px; height: 24px; background-color: #1f2937;">
        \\  <div style="width: 20px; height: 10px; background-color: #3b82f6;"></div>
        \\</root>
    ;
    var doc_tree = try docFromXml(std.testing.allocator, xml, .{});
    defer doc_tree.deinit();
    try doc_tree.computeStyles();
    try doc_tree.buildLayoutTree();
    try doc_tree.computeLayout(std.testing.allocator, available_space);
    var renderer = try init(std.testing.allocator);
    defer renderer.deinit();
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try doc_tree.paint(&renderer, &aw.writer, .app);

    try std.testing.expect(aw.writer.buffered().len > 0);
}
