const std = @import("std");
const css_types = @import("../../css/types.zig");
const math = @import("math.zig");
const mod = @import("mod.zig");
const CSSPoint = mod.CSSPoint;
const Line = mod.Line;

pub const AvailableSpace = union(enum) {
    definite: f32,
    min_content: void,
    max_content: void,
    pub fn format(self: AvailableSpace, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .min_content => try writer.print("min_content", .{}),
            .max_content => try writer.print("max_content", .{}),
            .definite => try writer.print("definite: {d}", .{self.definite}),
        }
    }

    pub fn from(f: f32) AvailableSpace {
        return .{ .definite = f };
    }

    pub fn intoOption(self: AvailableSpace) ?f32 {
        switch (self) {
            .definite => return self.definite,
            else => return null,
        }
    }
    pub fn maybeAddIfDefinite(self: AvailableSpace, other: anytype) AvailableSpace {
        switch (self) {
            .definite => |v| return .{ .definite = math.maybeAdd(v, other) orelse v },
            else => return self,
        }
    }

    pub fn maybeSubtractIfDefinite(self: AvailableSpace, other: anytype) AvailableSpace {
        switch (self) {
            .definite => |v| return .{ .definite = math.maybeSub(v, other) orelse v },
            else => return self,
        }
    }

    pub fn maybeClamp(self: AvailableSpace, min: anytype, max: anytype) AvailableSpace {
        switch (self) {
            .definite => |v| return .{ .definite = math.maybeClamp(v, min, max).? },
            else => return self,
        }
    }

    pub fn maybeMax(self: AvailableSpace, other: anytype) AvailableSpace {
        switch (self) {
            .definite => |v| return .{ .definite = math.maybeMax(v, other).? },
            else => return self,
        }
    }
    pub fn maybeMin(self: AvailableSpace, other: anytype) AvailableSpace {
        switch (self) {
            .definite => |v| return .{ .definite = math.maybeMin(v, other.?) },
            else => return self,
        }
    }

    pub fn maybeSet(self: AvailableSpace, other: anytype) AvailableSpace {
        if (other) |v| {
            return .{ .definite = v };
        } else return self;
    }
    pub fn set(other: f32) AvailableSpace {
        return .{ .definite = other };
    }

    pub fn fromPoint(point: anytype) mod.PointOf(AvailableSpace) {
        if (@TypeOf(point) == CSSPoint) {
            return .{
                .x = .{ .definite = point.x },
                .y = .{ .definite = point.y },
            };
        }
        return .{
            .x = if (point.x) |v| .{ .definite = v } else .max_content,
            .y = if (point.y) |v| .{ .definite = v } else .max_content,
        };
    }

    pub fn isRoughlyEqual(self: AvailableSpace, other: AvailableSpace) bool {
        switch (self) {
            .definite => |a| {
                switch (other) {
                    .definite => |b| return @abs(a - b) < std.math.floatEps(f32),
                    else => return false,
                }
            },
            else => return @intFromEnum(self) == @intFromEnum(other),
        }
    }
    pub const MAX_CONTENT: AvailableSpacePoint = .{ .x = .max_content, .y = .max_content };
    pub const MIN_CONTENT: AvailableSpacePoint = .{ .x = .min_content, .y = .min_content };
};
pub const AvailableSpacePoint = mod.PointOf(AvailableSpace);
pub const RunMode = enum {
    /// A full layout for this node and all children should be computed
    perform_layout,
    /// The layout algorithm should be executed such that an accurate container size for the node can be determined.
    /// Layout steps that aren't necessary for determining the container size of the current node can be skipped.
    compute_size,
    /// This node should have a null layout set as it has been hidden (i.e. using `Display::None`)
    perform_hidden_layout,
    pub fn format(self: RunMode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(".{s}", .{@tagName(self)});
    }
};

/// Whether styles should be taken into account when computing size
pub const SizingMode = enum {
    /// Only content contributions should be taken into account
    content_size,
    /// Inherent size styles should be taken into account in addition to content contributions
    inherent_size,
    pub fn format(self: SizingMode, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(".{s}", .{@tagName(self)});
    }
};

/// A set of margins that are available for collapsing with for block layout's margin collapsing
pub const CollapsibleMarginSet = struct {
    /// The largest positive margin
    positive: f32,
    /// The smallest negative margin (with largest absolute value)
    negative: f32,
    pub const ZERO = CollapsibleMarginSet{ .positive = 0.0, .negative = 0.0 };

    pub fn format(self: CollapsibleMarginSet, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
        _ = fmt;
        _ = options;
        try writer.print("CollapsibleMarginSet(positive: {d:.2}, negative: {d:.2})", .{ self.positive, self.negative });
    }

    /// Create a set from a single margin
    pub fn fromMargin(margin: f32) CollapsibleMarginSet {
        if (margin >= 0.0) {
            return .{ .positive = margin, .negative = 0.0 };
        } else {
            return .{ .positive = 0.0, .negative = margin };
        }
    }
    /// Collapse a single margin with this set
    pub fn collapseWithMargin(self: CollapsibleMarginSet, margin: f32) CollapsibleMarginSet {
        if (margin >= 0.0) {
            return .{ .positive = @max(self.positive, margin), .negative = self.negative };
        } else {
            return .{ .positive = self.positive, .negative = @max(self.negative, margin) };
        }
    }

    pub fn collapseWithSet(self: CollapsibleMarginSet, other: CollapsibleMarginSet) CollapsibleMarginSet {
        return .{
            .positive = @max(self.positive, other.positive),
            .negative = @min(self.negative, other.negative),
        };
    }

    pub fn resolve(self: CollapsibleMarginSet) f32 {
        return self.positive + self.negative;
    }
};

