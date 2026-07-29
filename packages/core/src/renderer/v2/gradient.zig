const std = @import("std");
const styles = @import("../../styles/styles.zig");
const ColorStop = styles.color_stop.ColorStop;
const Color = @import("../../colors/Color.zig");
const Canvas = @import("./Canvas.zig");
const Point = @import("../../layout/point.zig").Point;
const fmt = @import("../../fmt.zig");
const LayoutRect = @import("../../layout/rect.zig").Rect;
fn resolveLength(
    size: f32,
    length_percentage: styles.length_percentage.LengthPercentage,
) styles.length_percentage.LengthPercentage {
    switch (length_percentage) {
        .percentage => |percentage| {
            return .{ .length = size * percentage / 100 };
        },
        .length => return length_percentage,
    }
}
fn fixUpColorStops(
    allocator: std.mem.Allocator,
    src_stops: []const ColorStop,
    gradient_line_length: f32,
) ![]ColorStop {
    var stops = try allocator.dupe(ColorStop, src_stops);
    std.debug.assert(stops.len >= 2);

    // 1. If the first color stop does not have a position,
    // set its position to 0%. If the last color stop does not have a position,
    // set its position to 100%.
    var last_position: f32 = 0;
    var last_position_step: usize = 0;
    if (stops[0].position) |*position| {
        position.* = resolveLength(gradient_line_length, position.*);
        last_position = position.length;
        if (stops[0].hint) |*hint| {
            hint.* = resolveLength(gradient_line_length, hint.*);
            hint.length = @max(hint.length, last_position);
            last_position = @max(last_position, hint.length);
        }
    } else {
        stops[0].position = .{
            .length = 0,
        };
    }
    if (stops[stops.len - 1].position) |*position| {
        position.* = resolveLength(gradient_line_length, position.*);
    } else {
        stops[stops.len - 1].position = .{
            .length = gradient_line_length,
        };
    }

    var i: usize = 1;
    while (i < stops.len) : (i += 1) {
        var current_stop = &stops[i];
        // var previous_stop = stops[i - 1];
        // 2. If a color stop or transition hint
        // has a position that is less than the specified position
        // of any color stop or transition hint before it in the list,
        // set its position to be equal to the largest specified position
        // of any color stop or transition hint before it.
        if (current_stop.position) |*position| {
            position.* = resolveLength(gradient_line_length, position.*);
            const current_position = @max(last_position, position.length);
            position.* = .{ .length = current_position };
            // 3. If any color stop still does not have a position,
            // then, for each run of adjacent color stops without positions,
            // set their positions so that they are evenly spaced between the preceding
            // and following color stops with positions.
            const unresolved_steps = i - last_position_step;
            if (unresolved_steps > 1) {
                const step_size = (current_position - last_position) / @as(f32, @floatFromInt(unresolved_steps));
                for (0..unresolved_steps - 1) |j| {
                    const j_f: f32 = @floatFromInt(j + 1);
                    stops[last_position_step + j + 1].position = .{ .length = last_position + j_f * step_size };
                }
            }
            last_position = current_position;
            if (current_stop.hint) |*hint| {
                hint.* = resolveLength(gradient_line_length, hint.*);
                hint.length = @max(hint.length, current_position);
                last_position = @max(last_position, hint.length);
            }
            last_position_step = i;
        }
    }

    return stops;
}
const GradientLine = struct {
    allocator: std.mem.Allocator,
    line: []const Color,
    pub fn deinit(self: @This()) void {
        self.allocator.free(self.line);
    }
    pub fn at(self: @This(), t: f32) Color {
        const index_f = t * @as(f32, @floatFromInt(self.line.len - 1));
        const index: usize = @intFromFloat(@round(index_f));
        if (index >= self.line.len) {
            return self.line[self.line.len - 1];
        }
        return self.line[index];
    }
};
pub fn renderGradientLine(
    allocator: std.mem.Allocator,
    src_stops: []const ColorStop,
    gradient_line_length: f32,
    comptime premultiplied: bool,
) !GradientLine {
    const stops = try fixUpColorStops(allocator, src_stops, gradient_line_length);
    // try styles.color_stop.dumpColorStops(stops, std.io.getStdErr().writer().any());
    defer allocator.free(stops);
    const line_length_int: usize = @intFromFloat(@round(gradient_line_length));
    const line = try allocator.alloc(Color, line_length_int);
    {
        var j: f32 = 0;
        const first_stop = stops[0].position.?.length;
        const first_stop_color = stops[0].color;
        while (j < first_stop) {
            line[@intFromFloat(@round(j))] = first_stop_color;
            j += 1;
        }
    }
    var i: usize = 1;
    while (i < stops.len) : (i += 1) {
        const current_stop = stops[i];
        const previous_stop = stops[i - 1];
        const current_position = current_stop.position.?.length;
        const current_position_int: usize = @intFromFloat(@round(current_position));
        const previous_position = previous_stop.position.?.length;
        const previous_position_int: usize = @intFromFloat(@round(previous_position));
        if (current_position <= previous_position) {
            continue;
        }
        const current_color = current_stop.color;
        const previous_color = previous_stop.color;
        const distance = current_position_int - previous_position_int;
        const distance_f: f32 = @floatFromInt(distance);
        const interpolator = Color.Interpolator(premultiplied).init(previous_color, current_color);
        if (previous_stop.hint) |hint| {
            // 1. Determine the location of the transition hint as a percentage of the distance between the two color stops, denoted as a number between 0 and 1, where 0 indicates the hint is placed right on the first color stop, and 1 indicates the hint is placed right on the second color stop. Let this percentage be H.
            const H = (hint.length - previous_position) / distance_f;

            // will result in infinity so we short circuit it
            if (H >= 1) {
                for (0..distance) |j| {
                    line[previous_position_int + j] = previous_color;
                }
                continue;
            }
            for (0..distance) |j| {
                // 2. For any given point between the two color stops, determine the point's location as a percentage of the distance between the two color stops, in the same way as the previous step. Let this percentage be P.

                const j_f: f32 = @floatFromInt(j);
                const P: f32 = j_f / (distance_f - 1);

                // 3. Let C, the color weighting at that point, be equal to PlogH(.5).
                const C = std.math.clamp(std.math.pow(f32, P, std.math.log(f32, H, 0.5)), 0, 1);
                // 4. The color at that point is then a linear blend between the colors of the two color stops, blending (1 - C) of the first stop and C of the second stop.
                // std.debug.print("C: {d:} previous_color: {s} current_color: {s} color: {s}\n", .{ C, previous_color, current_color, interpolator.at(C) });
                line[previous_position_int + j] = interpolator.at(C);
            }
        } else {
            for (0..distance) |j| {
                const j_f: f32 = @floatFromInt(j);
                const t: f32 = j_f / (distance_f - 1);
                // std.debug.print("t: {d:} previous_color: {s} current_color: {s} color: {s}\n", .{ t, previous_color, current_color, interpolator.at(t) });
                line[previous_position_int + j] = interpolator.at(t);
            }
        }
    }
    const last_stop = stops[stops.len - 1];
    var last_stop_position = @round(last_stop.position.?.length);
    const last_stop_color = last_stop.color;
    while (last_stop_position < @round(gradient_line_length)) {
        const j: usize = @intFromFloat(@round(last_stop_position));
        line[j] = last_stop_color;
        last_stop_position += 1;
    }
    if (line.len > 0) {
        line[line.len - 1] = last_stop_color;
    }

    return .{
        .allocator = allocator,
        .line = line,
    };
}
// abs(W * sin(A)) + abs(H * cos(A))
const pi_180 = @as(f32, std.math.pi) / 180;
pub fn getGradientLineLength(
    width: f32,
    height: f32,
    angle: f32,
) f32 {
    const adjusted_angle = angle;
    return @abs(width * std.math.sin(adjusted_angle * pi_180)) + @abs(height * std.math.cos(adjusted_angle * pi_180));
}

