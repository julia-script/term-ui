const std = @import("std");
const test_runner = @import("root");

var last_src: ?std.builtin.SourceLocation = null;
var count: usize = 0;
pub const SnapshotOptions = struct {
    ext: []const u8 = ".snap",
    include_header: bool = true,
};

// test "tests:beforeAll" {
//     std.debug.print("beforeAll!\n", .{});
// }
// test "tests:afterAll" {
//     std.debug.print("afterAll!\n", .{});
// }

pub inline fn expectMatchSnapshot(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    description: []const u8,
    actual: []const u8,
    comptime options: SnapshotOptions,
) !void {
    try expectMatchSnapshotImpl(loc, allocator, description, actual, options);
}

fn shouldUpdateSnapshot(allocator: std.mem.Allocator) !bool {
    _ = allocator;
    return test_runner.test_options.update;
}
fn expectMatchSnapshotImpl(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    description: []const u8,
    actual: []const u8,
    comptime options: SnapshotOptions,
) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    if (last_src) |last| {
        if (!std.mem.eql(u8, last.file, loc.file) or !std.mem.eql(u8, last.fn_name, loc.fn_name)) {
            count = 0;
        }
    }
    count += 1;
    last_src = loc;
    const full_description = try std.fmt.allocPrint(arena.allocator(), "{s} {d}__{s}", .{ if (std.mem.startsWith(u8, loc.fn_name, "test.")) loc.fn_name[5..] else loc.fn_name, count, description });
    const sanitized = try sanitizeDescription(arena.allocator(), full_description, options.ext);

    last_src = loc;
    var file_path: []const u8 = loc.file;
    const allocated_path = if (!std.mem.startsWith(u8, file_path, "src/")) blk: {
        file_path = try std.fs.path.join(arena.allocator(), &.{ "src", file_path });
        break :blk true;
    } else false;
    defer if (allocated_path) arena.allocator().free(file_path);

    const test_dir = std.fs.path.dirname(file_path) orelse ".";
    const snapshot_dir = try std.fs.path.join(arena.allocator(), &.{ test_dir, "__snapshots__" });
    defer arena.allocator().free(snapshot_dir);
    const snapshot_path = try std.fs.path.join(arena.allocator(), &.{ snapshot_dir, sanitized });
    defer arena.allocator().free(snapshot_path);

    const update = try shouldUpdateSnapshot(arena.allocator());

    // Add header with source location info
    var actual_with_header = std.array_list.Managed(u8).init(arena.allocator());
    defer actual_with_header.deinit();

    if (options.include_header) {
        const header = try std.fmt.allocPrint(arena.allocator(),
            \\// Snapshot from: {s}:{d}:{d}
            \\// Function: {s}
            \\// Description: {s}
            \\
            \\
        , .{ loc.file, loc.line, loc.column, loc.fn_name, description });
        try actual_with_header.appendSlice(header);
    }
    try actual_with_header.appendSlice(actual);

    const io = test_runner.test_io;
    const buf = std.Io.Dir.cwd().readFileAlloc(io, snapshot_path, arena.allocator(), .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            return writeSnapshot(snapshot_path, actual_with_header.items);
        } else {
            return err;
        }
    };

    if (update) {
        return writeSnapshot(snapshot_path, actual_with_header.items);
    }

    if (!std.mem.eql(u8, buf, actual_with_header.items)) {
        std.debug.print("Snapshot mismatch for {s}\nPass the UPDATE_SNAPSHOTS=true environment variable to update the snapshot\n", .{snapshot_path});
    }
    try std.testing.expectEqualStrings(buf, actual_with_header.items);
}

fn writeSnapshot(path: []const u8, data: []const u8) !void {
    const io = test_runner.test_io;
    const dir = std.fs.path.dirname(path) orelse ".";
    std.Io.Dir.cwd().createDirPath(io, dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
}

fn sanitizeDescription(allocator: std.mem.Allocator, desc: []const u8, ext: []const u8) ![]u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();
    for (desc) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') {
            try buf.append(c);
        } else {
            try buf.append('_');
        }
    }
    try buf.appendSlice(ext);
    return buf.toOwnedSlice();
}