/// An axis that layout algorithms can be requested to compute a size for
pub const RequestedAxis = enum {
    /// The horizontal axis
    horizontal,
    /// The vertical axis
    vertical,
    /// Both axes
    both,
    pub fn format(self: RequestedAxis, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(".{s}", .{@tagName(self)});
    }
};

pub const AbsoluteAxis = enum {
    horizontal,
    vertical,
    pub fn format(self: AbsoluteAxis, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(".{s}", .{@tagName(self)});
    }
    pub fn otherAxis(self: AbsoluteAxis) AbsoluteAxis {
        switch (self) {
            .horizontal => return .vertical,
            .vertical => return .horizontal,
        }
    }
    pub fn toRequestedAxis(self: AbsoluteAxis) RequestedAxis {
        switch (self) {
            .horizontal => return RequestedAxis.horizontal,
            .vertical => return RequestedAxis.vertical,
        }
    }
    /// Returns the other variant of the enum
    /// @param self {AbsoluteAxis} The enum variant
    /// @param point {Point(type)} The point to get the axis from
    pub fn getAxis(self: AbsoluteAxis, point: anytype) @TypeOf(point.x) {
        switch (self) {
            .horizontal => return point.x,
            .vertical => return point.y,
        }
    }
    pub fn fromFlexDirection(direction: css_types.FlexDirection) AbsoluteAxis {
        switch (direction) {
            .row => return .horizontal,
            .row_reverse => return .horizontal,
            .column => return .vertical,
            .column_reverse => return .vertical,
        }
    }
};

/// A struct containing the inputs constraints/hints for laying out a node, which are passed in by the parent
pub const LayoutInput = struct {
    /// Whether we only need to know the Node's size, or whe
    run_mode: RunMode,
    /// Whether a Node's style sizes should be taken into account or ignored
    sizing_mode: SizingMode,
    /// Which axis we need the size of
    axis: RequestedAxis,

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
    /// for the purpose of wrapping.
    available_space: AvailableSpacePoint,
    /// Specific to CSS Block layout. Used for correctly computing margin collapsing. You probably want to set this to `Line::FALSE`.
    vertical_margins_are_collapsible: Line(bool),
    pub fn format(self: LayoutInput, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.io.AnyWriter) !void {
        _ = fmt;
        _ = options;
        try writer.print("LayoutInput(run_mode: {any}, sizing_mode: {any}, axis: {any}, known_dimensions: {any}, parent_size: {any}, available_space: {any}, vertical_margins_are_collapsible: {any})", .{ self.run_mode, self.sizing_mode, self.axis, self.known_dimensions, self.parent_size, self.available_space, self.vertical_margins_are_collapsible });
    }
};
/// A struct containing the result of laying a single node, which is returned up to the parent node
///
/// A baseline is the line on which text sits. Your node likely has a baseline if it is a text node, or contains
/// children that may be text nodes. See <https://www.w3.org/TR/css-writing-modes-3/#intro-baselines> for details.
/// If your node does not have a baseline (or you are unsure how to compute it), then simply return `Point::NONE`
/// for the first_baselines field
pub const LayoutOutput = struct {
    /// The size of the node
    size: CSSPoint = .{ .x = 0, .y = 0 },
    /// The size of the content within the node
    content_size: CSSPoint = .{ .x = 0, .y = 0 },
    /// The first baseline of the node in each dimension, if any
    first_baselines: mod.CSSMaybePoint = .{ .x = null, .y = null },
    /// Top margin that can be collapsed with. This is used for CSS block layout and can be set to
    /// `CollapsibleMarginSet::ZERO` for other layout modes that don't support margin collapsing
    top_margin: CollapsibleMarginSet = .{ .positive = 0, .negative = 0 },
    /// Bottom margin that can be collapsed with. This is used for CSS block layout and can be set to
    /// `CollapsibleMarginSet::ZERO` for other layout modes that don't support margin collapsing
    bottom_margin: CollapsibleMarginSet = .{ .positive = 0, .negative = 0 },
    /// Whether margins can be collapsed through this node. This is used for CSS block layout and can
    /// be set to `false` for other layout modes that don't support margin collapsing
    margins_can_collapse_through: bool = false,

    /// An all-zero `LayoutOutput` for hidden nodes
    pub const HIDDEN = LayoutOutput{
        .size = CSSPoint.ZERO,
        .content_size = CSSPoint.ZERO,
        .first_baselines = mod.CSSMaybePoint.NULL,
        .top_margin = .{ .positive = 0, .negative = 0 },
        .bottom_margin = .{ .positive = 0, .negative = 0 },
        .margins_can_collapse_through = false,
    };
};
