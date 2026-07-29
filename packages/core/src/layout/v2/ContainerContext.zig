const mod = @import("mod.zig");
const LayoutContext = mod.LayoutContext;
const LayoutNode = mod.LayoutNode;
const std = @import("std");

const math = @import("math.zig");

available_space: mod.constants.AvailableSpacePoint,

/// Whether we only need to know the Node's size, or whe
run_mode: RunMode,
/// Whether a Node's style sizes should be taken into account or ignored
sizing_mode: mod.constants.SizingMode,
/// Which axis we need the size of
axis: mod.constants.RequestedAxis,

/// Known dimensions represent dimensions (width/height) which should be taken as fixed when performing layout.
/// For example, if known_dimensions.width is set to Some(WIDTH) then this means something like:
///
///    "What would the height of this node be, assuming the width is WIDTH"
///
/// Layout functions will be called with both known_dimensions set for final layout. Where the meaning is:
///
///   "The exact size of this node is WIDTHxHEIGHT. Please lay out your children"
///
known_dimensions: mod.CSSMaybePoint,
/// Parent size dimensions are intended to be used for percentage resolution.
parent_size: mod.CSSMaybePoint,
/// Available space represents an amount of space to layout into, and is used as a soft constraint
/// Specific to CSS Block layout. Used for correctly computing margin collapsing. You probably want to set this to `Line::FALSE`.
vertical_margins_are_collapsible: mod.Line(bool),

// pub const AvailableSpace = union(enum) {
//     definite: f32,
//     min_content: void,
//     max_content: void,

//     pub fn from(f: f32) AvailableSpace {
//         return .{ .definite = f };
//     }

//     pub fn intoOption(self: AvailableSpace) ?f32 {
//         switch (self) {
//             .definite => return self.definite,
//             else => return null,
//         }
//     }
//     pub fn maybeAddIfDefinite(self: AvailableSpace, other: anytype) AvailableSpace {
//         switch (self) {
//             .definite => |v| return .{ .definite = math.maybeAdd(v, other) },
//             else => return self,
//         }
//     }

//     pub fn maybeSubtractIfDefinite(self: AvailableSpace, other: anytype) AvailableSpace {
//         switch (self) {
//             .definite => |v| return .{ .definite = math.maybeSub(v, other) },
//             else => return self,
//         }
//     }

//     pub fn maybeClamp(self: AvailableSpace, min: anytype, max: anytype) AvailableSpace {
//         switch (self) {
//             .definite => |v| return .{ .definite = math.maybeClamp(v, min, max) },
//             else => return self,
//         }
//     }

//     pub fn maybeMax(self: AvailableSpace, other: anytype) AvailableSpace {
//         switch (self) {
//             .definite => |v| return .{ .definite = math.maybeMax(v, other) },
//             else => return self,
//         }
//     }
//     pub fn maybeMin(self: AvailableSpace, other: anytype) AvailableSpace {
//         switch (self) {
//             .definite => |v| return .{ .definite = math.maybeMin(v, other) },
//             else => return self,
//         }
//     }

//     pub fn maybeSet(self: AvailableSpace, other: anytype) AvailableSpace {
//         if (other) |v| {
//             return .{ .definite = v };
//         } else return self;
//     }
//     pub fn set(other: f32) AvailableSpace {
//         return .{ .definite = other };
//     }

//     pub fn fromPoint(point: anytype) mod.PointOf(AvailableSpace) {
//         if (@TypeOf(point) == mod.CSSPoint) {
//             return .{
//                 .x = .{ .definite = point.x },
//                 .y = .{ .definite = point.y },
//             };
//         }
//         return .{
//             .x = if (point.x) |v| .{ .definite = v } else .max_content,
//             .y = if (point.y) |v| .{ .definite = v } else .max_content,
//         };
//     }

//     pub fn isRoughlyEqual(self: AvailableSpace, other: AvailableSpace) bool {
//         switch (self) {
//             .definite => |a| {
//                 switch (other) {
//                     .definite => |b| return @abs(a - b) < std.math.floatEps(f32),
//                     else => return false,
//                 }
//             },
//             else => return @intFromEnum(self) == @intFromEnum(other),
//         }
//     }
//     pub const MAX_CONTENT: AvailableSpace = .{ .x = .max_content, .y = .max_content };
//     pub const MIN_CONTENT: AvailableSpace = .{ .x = .min_content, .y = .min_content };
// };
// pub const AvailableSpacePoint = mod.PointOf(AvailableSpace);
pub const RunMode = enum {
    /// A full layout for this node and all children should be computed
    perform_layout,
    /// The layout algorithm should be executed such that an accurate container size for the node can be determined.
    /// Layout steps that aren't necessary for determining the container size of the current node can be skipped.
    compute_size,
};

// pub const SizingMode = enum {
//     /// Only content contributions should be taken into account
//     content_size,
//     /// Inherent size styles should be taken into account in addition to content contributions
//     inherent_size,
// };

pub const RequestedAxis = enum {
    /// The horizontal axis
    horizontal,
    /// The vertical axis
    vertical,
    /// Both axes
    both,
};

pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
    _ = fmt; // autofix
    _ = options; // autofix
    try writer.print("ContainerContext {{\n", .{});
    try writer.print("  available_space: {any},\n", .{self.available_space});
    try writer.print("  run_mode: {any},\n", .{self.run_mode});
    try writer.print("  sizing_mode: {any},\n", .{self.sizing_mode});
    try writer.print("  axis: {any},\n", .{self.axis});
    try writer.print("  known_dimensions: {any},\n", .{self.known_dimensions});
    try writer.print("  parent_size: {any},\n", .{self.parent_size});
    try writer.print("  vertical_margins_are_collapsible: {any},\n", .{self.vertical_margins_are_collapsible});
    try writer.print("}}\n", .{});
}
