r: f64,
g: f64,
b: f64,
a: f64,

const Color = @This();

pub const tw = @import("./tw.zig");
const Vec4 = @Vector(4, f64);

// pub fn new(r: f64, g: f64, b: f64, a: f64) Color {

// }

pub fn toHex(self: Color) u32 {
    return @as(u32, @intFromFloat(self.r * 255)) << 24 //
    | @as(u32, @intFromFloat(self.g * 255)) << 16 //
    | @as(u32, @intFromFloat(self.b * 255)) << 8 //
    | @as(u32, @intFromFloat(self.a * 255));
}
pub fn toHexString(
    self: Color,
    buffer: []u8,
) ![]const u8 {
    const r, const g, const b = self.toU8RGB();

    return (try std.fmt.bufPrint(buffer, "#{X:0>2}{X:0>2}{X:0>2}", .{ r, g, b }))[0..7];
}
pub fn toU8RGB(self: Color) [3]u8 {
    return [_]u8{
        @intFromFloat(@round(self.r * 255)),
        @intFromFloat(@round(self.g * 255)),
        @intFromFloat(@round(self.b * 255)),
    };
}

fn assertChannel(channel: f64) void {
    if (channel < 0 or channel > 1 or std.math.isNan(channel)) {
        std.debug.panic("Channel out of range: {d}", .{channel});
    }
}
pub fn rgba(r: f64, g: f64, b: f64, a: f64) Color {
    assertChannel(r);
    assertChannel(g);
    assertChannel(b);
    assertChannel(a);
    return .{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
}

pub fn rgb(r: f64, g: f64, b: f64) Color {
    return rgba(r, g, b, 1);
}

pub fn isOpaque(c: Color) bool {
    return c.a >= 1 - std.math.floatEps(f64);
}
pub fn equal(a: Color, b: Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// pub fn mixLinear(a: Color, b: Color) {}
// hex with or without alpha
pub inline fn hex(comptime h: u32, a: f64) Color {
    @setEvalBranchQuota(10_000);
    return rgba(
        @as(f64, @floatFromInt(h >> 16 & 255)) / 255,
        @as(f64, @floatFromInt(h >> 8 & 255)) / 255,
        @as(f64, @floatFromInt(h & 255)) / 255,
        a,
    );
}

const std = @import("std");
const expectEqual = std.testing.expectEqual;

fn print(comptime fmt: []const u8, args: anytype) void {
    if (@inComptime()) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    }
    std.debug.print(fmt, args);
}
fn expectEqualColor(expected: Color, received: Color) !void {
    const tolerance: f64 = 0.01;
    if (std.math.approxEqAbs(f64, expected.r, received.r, tolerance) and
        std.math.approxEqAbs(f64, expected.g, received.g, tolerance) and
        std.math.approxEqAbs(f64, expected.b, received.b, tolerance) and
        std.math.approxEqAbs(f64, expected.a, received.a, tolerance))
    {
        return;
    }

    print("expected: {d}, {d}, {d}, {d}\n", .{ expected.r, expected.g, expected.b, expected.a });
    print("received: {d}, {d}, {d}, {d}\n", .{ received.r, received.g, received.b, received.a });

    return error.TestExpectedEqual;
}

pub const BlendMode = enum {
    normal,
    multiply,
    darken,
    lighten,
    screen,
    overlay,
    burn,
    dodge,
};

pub const CompositeOperation = enum {
    clear,
    copy,
    source_over,
    destination_over,
    source_in,
    destination_in,
    source_out,
    destination_out,
    source_atop,
    destination_atop,
    xor,
    lighter,
};
inline fn blendFunctions(a: f64, b: f64, comptime blend_mode: BlendMode) f64 {
    return switch (blend_mode) {
        .normal => a,
        .multiply => a * b,
        .darken => @min(a, b),
        .lighten => @max(a, b),
        .screen => 1 - (1 - a) * (1 - b),
        .overlay => if (b < 0.5) a * b * 2 else 1 - 2 * (1 - a) * (1 - b),
        .burn => 1 - @min(1, (1 - a) / b),
        .dodge => @min(1, a / (1 - b)),
    };
}
pub fn blend(a: Color, b: Color, comptime blend_mode: BlendMode) Color {
    return rgba(
        blendFunctions(a.r, b.r, blend_mode),
        blendFunctions(a.g, b.g, blend_mode),
        blendFunctions(a.b, b.b, blend_mode),
        a.a,
    );
}

fn mix(src: Color, dst: Color) Color {
    return rgba(
        src.r * src.a + dst.r * (1.0 - src.a),
        src.g * src.a + dst.g * (1.0 - src.a),
        src.b * src.a + dst.b * (1.0 - src.a),
        src.a + dst.a * (1.0 - src.a),
    );
}

fn premultipliedMix(src: Color, dst: Color) Color {
    const r = src.r * src.a + dst.r * dst.a * (1.0 - src.a);
    const g = src.g * src.a + dst.g * dst.a * (1.0 - src.a);
    const b = src.b * src.a + dst.b * dst.a * (1.0 - src.a);
    const a = src.a + dst.a * (1.0 - src.a);
    if (a == 0) {
        return rgba(0, 0, 0, 0);
    }
    return rgba(
        r / a,
        g / a,
        b / a,
        a,
    );
}
pub fn composite(src: Color, dst: Color, composite_operation: CompositeOperation) Color {
    return switch (composite_operation) {
        .clear => rgba(0, 0, 0, 0),
        .copy => src,
        .source_over => premultipliedMix(
            src,
            dst,
        ),
        .destination_over => premultipliedMix(
            dst,
            src,
        ),
        .source_in => rgba(src.r * dst.a, src.g * dst.a, src.b * dst.a, src.a * dst.a),
        .destination_in => rgba(dst.r * src.a, dst.g * src.a, dst.b * src.a, dst.a * src.a),
        .source_out => rgba(src.r * (1 - dst.a), src.g * (1 - dst.a), src.b * (1 - dst.a), src.a * (1 - dst.a)),
        .destination_out => rgba(dst.r * (1 - src.a), dst.g * (1 - src.a), dst.b * (1 - src.a), dst.a * (1 - src.a)),
        .source_atop => rgba(src.r * dst.a + dst.r * (1 - src.a), src.g * dst.a + dst.g * (1 - src.a), src.b * dst.a + dst.b * (1 - src.a), src.a * dst.a + dst.a * (1 - src.a)),
        .destination_atop => rgba(dst.r * src.a + src.r * (1 - dst.a), dst.g * src.a + src.g * (1 - dst.a), dst.b * src.a + src.b * (1 - dst.a), dst.a * src.a + src.a * (1 - dst.a)),
        .xor => rgba(src.r * (1 - dst.a) + dst.r * (1 - src.a), src.g * (1 - dst.a) + dst.g * (1 - src.a), src.b * (1 - dst.a) + dst.b * (1 - src.a), src.a * (1 - dst.a) + dst.a * (1 - src.a)),
        .lighter => rgba(@min(src.r + dst.r, 1), @min(src.g + dst.g, 1), @min(src.b + dst.b, 1), @min(src.a + dst.a, 1)),
    };
}

pub fn premultiply(color: Color) Color {
    return rgba(color.r * color.a, color.g * color.a, color.b * color.a, color.a);
}

inline fn rgb2linear(channel: f64) f64 {
    return if (channel <= 0.04045)
        channel / 12.92
    else
        std.math.pow(f64, (channel + 0.055) / 1.055, 2.4);
}

inline fn linear2rgb(channel: f64) f64 {
    return if (channel <= 0.0031308)
        channel * 12.92
    else
        1.055 * std.math.pow(f64, channel, 1.0 / 2.4) - 0.055;
}

pub fn premultiplyChannel(channel: f64, a: f64) f64 {
    return channel * a;
}
const Interpolate = struct {
    src: Color,
    dest: Color,
    premultiplied: bool,
    pub fn init(src: Color, dest: Color, premultiplied: bool) Interpolate {
        const src_lin_r = rgb2linear(src.r);
        const src_lin_g = rgb2linear(src.g);
        const src_lin_b = rgb2linear(src.b);
        const src_lin_a = src.a;
        const dest_lin_r = rgb2linear(dest.r);
        const dest_lin_g = rgb2linear(dest.g);
        const dest_lin_b = rgb2linear(dest.b);
        const dest_lin_a = dest.a;
        if (premultiplied) {
            return .{
                .premultiplied = true,
                .src = rgba(src_lin_r * src_lin_a, src_lin_g * src_lin_a, src_lin_b * src_lin_a, src_lin_a),
                .dest = rgba(dest_lin_r * dest_lin_a, dest_lin_g * dest_lin_a, dest_lin_b * dest_lin_a, dest_lin_a),
            };
        }
        return .{
            .premultiplied = false,
            .src = rgba(src_lin_r, src_lin_g, src_lin_b, src_lin_a),
            .dest = rgba(dest_lin_r, dest_lin_g, dest_lin_b, dest_lin_a),
        };
    }
    pub fn at(self: Interpolate, t: f64) Color {
        const out = rgba(
            self.src.r + (self.dest.r - self.src.r) * t,
            self.src.g + (self.dest.g - self.src.g) * t,
            self.src.b + (self.dest.b - self.src.b) * t,
            self.src.a + (self.dest.a - self.src.a) * t,
        );
        if (self.premultiplied) {
            const inv_a = if (out.a > 0.0) 1.0 / out.a else 0.0;
            return rgba(
                linear2rgb(out.r * inv_a),
                linear2rgb(out.g * inv_a),
                linear2rgb(out.b * inv_a),
                out.a,
            );
        }
        return rgba(linear2rgb(out.r), linear2rgb(out.g), linear2rgb(out.b), out.a);
    }
};
inline fn clamp01(x: f64) f64 {
    return std.math.clamp(x, 0.0, 1.0);
}
pub fn Interpolator(comptime premultiplied: bool) type {
    return struct {
        const Self = @This();
        src: Color,
        dest: Color,
        effectivePremultiplied: bool, // Cache whether the values were premultiplied

        pub fn init(src: Color, dest: Color) Self {
            // Determine if we should use premultiplied values.
            // We force premultiplication if both colors are fully opaque.
            const fully_opaque = src.a == 1.0 and dest.a == 1.0;
            const effective = premultiplied or fully_opaque;

            // Convert from sRGB to linear.
            const src_lin: Color = rgba(rgb2linear(src.r), rgb2linear(src.g), rgb2linear(src.b), src.a);
            const dest_lin: Color = rgba(rgb2linear(dest.r), rgb2linear(dest.g), rgb2linear(dest.b), dest.a);

            // If effective, premultiply by alpha.
            const src_pre: Color = if (effective) rgba(src_lin.r * src_lin.a, src_lin.g * src_lin.a, src_lin.b * src_lin.a, src_lin.a) else src_lin;

            const dest_pre: Color = if (effective) rgba(dest_lin.r * dest_lin.a, dest_lin.g * dest_lin.a, dest_lin.b * dest_lin.a, dest_lin.a) else dest_lin;

            return .{
                .src = src_pre,
                .dest = dest_pre,
                .effectivePremultiplied = effective,
            };
        }

        pub inline fn at(self: Self, t: f64) Color {
            // Interpolate the cached (linear) values.
            const r = self.src.r + (self.dest.r - self.src.r) * t;
            const g = self.src.g + (self.dest.g - self.src.g) * t;
            const b = self.src.b + (self.dest.b - self.src.b) * t;
            const a = self.src.a + (self.dest.a - self.src.a) * t;

            // Only unpremultiply if our stored values were premultiplied.
            if (self.effectivePremultiplied) {
                const inv_a = if (a > 0.0) 1.0 / a else 0.0;
                return rgba(clamp01(linear2rgb(r * inv_a)), clamp01(linear2rgb(g * inv_a)), clamp01(linear2rgb(b * inv_a)), clamp01(a));
            } else {
                return rgba(clamp01(linear2rgb(r)), clamp01(linear2rgb(g)), clamp01(linear2rgb(b)), clamp01(a));
            }
        }
    };
}
pub fn interpolate(src: Color, dest: Color, t: f64, comptime premultiplied: bool) Color {
    // const interpolator = Interpolate.init(src, dest, premultiplied);
    const interpolator = Interpolator(premultiplied).init(src, dest);
    return interpolator.at(t);
    // _ = premultiplied; // autofix
    // // --- Step 1: Convert from sRGB to linear light ---
    // const src_lin = .{
    //     .r = rgb2linear(src.r),
    //     .g = rgb2linear(src.g),
    //     .b = rgb2linear(src.b),
    //     .a = src.a,
    // };
    // const dest_lin = .{
    //     .r = rgb2linear(dest.r),
    //     .g = rgb2linear(dest.g),
    //     .b = rgb2linear(dest.b),
    //     .a = dest.a,
    // };

    // // --- Step 2: Premultiply by alpha ---
    // const src_premul = .{
    //     .r = src_lin.r * src_lin.a,
    //     .g = src_lin.g * src_lin.a,
    //     .b = src_lin.b * src_lin.a,
    //     .a = src_lin.a,
    // };
    // const dest_premul = .{
    //     .r = dest_lin.r * dest_lin.a,
    //     .g = dest_lin.g * dest_lin.a,
    //     .b = dest_lin.b * dest_lin.a,
    //     .a = dest_lin.a,
    // };

    // // --- Step 3: Interpolate each component ---
    // const out_premul = .{
    //     .r = src_premul.r + (dest_premul.r - src_premul.r) * t,
    //     .g = src_premul.g + (dest_premul.g - src_premul.g) * t,
    //     .b = src_premul.b + (dest_premul.b - src_premul.b) * t,
    //     .a = src_premul.a + (dest_premul.a - src_premul.a) * t,
    // };

    // // --- Step 4: Un-premultiply (avoid divide by zero) ---
    // const inv_a = if (out_premul.a > 0.0) 1.0 / out_premul.a else 0.0;
    // const out_lin = .{
    //     .r = out_premul.r * inv_a,
    //     .g = out_premul.g * inv_a,
    //     .b = out_premul.b * inv_a,
    //     .a = out_premul.a,
    // };

    // // --- Step 5: Convert back to sRGB ---
    // return .{
    //     .r = linear2rgb(out_lin.r),
    //     .g = linear2rgb(out_lin.g),
    //     .b = linear2rgb(out_lin.b),
    //     .a = out_lin.a,
    // };
}

pub fn alpha(src: Color, a: f64) Color {
    return rgba(src.r, src.g, src.b, a);
}

pub fn blendAndComposite(src: Color, dst: Color, comptime blend_mode: BlendMode, comptime composite_operation: CompositeOperation) Color {
    return composite(blend(src, dst, blend_mode), dst, composite_operation);
}

// /**
//  * convert a single default RGB (a.k.a. sRGB) channel to linear RGB
//  * @param channel    R, G or B channel
//  * @return channel in linear RGB
//  */

inline fn toLinear(color: Color) Color {
    return rgba(rgb2linear(color.r), rgb2linear(color.g), rgb2linear(color.b), color.a);
}
inline fn toSRGB(color: Color) Color {
    return rgba(linear2rgb(color.r), linear2rgb(color.g), linear2rgb(color.b), color.a);
}

test "blend" {
    try expectEqualColor(hex(0x4CBBFC, 1).blend(hex(0xEEEE22, 1), .multiply), hex(0x47AF22, 1));

    try expectEqualColor(
        rgba(1, 0, 0, 0.5)
            .composite(
                rgba(0, 1, 0, 0.5),
                .source_over,
            ).composite(
            rgba(1, 1, 1, 1),
            .source_over,
        ),
        hex(0xbf7f3f, 1),
    );
}
fn parseHexChannel(text: []const u8) !f32 {
    @setEvalBranchQuota(10_000);
    const a: u32 = blk: {
        const c = text[text.len - 1];
        if (c >= '0' and c <= '9') {
            break :blk c - '0';
        }
        if (c >= 'A' and c <= 'F') {
            break :blk c - 'A' + 10;
        }
        if (c >= 'a' and c <= 'f') {
            break :blk c - 'a' + 10;
        }
        return error.InvalidHex;
    };
    const b = blk: {
        if (text.len == 1) {
            break :blk a;
        }
        const c = text[0];
        if (c >= '0' and c <= '9') {
            break :blk c - '0';
        }
        if (c >= 'A' and c <= 'F') {
            break :blk c - 'A' + 10;
        }
        if (c >= 'a' and c <= 'f') {
            break :blk c - 'a' + 10;
        }
        return error.InvalidHex;
    };
    // @compileLog(a, b, text);
    return @as(f32, @floatFromInt(a + b * 16)) / 255;
}
pub fn fromHex(h: []const u8) ?Color {
    if (!std.mem.startsWith(u8, h, "#")) {
        return null;
    }
    const channels = h[1..];
    if (channels.len == 3) {
        const r = parseHexChannel(channels[0..1]) catch return null;
        const g = parseHexChannel(channels[1..2]) catch return null;
        const b = parseHexChannel(channels[2..3]) catch return null;
        return rgba(r, g, b, 1);
    }
    if (channels.len == 4) {
        const r = parseHexChannel(channels[0..1]) catch return null;
        const g = parseHexChannel(channels[1..2]) catch return null;
        const b = parseHexChannel(channels[2..3]) catch return null;
        const a = parseHexChannel(channels[3..4]) catch return null;
        return rgba(r, g, b, a);
    }
    if (channels.len == 6) {
        const r = parseHexChannel(channels[0..2]) catch return null;
        const g = parseHexChannel(channels[2..4]) catch return null;
        const b = parseHexChannel(channels[4..6]) catch return null;
        return rgba(r, g, b, 1);
    }
    if (channels.len == 8) {
        const r = parseHexChannel(channels[0..2]) catch return null;
        const g = parseHexChannel(channels[2..4]) catch return null;
        const b = parseHexChannel(channels[4..6]) catch return null;
        const a = parseHexChannel(channels[6..8]) catch return null;
        return rgba(r, g, b, a);
    }
    return null;
}
pub fn format(self: Color, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    const renderable = self.composite(Color.fromHex("#000000").?, .source_over).toU8RGB();
    _ = fmt; // autofix
    _ = options; // autofix
    try writer.print("\x1b[48;2;{d};{d};{d}m \x1b[0m ", .{
        renderable[0],
        renderable[1],
        renderable[2],
    });
    const channels = self.toU8RGB();
    try writer.print("rgba({d:.2}, {d:.2}, {d:.2}, {d:.2})", .{ channels[0], channels[1], channels[2], self.a });
}

test "parseHexChannel" {
    try std.testing.expectEqual(1, comptime parseHexChannel("f"));
    try std.testing.expectEqual(1, parseHexChannel("F"));
    try std.testing.expectEqual(1, parseHexChannel("fF"));
    try std.testing.expectEqual(1, parseHexChannel("Ff"));
}

/// Calculates the contrast ratio between two colors. The contrast
/// ration is a value between 1 and 21 where 1 is the lowest contrast
/// and 21 is the highest contrast.
///
/// https://www.w3.org/TR/WCAG20/#contrast-ratiodef
pub fn contrast(self: Color, other: Color) f64 {
    // pair[0] = lighter, pair[1] = darker
    const pair: [2]f64 = pair: {
        const self_lum = self.luminance();
        const other_lum = other.luminance();
        if (self_lum > other_lum) break :pair .{ self_lum, other_lum };
        break :pair .{ other_lum, self_lum };
    };

    return (pair[0] + 0.05) / (pair[1] + 0.05);
}

pub fn contrastedColor(
    self: Color,
    other: Color,
    min: f64,
) Color {
    const ratio = self.contrast(other);
    if (ratio < min) {
        const white_ratio = self.contrast(Color.tw.white);
        const black_ratio = self.contrast(Color.tw.black);
        if (white_ratio > black_ratio) {
            return Color.tw.white;
        } else {
            return Color.tw.black;
        }
    }

    return self;
}

/// Calculates luminance based on the W3C formula. This returns a
/// normalized value between 0 and 1 where 0 is black and 1 is white.
///
/// https://www.w3.org/TR/WCAG20/#relativeluminancedef
pub fn luminance(self: Color) f64 {
    const r_lum = componentLuminance(self.r);
    const g_lum = componentLuminance(self.g);
    const b_lum = componentLuminance(self.b);
    return 0.2126 * r_lum + 0.7152 * g_lum + 0.0722 * b_lum;
}

/// Calculates single-component luminance based on the W3C formula.
///
/// Expects sRGB color space which at the time of writing we don't
/// generally use but it's a good enough approximation until we fix that.
/// https://www.w3.org/TR/WCAG20/#relativeluminancedef
fn componentLuminance(c: f64) f64 {
    if (c <= 0.03928) return c / 12.92;
    return std.math.pow(f64, (c + 0.055) / 1.055, 2.4);
}
