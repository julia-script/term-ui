// Changed Jan 29, 2025 to accomodate latest Zig changes
// See history if you're using an older version of Zig.

// in your build.zig, you can specify a custom test runner:
// const tests = b.addTest(.{
//   .target = target,
//   .optimize = optimize,
//   .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple }, // add this line
//   .root_source_file = b.path("src/main.zig"),
// });

const std = @import("std");
const builtin = @import("builtin");

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    inline for (test_options.scopes) |scope_name| {
        if (comptime std.mem.eql(u8, scope_name, @tagName(scope))) {
            std.log.defaultLog(message_level, scope, format, args);
            return;
        }
    }
}
pub const test_options = @import("test_options");
pub const std_options: std.Options = .{
    // .log_level = if (is_debug) .debug else .err,
    .log_level = .debug,
    .logFn = logFn,

    // .log_scope_levels = &[_]std.log.ScopeLevel{
    //     .{ .scope = .paint, .level = .debug },
    //     .{ .scope = .tree_dump, .level = .debug },
    // },
    // .log_scope_levels = blk: {
    //     var levels: [test_options.scopes.len]std.log.ScopeLevel = undefined;
    //     // @compileLog(@typeInfo(@TypeOf(.enumlit)));

    //     for (test_options.scopes, 0..) |scope, i| {
    //         _ = scope; // autofix
    //         // const enum_literal = std.meta.stringToEnum(@TypeOf(.enum_literal), scope) orelse @panic("Invalid scope: " ++ scope);
    //         levels[i] = .{ .scope = .scope, .level = .debug };
    //     }
    //     @compileLog(levels);

    //     break :blk &levels;
    // },
    .fmt_max_depth = 20,
    // .log_level = .err,
};
const Allocator = std.mem.Allocator;
var gpa = std.heap.DebugAllocator(.{}){};
const root_allocator = gpa.allocator();
const UpdateTransaction = struct {
    start: u32,
    end: u32,
    content: []const u8,
};
const Update = struct {
    file: []const u8,
    content: []const u8,
    transactions: std.ArrayList(UpdateTransaction),
};

pub var files_to_update: std.StringHashMapUnmanaged(Update) = .{};

var arena = std.heap.ArenaAllocator.init(root_allocator);
pub var test_io: std.Io = undefined;

pub fn getSource(file: []const u8) ![]const u8 {
    const allocator = arena.allocator();
    const gop = files_to_update.getOrPut(allocator, file) catch @panic("OOM");
    if (gop.found_existing) {
        return gop.value_ptr.content;
    }

    const path = try std.fs.path.join(allocator, &.{ "src", file });
    defer allocator.free(path);
    const stat = try std.Io.Dir.cwd().statFile(test_io, path, .{});
    if (stat.kind != .file) {
        return error.FileNotFound;
    }

    const file_content = try std.Io.Dir.cwd().readFileAlloc(test_io, path, allocator, .unlimited);
    gop.value_ptr.* = .{
        .file = allocator.dupe(u8, file) catch @panic("OOM"),
        .content = file_content,
        .transactions = .empty,
    };

    return file_content;
}

pub fn addReplace(file: []const u8, start: u32, end: u32, content: []const u8) !void {
    const allocator = arena.allocator();
    var gop = files_to_update.getOrPut(allocator, file) catch @panic("OOM");
    const transaction = UpdateTransaction{
        .start = start,
        .end = end,
        .content = allocator.dupe(u8, content) catch @panic("OOM"),
    };
    if (!gop.found_existing) {
        gop.value_ptr.* = .{
            .file = allocator.dupe(u8, file) catch @panic("OOM"),
            .content = try getSource(file),
            .transactions = .empty,
        };
    }
    gop.value_ptr.transactions.append(allocator, transaction) catch @panic("OOM");
}

const BORDER: [80]u8 = @splat('=');
// pub const std_options: std.Options = .{

// };
// use in custom panic handler
var current_test: ?[]const u8 = null;

