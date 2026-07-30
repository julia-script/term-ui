const std = @import("std");
const Array = std.ArrayListUnmanaged;
const Point = @import("../../layout/point.zig").Point;
const PointF32 = Point(f32);
const Color = @import("../../colors/Color.zig");
const LayoutRect = @import("../../layout/rect.zig").Rect;
const styles = @import("../../styles/styles.zig");
const RenderList = @import("../../layout/v2/mod.zig").RenderList;
const string_width = @import("../../uni/string-width.zig");
const grapheme = @import("../../layout/grapheme.zig");
const css_types = @import("../../css/types.zig");
const toType = @import("../../utils/convert.zig").toType;
const assert = std.debug.assert;
const gradient = @import("./gradient.zig");
const Sampler = gradient.Sampler;

cells: Array(Cell) = .empty,
previous_cells: Array(Cell) = .empty,
force_redraw: bool = true,
clear_color: Color = Color.tw.black,
fg_color: Color = Color.tw.white,
allocator: std.mem.Allocator,
size: PointF32,
/// Stack of clipping rectangles
clip_stack: Array(RenderList.Rect) = .empty,
/// Current clipping rectangle
clip_rect: RenderList.Rect,

const Self = @This();

pub const Rect = RenderList.Rect;

pub const Cell = struct {
    data: CellData = .text,
    bg: Color,
    fg: Color,
    format: TextFormat = .{},
    width: u32 = 1,
    is_continuation: bool = false,
    // Inline UTF-8 storage for the cell's grapheme (text and border chars).
    // Cells are copied wholesale into previous_cells for frame diffing, so
    // they must own their bytes: a slice into the render list would dangle
    // once the next frame rebuilds it (this caused transient scrambling
    // while scrolling).
    char_buf: [28]u8 = @splat(' '),
    char_len: u8 = 1,

    pub const CellData = union(enum) {
        text: void,
        border_char: styles.border.BoxChar,
    };

    pub fn setTextBytes(self: *Cell, bytes: []const u8) void {
        const n: u8 = @intCast(@min(bytes.len, self.char_buf.len));
        @memcpy(self.char_buf[0..n], bytes[0..n]);
        self.char_len = n;
        self.data = .text;
    }

    /// Set border character, merging with existing border if present
    pub fn setBorderChar(self: *Cell, border_char: styles.border.BoxChar) void {
        switch (self.data) {
            .text => {
                // Replace text with border
                self.data = .{ .border_char = border_char };
                self.width = 1;
            },
            .border_char => |*existing| {
                // Merge borders - only update sides that have non-none style
                if (border_char.n.style != .none) {
                    existing.n = border_char.n;
                }
                if (border_char.e.style != .none) {
                    existing.e = border_char.e;
                }
                if (border_char.s.style != .none) {
                    existing.s = border_char.s;
                }
                if (border_char.w.style != .none) {
                    existing.w = border_char.w;
                }
                self.width = 1;
            },
        }

        // Update the char buffer with the UTF-8 representation
        if (self.data == .border_char) {
            const char_code = styles.border.BoxChar.getChar(self.data.border_char);
            self.char_len = @intCast(std.unicode.utf8Encode(char_code, &self.char_buf) catch 1);
        }
    }

    /// Get the character to render
    pub fn getChar(self: *const Cell) []const u8 {
        return self.char_buf[0..self.char_len];
    }

    /// Set background color with compositing
    pub fn setBg(self: *Cell, color: Color) void {
        self.bg = Color.composite(color, self.bg, .source_over);
    }

    /// Set foreground color with compositing against background
    pub fn setFg(self: *Cell, color: Color) void {
        self.fg = Color.composite(color, self.bg, .source_over);
    }

    /// Check if two cells are equal
    pub fn equal(self: *const Cell, other: *const Cell) bool {
        if (!self.bg.equal(other.bg)) return false;
        if (!self.fg.equal(other.fg)) return false;
        if (self.width != other.width) return false;
        if (self.is_continuation != other.is_continuation) return false;

        // Compare format
        if (!self.format.equal(other.format)) return false;

        // Compare cell data (bytes are owned inline)
        if (!std.mem.eql(u8, self.getChar(), other.getChar())) return false;
        switch (self.data) {
            .text => switch (other.data) {
                .text => {},
                .border_char => return false,
            },
            .border_char => |a_border| switch (other.data) {
                .text => return false,
                .border_char => |b_border| {
                    if (a_border.n.style != b_border.n.style or a_border.n.weight != b_border.n.weight) return false;
                    if (a_border.e.style != b_border.e.style or a_border.e.weight != b_border.e.weight) return false;
                    if (a_border.s.style != b_border.s.style or a_border.s.weight != b_border.s.weight) return false;
                    if (a_border.w.style != b_border.w.style or a_border.w.weight != b_border.w.weight) return false;
                },
            },
        }

        return true;
    }
};