fn countLb(src: []const u8) i32 {
    var lb: i32 = 0;
    for (src) |c| {
        if (c == '\n') {
            lb += 1;
        }
    }
    return lb;
}
const SnapshotArgRange = struct {
    start: u32,
    length: u32,
};
const ArgIterator = struct {
    source: []const u8,
    index: u32 = 0,
    arg_index: u32 = 0,
    const Arg = struct {
        start: u32,
        length: u32,
        has_trailing_comma: bool,
        arg_index: u32,
    };
    fn match(self: *ArgIterator, expected: u8) bool {
        return self.index < self.source.len and self.source[self.index] == expected;
    }
    pub fn skip(self: *ArgIterator, skip_count: usize) void {
        for (0..skip_count) |_| {
            _ = self.next() orelse break;
        }
    }
    pub fn next(self: *ArgIterator) ?Arg {
        if (self.index >= self.source.len or self.match(')')) return null;
        // let's trim leading whitespace
        self.consumeIgnorables();

        const start = self.index;

        // if a closing parenthesis is the first non-whitespace character after the comma, it's a trailing comma on the last argument
        // so we reached the end
        if (self.match(')')) {
            self.index = start;
            return null;
        }

        // if this is a multiline string, we need to treat it differently
        if (std.mem.startsWith(u8, self.source[self.index..], "\\\\")) {
            self.index += 2;
            self.consumeLine();
            self.consumeWhitespace();
            while (std.mem.startsWith(u8, self.source[self.index..], "\\\\")) {
                self.index += 2;
                self.consumeLine();
                self.consumeWhitespace();
            }
            self.arg_index += 1;
            self.index += 1;
            return Arg{
                .start = start,
                .length = self.index - start - 1,
                .has_trailing_comma = self.source[self.index - 1] == ',',
                .arg_index = self.arg_index - 1,
            };
        }

        while (self.index < self.source.len) {
            if (self.match(',')) {
                self.index += 1;
                break;
            }
            if (self.match(')')) {
                self.index += 1;
                break;
            }
            switch (self.source[self.index]) {
                '/' => {
                    self.index += 1;
                    if (self.match('/')) {
                        self.index += 1;
                        while (self.index < self.source.len) {
                            if (self.match('\n')) {
                                break;
                            }
                            self.index += 1;
                        }
                    } else {
                        self.index += 1;
                    }
                },
                '"' => {
                    self.index += 1;
                    while (self.index < self.source.len) {
                        if (self.match('\\')) {
                            self.index += 1;
                        }
                        if (self.match('"')) {
                            break;
                        }
                        self.index += 1;
                    }
                },
                inline '{', '(', '[' => |c| {
                    const end_pair: u8 = comptime switch (c) {
                        '{' => '}',
                        '(' => ')',
                        '[' => ']',
                        else => unreachable,
                    };

                    self.index += 1;
                    while (!self.match(end_pair)) {
                        self.index += 1;
                    }
                },
                else => {},
            }
            self.index += 1;
        }
        self.arg_index += 1;
        return Arg{
            .start = start,
            .length = self.index - start - 1,
            .has_trailing_comma = self.source[self.index - 1] == ',',
            .arg_index = self.arg_index - 1,
        };
    }
    fn consumeLine(self: *ArgIterator) void {
        while (self.index < self.source.len) {
            if (self.source[self.index] == '\n') {
                break;
            }
            self.index += 1;
        }
    }
    fn consumeWhitespace(self: *ArgIterator) void {
        while (self.index < self.source.len) {
            if (std.ascii.isWhitespace(self.source[self.index])) {
                self.index += 1;
            } else {
                break;
            }
        }
    }
    fn consumeIgnorables(self: *ArgIterator) void {
        self.consumeWhitespace();
        while (self.index < self.source.len) {
            if (std.mem.startsWith(u8, self.source[self.index..], "//")) {
                self.index += 2;
                self.consumeLine();
                self.consumeWhitespace();
            } else {
                break;
            }
        }
    }
};
pub fn unescapeString(allocator: std.mem.Allocator, str: []const u8, is_multiline: bool) ![]const u8 {
    _ = is_multiline; // autofix
    var buf = std.array_list.Managed(u8).init(allocator);
    try buf.ensureUnusedCapacity(str.len);
    defer buf.deinit();
    var i: usize = 0;
    while (i < str.len) {
        const c = str[i];
        if (c == '\\') {
            if (i + 1 < str.len) {
                i += 1;
                switch (str[i]) {
                    'n' => {
                        try buf.append('\n');
                        i += 1;
                    },
                    't' => {
                        try buf.append('\t');
                        i += 1;
                    },
                    'r' => {
                        try buf.append('\r');
                        i += 1;
                    },
                    '\\' => {
                        try buf.append('\\');
                        i += 1;
                    },
                    '"' => {
                        try buf.append('"');
                        i += 1;
                    },
                    'u' => {
                        i += 1;
                        const hex = str[i..@min(i + 4, str.len)];
                        const value = try std.fmt.parseInt(u16, hex, 16);
                        var hex_buf: [4]u8 = undefined;
                        const hex_len = try std.unicode.utf8Encode(value, &hex_buf);
                        try buf.appendSlice(hex_buf[0..hex_len]);
                        i += 4;
                    },

                    else => {
                        @panic("unsupported escape sequence");
                    },
                }
            }
        }
        i += 1;
        try buf.append(c);
    }
    return buf.toOwnedSlice();
}
pub fn escapeString(allocator: std.mem.Allocator, str: []const u8, is_multiline: bool) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    defer buf.deinit();
    for (str) |c| {
        if (is_multiline) {
            switch (c) {
                '\x1b' => {
                    try buf.appendSlice("\\u001b");
                },
                '\x00' => {
                    try buf.appendSlice("\\u0000");
                },

                else => {},
            }
        }
        switch (c) {
            '\n' => {
                try buf.appendSlice("\\n");
            },
            '\r' => {
                try buf.appendSlice("\\r");
            },
            '\t' => {
                try buf.appendSlice("\\t");
            },
            '\\' => {
                try buf.appendSlice("\\\\");
            },
            '"' => {
                try buf.appendSlice("\\\"");
            },
            else => {
                try buf.append(c);
            },
        }
    }
    return buf.toOwnedSlice();
}

