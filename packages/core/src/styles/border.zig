const utils = @import("utils.zig");
const std = @import("std");
const parsers = @import("styles.zig");

pub const BoxChar = struct {
    n: Cell = .{},
    e: Cell = .{},
    s: Cell = .{},
    w: Cell = .{},

    fn isCorner(self: BoxChar) bool {
        return (self.n.style == .none and self.e.style == .none) or
            (self.n.style == .none and self.w.style == .none) or
            (self.s.style == .none and self.e.style == .none) or
            (self.s.style == .none and self.w.style == .none);
    }
    const Class = enum {
        none,
        corner,
        horizontal,
        vertical,
        t_junction,
        cross,
    };
    fn getClass(self: BoxChar) BoxChar.Class {
        var bit: u8 = 0;
        if (self.n.style != .none) bit |= 0b1000;
        if (self.e.style != .none) bit |= 0b0100;
        if (self.s.style != .none) bit |= 0b0010;
        if (self.w.style != .none) bit |= 0b0001;
        switch (bit) {
            0b1111 => return .cross,
            0b1100, 0b0110, 0b0011, 0b1001 => return .corner,
            0b1010 => return .horizontal,
            0b0101 => return .vertical,
            0b1110, 0b1101, 0b1011, 0b0111 => return .t_junction,
            0b0000 => return .cross,
            else => unreachable,
        }
    }
    pub fn normalize(self: BoxChar) BoxChar {
        // 0b N E S W
        var bit: u8 = 0;
        if (self.n.style != .none) {
            bit |= 0b1000;
        }
        if (self.e.style != .none) {
            bit |= 0b0100;
        }
        if (self.s.style != .none) {
            bit |= 0b0010;
        }
        if (self.w.style != .none) {
            bit |= 0b0001;
        }
        switch (bit) {
            // none
            0b0000 => return .{},
            // cross
            0b1111 => return .{
                .n = normalizeCell(self.n, true, true),
                .e = normalizeCell(self.e, true, true),
                .s = normalizeCell(self.s, true, true),
                .w = normalizeCell(self.w, true, true),
            },
            // corner
            0b1100 => {
                const n, const e = normalizeCorner(self.n, self.e);
                return .{
                    .n = n,
                    .e = e,
                };
            },
            0b0110 => {
                const e, const s = normalizeCorner(self.e, self.s);
                return .{
                    .e = e,
                    .s = s,
                };
            },
            0b0011 => {
                const s, const w = normalizeCorner(self.s, self.w);
                return .{
                    .s = s,
                    .w = w,
                };
            },
            0b1001 => {
                const n, const w = normalizeCorner(self.n, self.w);
                return .{
                    .n = n,
                    .w = w,
                };
            },
            // horizontal
            0b1010 => {
                const n, const s = normalizeBar(self.n, self.s);

                return .{
                    .n = n,
                    .s = s,
                };
            },
            // vertical
            0b0101 => {
                const e, const w = normalizeBar(self.e, self.w);
                return .{
                    .e = e,
                    .w = w,
                };
            },
            // t_junction
            0b1110 => {
                const n, const e, const s = normalizeTJunction(self.n, self.e, self.s);
                return .{
                    .n = n,
                    .e = e,
                    .s = s,
                };
            },

            0b0111 => {
                const e, const s, const w = normalizeTJunction(self.e, self.s, self.w);
                return .{
                    .e = e,
                    .s = s,
                    .w = w,
                };
            },
            0b1011 => {
                const n, const w, const s = normalizeTJunction(self.n, self.w, self.s);
                return .{
                    .n = n,
                    .w = w,
                    .s = s,
                };
            },
            0b1101 => {
                const n, const e, const w = normalizeTJunction(self.n, self.e, self.w);
                return .{
                    .n = n,
                    .e = e,
                    .w = w,
                };
            },
            else => unreachable,
        }
    }
    fn normalizeBar(_left: Cell, _right: Cell) struct { Cell, Cell } {
        const left = normalizeCell(_left, true, false);
        const right = normalizeCell(_right, true, false);
        const mixed_styles = left.style != right.style;
        const mixed_weights = left.weight != right.weight;
        if (!mixed_styles and !mixed_weights) {
            return .{ left, right };
        }

        if (mixed_weights) {
            if (left.style != .solid) {
                return .{ left, left };
            }
            if (right.style != .solid) {
                return .{ right, right };
            }
            // if both are solid, we are fine
            return .{ left, right };
        }

        const cell: Cell = .{
            .style = getLowestValue(left.style, right.style),
            .weight = getLowestValue(left.weight, right.weight),
        };
        return .{ cell, cell };
    }
    fn normalizeCorner(_left: Cell, _right: Cell) struct { Cell, Cell } {
        const left = normalizeCell(_left, false, true);
        const right = normalizeCell(_right, false, true);
        return .{ .{
            .style = getLowestValue(left.style, right.style),
            .weight = getLowestValue(left.weight, right.weight),
        }, .{
            .style = getLowestValue(left.style, right.style),
            .weight = getLowestValue(left.weight, right.weight),
        } };
    }
    fn normalizeTJunction(_a: Cell, _b: Cell, _c: Cell) struct { Cell, Cell, Cell } {
        const a = normalizeCell(_a, true, true);
        const b = normalizeCell(_b, true, true);
        const c = normalizeCell(_c, true, true);
        if (a.style == b.style and b.style == c.style) {
            return .{ a, b, c };
        }
        if (b.style == .double) {
            // if it has a corner of doubles in it, we return the corner
            // it's what looked the least weird to me
            if (a.style == .double) {
                return .{ a, b, .{} };
            }
            if (c.style == .double) {
                return .{ .{}, b, c };
            }

            // if only c is double, the corners are dashed or solid
            return .{
                .{ .style = .solid, .weight = .light },
                b,
                .{ .style = .solid, .weight = .light },
            };
        }
        if (a.style == .double and c.style == .double) {
            return .{ a, .{
                .style = .solid,
                .weight = .light,
            }, c };
        }

        // otherwise its solid or a dash, so we return solid.. we have all combinations of solid weights
        // so we can safely mix them

        return .{ .{
            .style = .solid,
            .weight = a.weight,
        }, .{
            .style = .solid,
            .weight = b.weight,
        }, .{
            .style = .solid,
            .weight = c.weight,
        } };
    }
    pub fn normalizeCross(border: BoxChar) BoxChar {
        // these are the options we have, so we have to fallback to one of them
        // [n: light solid, e: light solid, s: light solid, w: light solid] ┼
        // [n: light solid, e: light solid, s: light solid, w: heavy solid] ┽
        // [n: light solid, e: heavy solid, s: light solid, w: light solid] ┾
        // [n: light solid, e: heavy solid, s: light solid, w: heavy solid] ┿
        // [n: heavy solid, e: light solid, s: light solid, w: light solid] ╀
        // [n: light solid, e: light solid, s: heavy solid, w: light solid] ╁
        // [n: heavy solid, e: light solid, s: heavy solid, w: light solid] ╂
        // [n: heavy solid, e: light solid, s: light solid, w: heavy solid] ╃
        // [n: heavy solid, e: heavy solid, s: light solid, w: light solid] ╄
        // [n: light solid, e: light solid, s: heavy solid, w: heavy solid] ╅
        // [n: light solid, e: light solid, s: heavy solid, w: heavy solid] ╆
        // [n: heavy solid, e: heavy solid, s: light solid, w: heavy solid] ╇
        // [n: light solid, e: heavy solid, s: heavy solid, w: heavy solid] ╈
        // [n: heavy solid, e: light solid, s: heavy solid, w: heavy solid] ╉
        // [n: heavy solid, e: heavy solid, s: heavy solid, w: light solid] ╊
        // [n: heavy solid, e: heavy solid, s: heavy solid, w: heavy solid] ╋
        // [n: light solid, e: light double, s: light solid, w: light double] ╪
        // [n: light double, e: light solid, s: light double, w: light solid] ╫
        // [n: light double, e: light double, s: light double, w: light double] ╬
        const n = normalizeCell(border.n, true, true);
        const e = normalizeCell(border.e, true, true);
        const s = normalizeCell(border.s, true, true);
        const w = normalizeCell(border.w, true, true);

        const is_horizontally_symmetric = w.style == e.style;
        const is_vertically_symmetric = n.style == s.style;
        if (is_horizontally_symmetric and is_vertically_symmetric) {
            if (n.style == .double or e.style == .double) {
                // we have this char, but only with light weight
                // so we need to normalize the weight only
                return .{
                    .n = .{ .style = n.style, .weight = .light },
                    .e = .{ .style = e.style, .weight = .light },
                    .s = .{ .style = s.style, .weight = .light },
                    .w = .{ .style = w.style, .weight = .light },
                };
            }
            // otherwise all of them are solid , we have all possible combinations of solid weights so we can safely mix them
            return .{
                .n = n,
                .e = e,
                .s = s,
                .w = w,
            };
        }

        // if it has a T junction in it, remove the outstanding style and normalize it
        if (is_horizontally_symmetric and !is_vertically_symmetric) {
            if (n.style == e.style) { // s is the outstanding style
                const w_, const n_, const e_ = normalizeTJunction(w, n, e);
                return .{
                    .n = n_,
                    .e = e_,
                    .s = .{},
                    .w = w_,
                };
            } else {
                // otherwise n is the outstanding style
                const w_, const s_, const e_ = normalizeTJunction(w, n, s);
                return .{
                    .n = .{},
                    .e = e_,
                    .s = s_,
                    .w = w_,
                };
            }
        }
        if (!is_horizontally_symmetric and is_vertically_symmetric) {
            if (e.style == s.style) { // w is the outstanding style
                const n_, const e_, const s_ = normalizeTJunction(n, e, s);
                return .{
                    .n = n_,
                    .e = e_,
                    .s = s_,
                    .w = .{},
                };
            } else {
                // otherwise e is the outstanding style
                const n_, const w_, const s_ = normalizeTJunction(n, w, s);
                return .{
                    .n = n_,
                    .e = .{},
                    .s = s_,
                    .w = w_,
                };
            }
        }

        // if it reaches here, it's a mix of many styles..let's keep the highest style and remove the others
        var highest = n;
        highest = getHighestValue(highest.style, e.style);
        highest = getHighestValue(highest.style, s.style);
        highest = getHighestValue(highest.style, w.style);

        return .{
            .n = if (n.style == highest.style) n else .{},
            .e = if (e.style == highest.style) e else .{},
            .s = if (s.style == highest.style) s else .{},
            .w = if (w.style == highest.style) w else .{},
        };
    }
    fn getLowestValue(a: anytype, b: anytype) @TypeOf(a, b) {
        return if (@backingInt(a) < @backingInt(b)) a else b;
    }
    pub fn getHighestValue(a: anytype, b: anytype) @TypeOf(a, b) {
        return if (@backingInt(a) > @backingInt(b)) a else b;
    }
    fn normalizeCell(cell: Cell, comptime clear_rounded: bool, comptime clear_dashed: bool) Cell {
        switch (cell.style) {
            .none => return .{},
            .double => return .{ .style = .double, .weight = .light },
            .rounded => {
                if (clear_rounded) {
                    return .{ .style = .solid, .weight = .light };
                }
                return .{ .style = .rounded, .weight = cell.weight };
            },
            .dashed_half, .dashed_double, .dashed_triple, .dashed_quadruple => {
                if (clear_dashed) {
                    return .{ .style = .solid, .weight = cell.weight };
                }
                return cell;
            },
            else => return .{ .style = cell.style, .weight = cell.weight },
            // .solid => return .{ .style = .solid, .weight = cell.weight },
            // .dashed_half => return .{ .style = .dashed_half, .weight = cell.weight },
            // .dashed_double => return .{ .style = .dashed_double, .weight = cell.weight },
            // .dashed_triple => return .{ .style = .dashed_triple, .weight = cell.weight },
            // .dashed_quadruple => return .{ .style = .dashed_quadruple, .weight = cell.weight },
        }
    }
    pub fn encode(self: BoxChar) u64 {
        var encoded: u64 = 0;
        encoded |= self.n.encode();
        encoded |= self.e.encode() << 5;
        encoded |= self.s.encode() << 10;
        encoded |= self.w.encode() << 15;
        return encoded;
    }

    pub fn decode(value: u64) BoxChar {
        return .{
            .n = Cell.decode(value),
            .e = Cell.decode(value >> 5),
            .s = Cell.decode(value >> 10),
            .w = Cell.decode(value >> 15),
        };
    }
    pub fn format(self: BoxChar, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("[n: {any}, e: {any}, s: {any}, w: {any}]", .{ self.n, self.e, self.s, self.w });
    }

    // Look up rules
    // when drawing a rectangle
    // - if style is none in all directions, return a space
    // - If find exact match, return it
    // - if side style is double or rounded, normalize weight to light
    // - if style Style is not solid, none or double, and this is a junction or a corner, replace to solid
    // - If it's horizontal or vertical, and the ends are different, normalize to the style with the lowest value
    // - If it's a corner, normalize to the style with the lowest value

    // -  If not, find the closest match following the rules below
    //   - If it's a T-junction, find the 2 most common style of the 3 sections and remove the least common one, and go to step 1
    //   - If it's a cross, find the highest weight style of the 4 sections and remove the others, and go to step 1
    // - if still not found, return ╳ in dev mode, and space in release mode
    pub fn getChar(key: BoxChar) u21 {
        load() catch unreachable;
        //tries happy path first
        if (lut.get(key)) |c| {
            return c;
        }
        if (lut.get(key.normalize())) |c| {
            return c;
        }
        return '╳';
    }

    pub const Cell = struct {
        weight: Weight = .light,
        style: Style = .none,
        pub fn encode(self: Cell) u64 {
            // 5 bits wide
            return (self.weight.toInt() << 3) | self.style.toInt();
        }
        const weight_mask: u64 = 0b11000;
        const style_mask: u64 = 0b00111;
        pub fn decode(value: u64) Cell {
            return .{
                .weight = Weight.fromInt((value & weight_mask) >> 3),
                .style = Style.fromInt(value & style_mask),
            };
        }
        pub fn format(self: Cell, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("{s} {s}", .{ @tagName(self.weight), @tagName(self.style) });
        }
    };
    pub const Weight = enum(u64) {
        light = 0,
        heavy = 1,
        pub fn toInt(self: Weight) u64 {
            return @backingInt(self);
        }
        pub fn fromInt(value: u64) Weight {
            return @fromBackingInt(@intCast(value));
        }
    };

    pub const Style = enum(u64) {
        none = 0,
        solid = 1,
        dashed_half = 2,
        dashed_double = 3,
        dashed_triple = 4,
        dashed_quadruple = 5,
        double = 6,
        rounded = 7,
        pub fn isDash(self: Style) bool {
            return switch (self) {
                .dashed_half, .dashed_double, .dashed_triple, .dashed_quadruple => true,
                else => false,
            };
        }
        pub fn toInt(self: Style) u64 {
            return @backingInt(self);
        }
        pub fn fromInt(value: u64) Style {
            return @fromBackingInt(@intCast(value));
        }
    };
    pub const Rounded = enum(u64) {
        none = 0,
        light_only = 1,
        always = 2,
    };
    var buf: [300000]u8 = undefined;
    var fbo = std.heap.FixedBufferAllocator.init(&buf);
    var lut = std.AutoArrayHashMapUnmanaged(BoxChar, u21){};
    // var LUT = [_]u21{'*'} ** 574482;
    pub var loaded: bool = false;
    fn register(border: BoxChar, c: u21) !void {
        try lut.put(fbo.allocator(), border, c);
    }
    pub fn load() !void {
        if (loaded) return;
        loaded = true;
        // 2500  ─  Box Drawings Light Horizontal
        try register(.{
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '─');
        // 2501  ━  Box Drawings Heavy Horizontal
        try register(.{
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '━');
        // 2502  │  Box Drawings Light Vertical
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
        }, '│');
        // 2503  ┃  Box Drawings Heavy Vertical
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
        }, '┃');
        // 2504  ┄  Box Drawings Light Triple Dash Horizontal
        try register(.{
            .e = .{ .weight = .light, .style = .dashed_triple },
            .w = .{ .weight = .light, .style = .dashed_triple },
        }, '┄');
        // 2505  ┅  Box Drawings Heavy Triple Dash Horizontal
        try register(.{
            .e = .{ .weight = .heavy, .style = .dashed_triple },
            .w = .{ .weight = .heavy, .style = .dashed_triple },
        }, '┅');
        // 2506  ┆  Box Drawings Light Triple Dash Vertical
        try register(.{
            .n = .{ .weight = .light, .style = .dashed_triple },
            .s = .{ .weight = .light, .style = .dashed_triple },
        }, '┆');
        // 2507  ┇  Box Drawings Heavy Triple Dash Vertical
        try register(.{
            .n = .{ .weight = .heavy, .style = .dashed_triple },
            .s = .{ .weight = .heavy, .style = .dashed_triple },
        }, '┇');

        // 2508  ┈  Box Drawings Light Quadruple Dash Horizontal
        try register(.{
            .e = .{ .weight = .light, .style = .dashed_quadruple },
            .w = .{ .weight = .light, .style = .dashed_quadruple },
        }, '┈');
        // 2509  ┉  Box Drawings Heavy Quadruple Dash Horizontal
        try register(.{
            .e = .{ .weight = .heavy, .style = .dashed_quadruple },
            .w = .{ .weight = .heavy, .style = .dashed_quadruple },
        }, '┉');
        // 250A  ┊  Box Drawings Light Quadruple Dash Vertical
        try register(.{
            .n = .{ .weight = .light, .style = .dashed_quadruple },
            .s = .{ .weight = .light, .style = .dashed_quadruple },
        }, '┊');
        // 250B  ┋  Box Drawings Heavy Quadruple Dash Vertical
        try register(.{
            .n = .{ .weight = .heavy, .style = .dashed_quadruple },
            .s = .{ .weight = .heavy, .style = .dashed_quadruple },
        }, '┋');
        // 250C  ┌  Box Drawings Light Down And Right
        try register(.{
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '┌');
        // 250D  ┍  Box Drawings Down Light And Right Heavy
        try register(.{
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┍');
        // 250E  ┎  Box Drawings Down Heavy And Right Light
        try register(.{
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '┎');
        // 250F  ┏  Box Drawings Heavy Down And Right
        try register(.{
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┏');
        // 2510  ┐  Box Drawings Light Down And Left
        try register(.{
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┐');
        // 2511  ┑  Box Drawings Down Light And Left Heavy
        try register(.{
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┑');
        // 2512  ┒  Box Drawings Down Heavy And Left Light
        try register(.{
            .s = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┒');
        // 2513  ┓  Box Drawings Heavy Down And Left
        try register(.{
            .s = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┓');
        // 2514  └  Box Drawings Down Light And Right Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '└');
        // 2515  ┕  Box Drawings Up Light And Right Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┕');
        // 2516  ┖  Box Drawings Up Heavy And Right Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '┖');
        // 2517  ┗  Box Drawings Heavy Up And Right
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┗');
        // 2518  ┘  Box Drawings Light Up And Left
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┘');
        // 2519  ┙  Box Drawings Up Light And Left Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┙');
        // 251A  ┚  Box Drawings Up Heavy And Left Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┚');
        // 251B  ┛  Box Drawings Heavy Up And Left
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┛');
        // 251C  ├  Box Drawings Light Vertical And Right
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '├');
        // 251D  ┝  Box Drawings Vertical Light And Right Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┝');
        // 251E  ┞  Box Drawings Up Heavy And Right Down Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '┞');
        // 2522  ┢  Box Drawings Up Light And Right Down Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┢');
        // 2523  ┣  Box Drawings Heavy Vertical And Right
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
        }, '┣');
        // 2524  ┤  Box Drawings Light Vertical And Left
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┤');
        // 2527  ┧  Box Drawings Down Heavy And Left Up Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┧');
        // 252B  ┫  Box Drawings Heavy Vertical And Left
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┫');
        // 252C  ┬  Box Drawings Light Down And Horizontal
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
        }, '┬');
        // 252D  ┭  Box Drawings Left Heavy And Right Down Light
        try register(.{
            .w = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
        }, '┭');
        // 252E  ┮  Box Drawings Right Heavy And Left Down Light
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
        }, '┮');
        // 252F  ┯  Box Drawings Down Light And Horizontal Heavy
        try register(.{
            .w = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
        }, '┯');
        // 2530  ┰  Box Drawings Down Heavy And Horizontal Light
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
        }, '┰');
        // 2531  ┱  Box Drawings Right Light And Left Down Heavy
        try register(.{
            .w = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
        }, '┱');
        // 2532  ┲  Box Drawings Left Light And Right Down Heavy
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
        }, '┲');
        // 2533  ┳  Box Drawings Heavy Down And Horizontal
        try register(.{
            .w = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
        }, '┳');
        // 2534  ┴  Box Drawings Light Up And Horizontal
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .n = .{ .weight = .light, .style = .solid },
        }, '┴');
        // 2535  ┵  Box Drawings Left Heavy And Right Up Light
        try register(.{
            .w = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .n = .{ .weight = .light, .style = .solid },
        }, '┵');
        // 2536  ┶  Box Drawings Right Heavy And Left Up Light
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .n = .{ .weight = .light, .style = .solid },
        }, '┶');
        // 253A  ┺  Box Drawings Left Light And Right Up Heavy
        try register(.{
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .n = .{ .weight = .heavy, .style = .solid },
        }, '┺');
        // 253B  ┻  Box Drawings Heavy Up And Horizontal
        try register(.{
            .w = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .n = .{ .weight = .heavy, .style = .solid },
        }, '┻');
        // 253C  ┼  Box Drawings Light Vertical And Horizontal
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┼');
        // 253D  ┽  Box Drawings Left Heavy And Right Vertical Light
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┽');
        // 253E  ┾  Box Drawings Right Heavy And Left Vertical Light
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '┾');

        // 253F  ┿  Box Drawings Vertical Light And Horizontal Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '┿');

        // 2540  ╀  Box Drawings Up Heavy And Down Horizontal Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '╀');

        // 2541  ╁  Box Drawings Down Heavy And Up Horizontal Light
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '╁');

        // 2542  ╂  Box Drawings Vertical Heavy And Horizontal Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '╂');

        // 2543  ╃  Box Drawings Left Up Heavy And Right Down Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╃');

        // 2544  ╄  Box Drawings Right Up Heavy And Left Down Light
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '╄');
        // 2545  ╅  Box Drawings Left Down Heavy And Right Up Light
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╅');
        // 2546  ╆  Box Drawings Right Down Heavy And Left Up Light
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╆');
        // 2547  ╇  Box Drawings Down Light And Up Horizontal Heavy
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╇');

        // 2548  ╈  Box Drawings Up Light And Down Horizontal Heavy
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╈');

        // 2549  ╉  Box Drawings Right Light And Left Vertical Heavy
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╉');
        // 254A  ╊  Box Drawings Left Light And Right Vertical Heavy
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .light, .style = .solid },
        }, '╊');
        // 254B  ╋  Box Drawings Heavy Vertical And Horizontal
        try register(.{
            .n = .{ .weight = .heavy, .style = .solid },
            .s = .{ .weight = .heavy, .style = .solid },
            .e = .{ .weight = .heavy, .style = .solid },
            .w = .{ .weight = .heavy, .style = .solid },
        }, '╋');
        // 254C  ╌  Box Drawings Light Double Dash Horizontal
        try register(.{
            .e = .{ .weight = .light, .style = .dashed_double },
            .w = .{ .weight = .light, .style = .dashed_double },
        }, '╌');
        // 254D  ╍  Box Drawings Heavy Double Dash Horizontal
        try register(.{
            .e = .{ .weight = .heavy, .style = .dashed_double },
            .w = .{ .weight = .heavy, .style = .dashed_double },
        }, '╍');
        // 254E  ╎  Box Drawings Light Double Dash Vertical
        try register(.{
            .n = .{ .weight = .light, .style = .dashed_double },
            .s = .{ .weight = .light, .style = .dashed_double },
        }, '╎');
        // 254F  ╏  Box Drawings Heavy Double Dash Vertical
        try register(.{
            .n = .{ .weight = .heavy, .style = .dashed_double },
            .s = .{ .weight = .heavy, .style = .dashed_double },
        }, '╏');
        // 2550  ═  Box Drawings Double Horizontal
        try register(.{
            .e = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
        }, '═');
        // 2551  ║  Box Drawings Double Vertical
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .s = .{ .weight = .light, .style = .double },
        }, '║');
        // 2552  ╒  Box Drawings Down Single And Right Double
        try register(.{
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .double },
        }, '╒');
        // 2553  ╓  Box Drawings Down Double And Right Single
        try register(.{
            .s = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .solid },
        }, '╓');
        // 2554  ╔  Box Drawings Double Down And Right
        try register(.{
            .s = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╔');
        // 2556  ╖  Box Drawings Down Double And Left Single
        try register(.{
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .solid },
        }, '╖');
        // 2557  ╗  Box Drawings Double Down And Left
        try register(.{
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
        }, '╗');
        // 2558  ╘  Box Drawings Up Single And Right Double
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .double },
        }, '╘');
        // 2559  ╙  Box Drawings Up Double And Right Single
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .solid },
        }, '╙');
        // 255A  ╚  Box Drawings Double Up And Right
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╚');
        // 255B  ╛  Box Drawings Up Single And Left Double
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .double },
        }, '╛');
        // 255C  ╜  Box Drawings Up Double And Left Single
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .solid },
        }, '╜');
        // 255D  ╝  Box Drawings Double Up And Left
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
        }, '╝');
        // 255E  ╞  Box Drawings Vertical Single And Right Double
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .double },
        }, '╞');
        // 2561  ╡  Box Drawings Vertical Single And Left Double
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .double },
        }, '╡');
        // 2562  ╢  Box Drawings Vertical Double And Left Single
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .solid },
        }, '╢');
        // 2563  ╣  Box Drawings Double Vertical And Left
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
        }, '╣');
        // 2564  ╤  Box Drawings Down Single And Horizontal Double
        try register(.{
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╤');
        // 2565  ╥  Box Drawings Down Double And Horizontal Single
        try register(.{
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '╥');
        // 2566  ╦  Box Drawings Double Down And Horizontal
        try register(.{
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╦');
        // 2567  ╧  Box Drawings Up Single And Horizontal Double
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╧');
        // 2568  ╨  Box Drawings Up Double And Horizontal Single
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '╨');
        // 2569  ╩  Box Drawings Double Up And Horizontal
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╩');
        // 256A  ╪  Box Drawings Vertical Single And Horizontal Double
        try register(.{
            .n = .{ .weight = .light, .style = .solid },
            .s = .{ .weight = .light, .style = .solid },
            .w = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╪');

        // 256B  ╫  Box Drawings Vertical Double And Horizontal Single
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .solid },
            .e = .{ .weight = .light, .style = .solid },
        }, '╫');

        // 256C  ╬  Box Drawings Double Vertical And Horizontal
        try register(.{
            .n = .{ .weight = .light, .style = .double },
            .s = .{ .weight = .light, .style = .double },
            .w = .{ .weight = .light, .style = .double },
            .e = .{ .weight = .light, .style = .double },
        }, '╬');

        // 256D  ╭  Box Drawings Light Arc Down And Right
        try register(.{
            .s = .{ .weight = .light, .style = .rounded },
            .e = .{ .weight = .light, .style = .rounded },
        }, '╭');
        // 256E  ╮  Box Drawings Light Arc Down And Left
        try register(.{
            .s = .{ .weight = .light, .style = .rounded },
            .w = .{ .weight = .light, .style = .rounded },
        }, '╮');
        // 256F  ╯  Box Drawings Light Arc Up And Left
        try register(.{
            .n = .{ .weight = .light, .style = .rounded },
            .w = .{ .weight = .light, .style = .rounded },
        }, '╯');
        // 2570  ╰  Box Drawings Light Arc Up And Right
        try register(.{
            .n = .{ .weight = .light, .style = .rounded },
            .e = .{ .weight = .light, .style = .rounded },
        }, '╰');
        // 2574  ╴  Box Drawings Light Left
        try register(.{
            .w = .{ .weight = .light, .style = .rounded },
        }, '╴');
        // 2575  ╵  Box Drawings Light Up
        try register(.{
            .n = .{ .weight = .light, .style = .rounded },
        }, '╵');
        // 2576  ╶  Box Drawings Light Right
        try register(.{
            .e = .{ .weight = .light, .style = .rounded },
        }, '╶');
        // 2577  ╷  Box Drawings Light Down
        try register(.{
            .s = .{ .weight = .light, .style = .rounded },
        }, '╷');
        // 2578  ╸  Box Drawings Heavy Left
        try register(.{
            .w = .{ .weight = .heavy, .style = .rounded },
        }, '╸');
        // 2579  ╹  Box Drawings Heavy Up
        try register(.{
            .n = .{ .weight = .heavy, .style = .rounded },
        }, '╹');
        // 257A  ╺  Box Drawings Heavy Right
        try register(.{
            .e = .{ .weight = .heavy, .style = .rounded },
        }, '╺');
        // 257B  ╻  Box Drawings Heavy Down
        try register(.{
            .s = .{ .weight = .heavy, .style = .rounded },
        }, '╻');
        // 257C  ╼  Box Drawings Light Left And Heavy Right
        try register(.{
            .w = .{ .weight = .light, .style = .rounded },
            .e = .{ .weight = .heavy, .style = .rounded },
        }, '╼');
        // 257F  ╿  Box Drawings Heavy Up And Light Down
        try register(.{
            .n = .{ .weight = .heavy, .style = .rounded },
            .s = .{ .weight = .light, .style = .rounded },
        }, '╿');
    }
};

test "encode-decode" {
    {
        const border = BoxChar{
            .n = BoxChar.Cell{ .weight = .light, .style = .solid },
            .e = BoxChar.Cell{ .weight = .heavy, .style = .dashed_double },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }

    {
        const border = BoxChar{
            .n = BoxChar.Cell{ .weight = .heavy, .style = .solid },
            .s = BoxChar.Cell{ .weight = .light, .style = .dashed_quadruple },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }
    {
        const border = BoxChar{
            .n = BoxChar.Cell{ .weight = .light, .style = .solid },
            .e = BoxChar.Cell{ .weight = .light, .style = .solid },
            .s = BoxChar.Cell{ .weight = .light, .style = .solid },
            .w = BoxChar.Cell{ .weight = .light, .style = .solid },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }

    {
        const border = BoxChar{
            .n = BoxChar.Cell{ .weight = .heavy, .style = .solid },
            .e = BoxChar.Cell{ .weight = .heavy, .style = .solid },
            .s = BoxChar.Cell{ .weight = .heavy, .style = .solid },
            .w = BoxChar.Cell{ .weight = .heavy, .style = .solid },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }

    {
        const border = BoxChar{
            .n = BoxChar.Cell{ .weight = .light, .style = .none },
            .e = BoxChar.Cell{ .weight = .heavy, .style = .solid },
            .s = BoxChar.Cell{ .weight = .light, .style = .dashed_half },
            .w = BoxChar.Cell{ .weight = .light, .style = .solid },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }

    {
        const border = BoxChar{
            .e = BoxChar.Cell{ .weight = .heavy, .style = .dashed_double },
            .s = BoxChar.Cell{ .weight = .heavy, .style = .dashed_double },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }

    {
        const border = BoxChar{}; // Default values
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }

    {
        const border = BoxChar{
            .n = BoxChar.Cell{ .weight = .light, .style = .dashed_triple },
            .e = BoxChar.Cell{ .weight = .light, .style = .solid },
            .s = BoxChar.Cell{ .weight = .heavy, .style = .solid },
            .w = BoxChar.Cell{ .weight = .light, .style = .dashed_double },
        };
        const encoded = border.encode();
        const decoded = BoxChar.decode(encoded);
        try std.testing.expectEqual(border, decoded);
    }
}

pub const Border = struct {
    char: BoxChar,
    color: parsers.background.Background,
};
const Result = utils.Result(BoxChar.Cell);
pub fn parse(src: []const u8, pos: usize) !utils.Result(BoxChar.Cell) {
    const cursor = utils.eatWhitespace(src, pos);
    // const char = utils.consumeFnCall(src, cursor);
    // const color = parsers.background.parse(allocator, src, cursor);

    const identifier = utils.consumeIdentifier(src, cursor);
    if (identifier.match("none")) {
        return .{ .value = .{}, .start = identifier.start, .end = identifier.end };
    }
    if (identifier.match("solid")) {
        return .{
            .value = .{ .weight = .light, .style = .solid },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("heavy")) {
        return .{
            .value = .{ .weight = .heavy, .style = .solid },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-wide")) {
        return .{
            .value = .{ .weight = .light, .style = .dashed_half },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-wide-heavy")) {
        return .{
            .value = .{ .weight = .heavy, .style = .dashed_half },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-double") or identifier.match("dashed")) {
        return .{
            .value = .{ .weight = .light, .style = .dashed_double },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-double-heavy")) {
        return .{
            .value = .{ .weight = .heavy, .style = .dashed_double },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-triple")) {
        return .{
            .value = .{ .weight = .light, .style = .dashed_triple },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-triple-heavy")) {
        return .{
            .value = .{ .weight = .heavy, .style = .dashed_triple },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-quadruple")) {
        return .{
            .value = .{ .weight = .light, .style = .dashed_quadruple },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("dashed-quadruple-heavy")) {
        return .{
            .value = .{ .weight = .heavy, .style = .dashed_quadruple },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("double")) {
        return .{
            .value = .{ .weight = .light, .style = .double },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    if (identifier.match("rounded")) {
        return .{
            .value = .{ .weight = .light, .style = .rounded },
            .start = identifier.start,
            .end = identifier.end,
        };
    }
    return error.InvalidSyntax;
}