pub const TextFormat = struct {
    is_bold: bool = false,
    is_italic: bool = false,
    decoration_line: styles.text_decoration.TextDecorationLine = .none,
    decoration_color: ?Color = null,

    pub fn fromStyle(
        font_weight: styles.font_weight.FontWeight,
        font_style: styles.font_style.FontStyle,
        text_decoration: styles.text_decoration.TextDecoration,
    ) TextFormat {
        return .{
            .is_bold = font_weight == .bold,
            .is_italic = font_style == .italic,
            .decoration_line = text_decoration.line,
        };
    }

    pub fn equal(self: TextFormat, other: TextFormat) bool {
        if (self.is_bold != other.is_bold) return false;
        if (self.is_italic != other.is_italic) return false;
        if (self.decoration_line != other.decoration_line) return false;

        // Compare optional decoration_color
        if (self.decoration_color) |self_color| {
            if (other.decoration_color) |other_color| {
                if (!self_color.equal(other_color)) return false;
            } else {
                return false;
            }
        } else if (other.decoration_color != null) {
            return false;
        }

        return true;
    }
};

pub fn init(allocator: std.mem.Allocator, size: PointF32, clear_color: Color, fg_color: Color) !Self {
    var self = Self{
        .allocator = allocator,
        .size = size,
        .clear_color = clear_color,
        .fg_color = fg_color,
        .clip_rect = .{ .x = 0, .y = 0, .width = size.x, .height = size.y },
    };

    const width_int = toType(u32, @ceil(size.x));
    const height_int = toType(u32, @ceil(size.y));
    const cell_count = width_int * height_int;
    try self.cells.ensureTotalCapacity(allocator, cell_count);
    try self.previous_cells.ensureTotalCapacity(allocator, cell_count);

    // Initialize cells
    for (0..cell_count) |_| {
        self.cells.appendAssumeCapacity(.{ .bg = clear_color, .fg = fg_color });
        self.previous_cells.appendAssumeCapacity(.{ .bg = clear_color, .fg = fg_color });
    }

    return self;
}

pub fn deinit(self: *Self) void {
    self.cells.deinit(self.allocator);
    self.previous_cells.deinit(self.allocator);
    self.clip_stack.deinit(self.allocator);
}

/// Clear a cell and optionally its related cells (for multi-width characters)
/// @param check_related: if true, clears related cells for multi-width chars (use for boundary cells)
fn clearCell(self: *Self, x: u32, y: u32, check_related: bool) void {
    const cell = self.getCell(x, y) orelse return;

    if (check_related) {
        // If this is a continuation cell, find and clear from the main cell
        if (cell.is_continuation) {
            // Look left to find the main cell
            var main_x = @as(i32, @intCast(x)) - 1;
            while (main_x >= 0) : (main_x -= 1) {
                if (self.getCell(@intCast(main_x), y)) |main_cell| {
                    if (!main_cell.is_continuation and main_cell.width > 0) {
                        // Found the main cell, clear it and all its continuations
                        const width = main_cell.width;
                        for (0..width) |offset| {
                            if (self.getCell(@intCast(main_x + @as(i32, @intCast(offset))), y)) |c| {
                                c.setTextBytes("");
                                c.width = 0;
                                c.is_continuation = false;
                            }
                        }
                        return;
                    }
                } else {
                    break;
                }
            }
        } else if (cell.width > 1) {
            // This is a main cell with width > 1, clear all continuations
            for (1..cell.width) |offset| {
                if (self.getCell(x + @as(u32, @intCast(offset)), y)) |cont_cell| {
                    cont_cell.setTextBytes("");
                    cont_cell.width = 0;
                    cont_cell.is_continuation = false;
                }
            }
        }
    }

    // Clear the current cell
    cell.setTextBytes("");
    cell.width = 0;
    cell.is_continuation = false;
}

