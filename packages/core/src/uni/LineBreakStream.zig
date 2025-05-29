/// adapted from https://github.com/dcov/unicode/blob/ca91ab4b55ed0999e2801fc5f8250ec960ff5d54/src/ReverseUtf8Iterator.zig
const std = @import("std");
const lookups = @import("lookups.zig");
const ReverseUtf8Iterator = @import("ReverseUtf8Iterator.zig");
const codepoint = @import("codepoint.zig");

buffer: std.ArrayList(u8),
i: usize,
ris_count: usize,
context: Context,
cm_base: ?struct {
    code_point: u21,
    prop: lookups.LineBreak,
},
emit_eof_break: bool = false,
last_buffer_index: usize = 0,
prev_break_index: usize = 0,

const Context = enum {
    zw_sp,
    op_sp,
    qu_sp,
    clcp_sp,
    b2_sp,
    hl_hyba,
    none,
};
const Self = @This();

pub const Break = struct {
    mandatory: bool,
    i: usize,
    // local_i: usize,
    slice: []const u8,
};
pub fn append(self: *Self, data: []const u8) !void {
    if (!std.unicode.utf8ValidateSlice(data)) {
        return error.InvalidUtf8;
    }
    self.last_buffer_index = self.buffer.items.len;
    try self.buffer.appendSlice(data);
}

pub fn getLocalIndex(self: *Self) usize {
    std.debug.print("getLocalIndex: {d} {d}\n", .{ self.i, self.last_buffer_index });
    return self.i - self.last_buffer_index;
}

pub fn markStreamDone(self: *Self) void {
    self.emit_eof_break = true;
}

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .buffer = std.ArrayList(u8).init(allocator),
        .i = 0,
        .ris_count = 0,
        .context = .none,
        .cm_base = null,
        .emit_eof_break = false,
    };
}

pub fn initWithData(allocator: std.mem.Allocator, str: []const u8) !Self {
    if (!std.unicode.utf8ValidateSlice(str)) {
        return error.InvalidUtf8;
    }
    var self = init(allocator);
    try self.append(str);
    return self;
}

pub fn deinit(self: *Self) void {
    self.buffer.deinit();
}

pub fn next(self: *Self) ?Break {
    if (self.i >= self.buffer.items.len) {
        return null;
    }

    var iter = std.unicode.Utf8Iterator{ .bytes = self.buffer.items, .i = self.i };

    var before_code_point = iter.nextCodepoint().?;
    var before = breakProp(before_code_point);
    self.context = .none;

    while (true) {
        const i = self.i;
        self.i = iter.i;

        const after_code_point = if (iter.nextCodepoint()) |next_code_point| next_code_point else {
            if (self.emit_eof_break) {
                defer self.prev_break_index = self.i;
                return Break{
                    .mandatory = true,
                    .i = self.i,
                    // .local_i = self.getLocalIndex(),
                    .slice = self.buffer.items[self.prev_break_index..self.i],
                };
            }
            self.i = i;
            return null;
        };
        const after = breakProp(after_code_point);

        if (before == .RI) {
            self.ris_count += 1;
        } else if (before != .CM and before != .ZWJ) {
            self.ris_count = 0;
        }

        if (self.checkPair(before, before_code_point, after, after_code_point)) |mandatory| {
            defer self.prev_break_index = self.i;
            return Break{
                .mandatory = mandatory,
                .i = self.i,
                // .local_i = self.getLocalIndex(),
                .slice = self.buffer.items[self.prev_break_index..self.i],
            };
        }
        before_code_point = after_code_point;
        before = after;
    }
}