pub fn main() !void {
    const allocator = arena.allocator();
    defer arena.deinit();
    var threaded: std.Io.Threaded = .init(root_allocator, .{});
    defer threaded.deinit();
    test_io = threaded.io();
    if (test_options.update) {
        var src = try std.Io.Dir.cwd().openDir(test_io, "src", .{ .iterate = true });
        defer src.close(test_io);
        try rmSnapshotsRecursively(src);
    }

    const env = Env.init(allocator);
    defer env.deinit(allocator);

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    const printer = Printer.init();
    // clear screen
    // printer.fmt("\x1b[H\x1b[2J", .{});
    // printer.fmt("\r\x1b[0K", .{}); // beginning of line and clear to end of line

    for (builtin.test_functions) |t| {
        if (isSetup(t)) {
            t.func() catch |err| {
                printer.status(.fail, "\nsetup \"{s}\" failed: {}\n", .{ t.name, err });
                return err;
            };
        }
    }

    for (builtin.test_functions) |t| {
        if (isSetup(t) or isTeardown(t)) {
            continue;
        }

        var status = Status.pass;

        const is_unnamed_test = isUnnamed(t);
        if (!is_unnamed_test and test_options.filter.len > 0 and std.mem.indexOf(u8, t.name, test_options.filter) == null) {
            continue;
        }

        const friendly_name = blk: {
            const name = t.name;
            var it = std.mem.splitScalar(u8, name, '.');
            while (it.next()) |value| {
                if (std.mem.eql(u8, value, "test")) {
                    const rest = it.rest();
                    break :blk if (rest.len > 0) rest else name;
                }
            }
            break :blk name;
        };

        current_test = friendly_name;
        std.testing.allocator_instance = .init(std.heap.page_allocator, .{});
        const result = t.func();
        current_test = null;

        if (std.testing.allocator_instance.deinit() != 0) {
            leak += 1;
            printer.status(.fail, "\n{s}\n\"{s}\" - Memory Leak\n{s}\n", .{ BORDER, friendly_name, BORDER });
        }

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                status = .skip;
            },
            else => {
                status = .fail;
                fail += 1;
                printer.status(.fail, "\n{s}\n\"{s}\" - {s}\n{s}\n", .{ BORDER, friendly_name, @errorName(err), BORDER });
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpErrorReturnTrace(trace);
                }
                if (env.fail_first) {
                    break;
                }
            },
        }

        if (env.verbose) {
            printer.status(status, "{s}\n", .{friendly_name});
        } else {
            printer.status(status, ".", .{});
        }
    }

    for (builtin.test_functions) |t| {
        if (isTeardown(t)) {
            t.func() catch |err| {
                printer.status(.fail, "\nteardown \"{s}\" failed: {}\n", .{ t.name, err });
                return err;
            };
        }
    }

    try updateInlineSnapshots();

    const total_tests = pass + fail;
    const status = if (fail == 0) Status.pass else Status.fail;
    printer.status(status, "\n{d} of {d} test{s} passed\n", .{ pass, total_tests, if (total_tests != 1) "s" else "" });
    if (skip > 0) {
        printer.status(.skip, "{d} test{s} skipped\n", .{ skip, if (skip != 1) "s" else "" });
    }
    if (leak > 0) {
        printer.status(.fail, "{d} test{s} leaked\n", .{ leak, if (leak != 1) "s" else "" });
    }
    printer.fmt("\n", .{});
    std.process.exit(if (fail == 0) 0 else 1);
}
pub fn writeMultiline(allocator: Allocator, writer: anytype, content: []const u8) !void {
    _ = allocator; // autofix
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        try writer.writeAll("\\\\");
        try writer.writeAll(line);
        try writer.writeAll("\n");
    }
}

fn formatZig(allocator: Allocator, content: [:0]const u8) ![]const u8 {
    const ast = try std.zig.Ast.parse(allocator, content, .{ .mode = .zig });

    return try ast.renderAlloc(allocator);
}

fn updateInlineSnapshots() !void {
    const allocator = arena.allocator();
    var it = files_to_update.iterator();
    while (it.next()) |entry| {
        const file = entry.key_ptr.*;
        if (entry.value_ptr.transactions.items.len == 0) {
            continue;
        }

        const content = entry.value_ptr.content;
        var aw: std.Io.Writer.Allocating = .init(allocator);
        const writer = &aw.writer;

        var last_index: u32 = 0;
        for (entry.value_ptr.transactions.items) |transaction| {
            try writer.writeAll(content[last_index..transaction.start]);
            try writeMultiline(allocator, writer, transaction.content);
            last_index = transaction.end;
        }
        try writer.writeAll(content[last_index..]);
        const file_path = try std.fs.path.join(allocator, &.{ "src", file });
        const formatted = try formatZig(allocator, try aw.toOwnedSliceSentinel(0));
        try std.Io.Dir.cwd().writeFile(test_io, .{ .sub_path = file_path, .data = formatted });
    }
}

