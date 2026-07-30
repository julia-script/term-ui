const std = @import("std");
const TermInfo = @import("../handle-term-info.zig");
const Osc = @import("osc.zig").Osc;
const Dcs = @import("dcs.zig").Dcs;
const constants = @import("constants.zig");
pub const logger = std.log.scoped(.input_manager);
const keys = @import("../keys.zig");

pub fn escape(writer: std.io.AnyWriter, slice: []const u8) !void {
    for (slice) |c| {
        switch (c) {
            '\n' => try writer.print("\\n", .{}),
            '\r' => try writer.print("\\r", .{}),
            '\t' => try writer.print("\\t", .{}),
            '\x1b' => try writer.print("\\e", .{}),
            '\x00' => try writer.print("\\0", .{}),
            '\x07' => try writer.print("\\a", .{}),
            '\x08' => try writer.print("\\b", .{}),
            '\x0c' => try writer.print("\\f", .{}),
            '\x0b' => try writer.print("\\v", .{}),
            // '\\' => try writer.print("\\\\", .{}),
            // '\"' => try writer.print("\\\"", .{}),
            // '\'' => try writer.print("\\'", .{}),
            else => {
                if (c < 32 or c >= 127) {
                    // Print non-printable characters as hex
                    try writer.print("\\x{x:0>2}", .{c});
                } else {
                    try writer.print("{c}", .{c});
                }
            },
        }
    }
}
pub const Event = struct {
    data: EventData,
    modifiers: u8,
    raw: []const u8,

    const EventData = union(enum) {
        key: KeyEvent,
        unknown_sequence: void,
        paste_chunk: struct {
            chunk: []const u8,
            kind: PasteChunkKind,
        },
        focus: Focus,
        osc: Osc,
        dcs: Dcs,
        mouse: Mouse,
        cursor_report: struct {
            row: u16,
            col: u16,
        },
        mode_report: struct {
            mode: u8,
            value1: u16,
            value2: u8,
        },
    };
    pub const KeyEvent = struct {
        key: ?keys.Key,
        codepoint: u21,

        base_codepoint: u21,

        action: KeyAction,
    };
    pub const Mouse = union(enum) {
        normal: struct {
            action: NormalModeAction,
            x: u16,
            y: u16,
        },
        extended: struct {
            button: Button,
            action: Action,
            x: u16,
            y: u16,
        },

        const NormalModeAction = enum(u8) {
            left_press = 0,
            middle_press = 1,
            right_press = 2,
            release = 3,
            wheel_forward = 4,
            wheel_back = 5,
            wheel_tilt_left = 6,
            wheel_tilt_right = 7,
        };
        const Button = enum(u8) {
            left = 0,
            middle = 1,
            right = 2,
            wheel = 3,
            button8 = 4,
            button9 = 5,
            button10 = 6,
            button11 = 7,
            none = 8,
        };
        const Action = enum(u8) {
            press = 0,
            release = 1,
            motion = 2,
            wheel_up = 3,
            wheel_down = 4,
            wheel_left = 5,
            wheel_right = 6,
        };
    };
    //     action: Action,
    //     button: Button,
    //     x: u16,
    //     y: u16,
    //     encoding: Encoding,
    //     pub const Action = enum {
    //         press,
    //         release,
    //         move,
    //     };
    //     pub const Button = enum {
    //         left,
    //         middle,
    //         right,
    //     };
    //     pub const Encoding = enum {
    //         x10,
    //         sgr,
    //         sgr_pixels,
    //     };
    // };
    pub const PasteChunkKind = enum {
        start,
        end,
        chunk,
        all,
    };
    pub const Focus = enum {
        in,
        out,
    };
    // pub const Named = enum {
    // key_escape,
    // key_space,
    // key_tab,

    // key_insert,
    // key_delete,
    // key_page_up,
    // key_page_down,
    // key_caps_lock,
    // key_scroll_lock,
    // key_num_lock,
    // key_pause,
    // key_menu,
    // key_kp_page_up,
    // key_kp_page_down,
    // key_kp_home,
    // key_kp_end,
    // key_kp_insert,
    // key_kp_delete,
    // key_kp_begin,
    // key_kp_0,
    // key_kp_1,
    // key_kp_2,
    // key_kp_3,
    // key_kp_4,
    // key_kp_5,
    // key_kp_6,
    // key_kp_7,
    // key_kp_8,
    // key_kp_9,
    // key_kp_left,
    // key_kp_right,
    // key_kp_up,
    // key_kp_down,
    // key_kp_equal,
    // key_kp_separator,
    // key_kp_decimal,
    // key_kp_divide,
    // key_kp_multiply,
    // key_kp_subtract,
    // key_kp_add,
    // key_kp_enter,

    // key_up,

    // key_undo,
    // key_suspend,
    // key_sundo,
    // key_stab,
    // key_ssuspend,
    // key_ssave,
    // key_srsume,
    // key_sright,
    // key_sreplace,
    // key_sredo,
    // key_sr,
    // key_sprint,
    // key_sprevious,
    // key_soptions,
    // key_snext,
    // key_smove,
    // key_smessage,
    // key_sleft,
    // key_sic,
    // key_shome,
    // key_shelp,
    // key_sfind,
    // key_sf,
    // key_sexit,
    // key_seol,
    // key_send,
    // key_select,
    // key_sdl,
    // key_sdc,
    // key_screate,
    // key_scopy,
    // key_scommand,
    // key_scancel,
    // key_sbeg,
    // key_save,
    // key_right,
    // key_resume,
    // key_restart,
    // key_replace,
    // key_refresh,
    // key_reference,
    // key_redo,
    // key_print,
    // key_previous,
    // key_ppage,
    // key_options,
    // key_open,
    // key_npage,
    // key_next,
    // key_move,
    // key_mouse,
    // key_message,
    // key_mark,
    // key_ll,
    // key_left,
    // key_il,
    // key_ic,
    // key_home,
    // key_help,
    // key_find,
    // key_f9,
    // key_f8,
    // key_f7,
    // key_f63,
    // key_f62,
    // key_f61,
    // key_f60,
    // key_f6,
    // key_f59,
    // key_f58,
    // key_f57,
    // key_f56,
    // key_f55,
    // key_f54,
    // key_f53,
    // key_f52,
    // key_f51,
    // key_f50,
    // key_f5,
    // key_f49,
    // key_f48,
    // key_f47,
    // key_f46,
    // key_f45,
    // key_f44,
    // key_f43,
    // key_f42,
    // key_f41,
    // key_f40,
    // key_f4,
    // key_f39,
    // key_f38,
    // key_f37,
    // key_f36,
    // key_f35,
    // key_f34,
    // key_f33,
    // key_f32,
    // key_f31,
    // key_f30,
    // key_f3,
    // key_f29,
    // key_f28,
    // key_f27,
    // key_f26,
    // key_f25,
    // key_f24,
    // key_f23,
    // key_f22,
    // key_f21,
    // key_f20,
    // key_f2,
    // key_f19,
    // key_f18,
    // key_f17,
    // key_f16,
    // key_f15,
    // key_f14,
    // key_f13,
    // key_f12,
    // key_f11,
    // key_f10,
    // key_f1,
    // key_f0,
    // key_exit,
    // key_eos,
    // key_eol,
    // key_enter,
    // key_end,
    // key_eic,
    // key_down,
    // key_dl,
    // key_dc,
    // key_ctab,
    // key_create,
    // key_copy,
    // key_command,
    // key_close,
    // key_clear,
    // key_catab,
    // key_cancel,
    // key_c3,
    // key_c1,
    // key_btab,
    // key_beg,
    // key_backspace,
    // key_b2,
    // key_a3,
    // key_a1,
    // key_media_play,
    // key_media_pause,
    // key_media_stop,
    // key_media_previous,
    // key_media_next,
    // key_media_volume_up,
    // key_media_volume_down,

    // key_space,
    // key_escape,
    // key_enter,
    // key_tab,
    // key_backspace,
    // key_insert,
    // key_delete,
    // key_left,
    // key_right,
    // key_up,
    // key_down,
    // key_page_up,
    // key_page_down,
    // key_home,
    // key_end,
    // key_caps_lock,
    // key_scroll_lock,
    // key_num_lock,
    // key_print,
    // key_pause,
    // key_menu,
    // // key_f0,
    // key_f1,
    // key_f2,
    // key_f3,
    // key_f4,
    // key_f5,
    // key_f6,
    // key_f7,
    // key_f8,
    // key_f9,
    // key_f10,
    // key_f11,
    // key_f12,
    // key_f13,
    // key_f14,
    // key_f15,
    // key_f16,
    // key_f17,
    // key_f18,
    // key_f19,
    // key_f20,
    // key_f21,
    // key_f22,
    // key_f23,
    // key_f24,
    // key_f25,
    // key_f26,
    // key_f27,
    // key_f28,
    // key_f29,
    // key_f30,
    // key_f31,
    // key_f32,
    // key_f33,
    // key_f34,
    // key_f35,
    // key_kp_0,
    // key_kp_1,
    // key_kp_2,
    // key_kp_3,
    // key_kp_4,
    // key_kp_5,
    // key_kp_6,
    // key_kp_7,
    // key_kp_8,
    // key_kp_9,
    // key_kp_decimal,
    // key_kp_divide,
    // key_kp_multiply,
    // key_kp_subtract,
    // key_kp_add,
    // key_kp_enter,
    // key_kp_equal,
    // key_kp_separator,
    // key_kp_left,
    // key_kp_right,
    // key_kp_up,
    // key_kp_down,
    // key_kp_page_up,
    // key_kp_page_down,
    // key_kp_home,
    // key_kp_end,
    // key_kp_insert,
    // key_kp_delete,
    // key_kp_begin,
    // key_media_play,
    // key_media_pause,
    // key_media_play_pause,
    // key_media_reverse,
    // key_media_stop,
    // key_media_fast_forward,
    // key_media_rewind,
    // key_media_track_next,
    // key_media_track_previous,
    // key_media_record,
    // key_lower_volume,
    // key_raise_volume,
    // key_mute_volume,
    // key_left_shift,
    // key_left_control,
    // key_left_alt,
    // key_left_super,
    // key_left_hyper,
    // key_left_meta,
    // key_right_shift,
    // key_right_control,
    // key_right_alt,
    // key_right_super,
    // key_right_hyper,
    // key_right_meta,
    // key_iso_level3_shift,
    // key_iso_level5_shift,
    // };
    fn isPrintable(char: u21) bool {
        return char >= 0x20 and char < 0x7f;
    }
    pub fn format(
        value: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: std.io.AnyWriter,
    ) !void {
        _ = options; // autofix
        _ = fmt; // autofix
        var buf: [124]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        var fbs_writer = fbs.writer().any();
        fbs_writer.writeAll("[") catch unreachable;
        switch (value.data) {
            .focus => |focus| {
                try fbs_writer.print("focus {s}", .{@tagName(focus)});
            },

            .key => |key| {
                switch (key.action) {
                    .press => {
                        try fbs_writer.print("key ", .{});
                    },
                    else => {
                        try fbs_writer.print("key .{s} ", .{@tagName(key.action)});
                    },
                }
                if (key.key) |_key| {
                    try fbs_writer.print(".{s} ", .{@tagName(_key)});
                }

                if (isPrintable(key.codepoint)) {
                    try fbs_writer.print("'{c}' {d}", .{ @as(u8, @intCast(key.codepoint)), key.codepoint });
                } else {
                    try fbs_writer.print("'{u}' {d}", .{ key.codepoint, key.codepoint });
                }
                if (key.base_codepoint != key.codepoint) {
                    if (isPrintable(key.base_codepoint)) {
                        try fbs_writer.print(" base_cp='{c}' {d}", .{ @as(u8, @intCast(key.base_codepoint)), key.base_codepoint });
                    } else {
                        try fbs_writer.print(" base_cp='{u}' {d}", .{ key.base_codepoint, key.base_codepoint });
                    }
                }

                if (value.raw.len > 0) {
                    try fbs_writer.print(" raw='", .{});
                    try escape(fbs_writer, value.raw);
                    try fbs_writer.print("'", .{});
                }
            },
            .unknown_sequence => {
                try fbs_writer.print("unknown_sequence '", .{});
                try escape(fbs_writer, value.raw);
                try fbs_writer.print("'", .{});
            },

            .paste_chunk => |paste_chunk| {
                try fbs_writer.print("paste {s} '", .{@tagName(paste_chunk.kind)});
                if (paste_chunk.chunk.len > 10) {
                    escape(fbs_writer, paste_chunk.chunk[0..10]) catch unreachable;
                    try fbs_writer.print("...", .{});
                } else {
                    escape(fbs_writer, paste_chunk.chunk) catch unreachable;
                }
                try fbs_writer.print("'", .{});
            },
            .osc => |osc| {
                try fbs_writer.print("osc <{d}>", .{@backingInt(osc.parameter_selector)});
            },
            .dcs => |dcs| {
                try fbs_writer.print("dcs <{d}>", .{@backingInt(dcs.parameter_selector)});
            },
            .mouse => |mouse| {
                // try fbs_writer.print("mouse .{s} (x={d} y={d})", .{ @tagName(mouse.normal.action), mouse.normal.x, mouse.normal.y });
                switch (mouse) {
                    .normal => |normal| {
                        try fbs_writer.print("mouse .{s} (x={d} y={d})", .{ @tagName(normal.action), normal.x, normal.y });
                    },
                    .extended => |extended| {
                        try fbs_writer.print("mouse .extended .{s} .{s} (x={d} y={d})", .{ @tagName(extended.action), @tagName(extended.button), extended.x, extended.y });
                    },
                }
            },
            .cursor_report => |position| {
                try fbs_writer.print("mouse .cursor_report (row={d} col={d})", .{ position.row, position.col });
            },
            .mode_report => |mode_report| {
                try fbs_writer.print("mode_report (mode={d} value1={d} value2={d})", .{ mode_report.mode, mode_report.value1, mode_report.value2 });
            },
        }
        if (value.modifiers != 0) {
            try fbs_writer.print(" mod='", .{});
            try mod.format(value.modifiers, fbs_writer);
            try fbs_writer.print("'", .{});
        }
        fbs_writer.writeAll("]") catch unreachable;
        try writer.print("{s}", .{fbs.getWritten()});
    }
    pub const mod = struct {
        pub const SHIFT: u8 = 1 << 0;
        pub const ALT: u8 = 1 << 1;
        pub const CTRL: u8 = 1 << 2;
        pub const SUPER: u8 = 1 << 3;
        pub const HYPER: u8 = 1 << 4;
        pub const META: u8 = 1 << 5;
        pub const CAPS_LOCK: u8 = 1 << 6;
        pub const NUM_LOCK: u8 = 1 << 7;
        pub fn format(modifiers: u8, writer: std.io.AnyWriter) !void {
            var is_first = true;
            if (modifiers & SHIFT != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("shift", .{});
                is_first = false;
            }
            if (modifiers & ALT != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("alt", .{});
                is_first = false;
            }
            if ((modifiers & CTRL) != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("ctrl", .{});
                is_first = false;
            }
            if (modifiers & SUPER != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("super", .{});
                is_first = false;
            }
            if (modifiers & HYPER != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("hyper", .{});
                is_first = false;
            }
            if (modifiers & META != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("meta", .{});
                is_first = false;
            }
            if (modifiers & CAPS_LOCK != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("capslock", .{});
                is_first = false;
            }
            if (modifiers & NUM_LOCK != 0) {
                if (!is_first) {
                    try writer.print("+", .{});
                }
                try writer.print("numlock", .{});
                is_first = false;
            }
        }
    };
    pub const KeyAction = enum {
        press,
        repeat,
        release,
    };
};

