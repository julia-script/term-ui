const styles = @import("styles.zig");
const std = @import("std");
const utils = styles.utils;
const fmt = @import("../fmt.zig");
const ColorStop = styles.color_stop.ColorStop;
// <radial-gradient()> =
//   radial-gradient( [ <radial-gradient-syntax> ] )

// <radial-gradient-syntax> =
//   [ <radial-shape> || <radial-size> ]? [ at <position> ]? , <color-stop-list>

// <radial-shape> =
//   circle   |
//   ellipse

// <radial-size> =
//   <radial-extent>               |
//   <length [0,∞]>                |
//   <length-percentage [0,∞]>{2}

// <position> =
//   [ left | center | right | top | bottom | <length-percentage> ]  |
//   [ left | center | right ] && [ top | center | bottom ]  |
//   [ left | center | right | <length-percentage> ] [ top | center | bottom | <length-percentage> ]  |
//   [ [ left | right ] <length-percentage> ] && [ [ top | bottom ] <length-percentage> ]

// <color-stop-list> =
//   <linear-color-stop> , [ <linear-color-hint>? , <linear-color-stop> ]#?

// <radial-extent> =
//   closest-corner   |
//   closest-side     |
//   farthest-corner  |
//   farthest-side

// <length-percentage> =
//   <length>      |
//   <percentage>

// <linear-color-stop> =
//   <color> <length-percentage>?

// <linear-color-hint> =
//   <length-percentage>

pub const RadialShape = enum {
    circle,
    ellipse,

    pub const default = RadialShape.ellipse;
};

pub const RadialExtent = enum {
    closest_corner,
    closest_side,
    farthest_corner,
    farthest_side,
};

pub const Position = struct {
    x: styles.length_percentage.LengthPercentage,
    y: styles.length_percentage.LengthPercentage,

    pub fn center() Position {
        return .{
            .x = .{ .percentage = 50 },
            .y = .{ .percentage = 50 },
        };
    }
};

pub const RadialSize = union(enum) {
    extent: RadialExtent,
    length: styles.length_percentage.LengthPercentage,
    lengths: struct {
        x: styles.length_percentage.LengthPercentage,
        y: styles.length_percentage.LengthPercentage,
    },
};

pub const RadialGradient = struct {
    shape: RadialShape,
    size: RadialSize,
    position: Position,
    color_stops: styles.color_stop.ColorStopList,
};

fn parseShapeAndSize(src: []const u8, pos: usize) utils.ParseError!?utils.Result(struct {
    shape: RadialShape,
    size: RadialSize,
}) {
    var cursor = utils.eatWhitespace(src, pos);
    var shape = RadialShape.default;
    var size: ?RadialSize = null;
    var shape_parsed = false;
    var size_parsed = false;

    // Try to parse shape
    const circle = utils.matchIdentifier(src, "circle", cursor);
    const ellipse = utils.matchIdentifier(src, "ellipse", cursor);

    if (circle != null) {
        shape = .circle;
        cursor = utils.eatWhitespace(src, circle.?.end);
        shape_parsed = true;
    } else if (ellipse != null) {
        shape = .ellipse;
        cursor = utils.eatWhitespace(src, ellipse.?.end);
        shape_parsed = true;
    }

    // Try to parse extent keywords
    if (!size_parsed) {
        const closest_corner = utils.matchIdentifier(src, "closest-corner", cursor);
        const closest_side = utils.matchIdentifier(src, "closest-side", cursor);
        const farthest_corner = utils.matchIdentifier(src, "farthest-corner", cursor);
        const farthest_side = utils.matchIdentifier(src, "farthest-side", cursor);

        if (closest_corner != null) {
            size = .{ .extent = .closest_corner };
            cursor = utils.eatWhitespace(src, closest_corner.?.end);
            size_parsed = true;
        } else if (closest_side != null) {
            size = .{ .extent = .closest_side };
            cursor = utils.eatWhitespace(src, closest_side.?.end);
            size_parsed = true;
        } else if (farthest_corner != null) {
            size = .{ .extent = .farthest_corner };
            cursor = utils.eatWhitespace(src, farthest_corner.?.end);
            size_parsed = true;
        } else if (farthest_side != null) {
            size = .{ .extent = .farthest_side };
            cursor = utils.eatWhitespace(src, farthest_side.?.end);
            size_parsed = true;
        }
    }

    // Try to parse one or two lengths
    if (!size_parsed) {
        if (styles.length_percentage.parse(src, cursor)) |first_length| {
            cursor = utils.eatWhitespace(src, first_length.end);

            // Check if there's a second length
            if (styles.length_percentage.parse(src, cursor)) |second_length| {
                // Two lengths (ellipse)
                size = .{
                    .lengths = .{
                        .x = first_length.value,
                        .y = second_length.value,
                    },
                };
                cursor = utils.eatWhitespace(src, second_length.end);
                size_parsed = true;

                // If shape wasn't explicitly specified, it's an ellipse when we have two lengths
                if (!shape_parsed) {
                    shape = .ellipse;
                }
            } else |_| {
                // Single length (circle)
                size = .{ .length = first_length.value };
                size_parsed = true;

                // If shape wasn't explicitly specified, it's a circle when we have one length
                if (!shape_parsed) {
                    shape = .circle;
                }
            }
        } else |_| {}
    }

    // If neither shape nor size was parsed, return null
    if (!shape_parsed and !size_parsed) {
        return null;
    }

    // If size wasn't explicitly set, use defaults based on shape
    if (size == null) {
        size = .{ .extent = .farthest_corner };
    }

    return .{
        .value = .{
            .shape = shape,
            .size = size.?,
        },
        .start = pos,
        .end = cursor,
    };
}