const Printer = struct {
    fn init() Printer {
        return .{};
    }

    fn fmt(self: Printer, comptime format: []const u8, args: anytype) void {
        _ = self;
        std.debug.print(format, args);
    }

    fn status(self: Printer, s: Status, comptime format: []const u8, args: anytype) void {
        const color = switch (s) {
            .pass => "\x1b[32m",
            .fail => "\x1b[31m",
            .skip => "\x1b[33m",
            else => "",
        };
        std.debug.print("{s}", .{color});
        std.debug.print(format, args);
        self.fmt("\x1b[0m", .{});
    }
};

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

const Env = struct {
    verbose: bool,
    fail_first: bool,
    filter: ?[]const u8,

    fn init(allocator: Allocator) Env {
        var filter: ?[]const u8 = null;
        // if (@import("test_env").filter) |f| {
        const filter_option = test_options.filter;
        if (filter_option.len > 0) {
            filter = filter_option;
        }

        // if (readEnv(allocator, "TEST_FILTER")) |rf| {
        //     filter = std.mem.replaceOwned(u8, allocator, rf, "%20", " ") catch @panic("OOM");
        //     allocator.free(rf);
        // }
        return .{
            .verbose = readEnvBool(allocator, "TEST_VERBOSE", true),
            .fail_first = readEnvBool(allocator, "TEST_FAIL_FIRST", false),
            .filter = filter,
        };
    }

    fn deinit(self: Env, allocator: Allocator) void {
        if (self.filter) |f| {
            allocator.free(f);
        }
    }

    fn readEnv(allocator: Allocator, key: []const u8) ?[]const u8 {
        // ponytail: env access now needs a std.Io instance; TEST_VERBOSE and
        // TEST_FAIL_FIRST fall back to defaults until one is threaded through.
        _ = allocator;
        _ = key;
        return null;
    }

    fn readEnvBool(allocator: Allocator, key: []const u8, deflt: bool) bool {
        const value = readEnv(allocator, key) orelse return deflt;
        defer allocator.free(value);
        return std.ascii.eqlIgnoreCase(value, "true");
    }
};

pub const panic = std.debug.FullPanic(struct {
    pub fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
        if (current_test) |ct| {
            std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
        }
        std.debug.defaultPanic(msg, first_trace_addr);
    }
}.panicFn);

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:beforeAll");
}

fn isTeardown(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:afterAll");
}

pub const InlineSnapshotOptions = struct {};

pub fn unescapeString(allocator: std.mem.Allocator, str: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
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
    var buf = std.ArrayList(u8).init(allocator);
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
pub fn matchInlineSnapshot(
    comptime loc: std.builtin.SourceLocation,
    actual: anytype,
    expected: ?[]const u8,
) !void {
    const actual_string: []const u8 = if (isString(@TypeOf(actual))) actual else try std.fmt.allocPrint(arena.allocator(), "{any}", .{actual});

    const source: []const u8 = try getSource(loc.file);
    const arg_range = try findSnapshotArgRange(loc, source);
    const arg_source = source[arg_range.start .. arg_range.start + arg_range.length];
    _ = arg_source; // autofix
    const should_update = expected == null or test_options.update;
    const escaped_actual = try escapeString(arena.allocator(), actual_string, true);

    if (should_update) {
        try addReplace(loc.file, arg_range.start, arg_range.start + arg_range.length, actual_string);
        return;
    }

    const escaped_expected = try escapeString(arena.allocator(), expected.?, true);

    // _ = expected_value; // autofix
    try std.testing.expectEqualStrings(escaped_expected, escaped_actual);
}
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
    var buf = std.ArrayList(u8).init(allocator);
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
const SnapshotArgRange = struct {
    start: u32,
    length: u32,
};
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
    arg_iter.skip(2);
    const snapshot_arg = arg_iter.next() orelse return error.NoSnapshotArg;
    return SnapshotArgRange{
        .start = snapshot_arg.start,
        .length = snapshot_arg.length,
    };
}

