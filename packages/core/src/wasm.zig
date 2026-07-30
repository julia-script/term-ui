const Tree = @import("tree/Tree.zig");
const Style = @import("tree/Style.zig");
const std = @import("std");
const parsers = @import("styles/styles.zig");
const Renderer = @import("renderer/v2/Renderer.zig");
const fmt = @import("fmt.zig");
const TermInfo = @import("cmd/terminfo/main.zig").TermInfo;
const InputManager = @import("cmd/input/manager.zig");
const builtin = @import("builtin");

const logger = std.log.scoped(.wasm);
const RenderList = @import("layout/v2/RenderList.zig");
const is_debug = builtin.mode == .debug;

const is_wasm = @import("builtin").target.cpu.arch.isWasm();

pub const std_options: std.Options = .{
    .logFn = wasmLog,
    // .log_level = if (is_debug) .debug else .err,
    .log_level = .err,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .paint, .level = .debug },
        .{ .scope = .tree_dump, .level = .debug },
    },
};

extern fn externalLog(message: [*:0]u8) void;

pub const panic = std.debug.FullPanic(wasmPanic);

fn wasmPanic(msg: []const u8, first_trace_addr: ?usize) noreturn {
    _ = first_trace_addr;
    var buffer: [512]u8 = undefined;
    const formatted = std.fmt.bufPrint(&buffer, "level: err;scope: panic;\r\npanic: {s}", .{msg}) catch msg;
    const ptr = std.heap.wasm_allocator.allocSentinel(u8, formatted.len, 0) catch @trap();
    @memcpy(ptr[0..formatted.len], formatted);
    externalLog(ptr);
    @trap();
}

pub fn wasmLog(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();

    var buffer: [4096]u8 = undefined;
    const header = std.fmt.bufPrint(&buffer, "level: {s};scope: {s};\r\n", .{ level_txt, @tagName(scope) }) catch return;
    const remaining = buffer[header.len..];
    const body = std.fmt.bufPrint(remaining, format, args) catch return;
    const total_len = header.len + body.len;

    const msg = wasm_try([*:0]u8, std.heap.wasm_allocator.allocSentinel(u8, total_len, 0));
    @memcpy(msg[0..total_len], buffer[0..total_len]);

    externalLog(msg);
    std.heap.wasm_allocator.free(msg[0 .. total_len + 1]);
}

var gpa = std.heap.DebugAllocator(.{
    .safety = true,
    .verbose_log = false,
}){};

const wasm_allocator = blk: {
    if (is_debug or !is_wasm) {
        break :blk gpa.allocator();
    } else {
        break :blk std.heap.wasm_allocator;
    }
};

/// Reply arena: every export returning transient data allocates its output
/// here and resets the arena at entry. Contract: an output stays valid until
/// the NEXT call into any wasm export; the client never frees it.
var reply_arena = std.heap.ArenaAllocator.init(wasm_allocator);

fn replyAllocator() std.mem.Allocator {
    _ = reply_arena.reset(.retain_capacity);
    return reply_arena.allocator();
}

pub fn main() void {}

pub inline fn wasm_try(T: type, triable: anytype) T {
    return triable catch |e| {
        logger.err("wasm_try({s})", .{@errorName(e)});
        @panic(@errorName(e));
    };
}

pub export const NULL: u32 = std.math.maxInt(u32);
export fn allocBuffer(size: usize) [*]u8 {
    logger.info("allocBuffer({d})", .{size});
    return wasm_try([]u8, wasm_allocator.alloc(u8, size)).ptr;
}
pub export fn allocNullTerminatedBuffer(size: usize) [*:0]u8 {
    logger.info("allocNullTerminatedBuffer({d})", .{size});
    const ptr = wasm_try([*:0]u8, wasm_allocator.allocSentinel(u8, size, 0));
    return ptr;
}
export fn freeNullTerminatedBuffer(ptr: [*:0]u8) void {
    logger.info("freeNullTerminatedBuffer({d})", .{std.mem.len(ptr)});
    const slice = ptr[0 .. std.mem.len(ptr) + 1];
    wasm_allocator.free(slice);
}
export fn freeBuffer(ptr: [*]u8, size: usize) void {
    logger.info("freeBuffer({d})", .{size});
    wasm_allocator.free(ptr[0..size]);
}

pub export fn Tree_init() *Tree {
    const ptr = wasm_try(*Tree, wasm_allocator.create(Tree));
    ptr.* = wasm_try(Tree, Tree.init(wasm_allocator));

    logger.info("Tree_init():{*}", .{ptr});
    return ptr;
}
pub export fn Tree_deinit(tree: *Tree) void {
    logger.info("Tree_deinit({*})", .{tree});
    tree.deinit();
    wasm_allocator.destroy(tree);
}