pub fn resize(self: *Self, size: PointF32) !void {
    if (size.x == self.size.x and size.y == self.size.y) {
        return;
    }

    self.size = size;
    self.clip_rect = .{ .x = 0, .y = 0, .width = size.x, .height = size.y };
    self.force_redraw = true;

    const width_int = toType(u32, @ceil(size.x));
    const height_int = toType(u32, @ceil(size.y));
    const cell_count = width_int * height_int;
    try self.cells.resize(self.allocator, cell_count);
    try self.previous_cells.resize(self.allocator, cell_count);

    // Initialize new cells
    for (self.cells.items) |*cell| {
        cell.* = .{ .bg = self.clear_color, .fg = self.fg_color };
    }
    for (self.previous_cells.items) |*cell| {
        cell.* = .{ .bg = self.clear_color, .fg = self.fg_color };
    }
}

pub fn clear(self: *Self) void {
    for (self.cells.items) |*cell| {
        cell.* = .{ .bg = self.clear_color, .fg = self.fg_color };
    }
    self.force_redraw = true;
}

fn getCell(self: *Self, x: u32, y: u32) ?*Cell {
    const width_int = toType(u32, @ceil(self.size.x));
    const height_int = toType(u32, @ceil(self.size.y));
    if (x >= width_int or y >= height_int) return null;
    return &self.cells.items[y * width_int + x];
}

fn setCell(self: *Self, x: u32, y: u32, cell: Cell) void {
    const width_int = toType(u32, @ceil(self.size.x));
    const height_int = toType(u32, @ceil(self.size.y));
    if (x >= width_int or y >= height_int) return;
    self.cells.items[y * width_int + x] = cell;
}

/// Get previous cells slice for diffing
pub fn getPreviousCells(self: *const Self) []const Cell {
    return self.previous_cells.items;
}

/// Save current state as previous for diffing
pub fn savePreviousState(self: *Self) !void {
    self.previous_cells.clearRetainingCapacity();
    try self.previous_cells.appendSlice(self.allocator, self.cells.items);
}

/// Paint from a render list
pub fn paintFromRenderList(self: *Self, render_list: *const RenderList) !void {
    // Clear canvas first
    self.clear();

    // Paint each item in order
    for (render_list.items.items) |item| {
        switch (item) {
            .box => |box| {
                // Skip if outside clip rect
                if (!box.bounds.intersectsWith(self.clip_rect)) continue;

                // Draw background
                if (box.background) |bg| {
                    try self.fillRect(box.bounds, bg);
                }

                // Draw borders
                if (hasBorders(box.border_style)) {
                    try self.drawBorder(box.bounds, box.border_style, box.border_color);
                }
            },
            .text_fragment => |text| {
                // skip if outside clip rect
                if (!text.bounds.intersectsWith(self.clip_rect)) continue;

                // Use the color and format from the text fragment
                try self.drawText(text.bounds.x, text.bounds.y, text.text, text.color, text.format);
            },
            .selection_overlay => |sel| {
                // skip if outside clip rect
                if (!sel.bounds.intersectsWith(self.clip_rect)) continue;

                // draw semi-transparent selection overlay without clearing text
                try self.fillRectPreserveText(sel.bounds, sel.color);
            },
            .push_clip => |clip| {
                try self.pushClip(clip.rect);
            },
            .pop_clip => {
                self.popClip();
            },
            .line_box => {
                // Line boxes are for hit testing only, not rendered
            },
        }
    }
}

fn pushClip(self: *Self, rect: Rect) !void {
    // Save current clip rect
    try self.clip_stack.append(self.allocator, self.clip_rect);
    // Set new clip rect as intersection with current
    self.clip_rect = self.clip_rect.intersect(rect);
}

fn popClip(self: *Self) void {
    if (self.clip_stack.pop()) |rect| {
        self.clip_rect = rect;
    }
}