pub fn parseSnapshotArg(allocator: std.mem.Allocator, arg_str: []const u8) !?[]const u8 {
    var trimmed = std.mem.trim(u8, arg_str, " \t\n");
    if (std.mem.eql(u8, trimmed, "null")) {
        return null;
    }
    if (std.mem.startsWith(u8, trimmed, "\"")) {
        return try unescapeString(allocator, trimmed[1 .. trimmed.len - 1], false);
    }
    if (!std.mem.startsWith(u8, trimmed, "\\\\")) {
        return error.NotAString;
    }
    var buf = std.array_list.Managed(u8).init(allocator);
    var iter = std.mem.splitSequence(u8, trimmed, "\n");
    while (iter.next()) |_| {
        var index = iter.index orelse break;
        defer iter.index = index;
        while (index < trimmed.len and std.ascii.isWhitespace(trimmed[index])) {
            index += 1;
        }
        if (!std.mem.startsWith(u8, trimmed[index..], "\\\\")) {
            continue;
        }

        const unescaped = try unescapeString(allocator, trimmed[index .. std.mem.indexOf(u8, trimmed[index..], "\n") orelse trimmed.len], true);
        try buf.appendSlice(unescaped);
        try buf.append('\n');
    }
    return try buf.toOwnedSlice();
}
fn findSnapshotArgRange(loc: std.builtin.SourceLocation, source: []const u8) !SnapshotArgRange {
    var start: u32 = 0;
    // var len: usize = 0;
    // var line_breaks: usize = 0;

    var line_iter = std.mem.splitSequence(u8, source, "\n");
    var current_line: u32 = 1;
    while (line_iter.next()) |_| {
        if (current_line == loc.line - 1) {
            start = @intCast(line_iter.index orelse source.len - 1);

            break;
        }
        current_line += 1;
    }
    // now we need to find the inline snapshot arg, which is the last argument

    var arg_iter = ArgIterator{ .source = source, .index = start };
    arg_iter.skip(5);
    const snapshot_arg = arg_iter.next() orelse return error.NoSnapshotArg;
    return SnapshotArgRange{
        .start = snapshot_arg.start,
        .length = snapshot_arg.length,
    };
}
pub fn prepareSnapshot(allocator: std.mem.Allocator, str: []const u8, col: usize, is_multiline: bool) ![]const u8 {
    var buf = std.array_list.Managed(u8).init(allocator);
    if (is_multiline) {
        try buf.ensureUnusedCapacity(str.len);
        defer buf.deinit();
        var iter = std.mem.splitSequence(u8, str, "\n");
        var is_first_line = true;
        while (iter.next()) |line| {
            const escaped = try escapeString(allocator, line, true);
            if (!is_first_line) {
                try buf.appendNTimes(' ', col - 1);
            }
            is_first_line = false;
            try buf.appendSlice("\\\\");
            try buf.appendSlice(escaped);
            try buf.append('\n');
        }
        try buf.appendNTimes(' ', col - 1);
        return buf.toOwnedSlice();
    } else {
        try buf.appendSlice("\"");
        try buf.appendSlice(try escapeString(allocator, str, false));
        try buf.appendSlice("\"");
        return buf.toOwnedSlice();
    }
}
pub inline fn expectMatchInlineSnapshot(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    description: []const u8,
    comptime options: SnapshotOptions,
    actual: []const u8,
    expected: ?[]const u8,
) !void {
    // try test_runner.addReplace(loc.file, loc.line, loc.column, actual);
    _ = description; // autofix
    _ = options; // autofix
    var arena = std.heap.ArenaAllocator.init(allocator);

    defer arena.deinit();

    const source: []const u8 = try test_runner.getSource(loc.file);
    const arg_range = try findSnapshotArgRange(loc, source);
    const arg_source = source[arg_range.start .. arg_range.start + arg_range.length];
    _ = arg_source; // autofix
    const should_update = expected == null or try shouldUpdateSnapshot(arena.allocator());
    const escaped_actual = try escapeString(arena.allocator(), actual, true);

    if (should_update) {
        try test_runner.addReplace(loc.file, arg_range.start, arg_range.start + arg_range.length, actual);
        return;
    }

    const escaped_expected = try escapeString(arena.allocator(), expected.?, true);

    // _ = expected_value; // autofix
    try std.testing.expectEqualStrings(escaped_expected, escaped_actual);
}

test "snapshot file roundtrip" {
    try expectMatchSnapshot(@src(), std.testing.allocator, "basic", "hello snapshot\n", .{});
}

test "snapshot inline roundtrip" {
    try expectMatchInlineSnapshot(
        @src(),
        std.testing.allocator,
        "inline",
        .{},
        "hello inline",
        \\hello inline
        ,
    );
}