fn trim(slice: []const u8) []const u8 {
    var begin: usize = 0;
    var end: usize = slice.len;
    while (begin < end and std.ascii.isWhitespace(slice[begin])) : (begin += 1) {}
    while (end > begin and std.ascii.isWhitespace(slice[end - 1])) : (end -= 1) {}
    return slice[begin..end];
}
pub export fn Tree_createNode(tree: *Tree, styles: [*:0]u8) u32 {
    logger.info("Tree_createNode({*}, \"{s}\")", .{ tree, styles });
    defer freeNullTerminatedBuffer(styles);
    const style_slice = styles[0..std.mem.len(styles)];
    const node = wasm_try(Tree.Node.NodeId, tree.createNode());
    wasm_try(void, parsers.parseStyleString(tree, node, style_slice));

    return @intCast(node);
}
pub export fn Tree_createTextNode(tree: *Tree, text: [*:0]u8) u32 {
    logger.info("Tree_createTextNode({*}, {s})", .{ tree, text });
    defer freeNullTerminatedBuffer(text);
    const text_slice = text[0..std.mem.len(text)];
    return @intCast(wasm_try(Tree.Node.NodeId, tree.createTextNode(text_slice)));
}
var ctx: void = {};
export fn Tree_enableInputManager(tree: *Tree) void {
    logger.info("Tree_enableInputManager({*})", .{tree});
    wasm_try(void, tree.enableInputManager());
    wasm_try(void, tree.input_manager.?.subscribe(.{
        .context = &ctx,
        .emitFn = emitEventFn,
    }));
}
export fn Tree_disableInputManager(tree: *Tree) void {
    logger.info("Tree_disableInputManager({*})", .{tree});
    tree.disableInputManager();
}
const external = if (!builtin.is_test and is_wasm) struct {
    extern fn emitEvent(data: [*]const u32) void;
} else struct {
    pub fn emitEvent(_: [*]const u32) void {}
};
pub fn emitEventFn(_: *anyopaque, event: InputManager.Event) void {
    var event_buffer: [8]u32 = undefined;
    switch (event.data) {
        .key => |key| {
            const action: u32 = @intCast(@backingInt(key.action));
            event_buffer[0] = 1;
            event_buffer[1] = 0; // reserve for future event id
            event_buffer[2] = key.codepoint;
            event_buffer[3] = key.base_codepoint;
            event_buffer[4] = action;
            event_buffer[5] = event.modifiers;
            external.emitEvent((&event_buffer).ptr);
        },
        .paste_chunk => |paste| {
            const kind: u32 = @intCast(@backingInt(paste.kind));
            event_buffer[0] = 2;
            event_buffer[1] = 0; // reserve for future event id
            event_buffer[2] = kind;
            event_buffer[3] = @intCast(@intFromPtr(paste.chunk.ptr));
            event_buffer[4] = @intCast(paste.chunk.len);
            external.emitEvent((&event_buffer).ptr);
        },
        .mouse => |mouse| {
            // const action: u32 = @intCast(@intFromEnum(mouse.));
            switch (mouse) {
                .extended => |extended| {
                    event_buffer[0] = 5;
                    event_buffer[1] = 0; // reserve for future event id
                    event_buffer[2] = @backingInt(extended.button);
                    event_buffer[3] = @backingInt(extended.action);
                    event_buffer[4] = extended.x;
                    event_buffer[5] = extended.y;
                    event_buffer[6] = event.modifiers;
                    external.emitEvent((&event_buffer).ptr);
                },
                else => {},
            }
        },
        else => {},
        // .paste =>|paste| {
        //     const data = [_]u32{ 2, event.paste.kind, event.paste.body_position, event.paste.body_length, event.paste.position, event.paste.length };
        //     emitEvent(&data);
        // },
    }

    // ctx.consumed += handleRawBuffer(ctx, ctx.buffer.items[ctx.consumed..]);
}

export fn Tree_consumeEvents(tree: *Tree, array_buffer: *std.ArrayList(u8), force: bool) u32 {
    var manager = tree.input_manager orelse std.debug.panic("Input manager not enabled", .{});
    const original_mode = manager.mode;
    if (force) {
        manager.setMode(.force);
    }
    const consumed = handleRawBuffer(&manager, array_buffer.items, 0);
    if (force) {
        manager.setMode(original_mode);
    }
    return @intCast(consumed);
}
export fn Tree_getNodeKind(tree: *Tree, node: u32) u32 {
    logger.info("Tree_getNodeKind({*}, {d})", .{ tree, node });
    return @backingInt(tree.getNodeKind(node));
}
export fn Tree_destroyNode(tree: *Tree, node: u32) void {
    logger.info("Tree_destroyNode({*}, {d})", .{ tree, node });
    wasm_try(void, tree.destroyNode(node));
}
export fn Tree_destroyNodeRecursive(tree: *Tree, node: u32) void {
    logger.info("Tree_destroyNodeRecursive({*}, {d})", .{ tree, node });
    wasm_try(void, tree.destroyNodeRecursive(node));
}
pub export fn Tree_appendChild(tree: *Tree, parent: u32, child: u32) u32 {
    logger.info("Tree_appendChild({*}, {d}, {d})", .{ tree, parent, child });
    return @intCast(wasm_try(Tree.Node.NodeId, tree.appendChild(parent, child)));
}
export fn Tree_insertBefore(tree: *Tree, parent: u32, child: u32, before: u32) u32 {
    logger.info("Tree_insertBefore({*}, {d}, {d}, {d})", .{ tree, parent, child, before });
    return @intCast(wasm_try(Tree.Node.NodeId, tree.insertBefore(parent, child, before)));
}
export fn Tree_removeChildren(tree: *Tree, parent: u32) void {
    logger.info("Tree_removeChildren({*}, {d})", .{ tree, parent });
    tree.removeChildren(parent);
}

