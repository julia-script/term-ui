const styles = @import("styles.zig");
const std = @import("std");
const utils = styles.utils;
const fmt = @import("../fmt.zig");

// <color-stop-list> =
//   <linear-color-stop> , [ <linear-color-hint>? , <linear-color-stop> ]#?

// <linear-color-stop> =
//   <color> <length-percentage>?

// <linear-color-hint> =
//   <length-percentage>

pub const ColorStop = struct {
    color: styles.color.Color,
    position: ?styles.length_percentage.LengthPercentage,
    hint: ?styles.length_percentage.LengthPercentage,

    pub fn init(color: styles.color.Color, position: ?styles.length_percentage.LengthPercentage) ColorStop {
        return .{
            .color = color,
            .position = position,
            .hint = null,
        };
    }

    /// Prints a formatted representation of the ColorStop to the provided writer
    pub fn dump(self: ColorStop, writer: anytype) !void {
        // Print colored square character
        const rgb = self.color.toU8RGB();
        try writer.print("\x1b[48;2;{d};{d};{d}m \x1b[0m ", .{ rgb[0], rgb[1], rgb[2] });

        // Print color
        try writer.print("rgb({d:.0},{d:.0},{d:.0}) ", .{ self.color.r * 255, self.color.g * 255, self.color.b * 255 });

        // Print position
        if (self.position) |pos| {
            switch (pos) {
                .percentage => |percentage| {
                    try writer.print("{d:.2}% ", .{percentage});
                },
                .length => |length| {
                    try writer.print("{d:.2}px ", .{length});
                },
            }
        } else {
            try writer.print("auto ", .{});
        }

        // Print hint
        if (self.hint) |hint| {
            switch (hint) {
                .percentage => |percentage| {
                    try writer.print("hint: {d:.2}%", .{percentage});
                },
                .length => |length| {
                    try writer.print("hint: {d:.2}px", .{length});
                },
            }
        } else {
            try writer.print("no hint", .{});
        }

        try writer.writeByte('\n');
    }
};

pub fn parseColorStop(src: []const u8, pos: usize) !utils.Result(ColorStop) {
    var cursor = utils.eatWhitespace(src, pos);

    // Parse the color
    const color_result = try styles.color.parse(src, cursor);
    cursor = utils.eatWhitespace(src, color_result.end);

    // Try to parse an optional length-percentage
    var position: ?styles.length_percentage.LengthPercentage = null;
    if (cursor < src.len and src[cursor] != ',') {
        if (styles.length_percentage.parse(src, cursor)) |length_percentage| {
            position = length_percentage.value;
            cursor = utils.eatWhitespace(src, length_percentage.end);
        } else |_| {}
    }

    return .{
        .value = ColorStop.init(color_result.value, position),
        .start = pos,
        .end = cursor,
    };
}

pub fn parseColorHint(allocator: std.mem.Allocator, src: []const u8, pos: usize) utils.ParseError!?utils.Result(styles.length_percentage.LengthPercentage) {
    var cursor = utils.eatWhitespace(src, pos);

    // Check if we can parse a length-percentage
    if (styles.length_percentage.parse(allocator, src, cursor)) |length_percentage| {
        cursor = utils.eatWhitespace(src, length_percentage.end);

        // Make sure the hint is followed by a comma (otherwise it's not a hint)
        if (cursor < src.len and src[cursor] == ',') {
            return length_percentage;
        } else {}
    } else |_| {}

    return null;
}
/// Color stops stored inline (max 16): parsed style values are copied by
/// value through the style system, so the storage must travel with the
/// struct — a heap/stack slice here becomes dangling after the parse returns.
pub const ColorStopList = struct {
    pub const capacity = 16;

    buffer: [capacity]ColorStop = undefined,
    len: usize = 0,

    pub fn appendAssumeCapacity(self: *ColorStopList, stop: ColorStop) void {
        self.buffer[self.len] = stop;
        self.len += 1;
    }

    pub fn items(self: *const ColorStopList) []const ColorStop {
        return self.buffer[0..self.len];
    }
};

pub fn parseColorStopList(src: []const u8, pos: usize) utils.ParseError!utils.Result(ColorStopList) {
    var cursor = utils.eatWhitespace(src, pos);

    var color_stops = ColorStopList{};

    // Parse additional color stops
    while (cursor < src.len) {
        const color_stop_result = try parseColorStop(src, cursor);
        var color_stop = color_stop_result.value;

        cursor = utils.eatWhitespace(src, color_stop_result.end);
        if (utils.nextIsDigitish(src, cursor)) {
            const hint = try styles.length_percentage.parse(src, cursor);
            cursor = utils.eatWhitespace(src, hint.end);
            color_stop.hint = hint.value;
        }
        color_stops.appendAssumeCapacity(color_stop);

        if (utils.consumeChar(src, ',', cursor)) |new_cursor| {
            cursor = utils.eatWhitespace(src, new_cursor);
            continue;
        }
        break;

        // // There should be a comma between color stops
        // if (utils.consumeChar(src, ',', cursor)) |new_cursor| {
        //     cursor = utils.eatWhitespace(src, new_cursor);
        // } else {
        //     break;
        // }

        // // Check for a color hint
        // if (try parseColorHint(allocator, src, cursor)) |hint| {
        //     // Apply the hint to the last color stop
        //     var last_stop = &color_stops.items[color_stops.items.len - 1];
        //     last_stop.hint = hint.value;

        //     cursor = utils.eatWhitespace(src, hint.end);

        //     // There should be a comma after the hint
        //     if (utils.consumeChar(src, ',', cursor)) |new_cursor| {
        //         cursor = utils.eatWhitespace(src, new_cursor);
        //     } else {
        //         return error.InvalidSyntax;
        //     }
        // }

        // // Parse the next color stop
        // const next_stop = try parseColorStop(allocator, src, cursor);
        // try color_stops.append(next_stop.value);
        // cursor = next_stop.end;
    }

    // We need at least two color stops for a valid gradient
    if (color_stops.len < 2) {
        return error.InvalidSyntax;
    }

    // Create the final color stops array
    // const color_stops_array = try allocator.dupe(ColorStop, color_stops.items);
    // color_stops.deinit();

    return .{
        .value = color_stops,
        .start = pos,
        .end = cursor,
    };
}

/// Dumps a list of color stops to the provided writer
pub fn dumpColorStops(stops: []const ColorStop, writer: anytype) !void {
    for (stops, 0..) |stop, i| {
        try writer.print("{d}: ", .{i});
        try stop.dump(writer);
    }
}
