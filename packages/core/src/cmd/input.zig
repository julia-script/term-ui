const std = @import("std");
const AnyInputManager = @import("input/manager.zig").AnyInputManager;
const Collector = @import("input/manager.zig").Collector;
const Event = @import("input/manager.zig").Event;
const Match = @import("input/manager.zig").Match;
const escape = @import("input/manager.zig").escape;
const handleTerminalInfo = @import("handle-term-info.zig").handleTerminalInfo;
const handleCsi = @import("handle-csi.zig").handleCsi;
const logger = @import("input/manager.zig").logger;
const root = @import("root");

fn matchStart(needle: []const u8, haystack: []const u8) Match {
    var i: usize = 0;
    while (i < needle.len and i < haystack.len) {
        if (needle[i] != haystack[i]) {
            return .nomatch;
        }
        i += 1;
    }
    if (i == needle.len) {
        return .{ .match = i };
    }
    return .{ .partial = {} };
}
fn handlePaste(manager: *AnyInputManager, buffer: []const u8, position: usize) Match {
    logger.info("try handlePaste", .{});
    var cursor = position;
    const is_start = blk: {
        if (manager.modeIs(.paste)) {
            logger.debug("is not start", .{});
            break :blk false;
        }
        if (buffer.len - position < PASTE_START.len) {
            logger.debug("not enough bytes", .{});
            return .nomatch;
        }
        if (std.mem.eql(u8, buffer[position .. position + PASTE_START.len], PASTE_START)) {
            logger.debug("is start", .{});
            cursor += PASTE_START.len;
            break :blk true;
        }
        return .nomatch;
    };
    while (cursor < buffer.len) {
        if (buffer[cursor] != ESC) {
            cursor += 1;
            continue;
        }
        switch (matchStart(PASTE_END, buffer[cursor..])) {
            .nomatch => {
                logger.debug("nomatch", .{});
                cursor += 1;
                continue;
            },
            .match => |len| {
                logger.debug("match", .{});
                cursor += len;
                manager.setMode(.normal);
                const kind: Event.PasteChunkKind = if (is_start) .all else .end;
                manager.emitPasteChunk(kind, buffer[position..cursor]);
                return .{ .match = cursor - position };
            },
            .partial => {
                logger.debug("partial", .{});
                // if we have an incomplete match, emit the chunk so far without the partial match
                // if it's start but not end, emit as "start", if it's neither start or end, emit as "chunk"
                const kind: Event.PasteChunkKind = if (is_start) .start else .chunk;
                // signal that we're in paste mode
                manager.setMode(.paste);

                manager.emitPasteChunk(kind, buffer[position..cursor]);

                return .{ .partial = {} };
            },
        }
    }

    const kind: Event.PasteChunkKind = if (is_start) .start else .chunk;
    manager.setMode(.paste);
    logger.debug("emitPasteChunk {s}", .{@tagName(kind)});
    manager.emitPasteChunk(kind, buffer[position..]);

    return .{ .match = cursor - position };
}

const ESC: u8 = '\x1b';
const ESC_SLICE: []const u8 = &[_]u8{ESC};

fn handleRawChar(manager: *AnyInputManager, buffer: []const u8, position: usize) Match {
    logger.info("try handleRawChar", .{});
    logger.info("[BUFFER]: {s}", .{buffer});
    var cursor: usize = position;

    var iter = std.unicode.Utf8Iterator{
        .bytes = buffer,
        .i = cursor,
    };
    while (iter.i < buffer.len) {
        const byte = buffer[iter.i];
        if (byte == ESC) {
            if (manager.modeIs(.force)) {
                manager.emitNamed(.escape, .press, 0, buffer[cursor .. cursor + 1]);
                cursor += 1;
                manager.setMode(.normal);
                continue;
            } else {
                break;
            }
        }
        const codepoint = iter.nextCodepoint() orelse break;
        manager.emitInterpretedCodepoint(codepoint, 0, buffer[cursor..iter.i]);
        cursor = iter.i;
    }
    // if we didn't consume any bytes, return nomatch
    if (cursor == position) {
        return .nomatch;
    }
    return .{ .match = cursor - position };
}
fn handleFocusEvent(manager: *AnyInputManager, buffer: []const u8, position: usize) Match {
    logger.info("try handleFocusEvent", .{});
    if (buffer.len - position < 3) {
        return .nomatch;
    }
    const seq = buffer[position .. position + 3];
    if (std.mem.eql(u8, seq, "\x1b[I")) {
        manager.emitFocus(.in, seq);
        return .{ .match = 3 };
    }
    if (std.mem.eql(u8, seq, "\x1b[O")) {
        manager.emitFocus(.out, seq);
        return .{ .match = 3 };
    }
    return .nomatch;
}

fn handleSequence(manager: *AnyInputManager, buffer: []const u8, position: usize) Match {
    logger.info("try handleSequence", .{});
    {
        const match = handleFocusEvent(manager, buffer, position);
        switch (match) {
            .nomatch => {},
            else => return match,
        }
    }
    {
        const match = handlePaste(manager, buffer, position);
        switch (match) {
            .nomatch => {},
            else => return match,
        }
    }
    {
        const match = handleTerminalInfo(manager, buffer, position);
        switch (match) {
            .nomatch => {},
            else => return match,
        }
    }
    {
        const match = handleCsi(manager, buffer, position);
        switch (match) {
            .nomatch => {},
            else => return match,
        }
    }
    return .nomatch;
}

const PASTE_START = "\x1b[200~";
const PASTE_END = "\x1b[201~";

pub fn handleRawBuffer(manager: *AnyInputManager, buffer: []const u8, position: usize) usize {
    logger.info("try handleRawBuffer in '{s}' mode", .{@tagName(manager.mode)});
    defer logger.info("finished handleRawBuffer in '{s}' mode", .{@tagName(manager.mode)});
    // var buffer = input[position..];
    var cursor: usize = position;

    // if we're in paste mode, continue until we find the paste end
    if (manager.modeIs(.paste)) {
        const match = handlePaste(manager, buffer, cursor);
        switch (match) {
            .nomatch => {},
            .match => |consumed| {
                cursor += consumed;
            },
            .partial => {
                unreachable;
            },
        }
    }
    while (cursor < buffer.len) {
        const current_cursor = cursor;

        {
            const match = handleRawChar(manager, buffer, cursor);
            switch (match) {
                .nomatch => {},
                .match => |consumed| {
                    cursor += consumed;
                    continue;
                },
                .partial => {
                    unreachable;
                },
            }
            if (cursor >= buffer.len) {
                break;
            }
        }

        {
            const match = handleSequence(manager, buffer, cursor);

            // If it's a partial match, it's either an incomplete sequence or an ambiguous ESC char
            // if force is true, we emit the esc event
            // otherwise we wait for more buffer to disambiguate it
            switch (match) {
                .nomatch => {},
                .match => |len| {
                    cursor += len;
                    if (cursor >= buffer.len) {
                        break;
                    }
                    continue;
                },
                .partial => {
                    if (manager.modeIs(.force)) {
                        const consumed = handleRawBuffer(manager, buffer, cursor);
                        cursor += consumed;
                        continue;
                    }

                    return cursor - position;
                },
            }
        }

        if (cursor == current_cursor) {
            if (manager.modeIs(.force)) {
                logger.err("finished a loop without consuming any bytes in force mode", .{});
            }
            break;
        }
    }
    return cursor - position;
}
