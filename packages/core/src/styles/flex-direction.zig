const std = @import("std");
const utils = @import("utils.zig");
const Point = @import("../layout/point.zig").Point;
const Rect = @import("../layout/rect.zig").Rect;

const MemberType = @import("../layout/utils/comptime.zig").MemberType;
pub const FlexDirection = enum {
    /// Defines +x as the main axis
    ///
    /// Items will be added from left to right in a row.
    row,
    /// Defines +y as the main axis
    ///
    /// Items will be added from top to bottom in a column.
    column,
    /// Defines -x as the main axis
    ///
    /// Items will be added from right to left in a row.
    row_reverse,
    /// Defines -y as the main axis
    ///
    /// Items will be added from bottom to top in a column.
    column_reverse,

    pub const default = FlexDirection.row;

    pub fn isRow(self: FlexDirection) bool {
        return self == FlexDirection.row or self == FlexDirection.row_reverse;
    }
    pub fn isColumn(self: FlexDirection) bool {
        return self == FlexDirection.column or self == FlexDirection.column_reverse;
    }

    pub fn getCross(self: FlexDirection, point: anytype) MemberType(@TypeOf(point)) {
        if (self.isRow()) {
            return point.y;
        } else {
            return point.x;
        }
    }
    pub fn getCrossStart(self: FlexDirection, T: type, rect: Rect(T)) T {
        if (self.isRow()) {
            return rect.top;
        } else {
            return rect.left;
        }
    }

    // pub fn getCrossStart(self: FlexDirection, rect: anytype) MemberType(@TypeOf(rect)) {
    //     if (self.isRow()) {
    //         return rect.top;
    //     } else {
    //         return rect.left;
    //     }
    // }

    pub fn getCrossEnd(self: FlexDirection, T: type, rect: Rect(T)) T {
        if (self.isRow()) {
            return rect.bottom;
        } else {
            return rect.right;
        }
    }
    pub fn getMain(self: FlexDirection, point: anytype) MemberType(@TypeOf(point)) {
        if (self.isRow()) {
            return point.x;
        } else {
            return point.y;
        }
    }

    pub fn getMainStart(self: FlexDirection, rect: anytype) MemberType(@TypeOf(rect)) {
        if (self.isRow()) {
            return rect.left;
        } else {
            return rect.top;
        }
    }

    pub fn getMainEnd(self: FlexDirection, rect: anytype) MemberType(@TypeOf(rect)) {
        if (self.isRow()) {
            return rect.right;
        } else {
            return rect.bottom;
        }
    }

    pub fn setCross(self: FlexDirection, point: anytype, value: anytype) @TypeOf(point) {
        if (self.isRow()) {
            return .{ .x = point.x, .y = value };
        } else {
            return .{ .x = value, .y = point.y };
        }
    }

    pub fn setMain(self: FlexDirection, point: anytype, value: anytype) @TypeOf(point) {
        if (self.isRow()) {
            return .{ .x = value, .y = point.y };
        } else {
            return .{ .x = point.x, .y = value };
        }
    }
    pub fn pointFromCross(self: FlexDirection, value: anytype) Point(@TypeOf(value)) {
        if (self.isRow()) {
            return .{ .x = null, .y = value };
        } else {
            return .{ .x = value, .y = null };
        }
    }
    pub fn sumCrossAxis(self: FlexDirection, value: anytype) MemberType(@TypeOf(value)) {
        if (self.isRow()) {
            return value.sumVertical();
        } else {
            return value.sumHorizontal();
        }
    }

    pub fn sumMainAxis(self: FlexDirection, value: anytype) MemberType(@TypeOf(value)) {
        if (self.isColumn()) {
            return value.sumVertical();
        } else {
            return value.sumHorizontal();
        }
    }

    pub fn isReverse(self: FlexDirection) bool {
        return self == FlexDirection.row_reverse or self == FlexDirection.column_reverse;
    }
};

pub fn parse(src: []const u8, pos: usize) !utils.Result(FlexDirection) {
    return utils.parseEnum(FlexDirection, src, pos) orelse error.InvalidSyntax;
}