export fn Tree_removeChild(tree: *Tree, parent: u32, child: u32) void {
    logger.info("Tree_removeChild({*}, {d}, {d})", .{ tree, parent, child });
    wasm_try(void, tree.removeChild(parent, child));
}
export fn Tree_getChildrenCount(tree: *Tree, parent: u32) u32 {
    logger.info("Tree_getChildrenCount({*}, {d})", .{ tree, parent });
    return @intCast(tree.getChildren(parent).items.len);
    // return 0;
}
export fn Tree_getChildren(tree: *Tree, node_id: u32) [*]u32 {
    logger.info("Tree_getChildren({*}, {d})", .{ tree, node_id });
    const reply = replyAllocator();
    const children = tree.getChildren(node_id).items;
    // length-prefixed: [u32 count][ids] so the JS wrapper is self-contained
    const out = wasm_try([]u32, reply.alloc(u32, 1 + children.len));
    out[0] = @intCast(children.len);
    for (children, 0..) |child, i| {
        out[i + 1] = @intCast(child);
    }
    return out.ptr;
}
export fn Tree_getNodeParent(tree: *Tree, node: u32) i32 {
    logger.info("Tree_getNodeParent({*}, {d})", .{ tree, node });
    if (tree.getNode(node).parent) |parent| {
        return @intCast(parent);
    }
    return -1;
}
export fn Tree_appendChildAtIndex(tree: *Tree, parent: u32, child: u32, index: u32) u32 {
    logger.info("Tree_appendChildAtIndex({*}, {d}, {d}, {d})", .{ tree, parent, child, index });
    return @intCast(wasm_try(Tree.Node.NodeId, tree.appendChildAtIndex(parent, child, index)));
}
export fn Tree_getNodeCursorStyle(tree: *Tree, node: u32) u32 {
    logger.info("Tree_getNodeCursorStyle({*}, {d})", .{ tree, node });
    const style = tree.getComputedStyle(node);
    return @backingInt(style.cursor);
}
pub export fn Tree_setStyle(tree: *Tree, node: u32, string: [*:0]u8) void {
    logger.info("Tree_setStyle({*}, {d}, \"{s}\")", .{ tree, node, string });
    defer freeNullTerminatedBuffer(string);
    tree.getNode(node).styles = .{};
    const style_slice = string[0..std.mem.len(string)];
    wasm_try(void, parsers.parseStyleString(tree, node, style_slice));
}
export fn Tree_setStyleProperty(tree: *Tree, node: u32, key: [*:0]u8, value: [*:0]u8) void {
    logger.info("Tree_setStyleProperty({*}, {d}, \"{s}\", \"{s}\")", .{ tree, node, key, value });
    defer freeNullTerminatedBuffer(key);
    defer freeNullTerminatedBuffer(value);

    const key_slice = key[0..std.mem.len(key)];
    const value_slice = value[0..std.mem.len(value)];

    // Use the updated parseStyleProperty that calls tree.setStyleProperty internally
    parsers.parseStyleProperty(tree, node, key_slice, value_slice);
}
export fn Tree_doesNodeExist(tree: *Tree, node: u32) bool {
    return tree.node_map.contains(node);
}

pub export fn Tree_getElementById(tree: *Tree, id: [*:0]u8) u32 {
    logger.info("Tree_getElementById({*}, \"{s}\")", .{ tree, id });
    defer freeNullTerminatedBuffer(id);
    const id_slice = id[0..std.mem.len(id)];
    const result = tree.getElementById(id_slice) orelse NULL;
    return @intCast(result);
}

pub export fn Node_getAttribute(tree: *Tree, node: u32, name: [*:0]u8) ?[*:0]const u8 {
    logger.info("Node_getAttribute({*}, {d}, \"{s}\")", .{ tree, node, name });
    defer freeNullTerminatedBuffer(name);
    const name_slice = name[0..std.mem.len(name)];
    const result = tree.getNode(node).getAttribute(name_slice) orelse {
        // Return null for non-existent attributes
        return null;
    };
    const reply = replyAllocator();
    return wasm_try([:0]u8, reply.dupeSentinel(u8, result, 0)).ptr;
}

export fn Node_setAttribute(tree: *Tree, node_id: u32, name: [*:0]u8, value: [*:0]u8) void {
    tree.invalidateStyles(node_id);
    logger.info("Node_setAttribute({*}, {d}, \"{s}\", \"{s}\")", .{ tree, node_id, name, value });
    defer freeNullTerminatedBuffer(name);
    defer freeNullTerminatedBuffer(value);
    const name_slice = name[0..std.mem.len(name)];
    const value_slice = value[0..std.mem.len(value)];
    const node = tree.getNode(node_id);
    wasm_try(void, node.setAttribute(name_slice, value_slice));
}

export fn Node_hasAttribute(tree: *Tree, node_id: u32, name: [*:0]u8) bool {
    logger.info("Node_hasAttribute({*}, {d}, \"{s}\")", .{ tree, node_id, name });
    defer freeNullTerminatedBuffer(name);
    const name_slice = name[0..std.mem.len(name)];
    const node = tree.getNode(node_id);
    return node.hasAttribute(name_slice);
}

export fn Node_removeAttribute(tree: *Tree, node_id: u32, name: [*:0]u8) void {
    tree.invalidateStyles(node_id);
    logger.info("Node_removeAttribute({*}, {d}, \"{s}\")", .{ tree, node_id, name });
    defer freeNullTerminatedBuffer(name);
    const name_slice = name[0..std.mem.len(name)];
    const node = tree.getNode(node_id);
    node.removeAttribute(name_slice);
}

pub export fn Tree_hitTest(tree: *Tree, x: f32, y: f32, filter: u8) [*]u32 {
    logger.info("Tree_hitTest({*}, {d}, {d}, {d})", .{ tree, x, y, filter });
    const reply = replyAllocator();
    const out = wasm_try([]u32, reply.alloc(u32, 2));
    const hit_result = tree.hitTest(.{ .x = x, .y = y }, filter) orelse {
        out[0] = 0;
        out[1] = 0;
        return out.ptr;
    };
    out[0] = @intCast(hit_result.external_id);
    out[1] = @backingInt(hit_result.item_type);
    return out.ptr;
}
pub export fn Tree_hitTestList(tree: *Tree, x: f32, y: f32, filter: u8) [*]u32 {
    logger.info("Tree_hitTestList({*}, {d}, {d}, {d})", .{ tree, x, y, filter });
    const reply = replyAllocator();
    var list: std.ArrayList(RenderList.HitTestResult) = .empty;
    wasm_try(void, tree.hitTestList(&list, reply, .{ .x = x, .y = y }, filter));
    const out = wasm_try([]u32, reply.alloc(u32, list.items.len * 2 + 2));
    for (list.items, 0..) |result, i| {
        out[i * 2] = @intCast(result.external_id);
        out[i * 2 + 1] = @backingInt(result.item_type);
    }
    out[list.items.len * 2] = 0;
    out[list.items.len * 2 + 1] = 0;
    return out.ptr;
}
/// Deprecated no-op: hit-test results are reply-arena owned; nothing to free.
pub export fn Tree_deinitHitTestList(list: [*:0]u32) void {
    _ = list;
}