pub const ComputedGradient = struct {
    gradient_line_length: f32,
    angle: f32,
    size: Point(f32),
    line: GradientLine,

    pub fn init(allocator: std.mem.Allocator, size: Point(f32), angle: f32, stops: []const ColorStop, comptime premultiplied: bool) !@This() {
        const gradient_line_length = getGradientLineLength(size.x, size.y, angle);

        return .{
            .gradient_line_length = gradient_line_length,
            .angle = angle,
            .size = size,
            .line = try renderGradientLine(allocator, stops, gradient_line_length, premultiplied),
        };
    }
    pub fn deinit(self: @This()) void {
        self.line.deinit();
    }
    pub fn at(self: @This(), position: Point(f32)) Color {
        // Get the center of the gradient box
        const center: Point(f32) = .{
            .x = (self.size.x - 1) / 2,
            .y = (self.size.y - 1) / 2,
        };

        // Convert angle to radians
        const angle_rad = (self.angle - 90) * std.math.pi / 180.0;

        // The normal vector to the gradient line
        const normal_x = std.math.cos(angle_rad);
        const normal_y = std.math.sin(angle_rad);

        // Calculate the distance from the center
        const dx = position.x - center.x;
        const dy = position.y - center.y;

        // Project the point onto the gradient line direction
        const projection = dx * normal_x + dy * normal_y;

        // Max projection value (half the distance from edge to edge)
        // For 0-based indexing, this should be (size-1)/2
        const max_projection = (self.size.x - 1) / 2 * @abs(normal_x) +
            (self.size.y - 1) / 2 * @abs(normal_y);

        // Normalize projection to [0, 1]
        const position_on_line = (projection + max_projection) / (2 * max_projection);

        // Clamp the position to [0, 1]
        const clamped_position = @max(0.0, @min(1.0, position_on_line));

        // Convert to index
        const index_f = clamped_position * @as(f32, @floatFromInt(self.line.line.len));
        const index: usize = @intFromFloat(@round(index_f));

        // Safety check
        if (index >= self.line.line.len) {
            return self.line.line[self.line.line.len - 1];
        }

        return self.line.line[index];
    }
};
pub const RadialGradientSampler = struct {
    center: Point(f32),
    line: GradientLine,
    radius: CircleRadius,

    pub fn init(allocator: std.mem.Allocator, size: Point(f32), radial_gradient: styles.radial_gradient.RadialGradient, comptime premultiplied: bool) !@This() {
        const center: Point(f32) = computeCenterPoint(radial_gradient.position, size);

        const radius = switch (radial_gradient.shape) {
            .circle => computeCircleRadius(size, radial_gradient.size, center),
            .ellipse => computeEllipseRadii(size, radial_gradient.size, center),
        };

        const gradient_line_length: f32 = radius.radius;

        return .{
            .center = center,
            .line = try renderGradientLine(
                allocator,
                radial_gradient.color_stops.items,
                gradient_line_length,
                premultiplied,
            ),
            .radius = radius,
        };
    }
    // fn computeRadius(size: Point(f32), radial_gradient: styles.radial_gradient.RadialGradient) Point(f32) {
    //     return switch (radial_gradient.size) {
    //         .extent => |extent| switch (extent) {
    //             .closest_side => radial.circleClosestSide(center, size),
    //         },
    //     };
    // }
    //     static inline float positionFromValue(const NumberOrPercentage<>& coordinate, float widthOrHeight)
    // {
    //     return WTF::switchOn(coordinate,
    //         [&](Number<> number) -> float { return number.value; },
    //         [&](Percentage<> percentage) -> float { return percentage.value / 100.0f * widthOrHeight; }
    //     );
    // }

    /// Resolves a position value (number or percentage) to an absolute value
    fn positionFromValue(coordinate: styles.length_percentage.LengthPercentage, widthOrHeight: f32) f32 {
        return switch (coordinate) {
            .length => |length| length,
            .percentage => |percentage| percentage / 100.0 * widthOrHeight,
        };
    }

    /// Computes the endpoint based on a Position value and size
    fn computeEndPoint(position: styles.radial_gradient.Position, size: Point(f32)) Point(f32) {
        return .{
            .x = positionFromValue(position.x, size.x),
            .y = positionFromValue(position.y, size.y),
        };
    }

    /// Computes the center point for a gradient, using default if position is not provided
    fn computeCenterPoint(position: ?styles.radial_gradient.Position, size: Point(f32)) Point(f32) {
        return if (position) |pos|
            computeEndPoint(pos, size)
        else
            .{ .x = size.x / 2, .y = size.y / 2 };
    }

    //     auto computeCenterPoint = [&](const std::optional<Position>& position) -> FloatPoint {
    //     return position ? computeEndPoint(*position, size) : FloatPoint { size.width() / 2, size.height() / 2 };
    // };

    /// Computes the radius for a circle gradient shape
    /// Returns a tuple with the radius and a scaling factor (1.0 for circles)
    const CircleRadius = struct {
        radius: f32,
        scale: f32,
    };
    fn computeCircleRadius(
        size: Point(f32),
        circleSizeOrExtent: styles.radial_gradient.RadialSize,
        centerPoint: Point(f32),
    ) CircleRadius {
        return switch (circleSizeOrExtent) {
            .length => |length| {
                // For a simple length value, return that length directly with scale factor 1.0
                const resolved = resolveLength(size.x, length);
                return .{ .radius = resolved.length, .scale = 1.0 };
            },
            .lengths => |lengths| {
                // For lengths, use the first dimension as radius since we're dealing with a circle
                const resolved = resolveLength(size.x, lengths.x);
                return .{ .radius = resolved.length, .scale = 1.0 };
            },
            .extent => |extent| {
                return switch (extent) {
                    .closest_side => .{
                        .radius = radial.distanceToClosestSide(centerPoint, size),
                        .scale = 1.0,
                    },
                    .farthest_side => .{
                        .radius = radial.distanceToFarthestSide(centerPoint, size),
                        .scale = 1.0,
                    },
                    .closest_corner => .{
                        .radius = radial.distanceToClosestCorner(centerPoint, size),
                        .scale = 1.0,
                    },
                    .farthest_corner => .{
                        .radius = radial.distanceToFarthestCorner(centerPoint, size),
                        .scale = 1.0,
                    },
                };
            },
        };
    }

    //     auto computeCircleRadius = [&](const std::variant<RadialGradient::Circle::Length, RadialGradient::Extent>& circleLengthOrExtent, FloatPoint centerPoint) -> std::pair<float, float> {
    //         return WTF::switchOn(circleLengthOrExtent,
    //             [&](const RadialGradient::Circle::Length& circleLength) -> std::pair<float, float> {
    //                 return { circleLength.value, 1 };
    //             },
    //             [&](const RadialGradient::Extent& extent) -> std::pair<float, float> {
    //                 return WTF::switchOn(extent,
    //                     [&](CSS::Keyword::ClosestSide) -> std::pair<float, float> {
    //                         return { distanceToClosestSide(centerPoint, size), 1 };
    //                     },
    //                     [&](CSS::Keyword::FarthestSide) -> std::pair<float, float> {
    //                         return { distanceToFarthestSide(centerPoint, size), 1 };
    //                     },
    //                     [&](CSS::Keyword::ClosestCorner) -> std::pair<float, float> {
    //                         return { distanceToClosestCorner(centerPoint, size), 1 };
    //                     },
    //                     [&](CSS::Keyword::FarthestCorner) -> std::pair<float, float> {
    //                         return { distanceToFarthestCorner(centerPoint, size), 1 };
    //                     }
    //                 );
    //             }
    //         );
    //     };

    /// Helper function to calculate the horizontal radius of an ellipse based on a point and aspect ratio
    fn horizontalEllipseRadius(point: Point(f32), aspectRatio: f32) f32 {
        return std.math.hypot(point.x, point.y * aspectRatio);
    }

    /// Computes the ellipse radii for a radial gradient
    /// Returns a struct with x radius and a scaling factor for the y radius
    fn computeEllipseRadii(
        size: Point(f32),
        ellipseSizeOrExtent: styles.radial_gradient.RadialSize,
        centerPoint: Point(f32),
    ) CircleRadius {
        return switch (ellipseSizeOrExtent) {
            .lengths => |lengths| {
                // Get explicit x and y dimensions
                const xDist = resolveLength(size.x, lengths.x).length;
                const yDist = resolveLength(size.y, lengths.y).length;
                return .{ .radius = xDist, .scale = xDist / yDist };
            },
            .length => |length| {
                // Single length value applied to both dimensions
                const resolved = resolveLength(size.x, length).length;
                return .{ .radius = resolved, .scale = 1.0 };
            },
            .extent => |extent| {
                return switch (extent) {
                    .closest_side => {
                        const xDist = @min(centerPoint.x, size.x - centerPoint.x);
                        const yDist = @min(centerPoint.y, size.y - centerPoint.y);
                        return .{ .radius = xDist, .scale = xDist / yDist };
                    },
                    .farthest_side => {
                        const xDist = @max(centerPoint.x, size.x - centerPoint.x);
                        const yDist = @max(centerPoint.y, size.y - centerPoint.y);
                        return .{ .radius = xDist, .scale = xDist / yDist };
                    },
                    .closest_corner => {
                        const distance, const corner = radial.findDistanceToClosestCorner(centerPoint, size);
                        _ = distance; // autofix
                        // std.debug.print("distance: {d:} corner: {any}\n", .{ distance, corner });
                        // If <shape> is ellipse, the gradient-shape has the same ratio of width to height
                        // that it would if closest-side or farthest-side were specified, as appropriate.
                        const xDist = @min(centerPoint.x, size.x - centerPoint.x);
                        const yDist = @min(centerPoint.y, size.y - centerPoint.y);
                        return .{ .radius = horizontalEllipseRadius(corner.sub(centerPoint), xDist / yDist), .scale = xDist / yDist };
                    },
                    .farthest_corner => {
                        const distance, const corner = radial.findDistanceToFarthestCorner(centerPoint, size);
                        _ = distance; // autofix
                        // std.debug.print("distance: {d:} corner: {any}\n", .{ distance, corner });
                        // If <shape> is ellipse, the gradient-shape has the same ratio of width to height
                        // that it would if closest-side or farthest-side were specified, as appropriate.
                        const xDist = @max(centerPoint.x, size.x - centerPoint.x);
                        const yDist = @max(centerPoint.y, size.y - centerPoint.y);
                        return .{ .radius = horizontalEllipseRadius(corner.sub(centerPoint), xDist / yDist), .scale = xDist / yDist };
                    },
                };
            },
        };
    }

    pub fn deinit(self: @This()) void {
        self.line.deinit();
    }
    pub fn at(self: @This(), position: Point(f32)) Color {
        // Calculate the distance from the center point to the current position
        const dx = position.x - self.center.x;
        const dy = (position.y - self.center.y) * self.radius.scale;

        // Calculate the Euclidean distance (scaled for ellipse if needed)
        const distance = std.math.sqrt(dx * dx + dy * dy);

        // Normalize the distance by the radius to get a value between 0 and 1
        // where 0 is at the center and 1 is at the edge of the circle/ellipse
        const normalized_distance = distance / self.radius.radius;
        return self.line.at(normalized_distance);

        // If we're within the gradient's radius, sample the color from the gradient line
        // if (normalized_distance <= 1.0) {
        //     const index_f = normalized_distance * @as(f32, @floatFromInt(self.line.line.len - 1));
        //     const index: usize = @intFromFloat(@min(index_f, @as(f32, @floatFromInt(self.line.line.len - 1))));
        //     return self.line.line[index];
        // }

        // const rainbow = [10]Color{
        //     Color.tw.red_400,
        //     Color.tw.orange_400,
        //     Color.tw.yellow_400,
        //     Color.tw.green_400,
        //     Color.tw.blue_400,
        //     Color.tw.indigo_400,
        //     Color.tw.purple_400,
        //     Color.tw.pink_400,
        //     Color.tw.red_400,
        //     Color.tw.orange_400,
        // };
        // if (normalized_distance > 1.0) {
        //     return Color.tw.amber_200;
        // }
        // inline for (rainbow, 0..) |color, i| {
        //     if (normalized_distance <= @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rainbow.len))) {
        //         return color;
        //     }
        // }
        // return Color.tw.white;
        // const index: usize = @intFromFloat(@round(normalized_distance * @as(f32, @floatFromInt(rainbow.len))));
        // if (index > rainbow.len) {
        //     return Color.tw.pink_400;
        // }
        // const color = self.line.line[@min(index, self.line.line.len - 1)];

        // return color;
    }
};