/// Fill a rectangle with a color, preserving any text content
fn fillRectPreserveText(self: *Self, rect: Rect, color: Color) !void {
    // Convert to integer coordinates
    const x_start = @max(0, @as(i32, @intFromFloat(@round(rect.x))));
    const y_start = @max(0, @as(i32, @intFromFloat(@round(rect.y))));
    const x_end = @min(@as(i32, @intFromFloat(@ceil(self.size.x))), @as(i32, @intFromFloat(@round(rect.x + rect.width))));
    const y_end = @min(@as(i32, @intFromFloat(@ceil(self.size.y))), @as(i32, @intFromFloat(@round(rect.y + rect.height))));

    // Fill cells with color without clearing text
    var y: i32 = y_start;
    while (y < y_end) : (y += 1) {
        var x: i32 = x_start;
        while (x < x_end) : (x += 1) {
            // Check if within clip rect
            if (!self.clip_rect.containsXY(@floatFromInt(x), @floatFromInt(y))) continue;

            const x_u32 = @as(u32, @intCast(x));
            const y_u32 = @as(u32, @intCast(y));

            if (self.getCell(x_u32, y_u32)) |cell| {
                // Only change background, preserve text content
                cell.setBg(color);
            }
        }
    }
}

fn fillRect(self: *Self, rect: Rect, background: styles.background.Background) !void {
    // Convert to integer coordinates
    const x_start = @max(0, @as(i32, @intFromFloat(@round(rect.x))));
    const y_start = @max(0, @as(i32, @intFromFloat(@round(rect.y))));
    const x_end = @min(@as(i32, @intFromFloat(@ceil(self.size.x))), @as(i32, @intFromFloat(@round(rect.x + rect.width))));
    const y_end = @min(@as(i32, @intFromFloat(@ceil(self.size.y))), @as(i32, @intFromFloat(@round(rect.y + rect.height))));

    // Handle different background types
    switch (background) {
        .solid => |color| {
            // Simple solid color fill
            var y: i32 = y_start;
            while (y < y_end) : (y += 1) {
                var x: i32 = x_start;
                while (x < x_end) : (x += 1) {
                    // Check if within clip rect
                    if (!self.clip_rect.containsXY(@floatFromInt(x), @floatFromInt(y))) continue;

                    const x_u32 = @as(u32, @intCast(x));
                    const y_u32 = @as(u32, @intCast(y));

                    // Check related cells only for boundary cells
                    const is_boundary = (x == x_start or x == x_end - 1);
                    self.clearCell(x_u32, y_u32, is_boundary);

                    if (self.getCell(x_u32, y_u32)) |cell| {
                        cell.setBg(color);
                    }
                }
            }
        },
        .linear_gradient, .radial_gradient => {
            // Create sampler for gradient
            var sampler = try Sampler.from(self.allocator, background, .{
                .x = rect.width,
                .y = rect.height,
            });
            defer sampler.deinit();

            // Fill cells with sampled colors
            var y: i32 = y_start;
            while (y < y_end) : (y += 1) {
                var x: i32 = x_start;
                while (x < x_end) : (x += 1) {
                    // Check if within clip rect
                    if (!self.clip_rect.containsXY(@floatFromInt(x), @floatFromInt(y))) continue;

                    const x_u32 = @as(u32, @intCast(x));
                    const y_u32 = @as(u32, @intCast(y));

                    // Check related cells only for boundary cells
                    const is_boundary = (x == x_start or x == x_end - 1);
                    self.clearCell(x_u32, y_u32, is_boundary);

                    if (self.getCell(x_u32, y_u32)) |cell| {
                        // Calculate position relative to rect origin
                        const rel_x = @as(f32, @floatFromInt(x)) - rect.x;
                        const rel_y = @as(f32, @floatFromInt(y)) - rect.y;
                        const gradient_color = sampler.at(.{ .x = rel_x, .y = rel_y });
                        cell.setBg(gradient_color);
                    }
                }
            }
        },
    }
}

