const std = @import("std");
const Rect = @import("../layout/rect.zig").Rect;
const Point = @import("../layout/point.zig").Point;
pub const ParseError = error{
    InvalidSyntax,
    Overflow,
};
pub const Range = struct {
    start: usize,
    end: usize,
    value: []const u8,
    pub fn init(src: []const u8, start: usize, end: usize) Range {
        return .{
            .start = start,
            .end = end,
            .value = src[start..end],
        };
    }
    pub fn empty(self: Range) bool {
        return self.start == self.end;
    }
    pub fn match(self: Range, src: []const u8) bool {
        return std.mem.eql(u8, self.value, src);
    }
};

pub fn eatWhitespace(src: []const u8, pos: usize) usize {
    var end = pos;
    while (end < src.len and std.ascii.isWhitespace(src[end])) {
        end += 1;
    }
    return end;
}
pub fn consumeIdentifier(src: []const u8, pos: usize) Range {
    var end = pos;
    while (end < src.len and (std.ascii.isAlphanumeric(src[end]) or
        src[end] == '-' or
        src[end] == '_'))
    {
        end += 1;
    }
    return Range.init(src, pos, end);
}
pub fn matchIdentifier(src: []const u8, ident: []const u8, pos: usize) ?Range {
    const identifier = consumeIdentifier(src, pos);
    if (identifier.match(ident)) {
        return identifier;
    }
    return null;
}
pub fn consumeFnCall(src: []const u8, pos: usize) Range {
    const identifier = consumeIdentifier(src, pos);

    if (identifier.empty()) {
        return Range.init(src, pos, pos);
    }
    const end = consumeChar(src, '(', identifier.end) orelse return Range.init(src, pos, pos);
    return Range.init(src, pos, end);
}
pub fn consumeChar(src: []const u8, char: u8, pos: usize) ?usize {
    const end = pos;
    if (end < src.len and src[end] == char) {
        return end + 1;
    }
    return null;
}

pub fn nextIs(src: []const u8, pos: usize, char: u8) bool {
    const end = pos;
    if (end < src.len and src[end] == char) {
        return true;
    }
    return false;
}
pub fn nextIsDigitish(src: []const u8, pos: usize) bool {
    const end = pos;
    if (end < src.len and (std.ascii.isDigit(src[end]) or src[end] == '-' or src[end] == '+')) {
        return true;
    }
    return false;
}
pub fn isEop(src: []const u8, pos: usize) bool {
    const rest = src[pos..];
    for (rest) |c| {
        if (!std.ascii.isWhitespace(c)) {
            return false;
        }
    }
    return true;
}

const NumberWithUnit = struct {
    value: Range,
    unit: Range,
};
pub fn eatNumberWithUnit(src: []const u8, pos: usize) !NumberWithUnit {
    var number_end = pos;
    if (src[number_end] == '-' or src[number_end] == '+') {
        number_end += 1;
    }
    while (number_end < src.len and (std.ascii.isDigit(src[number_end]) or src[number_end] == '.')) {
        number_end += 1;
    }
    const number_range = Range.init(src, pos, number_end);
    var unit_end = number_end;
    while (unit_end < src.len and (std.ascii.isAlphabetic(src[unit_end]) or src[unit_end] == '%')) {
        unit_end += 1;
    }
    const unit_range = Range.init(src, number_end, unit_end);
    return NumberWithUnit{ .value = number_range, .unit = unit_range };
}

pub fn parseNumber(src: []const u8, pos: usize) !Range {
    const number_with_unit = try eatNumberWithUnit(src, pos);
    if (number_with_unit.unit.empty()) {
        return number_with_unit.value;
    }
    return error.InvalidSyntax;
}

pub fn parseEnum(T: type, src: []const u8, pos: usize) ?Result(T) {
    const identifier = consumeIdentifier(src, pos);
    if (identifier.empty()) {
        return null;
    }
    inline for (comptime std.meta.fieldNames(T)) |field_name| {
        const kebab_case_name = comptime comptimeKebabCase(field_name);
        if (std.mem.eql(u8, identifier.value, &kebab_case_name)) {
            return .{
                .value = @field(T, field_name),
                .start = identifier.start,
                .end = identifier.end,
            };
        }
    }
    return null;
}
fn comptimeKebabCase(comptime str: []const u8) [str.len]u8 {
    @setEvalBranchQuota(10000);
    comptime {
        var out: [str.len * 2]u8 = undefined;
        var len: usize = 0;
        for (str) |c| {
            if (c == '_') {
                out[len] = '-';
                len += 1;
            } else {
                out[len] = c;
                len += 1;
            }
        }
        return out[0..len].*;
    }
}

pub fn parseRectShorthand(T: type, src: []const u8, pos: usize, parse_fn: fn (src: []const u8, pos: usize) ParseError!Result(T)) ParseError!Result(Rect(T)) {
    var cursor = eatWhitespace(src, pos);
    const a = try parse_fn(src, cursor);
    cursor = eatWhitespace(src, a.end);
    if (isEop(src, cursor)) {
        return .{
            .value = Rect(T){ .top = a.value, .right = a.value, .bottom = a.value, .left = a.value },
            .start = a.start,
            .end = a.end,
        };
    }
    const b = try parse_fn(src, cursor);
    cursor = eatWhitespace(src, b.end);
    if (isEop(src, cursor)) {
        return .{
            .value = Rect(T){ .top = a.value, .right = b.value, .bottom = a.value, .left = b.value },
            .start = a.start,
            .end = b.end,
        };
    }
    const c = try parse_fn(src, cursor);
    cursor = eatWhitespace(src, c.end);
    if (isEop(src, cursor)) {
        return .{
            .value = Rect(T){ .top = a.value, .right = b.value, .bottom = c.value, .left = b.value },
            .start = a.start,
            .end = c.end,
        };
    }
    const d = try parse_fn(src, cursor);
    cursor = eatWhitespace(src, d.end);
    if (isEop(src, cursor)) {
        return .{
            .value = Rect(T){ .top = a.value, .right = b.value, .bottom = c.value, .left = d.value },
            .start = a.start,
            .end = d.end,
        };
    }
    return error.InvalidSyntax;
}
pub fn parseVecShorthand(T: type, src: []const u8, pos: usize, parse_fn: fn (src: []const u8, pos: usize) ParseError!Result(T)) !Result(Point(T)) {
    var cursor = eatWhitespace(src, pos);
    const a = try parse_fn(src, cursor);
    cursor = eatWhitespace(src, a.end);
    if (isEop(src, cursor)) {
        return .{
            .value = Point(T){ .x = a.value, .y = a.value },
            .start = a.start,
            .end = a.end,
        };
    }
    const b = try parse_fn(src, cursor);
    cursor = eatWhitespace(src, b.end);
    if (isEop(src, cursor)) {
        return .{
            .value = Point(T){ .x = a.value, .y = b.value },
            .start = a.start,
            .end = b.end,
        };
    }
    return error.InvalidSyntax;
}

pub fn Result(comptime T: type) type {
    return struct {
        value: T,

        start: usize,
        end: usize,
    };
}