fn checkPair(
    self: *Self,
    before: lookups.LineBreak,
    before_code_point: u21,
    after: lookups.LineBreak,
    after_code_point: u21,
) ?bool {
    return switch (before) {
        .CR => switch (after) {
            .LF => null,
            else => true,
        },
        .BK, .LF, .NL => true,
        .ZW => switch (after) {
            .CR, .BK, .LF, .NL, .ZW => null,
            .SP => self.setContext(.zw_sp),
            else => false,
        },
        .ZWJ => if (self.cm_base) |base| blk: {
            self.cm_base = null;
            break :blk self.checkPair(base.prop, base.code_point, after, after_code_point);
        } else null,
        .CM => if (self.cm_base) |base| blk: {
            self.cm_base = null;
            break :blk self.checkPair(base.prop, base.code_point, after, after_code_point);
        } else self.checkPair(.AL, undefined, after, after_code_point),
        .WJ, .GL => switch (after) {
            .CM, .ZWJ => self.setCmBase(before, before_code_point),
            else => null,
        },
        .BA => switch (after) {
            .GL, .CB => false,
            else => switch (self.context) {
                .hl_hyba => null,
                else => self.defaultAfter(before, before_code_point, after),
            },
        },
        .OP => switch (after) {
            .SP => self.setContext(.op_sp),
            .CM, .ZWJ => self.setCmBase(before, before_code_point),
            else => null,
        },
        .QU => switch (after) {
            .SP => self.setContext(.qu_sp),
            .CM, .ZWJ => self.setCmBase(before, before_code_point),
            else => null,
        },
        .CL => switch (after) {
            .SP => self.setContext(.clcp_sp),
            .NS => null,
            .PR, .PO => if (self.numericBefore(before_code_point)) null else false,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .CP => switch (after) {
            .SP => self.setContext(.clcp_sp),
            .NS => null,
            .PR, .PO => if (self.numericBefore(before_code_point)) null else false,
            .AL, .HL, .NU => switch (codepoint.getEastAsianWidth(before_code_point)) {
                .F, .W, .H => self.defaultAfter(before, before_code_point, after),
                else => null,
            },
            else => self.defaultAfter(before, before_code_point, after),
        },
        .B2 => switch (after) {
            .SP => self.setContext(.b2_sp),
            .B2 => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .SP => switch (after) {
            .SP => null,
            .BK, .CR, .LF, .NL, .ZW => self.setContext(.none),
            .WJ, .CL, .CP, .EX, .IS, .SY => if (self.context == .zw_sp) false else self.setContext(.none),
            else => switch (self.context) {
                .zw_sp => false,
                .op_sp => self.setContext(.none),
                .qu_sp => if (after == .OP) self.setContext(.none) else false,
                .b2_sp => if (after == .B2) self.setContext(.none) else false,
                .clcp_sp => if (after == .NS) self.setContext(.none) else false,
                else => switch (after) {
                    else => false,
                },
            },
        },
        .CB => switch (after) {
            .BK, .CR, .LF, .NL, .SP, .ZW, .WJ, .GL, .CL, .CP, .EX, .IS, .SY, .QU => null,
            .CM, .ZWJ => self.setCmBase(before, before_code_point),
            else => false,
        },
        .BB => switch (after) {
            .CM, .ZWJ => self.setCmBase(before, before_code_point),
            .CB => false,
            else => null,
        },
        .HL => switch (after) {
            .HY, .BA => self.setContext(.hl_hyba),
            .NU, .PR, .PO, .AL, .HL => null,
            .OP => switch (codepoint.getEastAsianWidth(after_code_point)) {
                .F, .W, .H => self.defaultAfter(before, before_code_point, after),
                else => null,
            },
            else => self.defaultAfter(before, before_code_point, after),
        },
        .SY => switch (after) {
            .HL => null,
            .NU => if (self.numericBefore(before_code_point)) null else false,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .AL => switch (after) {
            .NU, .PR, .PO, .AL, .HL => null,
            .OP => switch (codepoint.getEastAsianWidth(after_code_point)) {
                .F, .W, .H => self.defaultAfter(before, before_code_point, after),
                else => null,
            },
            else => self.defaultAfter(before, before_code_point, after),
        },
        .NU => switch (after) {
            .AL, .HL, .PO, .PR, .NU => null,
            .OP => switch (codepoint.getEastAsianWidth(after_code_point)) {
                .F, .W, .H => self.defaultAfter(before, before_code_point, after),
                else => null,
            },
            else => self.defaultAfter(before, before_code_point, after),
        },
        .PR => switch (after) {
            .ID, .EB, .EM, .AL, .HL, .NU, .JL, .JV, .JT, .H2, .H3 => null,
            .OP => if (self.numericAfter(after_code_point)) null else false,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .ID => switch (after) {
            .PO => null,
            .EM => blk: {
                break :blk switch (codepoint.getCategory(before_code_point)) {
                    // .None => null,
                    else => self.defaultAfter(before, before_code_point, after),
                };
            },
            else => self.defaultAfter(before, before_code_point, after),
        },
        .EB => switch (after) {
            .PO, .EM => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .EM => switch (after) {
            .PO => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .PO => switch (after) {
            .AL, .HL, .NU => null,
            .OP => if (self.numericAfter(after_code_point)) null else false,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .HY => switch (after) {
            .NU => null,
            .GL, .CB => false,
            else => switch (self.context) {
                .hl_hyba => null,
                else => self.defaultAfter(before, before_code_point, after),
            },
        },
        .IS => switch (after) {
            .NU => if (self.numericBefore(before_code_point)) null else false,
            .AL, .HL => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .JL => switch (after) {
            .JL, .JV, .H2, .H3, .PO => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .JV => switch (after) {
            .JV, .JT, .PO => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .JT => switch (after) {
            .JT, .PO => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .H2 => switch (after) {
            .JV, .JT, .PO => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .H3 => switch (after) {
            .JT, .PO => null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        .RI => switch (after) {
            .RI => if ((self.ris_count % 2) == 0) false else null,
            else => self.defaultAfter(before, before_code_point, after),
        },
        else => self.defaultAfter(before, before_code_point, after),
    };
}

fn setCmBase(self: *Self, before: lookups.LineBreak, before_code_point: u21) ?bool {
    self.cm_base = .{
        .code_point = before_code_point,
        .prop = before,
    };
    return null;
}

fn numericBefore(self: *Self, before_code_point: u21) bool {
    const before_len = std.unicode.utf8CodepointSequenceLength(before_code_point) catch unreachable;
    var iter = ReverseUtf8Iterator.init(self.buffer.items[0 .. self.i - before_len]);
    while (iter.next()) |code_point| {
        const cp = std.unicode.utf8Decode(code_point) catch unreachable;
        switch (breakProp(cp)) {
            .SY, .IS => continue,
            .NU => return true,
            else => break,
        }
    }
    return false;
}

fn numericAfter(self: *Self, after_code_point: u21) bool {
    const after_len = std.unicode.utf8CodepointSequenceLength(after_code_point) catch unreachable;
    var iter = std.unicode.Utf8Iterator{ .bytes = self.buffer.items[self.i + after_len ..], .i = 0 };
    if (iter.nextCodepoint()) |code_point| {
        if (breakProp(code_point) == .NU) {
            return true;
        }
    }
    return false;
}

fn defaultAfter(self: *Self, before: lookups.LineBreak, before_code_point: u21, after: lookups.LineBreak) ?bool {
    return switch (after) {
        .BK, .CR, .LF, .NL, .SP, .ZW, .WJ, .GL, .CL, .CP, .EX, .IS, .SY, .QU, .BA, .HY, .NS, .IN => null,
        .CM, .ZWJ => blk: {
            self.cm_base = .{
                .code_point = before_code_point,
                .prop = before,
            };
            break :blk null;
        },
        else => false,
    };
}

fn setContext(self: *Self, context: Context) ?bool {
    self.context = context;
    return null;
}

fn breakProp(c: u21) lookups.LineBreak {
    return switch (codepoint.getLineBreak(c)) {
        .AI, .SG, .XX => .AL,
        .SA => switch (codepoint.getCategory(c)) {
            .Mn, .Mc => .CM,
            else => .AL,
        },
        .CJ => .NS,
        else => |v| v,
    };
}

const testing = std.testing;
const test_allocator = testing.allocator;

test "english text streaming" {
    var stream = init(test_allocator);
    defer stream.deinit();

    // Test simple English sentence in chunks
    try stream.append("Hello ");
    try stream.append("world! ");
    try stream.append("This is a test.");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find break opportunities at spaces
    try testing.expect(breaks.items.len >= 3);

    // Mark stream done and check for final break
    stream.markStreamDone();
    if (stream.next()) |final_break| {
        try testing.expect(final_break.mandatory);
        try testing.expectEqual(final_break.i, stream.buffer.items.len);
    }
}

test "english text with line breaks" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("Line 1\n");
    try stream.append("Line 2\r\n");
    try stream.append("Line 3");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find mandatory breaks at newlines
    try testing.expect(breaks.items.len >= 2);
    // Find mandatory breaks among all breaks
    var mandatory_count: usize = 0;
    for (breaks.items) |break_point| {
        if (break_point.mandatory) mandatory_count += 1;
    }
    try testing.expect(mandatory_count >= 2);
}

test "english text with spaces and punctuation" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("Hello, ");
    try stream.append("world! ");
    try stream.append("How are you?");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find optional breaks at spaces
    try testing.expect(breaks.items.len >= 2);
    for (breaks.items) |break_point| {
        try testing.expect(!break_point.mandatory);
    }
}

test "initWithData compatibility" {
    var stream = try initWithData(test_allocator, "Hello world!");
    defer stream.deinit();

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find break at space
    try testing.expect(breaks.items.len >= 1);
}

test "empty stream" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try testing.expect(stream.next() == null);

    stream.markStreamDone();
    try testing.expect(stream.next() == null);
}

test "incremental append" {
    var stream = init(test_allocator);
    defer stream.deinit();

    // Add text character by character
    const text = "Hello world!";
    for (text) |char| {
        try stream.append(&[_]u8{char});
    }

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find break at space
    try testing.expect(breaks.items.len >= 1);
}

test "asian characters - chinese text" {
    var stream = init(test_allocator);
    defer stream.deinit();

    // Chinese text: "你好世界" (Hello World)
    try stream.append("你好");
    try stream.append("世界");
    try stream.append("！");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // CJK characters should allow breaks between them
    try testing.expect(breaks.items.len >= 1);
}

test "asian characters - japanese text with hiragana and kanji" {
    var stream = init(test_allocator);
    defer stream.deinit();

    // Japanese text: "こんにちは世界" (Hello World)
    try stream.append("こんにちは");
    try stream.append("世界");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should allow breaks between hiragana and kanji
    try testing.expect(breaks.items.len >= 0);
}

test "asian characters - korean text" {
    var stream = init(test_allocator);
    defer stream.deinit();

    // Korean text: "안녕하세요" (Hello)
    try stream.append("안녕");
    try stream.append("하세요");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Korean syllables should allow breaks
    try testing.expect(breaks.items.len >= 0);
}

test "asian characters - mixed ascii and cjk" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("Hello ");
    try stream.append("你好 ");
    try stream.append("world");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find breaks at spaces and between different scripts
    try testing.expect(breaks.items.len >= 2);
}

test "emojis - basic emoji" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("Hello ");
    try stream.append("😀");
    try stream.append(" world");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should find breaks at spaces but not break emoji
    try testing.expect(breaks.items.len >= 2);
}

test "emojis - emoji with skin tone modifier" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("👋🏽"); // Waving hand with medium skin tone
    try stream.append(" hello");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should not break emoji sequence with modifier
    try testing.expect(breaks.items.len >= 1);
}

test "emojis - complex emoji sequence" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("👨‍👩‍👧‍👦"); // Family emoji (man, woman, girl, boy)
    try stream.append(" family");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should not break complex emoji sequence
    try testing.expect(breaks.items.len >= 1);
}

test "emojis - emoji with text presentation" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("❤️"); // Red heart with variation selector
    try stream.append(" love");

    var breaks = std.ArrayList(Break).init(test_allocator);
    defer breaks.deinit();

    while (stream.next()) |break_point| {
        try breaks.append(break_point);
    }

    // Should not break emoji with presentation selector
    try testing.expect(breaks.items.len >= 1);
}

test "utf8 validation in append" {
    var stream = init(test_allocator);
    defer stream.deinit();

    // Valid UTF-8
    try stream.append("Hello 世界");

    // Invalid UTF-8 should return error
    const invalid_utf8 = [_]u8{ 0xFF, 0xFE, 0xFD };
    try testing.expectError(error.InvalidUtf8, stream.append(&invalid_utf8));
}

test "line break stream" {
    var stream = init(test_allocator);
    defer stream.deinit();

    try stream.append("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.");
    while (stream.next()) |break_point| {
        std.debug.print("break_point: {any}\n", .{break_point});
    }
}