fn drawBorder(
    self: *Self,
    _rect: Rect,
    border: LayoutRect(styles.border.BoxChar.Cell),
    border_color: LayoutRect(styles.background.Background),
) !void {
    if (border.top.style == .none and border.bottom.style == .none and border.left.style == .none and border.right.style == .none) {
        return;
    }
    var rect = _rect.round();

    const clamp_rect = rect.intersect(self.clip_rect).round();
    if (clamp_rect.isZero()) {
        return;
    }

    // const

    var top_sampler = try Sampler.from(self.allocator, border_color.top, .{
        .x = rect.width,
        .y = rect.height,
    });
    defer top_sampler.deinit();
    var bottom_sampler = try Sampler.from(self.allocator, border_color.bottom, .{
        .x = rect.width,
        .y = rect.height,
    });
    defer bottom_sampler.deinit();
    var left_sampler = try Sampler.from(self.allocator, border_color.left, .{
        .x = rect.width,
        .y = rect.height,
    });
    defer left_sampler.deinit();
    var right_sampler = try Sampler.from(self.allocator, border_color.right, .{
        .x = rect.width,
        .y = rect.height,
    });
    defer right_sampler.deinit();

    const will_draw_corners = rect.width > 1 and rect.height > 1;

    // std.debug.print("rect: {any}\nclamp_rect: {any}\n will_draw_corners: {}\n", .{ rect, clamp_rect, will_draw_corners });
    const will_render_top_line = clamp_rect.top() == rect.top() and rect.width > 1;
    const will_render_bottom_line = clamp_rect.bottom() == rect.bottom() and rect.width > 1;

    const will_render_left_line = clamp_rect.left() == rect.left() and rect.height > 1;
    const will_render_right_line = clamp_rect.right() == rect.right() and rect.height > 1;

    const top_cell_style: styles.border.BoxChar = if (will_render_top_line) .{ .w = border.top, .e = border.top } else .{};
    const bottom_cell_style: styles.border.BoxChar = if (will_render_bottom_line) .{ .w = border.bottom, .e = border.bottom } else .{};
    const left_cell_style: styles.border.BoxChar = if (will_render_left_line) .{ .n = border.left, .s = border.left } else .{};
    const right_cell_style: styles.border.BoxChar = if (will_render_right_line) .{ .n = border.right, .s = border.right } else .{};

    const left = clamp_rect.left();
    const right = @max(clamp_rect.right() - 1, 0);
    const top = clamp_rect.top();
    const bottom = @max(clamp_rect.bottom() - 1, 0);

    if (will_draw_corners) {
        if (will_render_left_line and will_render_top_line) {
            // top left
            const point: Point(f32) = .{ .x = left, .y = top };
            if (self.clip_rect.contains(point)) if (self.getCell(toType(u32, @round(point.x)), toType(u32, @round(point.y)))) |top_left_cell| {

                // top_left_cell.border.s = left_cell_style.n;
                // top_left_cell.border.e = top_cell_style.w;
                top_left_cell.setBorderChar(.{
                    .s = left_cell_style.n,
                    .e = top_cell_style.w,
                });
                top_left_cell.setFg(top_sampler.at(.{ .x = 0, .y = 0 }));
            };
        }

        if (will_render_right_line and will_render_top_line) {
            const point: Point(f32) = .{ .x = right, .y = top };
            // top right
            if (self.clip_rect.contains(point)) if (self.getCell(toType(u32, @round(point.x)), toType(u32, @round(point.y)))) |top_right_cell| {
                // top_right_cell.border |= top_right_cell_style.encode();
                top_right_cell.setBorderChar(.{
                    .s = right_cell_style.n,
                    .w = top_cell_style.e,
                });
                top_right_cell.setFg(top_sampler.at(.{ .x = rect.width, .y = 0 }));
            };
        }

        if (will_render_left_line and will_render_bottom_line) {
            const point: Point(f32) = .{ .x = left, .y = bottom };
            // bottom left
            if (self.clip_rect.contains(point)) if (self.getCell(toType(u32, @round(point.x)), toType(u32, @round(point.y)))) |bottom_left_cell| {
                bottom_left_cell.setBorderChar(.{
                    .n = left_cell_style.s,
                    .e = bottom_cell_style.w,
                });
                bottom_left_cell.setFg(bottom_sampler.at(.{ .x = 0, .y = rect.height }));
            };
        }
        if (will_render_right_line and will_render_bottom_line) {
            const point: Point(f32) = .{ .x = right, .y = bottom };
            if (self.clip_rect.contains(point)) if (self.getCell(toType(u32, @round(point.x)), toType(u32, @round(point.y)))) |bottom_right_cell| {
                // bottom right
                bottom_right_cell.setBorderChar(.{
                    .n = right_cell_style.s,
                    .w = bottom_cell_style.e,
                });
                bottom_right_cell.setFg(bottom_sampler.at(.{ .x = rect.width, .y = rect.height }));
            };
        }
    }
    var x = left;
    if (will_render_left_line and will_draw_corners) {
        x += 1;
    }
    // const x_end = right + @floatFromInt(@intFromBool(will_render_right_line));
    var x_end = right;
    if (will_render_right_line and will_draw_corners) {
        x_end -= 1;
    }
    while (x <= x_end) : (x += 1) {
        if (will_render_top_line) if (self.getCell(toType(u32, @round(x)), toType(u32, @round(top)))) |top_cell| {
            top_cell.setBorderChar(.{
                .w = top_cell_style.w,
                .e = top_cell_style.e,
            });
            top_cell.setFg(top_sampler.at(.{ .x = x - rect.left(), .y = 0 }));
        };
        if (will_render_bottom_line) if (self.getCell(toType(u32, @round(x)), toType(u32, @round(bottom)))) |bottom_cell| {
            bottom_cell.setBorderChar(.{
                .w = bottom_cell_style.w,
                .e = bottom_cell_style.e,
            });
            bottom_cell.setFg(bottom_sampler.at(.{ .x = x - rect.left(), .y = rect.height }));
        };
    }

    var y = top;
    if (will_render_top_line and will_draw_corners) {
        y += 1;
    }
    var y_end = bottom;
    if (will_render_bottom_line and will_draw_corners) {
        y_end -= 1;
    }
    while (y <= y_end) : (y += 1) {
        if (will_render_left_line) if (self.getCell(toType(u32, @round(left)), toType(u32, @round(y)))) |left_cell| {
            left_cell.setBorderChar(.{
                .n = left_cell_style.n,
                .s = left_cell_style.s,
            });
            left_cell.setFg(left_sampler.at(.{ .x = 0, .y = y - rect.top() }));
        };
        if (will_render_right_line) if (self.getCell(toType(u32, @round(right)), toType(u32, @round(y)))) |right_cell| {
            right_cell.setBorderChar(.{
                .n = right_cell_style.n,
                .s = right_cell_style.s,
            });
            right_cell.setFg(right_sampler.at(.{ .x = rect.width, .y = y - rect.top() }));
        };
    }
    // // Ensure border char lookup is loaded
    // _ = styles.border.BoxChar.load() catch {};
    // const clamped_rect = rect.intersect(self.clip_rect);

    // std.debug.print("drawBorder {any}\n", .{clamped_rect});
    // const x_start = @as(u32, @intFromFloat(@round(clamped_rect.x)));
    // const y_start = @as(u32, @intFromFloat(@round(clamped_rect.y)));
    // const x_end = @as(u32, @intFromFloat(@round(clamped_rect.x + clamped_rect.width)));
    // const y_end = @as(u32, @intFromFloat(@round(clamped_rect.y + clamped_rect.height)));

    // // Create samplers for each border side
    // var top_sampler = try Sampler.from(self.allocator, border_color.top, .{
    //     .x = rect.width,
    //     .y = rect.height,
    // });
    // defer top_sampler.deinit();

    // var bottom_sampler = try Sampler.from(self.allocator, border_color.bottom, .{
    //     .x = rect.width,
    //     .y = rect.height,
    // });
    // defer bottom_sampler.deinit();

    // var left_sampler = try Sampler.from(self.allocator, border_color.left, .{
    //     .x = rect.width,
    //     .y = rect.height,
    // });
    // defer left_sampler.deinit();

    // var right_sampler = try Sampler.from(self.allocator, border_color.right, .{
    //     .x = rect.width,
    //     .y = rect.height,
    // });
    // defer right_sampler.deinit();

    // // Draw corners
    // if (x_end > x_start and y_end > y_start) {
    //     // Top-left corner
    //     if (self.getCell(x_start, y_start)) |cell| {
    //         cell.setBorderChar(.{
    //             .s = border_style.left,
    //             .e = border_style.top,
    //         });
    //         const rel_x = @as(f32, @floatFromInt(x_start)) - rect.x;
    //         const rel_y = @as(f32, @floatFromInt(y_start)) - rect.y;
    //         cell.fg = top_sampler.at(.{ .x = rel_x, .y = rel_y });
    //     }

    //     // Top-right corner
    //     if (x_end > x_start + 1) {
    //         if (self.getCell(x_end - 1, y_start)) |cell| {
    //             cell.setBorderChar(.{
    //                 .s = border_style.right,
    //                 .w = border_style.top,
    //             });
    //             const rel_x = @as(f32, @floatFromInt(x_end - 1)) - rect.x;
    //             const rel_y = @as(f32, @floatFromInt(y_start)) - rect.y;
    //             cell.fg = top_sampler.at(.{ .x = rel_x, .y = rel_y });
    //         }
    //     }

    //     // Bottom-left corner
    //     if (y_end > y_start + 1) {
    //         if (self.getCell(x_start, y_end - 1)) |cell| {
    //             cell.setBorderChar(.{
    //                 .n = border_style.left,
    //                 .e = border_style.bottom,
    //             });
    //             const rel_x = @as(f32, @floatFromInt(x_start)) - rect.x;
    //             const rel_y = @as(f32, @floatFromInt(y_end - 1)) - rect.y;
    //             cell.fg = bottom_sampler.at(.{ .x = rel_x, .y = rel_y });
    //         }

    //         // Bottom-right corner
    //         if (x_end > x_start + 1) {
    //             if (self.getCell(x_end - 1, y_end - 1)) |cell| {
    //                 cell.setBorderChar(.{
    //                     .n = border_style.right,
    //                     .w = border_style.bottom,
    //                 });
    //                 const rel_x = @as(f32, @floatFromInt(x_end - 1)) - rect.x;
    //                 const rel_y = @as(f32, @floatFromInt(y_end - 1)) - rect.y;
    //                 cell.fg = bottom_sampler.at(.{ .x = rel_x, .y = rel_y });
    //             }
    //         }
    //     }
    // }

    // // Draw horizontal borders
    // if (x_end > x_start + 2) {
    //     var x = x_start + 1;
    //     while (x < x_end - 1) : (x += 1) {
    //         // Top border
    //         if (self.getCell(x, y_start)) |cell| {
    //             cell.setBorderChar(.{
    //                 .e = border_style.top,
    //                 .w = border_style.top,
    //             });
    //             const rel_x = @as(f32, @floatFromInt(x)) - rect.x;
    //             const rel_y = @as(f32, @floatFromInt(y_start)) - rect.y;
    //             cell.fg = top_sampler.at(.{ .x = rel_x, .y = rel_y });
    //         }

    //         // Bottom border
    //         if (y_end > y_start + 1) {
    //             if (self.getCell(x, y_end - 1)) |cell| {
    //                 cell.setBorderChar(.{
    //                     .e = border_style.bottom,
    //                     .w = border_style.bottom,
    //                 });
    //                 const rel_x = @as(f32, @floatFromInt(x)) - rect.x;
    //                 const rel_y = @as(f32, @floatFromInt(y_end - 1)) - rect.y;
    //                 cell.fg = bottom_sampler.at(.{ .x = rel_x, .y = rel_y });
    //             }
    //         }
    //     }
    // }

    // // Draw vertical borders
    // if (y_end > y_start + 2) {
    //     var y = y_start + 1;
    //     while (y < y_end - 1) : (y += 1) {
    //         // Left border
    //         if (self.getCell(x_start, y)) |cell| {
    //             cell.setBorderChar(.{
    //                 .n = border_style.left,
    //                 .s = border_style.left,
    //             });
    //             const rel_x = @as(f32, @floatFromInt(x_start)) - rect.x;
    //             const rel_y = @as(f32, @floatFromInt(y)) - rect.y;
    //             cell.fg = left_sampler.at(.{ .x = rel_x, .y = rel_y });
    //         }

    //         // Right border
    //         if (x_end > x_start + 1) {
    //             if (self.getCell(x_end - 1, y)) |cell| {
    //                 cell.setBorderChar(.{
    //                     .n = border_style.right,
    //                     .s = border_style.right,
    //                 });
    //                 const rel_x = @as(f32, @floatFromInt(x_end - 1)) - rect.x;
    //                 const rel_y = @as(f32, @floatFromInt(y)) - rect.y;
    //                 cell.fg = right_sampler.at(.{ .x = rel_x, .y = rel_y });
    //             }
    //         }
    //     }
    // }
}