pub const radial = struct {
    pub fn distanceToClosestSide(p: Point(f32), size: Point(f32)) f32 {
        const widthDelta = @abs(size.x - p.x);
        const heightDelta = @abs(size.y - p.y);
        return @min(widthDelta, heightDelta);
    }
    pub fn distanceToFarthestSide(p: Point(f32), size: Point(f32)) f32 {
        const widthDelta = @abs(size.x - p.x);
        const heightDelta = @abs(size.y - p.y);
        return @max(widthDelta, heightDelta);
    }

    pub fn distanceToClosestCorner(p: Point(f32), size: Point(f32)) f32 {
        const topLeft = Point(f32){ .x = 0, .y = 0 };
        const topLeftDistance = std.math.hypot(p.x - topLeft.x, p.y - topLeft.y);

        const topRight = Point(f32){ .x = size.x, .y = 0 };
        const topRightDistance = std.math.hypot(p.x - topRight.x, p.y - topRight.y);

        const bottomLeft = Point(f32){ .x = 0, .y = size.y };
        const bottomLeftDistance = std.math.hypot(p.x - bottomLeft.x, p.y - bottomLeft.y);

        const bottomRight = Point(f32){ .x = size.x, .y = size.y };
        const bottomRightDistance = std.math.hypot(p.x - bottomRight.x, p.y - bottomRight.y);

        return std.mem.min(f32, &[4]f32{ topLeftDistance, topRightDistance, bottomLeftDistance, bottomRightDistance });
    }

    pub fn distanceToFarthestCorner(p: Point(f32), size: Point(f32)) f32 {
        const topLeft = Point(f32){ .x = 0, .y = 0 };
        const topLeftDistance = std.math.hypot(p.x - topLeft.x, p.y - topLeft.y);

        const topRight = Point(f32){ .x = size.x, .y = 0 };
        const topRightDistance = std.math.hypot(p.x - topRight.x, p.y - topRight.y);

        const bottomLeft = Point(f32){ .x = 0, .y = size.y };
        const bottomLeftDistance = std.math.hypot(p.x - bottomLeft.x, p.y - bottomLeft.y);

        const bottomRight = Point(f32){ .x = size.x, .y = size.y };
        const bottomRightDistance = std.math.hypot(p.x - bottomRight.x, p.y - bottomRight.y);

        return std.mem.max(f32, &[4]f32{ topLeftDistance, topRightDistance, bottomLeftDistance, bottomRightDistance });
    }

    pub fn findDistanceToFarthestCorner(p: Point(f32), size: Point(f32)) struct { f32, Point(f32) } {
        const topLeft = Point(f32){ .x = 0, .y = 0 };
        const topLeftDistance = std.math.hypot(p.x - topLeft.x, p.y - topLeft.y);

        const topRight = Point(f32){ .x = size.x, .y = 0 };
        const topRightDistance = std.math.hypot(p.x - topRight.x, p.y - topRight.y);

        const bottomLeft = Point(f32){ .x = 0, .y = size.y };
        const bottomLeftDistance = std.math.hypot(p.x - bottomLeft.x, p.y - bottomLeft.y);

        const bottomRight = Point(f32){ .x = size.x, .y = size.y };
        const bottomRightDistance = std.math.hypot(p.x - bottomRight.x, p.y - bottomRight.y);

        var corner = topLeft;
        var maxDistance = topLeftDistance;

        if (topRightDistance > maxDistance) {
            maxDistance = topRightDistance;
            corner = topRight;
        }

        if (bottomLeftDistance > maxDistance) {
            maxDistance = bottomLeftDistance;
            corner = bottomLeft;
        }

        if (bottomRightDistance > maxDistance) {
            maxDistance = bottomRightDistance;
            corner = bottomRight;
        }

        return .{ maxDistance, corner };
    }
    pub fn findDistanceToClosestCorner(p: Point(f32), size: Point(f32)) struct { f32, Point(f32) } {
        const topLeft = Point(f32){ .x = 0, .y = 0 };
        const topLeftDistance = std.math.hypot(p.x - topLeft.x, p.y - topLeft.y);

        const topRight = Point(f32){ .x = size.x, .y = 0 };
        const topRightDistance = std.math.hypot(p.x - topRight.x, p.y - topRight.y);

        const bottomLeft = Point(f32){ .x = 0, .y = size.y };
        const bottomLeftDistance = std.math.hypot(p.x - bottomLeft.x, p.y - bottomLeft.y);

        const bottomRight = Point(f32){ .x = size.x, .y = size.y };
        const bottomRightDistance = std.math.hypot(p.x - bottomRight.x, p.y - bottomRight.y);

        var corner = topLeft;
        var minDistance = topLeftDistance;

        if (topRightDistance < minDistance) {
            minDistance = topRightDistance;
            corner = topRight;
        }

        if (bottomLeftDistance < minDistance) {
            minDistance = bottomLeftDistance;
            corner = bottomLeft;
        }

        if (bottomRightDistance < minDistance) {
            minDistance = bottomRightDistance;
            corner = bottomRight;
        }

        return .{ minDistance, corner };
    }

    // pub fn circleClosestSide(center: Point(f32), size: Point(f32)) f32 {
    //     return @min(center.x, size.x - center.x, center.y, size.y - center.y);
    // }

    // pub fn circleFarthestSide(center: Point(f32), size: Point(f32)) f32 {
    //     return @max(center.x, size.x - center.x, center.y, size.y - center.y);
    // }

    // pub fn circleCornerDistances(center: Point(f32), size: Point(f32)) [4]f32 {
    //     return .{
    //         std.math.hypot(center.x, center.y),
    //         std.math.hypot(size.x - center.x, center.y),
    //         std.math.hypot(center.x, size.y - center.y),
    //         std.math.hypot(size.x - center.x, size.y - center.y),
    //     };
    // }
    // pub fn circleClosestCorner(center: Point(f32), size: Point(f32)) f32 {
    //     const distances = circleCornerDistances(center, size);
    //     return std.mem.min(f32, &distances);
    // }

    // pub fn circleFarthestCorner(center: Point(f32), size: Point(f32)) f32 {
    //     const distances = circleCornerDistances(center, size);
    //     return std.mem.max(f32, &distances);
    // }

    // pub fn ellipseRadiiClosestCorner(center: Point(f32), size: Point(f32)) Point(f32) {
    //     // closest-side radii:
    //     const rx_cs = @min(center.x, size.x - center.x);
    //     const ry_cs = @min(center.y, size.y - center.y);
    //     const k = if (ry_cs != 0) rx_cs / ry_cs else 1;

    //     // Choose the nearest corner
    //     const corners = [4]Point(f32){
    //         .{ .x = center.x, .y = center.y },
    //         .{ .x = size.x - center.x, .y = center.y },
    //         .{ .x = center.x, .y = size.y - center.y },
    //         .{ .x = size.x - center.x, .y = size.y - center.y },
    //     };

    //     var best_rx: f32 = std.math.floatMax(f32);
    //     var best_ry: f32 = std.math.floatMax(f32);
    //     var best_r: f32 = std.math.floatMax(f32);
    //     for (corners) |corner| {
    //         const d_x = corner.x;
    //         const d_y = corner.y;
    //         const r_y = std.math.sqrt((std.math.pow(f32, d_x, 2)) / (std.math.pow(f32, k, 2)) + std.math.pow(f32, d_y, 2));
    //         const r_x = k * r_y;
    //         const r = std.math.sqrt(std.math.pow(f32, r_x, 2) + std.math.pow(f32, r_y, 2));
    //         if (r < best_r) {
    //             best_r = r;
    //             best_rx = r_x;
    //             best_ry = r_y;
    //         }
    //     }
    //     return .{ .x = best_rx, .y = best_ry };
    // }

    // pub fn ellipseRadiiFarthestCorner(center: Point(f32), size: Point(f32)) Point(f32) {
    //     // closest-side radii:
    //     const rx_cs = @min(center.x, size.x - center.x);
    //     const ry_cs = @min(center.y, size.y - center.y);
    //     const k = if (ry_cs != 0) rx_cs / ry_cs else 1;

    //     // Choose the farthest corner
    //     const corners = [4]Point(f32){
    //         .{ .x = center.x, .y = center.y },
    //         .{ .x = size.x - center.x, .y = center.y },
    //         .{ .x = center.x, .y = size.y - center.y },
    //         .{ .x = size.x - center.x, .y = size.y - center.y },
    //     };

    //     var best_rx: f32 = 0;
    //     var best_ry: f32 = 0;
    //     var best_r: f32 = 0;
    //     for (corners) |corner| {
    //         const d_x = corner.x;
    //         const d_y = corner.y;
    //         const r_y = std.math.sqrt((std.math.pow(f32, d_x, 2)) / (std.math.pow(f32, k, 2)) + std.math.pow(f32, d_y, 2));
    //         const r_x = k * r_y;
    //         const r = std.math.sqrt(std.math.pow(f32, r_x, 2) + std.math.pow(f32, r_y, 2));
    //         if (r > best_r) {
    //             best_r = r;
    //             best_rx = r_x;
    //             best_ry = r_y;
    //         }
    //     }
    //     return .{ .x = best_rx, .y = best_ry };
    // }
    // pub fn ellipseRadiiFarthestSide(center: Point(f32), size: Point(f32)) Point(f32) {
    //     // farthest-side radii:
    //     const rx_fs = @max(center.x, size.x - center.x);
    //     const ry_fs = @max(center.y, size.y - center.y);
    //     // const k = if (ry_fs != 0) rx_fs / ry_fs else 1;
    //     return .{ .x = rx_fs, .y = ry_fs };
    // }
    // pub fn ellipseRadiiClosestSide(center: Point(f32), size: Point(f32)) Point(f32) {
    //     // closest-side radii:
    //     const rx_cs = @min(center.x, size.x - center.x);
    //     const ry_cs = @min(center.y, size.y - center.y);
    //     // const k = if (ry_cs != 0) rx_cs / ry_cs else 1;
    //     return .{ .x = rx_cs, .y = ry_cs };
    // }
};
pub const Sampler = struct {
    sampler: union(enum) {
        solid: Color,
        linear: ComputedGradient,
        radial: RadialGradientSampler,
    },
    pub fn from(allocator: std.mem.Allocator, color: styles.background.Background, size: Point(f32)) !Sampler {
        switch (color) {
            .solid => |c| return Sampler{ .sampler = .{ .solid = c } },
            .linear_gradient => |gradient| return Sampler{ .sampler = .{ .linear = try ComputedGradient.init(
                allocator,
                size,
                gradient.angle,
                gradient.color_stops.items,
                true,
            ) } },
            .radial_gradient => |gradient| return Sampler{ .sampler = .{ .radial = try RadialGradientSampler.init(
                allocator,
                size,
                gradient,
                true,
            ) } },
        }
    }
    pub fn deinit(self: Sampler) void {
        switch (self.sampler) {
            .linear => self.sampler.linear.deinit(),
            .radial => self.sampler.radial.deinit(),
            .solid => {},
        }
    }

    pub fn at(self: Sampler, point: Point(f32)) Color {
        switch (self.sampler) {
            .solid => return self.sampler.solid,
            .linear => return self.sampler.linear.at(point),
            .radial => return self.sampler.radial.at(point),
        }
    }
};