fn parsePosition(src: []const u8, pos: usize) utils.ParseError!?utils.Result(Position) {
    var cursor = utils.eatWhitespace(src, pos);

    // Check for "at" keyword
    const at = utils.matchIdentifier(src, "at", cursor);
    if (at == null) {
        return null;
    }

    cursor = utils.eatWhitespace(src, at.?.end);
    var x_pos: ?styles.length_percentage.LengthPercentage = null;
    var y_pos: ?styles.length_percentage.LengthPercentage = null;

    // First value
    const left = utils.matchIdentifier(src, "left", cursor);
    const center_x = utils.matchIdentifier(src, "center", cursor);
    const right = utils.matchIdentifier(src, "right", cursor);
    const top = utils.matchIdentifier(src, "top", cursor);
    const center_y = center_x; // center can be used for both x and y
    _ = center_y; // autofix
    const bottom = utils.matchIdentifier(src, "bottom", cursor);

    if (left != null) {
        x_pos = .{ .percentage = 0 };
        cursor = utils.eatWhitespace(src, left.?.end);
    } else if (center_x != null) {
        x_pos = .{ .percentage = 50 };
        cursor = utils.eatWhitespace(src, center_x.?.end);
    } else if (right != null) {
        x_pos = .{ .percentage = 100 };
        cursor = utils.eatWhitespace(src, right.?.end);
    } else if (top != null) {
        y_pos = .{ .percentage = 0 };
        cursor = utils.eatWhitespace(src, top.?.end);
    } else if (bottom != null) {
        y_pos = .{ .percentage = 100 };
        cursor = utils.eatWhitespace(src, bottom.?.end);
    } else if (styles.length_percentage.parse(src, cursor)) |length| {
        x_pos = length.value;
        cursor = utils.eatWhitespace(src, length.end);
    } else |_| {
        return error.InvalidSyntax;
    }

    // Second value (optional)
    const second_left = utils.matchIdentifier(src, "left", cursor);
    const second_center_x = utils.matchIdentifier(src, "center", cursor);
    const second_right = utils.matchIdentifier(src, "right", cursor);
    const second_top = utils.matchIdentifier(src, "top", cursor);
    const second_center_y = second_center_x;
    _ = second_center_y; // autofix
    const second_bottom = utils.matchIdentifier(src, "bottom", cursor);

    if (second_left != null) {
        if (x_pos != null) return error.InvalidSyntax;
        x_pos = .{ .percentage = 0 };
        cursor = utils.eatWhitespace(src, second_left.?.end);
    } else if (second_center_x != null) {
        if (x_pos == null) {
            x_pos = .{ .percentage = 50 };
        } else if (y_pos == null) {
            y_pos = .{ .percentage = 50 };
        } else {
            return error.InvalidSyntax;
        }
        cursor = utils.eatWhitespace(src, second_center_x.?.end);
    } else if (second_right != null) {
        if (x_pos != null) return error.InvalidSyntax;
        x_pos = .{ .percentage = 100 };
        cursor = utils.eatWhitespace(src, second_right.?.end);
    } else if (second_top != null) {
        if (y_pos != null) return error.InvalidSyntax;
        y_pos = .{ .percentage = 0 };
        cursor = utils.eatWhitespace(src, second_top.?.end);
    } else if (second_bottom != null) {
        if (y_pos != null) return error.InvalidSyntax;
        y_pos = .{ .percentage = 100 };
        cursor = utils.eatWhitespace(src, second_bottom.?.end);
    } else if (styles.length_percentage.parse(src, cursor)) |length| {
        if (y_pos != null) return error.InvalidSyntax;
        y_pos = length.value;
        cursor = utils.eatWhitespace(src, length.end);
    } else |_| {
        // No second value is fine
    }

    // If one of the positions wasn't specified, use default
    if (x_pos == null) {
        x_pos = .{ .percentage = 50 };
    }

    if (y_pos == null) {
        y_pos = .{ .percentage = 50 };
    }

    return .{
        .value = .{
            .x = x_pos.?,
            .y = y_pos.?,
        },
        .start = pos,
        .end = cursor,
    };
}

