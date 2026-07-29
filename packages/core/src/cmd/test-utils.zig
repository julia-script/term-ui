const std = @import("std");
const InputManager = @import("input/manager.zig").AnyInputManager;
const Event = @import("input/manager.zig").Event;
const TermInfoHandler = @import("handle-term-info.zig");
const handleRawBuffer = @import("input.zig").handleRawBuffer;
const TermInfo = @import("terminfo/main.zig").TermInfo;
const escape = @import("input/manager.zig").escape;
const root = @import("root");
// FIXME: move this to the tests directory
const snapshot = @import("../tests/utils/snapshot.zig");

fn readTermInfo(allocator: std.mem.Allocator, comptime name: []const u8) !TermInfoHandler {
    var file = try std.fs.cwd().openFile("src/cmd/test-data/" ++ name, .{});
    defer file.close();
    const term_info = try TermInfo.initFromFile(std.testing.allocator, file);
    defer term_info.deinit();
    var iter = term_info.strings.iter();
    var handler = TermInfoHandler.init(allocator);
    while (iter.next()) |item| {
        try handler.trie.insert(item.value, item.capability);
    }
    return handler;
}

const Collector = struct {
    event_str: std.ArrayList(Event),
    pub fn emitEventFn(ptr: *anyopaque, event: Event) void {
        var self: *Collector = @ptrCast(@alignCast(ptr));
        self.event_str.append(event) catch unreachable;
    }
    pub fn deinit(self: *Collector) void {
        self.event_str.deinit();
    }
};
pub fn expectEvents(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    comptime namespace: []const u8,
    buffers: []const []const u8,
) !void {
    var input_manager: InputManager = .{
        .allocator = allocator,
    };

    defer input_manager.deinit();
    var collector = Collector{
        .event_str = std.ArrayList(Event).init(allocator),
    };
    try input_manager.subscribe(.{
        .context = &collector,
        .emitFn = Collector.emitEventFn,
    });
    defer collector.deinit();

    var term_info = try readTermInfo(allocator, "xterm-ghostty");

    defer term_info.deinit();
    input_manager.term_info_driver = &term_info;

    var actual_str = std.ArrayList(u8).init(allocator);
    defer actual_str.deinit();
    var actual_str_writer = actual_str.writer().any();

    var buffered = std.ArrayList(u8).init(allocator);
    defer buffered.deinit();
    var position: usize = 0;
    for (buffers) |buf| {
        try buffered.appendSlice(buf);
        const consumed = handleRawBuffer(
            &input_manager,
            buffered.items,
            position,
        );
        position += consumed;
    }

    for (collector.event_str.items) |event| {
        try actual_str_writer.print("{}\n", .{event});
    }

    try root.matchSnapshot(loc, .{
        .namespace = namespace,
    }, actual_str.items);
}

pub fn dumpEvents(
    allocator: std.mem.Allocator,
    buffers: []const []const u8,
) ![]const u8 {
    var input_manager: InputManager = .{
        .allocator = allocator,
    };

    defer input_manager.deinit();
    var collector = Collector{
        .event_str = std.ArrayList(Event).init(allocator),
    };
    try input_manager.subscribe(.{
        .context = &collector,
        .emitFn = Collector.emitEventFn,
    });
    defer collector.deinit();

    var term_info = try readTermInfo(allocator, "xterm-ghostty");

    defer term_info.deinit();
    input_manager.term_info_driver = &term_info;

    var actual_str = std.ArrayList(u8).init(allocator);
    defer actual_str.deinit();
    var actual_str_writer = actual_str.writer().any();

    var buffered = std.ArrayList(u8).init(allocator);
    defer buffered.deinit();
    var position: usize = 0;
    for (buffers) |buf| {
        try buffered.appendSlice(buf);
        const consumed = handleRawBuffer(
            &input_manager,
            buffered.items,
            position,
        );
        position += consumed;
    }

    for (collector.event_str.items) |event| {
        try actual_str_writer.print("{}\n", .{event});
    }

    return try actual_str.toOwnedSlice();
}