pub const PASTE_START = "\x1b[200~";
pub const PASTE_END = "\x1b[201~";
pub const Subscriber = struct {
    context: *anyopaque,
    emitFn: *const fn (context: *anyopaque, event: Event) void,
};
pub const AnyInputManager = struct {
    mode: Mode = .normal,
    term_info_driver: ?*TermInfo = null,
    subscribers: std.AutoHashMapUnmanaged(*anyopaque, Subscriber) = .{},
    allocator: std.mem.Allocator,
    pub fn deinit(self: *AnyInputManager) void {
        self.subscribers.deinit(self.allocator);
    }
    //       TERMKEY_KEYMOD_SHIFT = 1 << 0,
    //   TERMKEY_KEYMOD_ALT   = 1 << 1,
    //   TERMKEY_KEYMOD_CTRL  = 1 << 2,
    pub fn subscribe(self: *AnyInputManager, subscriber: Subscriber) !void {
        try self.subscribers.put(self.allocator, subscriber.context, subscriber);
    }
    pub fn unsubscribe(self: *AnyInputManager, context: *anyopaque) void {
        _ = self.subscribers.remove(context);
    }

    pub fn emit(self: *AnyInputManager, event: Event) void {
        logger.info("[EMIT] {}", .{event});
        var it = self.subscribers.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.emitFn(entry.key_ptr.*, event);
        }
    }
    pub fn setMode(self: *AnyInputManager, mode: Mode) void {
        self.mode = mode;
    }
    pub fn modeIs(self: *AnyInputManager, mode: Mode) bool {
        return self.mode == mode;
    }
    pub fn modeIsNot(self: *AnyInputManager, mode: Mode) bool {
        return self.mode != mode;
    }

    pub fn emitFromCodepoint(self: *AnyInputManager, codepoint: u21, base_codepoint: u21, action: Event.KeyAction, modifiers: u8, raw: []const u8) void {
        var cp = codepoint;
        const unshifted = constants.getUnshifted(base_codepoint);
        const is_shift = (modifiers & Event.mod.SHIFT) != 0;
        const is_capslock = (modifiers & Event.mod.CAPS_LOCK) != 0;
        if (cp >= 'a' and cp <= 'z' and (is_shift or is_capslock)) {
            cp = cp - 0x20;
        }

        self.emit(.{
            .data = .{ .key = .{
                .key = constants.getKeyNameFromNumber(cp),
                .codepoint = cp,
                .base_codepoint = unshifted,
                .action = action,
            } },
            .modifiers = modifiers,
            .raw = raw,
        });
    }
    pub fn emitInterpretedCodepoint(self: *AnyInputManager, codepoint: u21, modifiers: u8, raw: []const u8) void {
        var adjusted_codepoint: u21 = codepoint;
        var adjusted_modifiers: u8 = modifiers;

        if (codepoint == 0) {
            // ASCII NUL = Ctrl-Space
            self.emitNamed(.space, .press, Event.mod.CTRL, raw);
            return;
        } else if (codepoint < 0x20) {
            // C0 range - handle special cases first
            switch (codepoint) {
                0x09 => { // Tab (HT)
                    self.emitNamed(.tab, .press, adjusted_modifiers, raw);
                    return;
                },
                0x0d => { // Enter/Return (CR)
                    self.emitNamed(.enter, .press, adjusted_modifiers, raw);
                    return;
                },
                0x0a => { // Line Feed (LF)
                    // Plain enter arrives as CR; a raw LF only reaches us from
                    // a newline keybind (e.g. Ghostty's default shift+enter)
                    // or an unbracketed paste. Both mean "line break", not
                    // Ctrl+J — report it as shift+enter.
                    self.emitNamed(.enter, .press, Event.mod.SHIFT, raw);
                    return;
                },
                0x1b => { // Escape (ESC)
                    self.emitNamed(.escape, .press, adjusted_modifiers, raw);
                    return;
                },
                else => {
                    // Handle generic C0 control codes
                    if (codepoint + 0x40 >= 'A' and codepoint + 0x40 <= 'Z') {
                        // It's a letter - use lowercase instead
                        adjusted_codepoint = codepoint + 0x60;
                    } else {
                        adjusted_codepoint = codepoint + 0x40;
                    }
                    adjusted_modifiers = Event.mod.CTRL;
                },
            }
        } else if (codepoint == 0x7f) {
            // ASCII DEL
            self.emitNamed(.backspace, .press, 0, raw);
            return;
        } else if (codepoint >= 0x20 and codepoint < 0x80) {
            // ASCII lowbyte range
            if (codepoint == 0x20) {
                // Special case for space
                self.emitNamed(.space, .press, adjusted_modifiers, raw);
                return;
            }
            // Regular ASCII - just use as is
            adjusted_codepoint = codepoint;
            adjusted_modifiers = modifiers;
        } else if (codepoint >= 0x80 and codepoint < 0xa0) {
            // UTF-8 never starts with a C1 byte. So we can be sure of these
            adjusted_codepoint = codepoint - 0x40;
            adjusted_modifiers = Event.mod.CTRL | Event.mod.ALT;
        } else {
            // Regular UTF-8 codepoint
            adjusted_codepoint = codepoint;
            adjusted_modifiers = modifiers;
        }
        self.emitFromCodepoint(adjusted_codepoint, adjusted_codepoint, .press, adjusted_modifiers, raw);
        // self.emit(.{
        //     .data = .{
        //         .key = .{ .codepoint = adjusted_codepoint, .action = .press },
        //     },
        //     .modifiers = adjusted_modifiers,
        //     .raw = raw,
        // });
    }
    pub fn emitNamed(self: *AnyInputManager, name: keys.Key, action: Event.KeyAction, modifiers: u8, raw: []const u8) void {
        const codepoint = constants.getNumberFromKeyName(name);
        // const unshifted = constants.getUnshifted(codepoint);
        self.emit(.{
            // .data = .{ .key = .{ .name = name, .codepoint = codepoint, .action = .press } },
            .data = .{
                .key = .{
                    .key = name,
                    .codepoint = codepoint,
                    .base_codepoint = codepoint,
                    .action = action,
                },
            },
            .modifiers = modifiers,
            .raw = raw,
        });
    }
    pub fn emitFocus(self: *AnyInputManager, focus: Event.Focus, raw: []const u8) void {
        self.emit(.{
            .data = .{ .focus = focus },
            .modifiers = 0,
            .raw = raw,
        });
    }
    pub fn emitPasteChunk(self: *AnyInputManager, kind: Event.PasteChunkKind, raw: []const u8) void {
        const chunk = switch (kind) {
            .chunk => raw,
            .start => raw[PASTE_START.len..],
            .end => raw[0 .. raw.len - PASTE_END.len],
            .all => raw[PASTE_START.len .. raw.len - PASTE_END.len],
        };
        self.emit(.{
            .data = .{ .paste_chunk = .{ .kind = kind, .chunk = chunk } },
            .modifiers = 0,
            .raw = raw,
        });
    }
    pub fn emitOsc(self: *AnyInputManager, osc: Osc, raw: []const u8) void {
        self.emit(.{
            .data = .{ .osc = osc },
            .modifiers = 0,
            .raw = raw,
        });
    }
    pub fn emitDcs(self: *AnyInputManager, dcs: Dcs, raw: []const u8) void {
        self.emit(.{
            .data = .{ .dcs = dcs },
            .modifiers = 0,
            .raw = raw,
        });
    }
    pub fn emitMouse(self: *AnyInputManager, mouse: Event.Mouse, modifiers: u8, raw: []const u8) void {
        self.emit(.{
            .data = .{ .mouse = mouse },
            .modifiers = modifiers,
            .raw = raw,
        });
    }

    pub fn emitModeReport(self: *AnyInputManager, mode: u8, value1: u16, value2: u8, raw: []const u8) void {
        self.emit(.{
            .data = .{ .mode_report = .{ .mode = mode, .value1 = value1, .value2 = value2 } },
            .modifiers = 0,
            .raw = raw,
        });
    }
};
pub const Mode = enum {
    normal,
    force,
    paste,
};

pub fn MatchResult(comptime T: type) type {
    return union(enum) {
        match: T,
        partial: void,
        nomatch: void,
    };
}
pub const Match = MatchResult(usize);