pub fn parse(src: []const u8, pos: usize) utils.ParseError!utils.Result(RadialGradient) {
    const start = utils.eatWhitespace(src, pos);
    var cursor = start;

    // Check for radial-gradient function call
    const fn_call = utils.consumeFnCall(src, cursor);

    if (fn_call.match("radial-gradient(")) {
        cursor = fn_call.end;
        cursor = utils.eatWhitespace(src, cursor);
    } else {
        return error.InvalidSyntax;
    }

    cursor = utils.eatWhitespace(src, cursor);

    // Parse optional shape and size
    var shape = RadialShape.default;
    var size = RadialSize{ .extent = .farthest_corner };
    var shape_size_specified = false;

    if (try parseShapeAndSize(src, cursor)) |shape_size| {
        shape = shape_size.value.shape;
        size = shape_size.value.size;
        cursor = utils.eatWhitespace(src, shape_size.end);
        shape_size_specified = true;
    }

    // Parse optional position
    var position = Position.center();
    var position_specified = false;

    if (try parsePosition(src, cursor)) |pos_result| {
        position = pos_result.value;
        cursor = utils.eatWhitespace(src, pos_result.end);
        position_specified = true;
    }

    // There should be a comma before the color stops if we specified shape, size, or position
    if (shape_size_specified or position_specified) {
        if (utils.consumeChar(src, ',', cursor)) |new_cursor| {
            cursor = utils.eatWhitespace(src, new_cursor);
        } else {
            return error.InvalidSyntax;
        }
    } else {
        // Check for first color directly
        // Try to parse shape/size/position again, but this time we want to fail to avoid confusion with colors
        // const color_result = styles.color.parse(allocator, src, cursor) catch {
        //     return error.InvalidSyntax;
        // };
        // _ = color_result; // autofix

        // If we got here, it's a color directly after the function name, so proceed with color stops
    }

    var gradient = RadialGradient{
        .shape = shape,
        .size = size,
        .position = position,
        .color_stops = .{},
    };
    // Parse the color stop list
    const color_stops_result = try styles.color_stop.parseColorStopList(src, cursor);
    cursor = color_stops_result.end;
    cursor = utils.consumeChar(src, ')', cursor) orelse return error.InvalidSyntax;
    gradient.color_stops = color_stops_result.value;

    // Create the radial gradient

    return .{
        .value = gradient,
        .start = start,
        .end = cursor,
    };
}