pub const SnapshotOptions = struct {
    namespace: []const u8 = "",
    ext: []const u8 = "snap",
    include_header: bool = true,
};
fn isString(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                return ptr.child == u8;
            }
            return isString(ptr.child);
        },
        .array => |arr| return arr.child == u8,
        else => return false,
    }
}

pub fn matchSnapshot(comptime loc: std.builtin.SourceLocation, comptime options: SnapshotOptions, actual: anytype) !void {
    const actual_string = if (isString(@TypeOf(actual))) actual else try std.fmt.allocPrint(arena.allocator(), "{any}", .{actual});
    try matchSnapshotImpl(loc, options, actual_string);
}

var last_src: ?std.builtin.SourceLocation = null;
var test_count: usize = 0;

fn matchSnapshotImpl(
    comptime loc: std.builtin.SourceLocation,
    comptime options: SnapshotOptions,
    actual: []const u8,
) !void {
    const allocator = arena.allocator();
    if (last_src) |last| {
        if (!std.mem.eql(u8, last.file, loc.file) or !std.mem.eql(u8, last.fn_name, loc.fn_name)) {
            test_count = 0;
        }
    }
    test_count += 1;
    last_src = loc;
    const full_description = try std.fmt.allocPrint(
        allocator,
        "{s} {s} {d}" ++ if (options.namespace.len > 0) "-" ++ options.namespace else "",
        .{
            loc.fn_name,
            loc.module,
            test_count,
        },
    );
    const sanitized = try sanitizeDescription(allocator, full_description, options.ext);

    last_src = loc;
    var file_path: []const u8 = loc.file;
    const allocated_path = if (!std.mem.startsWith(u8, file_path, "src/")) blk: {
        file_path = try std.fs.path.join(allocator, &.{ "src", file_path });
        break :blk true;
    } else false;
    defer if (allocated_path) allocator.free(file_path);

    const test_dir = std.fs.path.dirname(file_path) orelse ".";
    const snapshot_dir = try std.fs.path.join(allocator, &.{ test_dir, "__snapshots__" });
    defer allocator.free(snapshot_dir);
    const snapshot_path = try std.fs.path.join(allocator, &.{ snapshot_dir, sanitized });
    defer allocator.free(snapshot_path);

    var update = false;

    // Add header with source location info
    var actual_with_header = std.ArrayList(u8).init(arena.allocator());
    defer actual_with_header.deinit();

    if (options.include_header) {
        try actual_with_header.writer().print(
            \\// Snapshot from: {s}
            \\// Function: {s}
            \\
        , .{ loc.file, loc.fn_name });
    }
    try actual_with_header.appendSlice(actual);

    var file = std.fs.cwd().openFile(snapshot_path, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            update = true;
            return writeSnapshot(snapshot_path, actual_with_header.items);
        } else {
            return err;
        }
    };
    defer file.close();

    if (update) {
        return writeSnapshot(snapshot_path, actual_with_header.items);
    }

    const stat = try file.stat();
    const buf = try file.readToEndAlloc(arena.allocator(), stat.size);

    if (!std.mem.eql(u8, buf, actual_with_header.items)) {
        std.debug.print("Snapshot mismatch for {s}\nPass the UPDATE_SNAPSHOTS=true environment variable to update the snapshot\n", .{snapshot_path});
    }
    try std.testing.expectEqualStrings(buf, actual_with_header.items);
}

fn writeSnapshot(path: []const u8, data: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse ".";
    std.fs.cwd().makePath(dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn sanitizeDescription(allocator: std.mem.Allocator, desc: []const u8, ext: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    for (desc) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') {
            try buf.append(c);
        } else {
            try buf.append('_');
        }
    }
    try buf.appendSlice(".");
    try buf.appendSlice(ext);
    return buf.toOwnedSlice();
}

fn rmSnapshotsRecursively(dir: std.Io.Dir) !void {
    var it = dir.iterate();
    while (try it.next(test_io)) |entry| {
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.name, "__snapshots__")) {
                try dir.deleteTree(test_io, "__snapshots__");
                continue;
            }
            var subdir = try dir.openDir(test_io, entry.name, .{ .iterate = true });
            defer subdir.close(test_io);
            try rmSnapshotsRecursively(subdir);
        }
        // std.fs.cwd().deleteFile(try std.fs.path.join(allocator, &.{ subdir, entry.name })) catch |err| {
        //     std.debug.print("Error deleting file {s}: {}\n", .{ entry.name, err });
        // };

    }
}