fn drawText(self: *Self, x: f32, y: f32, text: []const u8, color: Color, format: TextFormat) !void {
    const y_int: u32 = @intFromFloat(@round(y));
    var x_pos = x;

    // Iterate through graphemes
    var iter = try grapheme.GraphemeIterator.init(text);
    while (iter.next()) |slice| {
        const width_usize = string_width.visible.width.exclude_ansi_colors.utf8(slice);
        const width = toType(u32, width_usize);

        const x_int: u32 = @intFromFloat(@round(x_pos));

        // Check if within bounds and clip rect
        const width_int = toType(u32, @ceil(self.size.x));
        const height_int = toType(u32, @ceil(self.size.y));
        if (x_int < width_int and y_int < height_int and
            self.clip_rect.containsXY(x_pos, y))
        {
            if (self.getCell(x_int, y_int)) |cell| {
                // If drawing over a continuation cell, clear the original cell
                if (cell.is_continuation) {
                    // Find and clear the original cell by going backwards
                    var scan_x = x_int;
                    while (scan_x > 0) : (scan_x -= 1) {
                        if (self.getCell(scan_x - 1, y_int)) |prev_cell| {
                            if (!prev_cell.is_continuation and prev_cell.width > 1) {
                                // Found the original multi-width cell, clear it
                                prev_cell.setTextBytes(" ");
                                prev_cell.width = 1;
                                break;
                            }
                        }
                    }
                }

                // If this cell was the start of a multi-width character, clear its continuations
                if (cell.width > 1) {
                    var i: u32 = 1;
                    while (i < cell.width) : (i += 1) {
                        if (x_int + i < width_int) {
                            if (self.getCell(x_int + i, y_int)) |next_cell| {
                                next_cell.setTextBytes(" ");
                                next_cell.width = 1;
                                next_cell.is_continuation = false;
                            }
                        }
                    }
                }

                // Now set the new content
                if (!std.mem.eql(u8, slice, " ")) {
                    cell.setTextBytes(slice);
                    cell.setFg(color);
                    cell.format = format;
                    cell.width = width;
                    cell.is_continuation = false;
                }
            }

            // Mark subsequent cells as continuations for multi-width characters
            if (width > 1) {
                // Get the current cell again to avoid scope issues
                const current_cell = self.getCell(x_int, y_int).?;

                var i: u32 = 1;
                while (i < width) : (i += 1) {
                    if (x_int + i < width_int) {
                        if (self.getCell(x_int + i, y_int)) |next_cell| {
                            next_cell.setTextBytes("");
                            next_cell.width = 0;
                            next_cell.bg = current_cell.bg; // Keep same background
                            next_cell.fg = current_cell.fg;
                            next_cell.format = current_cell.format;
                            next_cell.is_continuation = true;
                        }
                    }
                }
            }
        }

        x_pos += @floatFromInt(width);

        // Stop if we've gone past the canvas
        if (x_pos >= self.size.x) break;
    }
}

fn hasBorders(border_style: anytype) bool {
    return border_style.top.style != .none or
        border_style.right.style != .none or
        border_style.bottom.style != .none or
        border_style.left.style != .none;
}

/// Get cells for rendering
pub fn getCells(self: *const Self) []const Cell {
    return self.cells.items;
}

/// Get cell dimensions
pub fn getDimensions(self: *const Self) struct { width: u32, height: u32 } {
    return .{
        .width = toType(u32, @ceil(self.size.x)),
        .height = toType(u32, @ceil(self.size.y)),
    };
}

test "cells own their text bytes" {
    // previous_cells is a wholesale copy used for frame diffing; if cells
    // borrowed text from the render list, the copy would dangle when the
    // next frame rebuilds it (transient scrambling while scrolling)
    var cell = Cell{ .bg = Color.tw.black, .fg = Color.tw.white };
    var source = [_]u8{ 'a', 'b', 'c' };
    cell.setTextBytes(&source);
    const copy = cell;
    // mutating the original source or the live cell must not affect the copy
    source[0] = 'z';
    cell.setTextBytes("xyz");
    try std.testing.expectEqualStrings("abc", copy.getChar());
    try std.testing.expect(!copy.equal(&cell));
}