pub export fn Tree_getNodeInvalidationStatus(tree: *Tree, node: u32) u32 {
    logger.info("Tree_getNodeInvalidationStatus({*}, {d})", .{ tree, node });
    const node_obj = tree.getNode(node);

    return node_obj.regenerate_level.toInt();
}

export fn Tree_getNodeContains(tree: *Tree, root: u32, node: u32) bool {
    return tree.getNodeContains(root, node);
}

export fn Node_getScrollTop(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getScrollTop({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).scroll_offset.y;
}
export fn Node_getScrollLeft(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getScrollLeft({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getScrollLeft();
}

export fn Node_setScrollTop(tree: *Tree, node_id: u32, value: f32) void {
    logger.info("Node_setScrollTop({*}, {d}, {d})", .{ tree, node_id, value });
    tree.getNode(node_id).setScrollTop(tree, value);
}

export fn Node_setScrollLeft(tree: *Tree, node_id: u32, value: f32) void {
    logger.info("Node_setScrollLeft({*}, {d}, {d})", .{ tree, node_id, value });
    tree.getNode(node_id).setScrollLeft(tree, value);
}

export fn Node_getScrollHeight(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getScrollHeight({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getScrollHeight(tree);
}

export fn Node_getScrollWidth(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getScrollWidth({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getScrollWidth(tree);
}

export fn Node_getClientHeight(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getClientHeight({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getClientHeight(tree);
}

export fn Node_getClientWidth(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getClientWidth({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getClientWidth(tree);
}

export fn Node_getScrollTopMax(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getScrollTopMax({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getScrollTopMax(tree);
}

export fn Node_getScrollLeftMax(tree: *Tree, node_id: u32) f32 {
    logger.info("Node_getScrollLeftMax({*}, {d})", .{ tree, node_id });
    return tree.getNode(node_id).getScrollLeftMax(tree);
}

export fn Node_canScroll(tree: *Tree, node_id: u32, direction: u8, delta: f32) bool {
    logger.info("Node_canScroll({*}, {d}, {d}, {d})", .{ tree, node_id, direction, delta });
    const node = tree.getNode(node_id);
    return node.canScroll(tree, @fromBackingInt(@intCast(direction)), delta);
}

const tree_dump_logger = std.log.scoped(.tree_dump);
const ArrayListWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub const Error = error{OutOfMemory};

    pub fn print(self: ArrayListWriter, comptime format_str: []const u8, args: anytype) Error!void {
        var buf: [1024]u8 = undefined;
        const formatted = std.fmt.bufPrint(&buf, format_str, args) catch return error.OutOfMemory;
        try self.writeAll(formatted);
    }

    pub fn writeAll(self: ArrayListWriter, bytes: []const u8) Error!void {
        self.list.appendSlice(self.allocator, bytes) catch return error.OutOfMemory;
    }

    pub fn writeByte(self: ArrayListWriter, byte: u8) Error!void {
        self.list.append(self.allocator, byte) catch return error.OutOfMemory;
    }

    pub fn writeByteNTimes(self: ArrayListWriter, byte: u8, n: usize) Error!void {
        for (0..n) |_| {
            try self.writeByte(byte);
        }
    }

    pub fn splatByteAll(self: ArrayListWriter, byte: u8, n: usize) Error!void {
        try self.writeByteNTimes(byte, n);
    }
};

pub export fn Tree_dump(tree: *Tree) [*:0]u8 {
    const reply = replyAllocator();
    var list: std.ArrayList(u8) = .empty;
    const list_writer = ArrayListWriter{ .list = &list, .allocator = reply };
    wasm_try(void, tree.print(list_writer));
    wasm_try(void, list.append(reply, 0));
    return @ptrCast(list.items.ptr);
}
pub export fn Tree_dumpLayoutTree(tree: *Tree) void {
    var array_list: std.ArrayList(u8) = .empty;
    defer array_list.deinit(wasm_allocator);
    const list_writer = ArrayListWriter{ .list = &array_list, .allocator = wasm_allocator };
    wasm_try(void, tree.layout_tree.printRoot(list_writer));
    tree_dump_logger.info("{s}", .{array_list.items});
}
pub export fn Node_setText(tree: *Tree, node: u32, text: [*:0]u8) void {
    logger.info("Node_setText({*}, {d}, \"{s}\")", .{ tree, node, text });
    defer freeNullTerminatedBuffer(text);
    const text_slice = text[0..std.mem.len(text)];
    wasm_try(void, tree.setText(node, text_slice));
}
export fn Node_getText(tree: *Tree, node: u32) [*]u8 {
    logger.info("Node_getText({*}, {d})", .{ tree, node });
    const reply = replyAllocator();
    const bytes = tree.getNode(node).text.bytes.items;
    // length-prefixed: [u32 len][bytes] so the JS wrapper is self-contained
    const out = wasm_try([]u8, reply.alloc(u8, 4 + bytes.len));
    std.mem.writeInt(u32, out[0..4], @intCast(bytes.len), .little);
    @memcpy(out[4..], bytes);
    return out.ptr;
}
export fn Node_getTextLength(tree: *Tree, node: u32) u32 {
    logger.info("Node_getTextLength({*}, {d})", .{ tree, node });
    const node_obj = tree.getNode(node);
    return @intCast(node_obj.text.length());
}

export fn Node_appendData(tree: *Tree, node_id: u32, data: [*:0]u8) void {
    logger.info("Node_appendData({*}, {d}, \"{s}\")", .{ tree, node_id, data });
    defer freeNullTerminatedBuffer(data);
    const data_slice = data[0..std.mem.len(data)];
    const node = tree.getNode(node_id);
    wasm_try(void, node.appendData(tree, data_slice));
}

export fn Node_insertData(tree: *Tree, node_id: u32, offset: u32, data: [*:0]u8) void {
    logger.info("Node_insertData({*}, {d}, {d}, \"{s}\")", .{ tree, node_id, offset, data });
    defer freeNullTerminatedBuffer(data);
    const data_slice = data[0..std.mem.len(data)];
    const node = tree.getNode(node_id);
    wasm_try(void, node.insertData(tree, offset, data_slice));
}

export fn Node_replaceData(tree: *Tree, node_id: u32, offset: u32, count: u32, data: [*:0]u8) void {
    logger.info("Node_replaceData({*}, {d}, {d}, {d}, \"{s}\")", .{ tree, node_id, offset, count, data });
    defer freeNullTerminatedBuffer(data);
    const data_slice = data[0..std.mem.len(data)];
    const node = tree.getNode(node_id);
    wasm_try(void, node.replaceData(tree, offset, count, data_slice));
}

export fn Node_deleteData(tree: *Tree, node_id: u32, offset: u32, count: u32) void {
    logger.info("Node_deleteData({*}, {d}, {d}, {d})", .{ tree, node_id, offset, count });
    const node = tree.getNode(node_id);
    wasm_try(void, node.deleteData(tree, offset, count));
}

export fn Node_isEditingHost(tree: *Tree, node_id: u32) bool {
    logger.info("Node_isEditingHost({*}, {d})", .{ tree, node_id });
    const node = tree.getNode(node_id);
    return node.isEditingHost(tree);
}

export fn Node_isEditable(tree: *Tree, node_id: u32) bool {
    logger.info("Node_isEditable({*}, {d})", .{ tree, node_id });
    const node = tree.getNode(node_id);
    return node.isEditable(tree);
}

export fn Node_getEditingHost(tree: *Tree, node_id: u32) u32 {
    logger.info("Node_getEditingHost({*}, {d})", .{ tree, node_id });
    const node = tree.getNode(node_id);
    if (node.getEditingHost(tree)) |host_id| {
        return @intCast(host_id);
    }
    return NULL;
}

export fn Node_inSameEditingHost(tree: *Tree, node_id: u32, other_id: u32) bool {
    logger.info("Node_inSameEditingHost({*}, {d}, {d})", .{ tree, node_id, other_id });
    const node = tree.getNode(node_id);
    return node.inSameEditingHost(tree, other_id);
}

export fn Node_compareDocumentPosition(tree: *Tree, node_id: u32, other_id: u32) u16 {
    logger.info("Node_compareDocumentPosition({*}, {d}, {d})", .{ tree, node_id, other_id });
    const node = tree.getNode(node_id);
    return node.compareDocumentPosition(tree, other_id);
}

const Node = @import("tree/Node.zig");
const ClientRect = Node.ClientRect;

export fn Node_getClientRects(tree: *Tree, node_id: u32) [*]f32 {
    logger.info("Node_getClientRects({*}, {d})", .{ tree, node_id });
    const node = tree.getNode(node_id);

    const reply = replyAllocator();
    const rects = wasm_try([]ClientRect, node.getClientRects(tree, reply));

    // Convert to flat f32 array with flag format
    // Format: [flag, x, y, width, height, ...] where flag is 1 for valid rect, 0 for end
    const result_size = rects.len * 5 + 1; // 5 values per rect + sentinel
    const result = wasm_try([]f32, reply.alloc(f32, result_size));

    var idx: usize = 0;
    for (rects) |rect| {
        result[idx] = 1.0; // flag: valid rect
        result[idx + 1] = rect.x;
        result[idx + 2] = rect.y;
        result[idx + 3] = rect.width;
        result[idx + 4] = rect.height;
        idx += 5;
    }

    // End marker - just a single 0
    result[idx] = 0.0;

    return result.ptr;
}

export fn Node_getBoundingClientRect(tree: *Tree, node_id: u32) [*]f32 {
    logger.info("Node_getBoundingClientRect({*}, {d})", .{ tree, node_id });
    const node = tree.getNode(node_id);
    const rect = node.getBoundingClientRect(tree);

    const reply = replyAllocator();
    const out = wasm_try([]f32, reply.alloc(f32, 4));
    out[0] = rect.x;
    out[1] = rect.y;
    out[2] = rect.width;
    out[3] = rect.height;
    return out.ptr;
}

pub export fn Tree_computeStyles(tree: *Tree) void {
    logger.info("Tree_computeStyles({*})", .{tree});
    wasm_try(void, tree.computeStyles());
}
pub export fn Tree_buildLayoutTree(tree: *Tree) void {
    logger.info("Tree_buildLayoutTree({*})", .{tree});
    wasm_try(void, tree.buildLayoutTree());
}
pub export fn Tree_computeLayout(tree: *Tree, width: [*:0]u8, height: [*:0]u8) void {
    logger.info("Tree_computeLayout({*}, \"{s}\", \"{s}\")", .{ tree, width, height });
    defer freeNullTerminatedBuffer(width);
    defer freeNullTerminatedBuffer(height);
    const width_slice = std.mem.trim(u8, width[0..std.mem.len(width)], " \n\t\r");
    const height_slice = std.mem.trim(u8, height[0..std.mem.len(height)], " \n\t\r");
    wasm_try(void, tree.computeLayout(wasm_allocator, .{
        .x = width: {
            if (std.mem.eql(u8, width_slice, "min-content")) {
                break :width .min_content;
            } else if (std.mem.eql(u8, width_slice, "max-content")) {
                break :width .max_content;
            }
            const definite = wasm_try(f32, std.fmt.parseFloat(f32, width_slice));
            break :width .{ .definite = definite };
        },
        .y = height: {
            if (std.mem.eql(u8, height_slice, "min-content")) {
                break :height .min_content;
            } else if (std.mem.eql(u8, height_slice, "max-content")) {
                break :height .max_content;
            }
            const definite = wasm_try(f32, std.fmt.parseFloat(f32, height_slice));
            break :height .{ .definite = definite };
        },
    }));
}
pub export fn Tree_getBoundaryPointPosition(tree: *Tree, node_id: u32, offset: u32) [*]f32 {
    logger.info("Tree_getBoundaryPointPosition({*}, {d}, {d})", .{ tree, node_id, offset });
    const reply = replyAllocator();
    const out = wasm_try([]f32, reply.alloc(f32, 2));
    const position = tree.getBoundaryPointPosition(node_id, offset);
    out[0] = position.x;
    out[1] = position.y;
    return out.ptr;
}
pub export fn Tree_paintSimple(tree: *Tree, renderer: *Renderer) void {
    logger.info("Tree_paint({*}, {*})", .{ tree, renderer });
    const stdout_writer = WasiStdoutWriter{};
    wasm_try(void, tree.paint(renderer, stdout_writer, .simple));
}
pub export fn Tree_paintApp(tree: *Tree, renderer: *Renderer) void {
    logger.info("Tree_paintApp({*}, {*})", .{ tree, renderer });
    const stdout_writer = WasiStdoutWriter{};
    wasm_try(void, tree.paint(renderer, stdout_writer, .app));
}

/// Paint output goes to WASI stdout; the JS host's fd_write shim forwards it
/// to the configured write stream (the terminal).
const WasiStdoutWriter = struct {
    pub const Error = error{WriteFailed};

    pub fn writeAll(_: WasiStdoutWriter, bytes: []const u8) Error!void {
        if (!is_wasm) return;
        var iovs = [_]std.os.wasi.ciovec_t{.{ .base = bytes.ptr, .len = bytes.len }};
        var nwritten: usize = 0;
        _ = std.os.wasi.fd_write(1, &iovs, 1, &nwritten);
    }

    pub fn writeByte(self: WasiStdoutWriter, byte: u8) Error!void {
        try self.writeAll(&[_]u8{byte});
    }

    pub fn writeByteNTimes(self: WasiStdoutWriter, byte: u8, n: usize) Error!void {
        for (0..n) |_| try self.writeByte(byte);
    }

    pub fn splatByteAll(self: WasiStdoutWriter, byte: u8, n: usize) Error!void {
        try self.writeByteNTimes(byte, n);
    }

    pub fn print(self: WasiStdoutWriter, comptime format: []const u8, args: anytype) Error!void {
        var buf: [1024]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, format, args) catch return error.WriteFailed;
        try self.writeAll(slice);
    }
};

const NoOpWriter = struct {
    pub const Error = error{};

    pub fn print(_: NoOpWriter, comptime _: []const u8, _: anytype) Error!void {}
    pub fn writeAll(_: NoOpWriter, _: []const u8) Error!void {}
    pub fn writeByte(_: NoOpWriter, _: u8) Error!void {}
    pub fn writeByteNTimes(_: NoOpWriter, _: u8, _: usize) Error!void {}
    pub fn splatByteAll(_: NoOpWriter, _: u8, _: usize) Error!void {}
};

pub export fn Tree_caretPositionFromPoint(tree: *Tree, x: f32, y: f32) [*]u32 {
    const reply = replyAllocator();
    const out = wasm_try([]u32, reply.alloc(u32, 2));
    const boundary_point = tree.caretPositionFromPoint(.{ .x = x, .y = y }) orelse {
        out[0] = NULL;
        out[1] = 0;
        return out.ptr;
    };
    out[0] = @intCast(boundary_point.node_id);
    out[1] = @intCast(boundary_point.offset);
    return out.ptr;
}

export fn Tree_createSelection(tree: *Tree, start_node: u32, start_offset: u32, end_node: u32, end_offset: u32) Tree.Selection.Id {
    return @intCast(wasm_try(Tree.Selection.Id, tree.createSelection(
        .{ .node_id = start_node, .offset = start_offset },
        if (end_node == NULL) null else .{ .node_id = end_node, .offset = end_offset },
    )));
}
export fn Selection_getFocusPosition(tree: *Tree, selection_id: Tree.Selection.Id) [*]f32 {
    const reply = replyAllocator();
    const out = wasm_try([]f32, reply.alloc(f32, 2));
    const selection = tree.getSelection(selection_id);
    const position = selection.getFocusPosition(tree) orelse {
        out[0] = 0;
        out[1] = 0;
        return out.ptr;
    };
    out[0] = position.x;
    out[1] = position.y;
    return out.ptr;
}
export fn Selection_getAnchor(tree: *Tree, selection_id: Tree.Selection.Id) [*]u32 {
    const reply = replyAllocator();
    const out = wasm_try([]u32, reply.alloc(u32, 2));
    const selection = tree.getSelection(selection_id);
    const anchor = selection.getAnchor(tree);
    out[0] = @intCast(anchor.node_id);
    out[1] = @intCast(anchor.offset);
    return out.ptr;
}

export fn Tree_removeSelection(tree: *Tree, selection_id: Tree.Selection.Id) void {
    tree.removeSelection(selection_id);
}
export fn Selection_getDirection(tree: *Tree, selection_id: Tree.Selection.Id) i32 {
    const selection = tree.getSelection(selection_id);
    return @backingInt(selection.direction);
}
export fn Selection_getFocus(tree: *Tree, selection_id: Tree.Selection.Id) [*]u32 {
    const reply = replyAllocator();
    const out = wasm_try([]u32, reply.alloc(u32, 2));
    const selection = tree.getSelection(selection_id);
    const focus = selection.getFocus(tree);
    out[0] = @intCast(focus.node_id);
    out[1] = @intCast(focus.offset);
    return out.ptr;
}
export fn Selection_setAnchor(tree: *Tree, selection_id: Tree.Selection.Id, node_id: u32, offset: u32) void {
    const selection = tree.getSelection(selection_id);
    wasm_try(void, selection.setAnchor(tree, .{ .node_id = node_id, .offset = offset }));
}
export fn Selection_setFocus(tree: *Tree, selection_id: Tree.Selection.Id, node_id: u32, offset: u32) void {
    logger.debug("Selection_setFocus({d}, {d}, {d})", .{ selection_id, node_id, offset });
    const selection = tree.getSelection(selection_id);
    selection.setFocus(tree, .{ .node_id = node_id, .offset = offset }) catch |e| {
        logger.err("Error {s} Selection_setFocus({d}, {d}, {d})", .{ @errorName(e), selection_id, node_id, offset });
    };
}

export fn Selection_modify(
    tree: *Tree,
    selection_id: Tree.Selection.Id,
    alter: u8,
    direction: u8,
    granularity: u8,
    ghost_position: f32,
) void {
    logger.debug("Selection_modify({d}, {d}, {d}, {d}, {d})", .{ selection_id, alter, direction, granularity, ghost_position });
    const selection = tree.getSelection(selection_id);
    wasm_try(void, selection.modify(
        tree,
        @as(Tree.Selection.Alteration, @fromBackingInt(@intCast(alter))),
        @as(Tree.Selection.ExtendDirection, @fromBackingInt(@intCast(direction))),
        @as(Tree.Selection.ExtendGranularity, @fromBackingInt(@intCast(granularity))),
        if (ghost_position == -1) null else ghost_position,
    ));
}

export fn Selection_deleteFromDocument(tree: *Tree, selection_id: Tree.Selection.Id) void {
    logger.debug("Selection_deleteFromDocument({d})", .{selection_id});
    const selection = tree.getSelection(selection_id);
    wasm_try(void, selection.deleteFromDocument(tree));
}

export fn Selection_collapseToStart(tree: *Tree, selection_id: Tree.Selection.Id) void {
    logger.debug("Selection_collapseToStart({d})", .{selection_id});
    const selection = tree.getSelection(selection_id);
    wasm_try(void, selection.collapseToStart(tree));
}

export fn Selection_collapseToEnd(tree: *Tree, selection_id: Tree.Selection.Id) void {
    logger.debug("Selection_collapseToEnd({d})", .{selection_id});
    const selection = tree.getSelection(selection_id);
    wasm_try(void, selection.collapseToEnd(tree));
}

export fn Selection_isCollapsed(tree: *Tree, selection_id: Tree.Selection.Id) bool {
    const selection = tree.getSelection(selection_id);
    return selection.isCollapsed();
}

export fn Range_deleteContents(tree: *Tree, selection_id: Tree.Selection.Id) void {
    logger.debug("Range_deleteContents({d})", .{selection_id});
    const selection = tree.getSelection(selection_id);
    const range = selection.getRange(tree);
    wasm_try(void, range.deleteContents(tree));
}

export fn Range_setStart(tree: *Tree, selection_id: Tree.Selection.Id, node_id: u32, offset: u32) void {
    logger.debug("Range_setStart({d}, {d}, {d})", .{ selection_id, node_id, offset });
    const selection = tree.getSelection(selection_id);
    const range = selection.getRange(tree);
    wasm_try(void, range.setStart(tree, node_id, offset));
}

export fn Range_setEnd(tree: *Tree, selection_id: Tree.Selection.Id, node_id: u32, offset: u32) void {
    logger.debug("Range_setEnd({d}, {d}, {d})", .{ selection_id, node_id, offset });
    const selection = tree.getSelection(selection_id);
    const range = selection.getRange(tree);
    wasm_try(void, range.setEnd(tree, node_id, offset));
}

export fn Range_collapse(tree: *Tree, selection_id: Tree.Selection.Id, to_start: bool) void {
    logger.debug("Range_collapse({d}, {d})", .{ selection_id, to_start });
    const selection = tree.getSelection(selection_id);
    const range = selection.getRange(tree);
    wasm_try(void, range.collapse(tree, to_start));
}

export fn Range_insertNode(tree: *Tree, selection_id: Tree.Selection.Id, node_id: u32) void {
    logger.debug("Range_insertNode({d}, {d})", .{ selection_id, node_id });
    const selection = tree.getSelection(selection_id);
    const range = selection.getRange(tree);
    wasm_try(void, range.insertNode(tree, node_id));
}

// export fn Selection_extendBy(
//     tree: *Tree,
//     selection_id: Tree.Selection.Id,
//     granularity: u8,
//     direction: u8,
//     ghost_horizontal_position: f32,
//     root_node_id: u32,
// ) void {
//     logger.debug("Selection_extendBy({d}, {d}, {d}, {d}, {d})", .{ selection_id, granularity, direction, ghost_horizontal_position, root_node_id });
//     const selection = tree.getSelection(selection_id);
//     // selection.extendBy(tree, @as(Tree.Selection.ExtendGranularity, @enumFromInt(granularity)), @as(Tree.Selection.ExtendDirection, @enumFromInt(direction)), if (has_ghost_position) ghost_horizontal_position else null, root_node_id) catch |e| {
//     //     logger.err("Error {s} Selection_extendBy({d}, {d}, {d}, {d}, {d})", .{ @errorName(e), selection_id, granularity, direction, ghost_horizontal_position, root_node_id });
//     // };
//     wasm_try(void, selection.extendBy(
//         tree,
//         @as(Tree.Selection.ExtendGranularity, @enumFromInt(granularity)),
//         @as(Tree.Selection.ExtendDirection, @enumFromInt(direction)),
//         if (ghost_horizontal_position == NULL) null else ghost_horizontal_position,
//         root_node_id,
//     ));
// }

// export fn Selection_getHorizontalOffset(
//     tree: *Tree,
//     node_id: u32,
//     offset: u32,
// ) f32 {
//     // return Tree.Selection.getHorizontalOffset(tree, .{ .node_id = node_id, .offset = offset }) orelse 0;
// }

// pub export fn Renderer_renderToStdout(renderer: *Renderer, tree: *Tree, clear_screen: bool) void {
//     _ = clear_screen; // New renderer doesn't use clear_screen parameter
//     logger.info("Renderer_renderToStdout({*}, {*})", .{ renderer, tree });
//     wasm_try(void, renderer.render(&tree.render_list, std.io.getStdOut().writer().any(), .simple));
// }
// pub export fn Renderer_renderToErr(renderer: *Renderer, tree: *Tree, clear_screen: bool) void {
//     _ = clear_screen; // New renderer doesn't use clear_screen parameter
//     logger.info("Renderer_renderToErr({*}, {*})", .{ renderer, tree });
//     wasm_try(void, renderer.render(&tree.render_list, std.io.getStdErr().writer().any(), .app));
// }
pub export fn Renderer_init() *Renderer {
    logger.info("Renderer_init()", .{});
    const renderer = wasm_try(*Renderer, wasm_allocator.create(Renderer));
    renderer.* = wasm_try(Renderer, Renderer.init(wasm_allocator));
    return renderer;
}
pub export fn Renderer_deinit(renderer: *Renderer) void {
    logger.info("Renderer_deinit({*})", .{renderer});
    renderer.deinit();
    wasm_allocator.destroy(renderer);
}
export fn Renderer_getNodeAt(renderer: *Renderer, tree: *Tree, x: f32, y: f32, filter: u8) u32 {
    _ = renderer; // New renderer doesn't need to be involved in hit testing
    logger.info("Renderer_getNodeAt({*}, {d}, {d}, {d})", .{ tree, x, y, filter });

    // Use the tree's hit testing functionality with the provided filter
    const hit_result = tree.hitTest(.{ .x = x, .y = y }, filter) orelse return NULL;

    return @intCast(hit_result.external_id);
}

export const EventBuffer: [128]u8 = @splat(1);

fn readBufferWithLength(memory: [*]u8) []const u8 {
    const len = std.mem.readInt(u32, memory[0..4], .little);
    const slice = memory[4 .. len + 4];
    return slice;
}
fn freeBufferWithLength(memory: [*]u8) void {
    const len = std.mem.readInt(u32, memory[0..4], .little);
    freeBuffer(memory, len + 4);
}
export fn TermInfo_initFromMemory(memory: [*]u8) *TermInfo {
    logger.info("TermInfo_initFromMemory({*})", .{memory});
    const slice = readBufferWithLength(memory);
    defer freeBufferWithLength(memory);
    const term_info = wasm_try(*TermInfo, wasm_allocator.create(TermInfo));
    term_info.* = wasm_try(TermInfo, TermInfo.initFromMemory(wasm_allocator, slice));
    return term_info;
}
export fn TermInfo_deinit(term_info: *TermInfo) void {
    logger.info("TermInfo_deinit({*})", .{term_info});
    term_info.deinit();
    wasm_allocator.destroy(term_info);
}

// extern fn emitData(data: [*]u8, len: usize) void;

export fn ArrayList_init() *std.ArrayList(u8) {
    const ptr = wasm_try(*std.ArrayList(u8), wasm_allocator.create(std.ArrayList(u8)));
    ptr.* = .empty;
    return ptr;
}
export fn ArrayList_deinit(list: *std.ArrayList(u8)) void {
    list.deinit(wasm_allocator);
    wasm_allocator.destroy(list);
}

export fn ArrayList_appendUnusedSlice(list: *std.ArrayList(u8), capacity: usize) [*]u8 {
    wasm_try(void, list.ensureUnusedCapacity(wasm_allocator, capacity));
    list.items.len += capacity;
    const unused_capacity_pointer = list.items[list.items.len - capacity ..];
    return unused_capacity_pointer.ptr;
}
export fn ArrayList_getLength(list: *std.ArrayList(u8)) usize {
    return list.items.len;
}
export fn ArrayList_setLength(list: *std.ArrayList(u8), length: usize) void {
    list.items.len = length;
}
export fn memcopy(dest: [*]u8, src: [*]u8, n: usize) void {
    std.mem.copyForwards(u8, dest[0..n], src[0..n]);
}
export fn ArrayList_getPointer(list: *std.ArrayList(u8)) [*]u8 {
    return list.items.ptr;
}
export fn ArrayList_clearRetainingCapacity(list: *std.ArrayList(u8)) void {
    list.clearRetainingCapacity();
}
export fn ArrayList_dump(list: *std.ArrayList(u8)) void {
    std.debug.print("ArrayList: {any}\n", .{list.items});
}

const handleRawBuffer = @import("cmd/input.zig").handleRawBuffer;

export fn detectLeaks() bool {
    // the reply arena retains working-set capacity by design; release it so
    // only genuine leaks are counted
    _ = reply_arena.reset(.free_all);
    if (builtin.mode == .debug) {
        const leaked = gpa.detectLeaks();
        return leaked > 0;
    }
    return false;
}

fn allocTestString(str: []const u8) [*:0]u8 {
    const ptr: [*:0]u8 = allocNullTerminatedBuffer(str.len);
    std.mem.copyForwards(u8, ptr[0..str.len], str);
    return ptr;
}
const Cursor = @import("styles/cursor.zig").Cursor;

test {
    _ = @import("./tree/Range.zig");
    _ = @import("./testing/snapshot.zig");
    _ = @import("./tree/invalidation_oracle_test.zig");
    _ = @import("./layout/v2/layout_snapshot_test.zig");
    _ = @import("./layout/v2/scroll_snapshot_test.zig");
    _ = @import("./tree/selection_snapshot_test.zig");
    _ = @import("./tree/caret_position_test.zig");
    _ = @import("./uni/GraphemeBreak.zig");
    _ = @import("./tree/NodeIterator.zig");
    _ = @import("./layout/v2/mod.zig");
    _ = @import("./uni/LineBreakStream.zig");
    _ = @import("./uni/WordBreak.zig");
    _ = @import("./renderer/v2/mod.zig");
    // New line-builder tests
    _ = @import("./layout/v2/line-builder/Tokenizer.zig");
    _ = @import("./layout/v2/line-builder/WhitespaceRules.zig");
    _ = @import("./layout/v2/line-builder/wrap.zig");
    _ = @import("./layout/v2/line-builder/TextAlignment.zig");
    _ = @import("./layout/v2/line-builder/compute.zig");
    // RenderListBuilder tests
    _ = @import("./layout/v2/RenderListBuilder.zig");
    // Playground for testing WASM API
    _ = @import("./playground.zig");
}
