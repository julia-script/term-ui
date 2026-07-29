const std = @import("std");

const expectEvents = @import("test-utils.zig").expectEvents;
const AnyInputManager = @import("input/manager.zig").AnyInputManager;
const Match = @import("input/manager.zig").Match;
const Event = @import("input/manager.zig").Event;
const Capability = @import("terminfo/Strings.zig").Capability;
const Trie = @import("Trie.zig").Trie;
const logger = @import("input/manager.zig").logger;
const Self = @This();
const keys = @import("keys.zig");
trie: Trie(Capability),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .trie = Trie(Capability).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.trie.deinit();
}

pub fn handleTerminalInfo(manager: *AnyInputManager, buffer: []const u8, position: usize) Match {
    logger.info("try handleTerminalInfo", .{});
    const driver = manager.term_info_driver orelse return .nomatch;
    var trie = driver.trie;
    var cursor: usize = position;

    var current = &trie.root;
    while (cursor < buffer.len) {
        const c = buffer[cursor];
        if (current.children.get(c)) |next_node| {
            current = next_node;
            if (current.value) |capability| {
                const named: keys.Key = switch (capability) {
                    // .key_up => .key_up,
                    // // .key_undo => .key_undo,
                    // .key_suspend => .key_suspend,
                    // .key_sundo => .key_sundo,
                    // .key_stab => .key_stab,
                    // .key_ssuspend => .key_ssuspend,
                    // .key_ssave => .key_ssave,
                    // .key_srsume => .key_srsume,
                    // .key_sright => .key_sright,
                    // .key_sreplace => .key_sreplace,
                    // .key_sredo => .key_sredo,
                    // .key_sr => .key_sr,
                    // .key_sprint => .key_sprint,
                    // .key_sprevious => .key_sprevious,
                    // .key_soptions => .key_soptions,
                    // .key_snext => .key_snext,
                    // .key_smove => .key_smove,
                    // .key_smessage => .key_smessage,
                    // .key_sleft => .key_sleft,
                    // .key_sic => .key_sic,
                    // .key_shome => .key_shome,
                    // .key_shelp => .key_shelp,
                    // .key_sfind => .key_sfind,
                    // .key_sf => .key_sf,
                    // .key_sexit => .key_sexit,
                    // .key_seol => .key_seol,
                    // .key_send => .key_send,
                    // .key_select => .key_select,
                    // .key_sdl => .key_sdl,
                    // .key_sdc => .key_sdc,
                    // .key_screate => .key_screate,
                    // .key_scopy => .key_scopy,
                    // .key_scommand => .key_scommand,
                    // .key_scancel => .key_scancel,
                    // .key_sbeg => .key_sbeg,
                    // .key_save => .key_save,
                    // .key_right => .key_right,
                    // .key_resume => .key_resume,
                    // .key_restart => .key_restart,
                    // .key_replace => .key_replace,
                    // .key_refresh => .key_refresh,
                    // .key_reference => .key_reference,
                    // .key_redo => .key_redo,
                    // .key_print => .key_print,
                    // .key_previous => .key_previous,
                    // .key_ppage => .key_ppage,
                    // .key_options => .key_options,
                    // .key_open => .key_open,
                    // .key_npage => .key_npage,
                    // .key_next => .key_next,
                    // .key_move => .key_move,
                    // .key_mouse => .key_mouse,
                    // .key_message => .key_message,
                    // .key_mark => .key_mark,
                    // .key_ll => .key_ll,
                    // .key_left => .key_left,
                    // .key_il => .key_il,
                    // .key_ic => .key_ic,
                    // .key_home => .key_home,
                    // .key_help => .key_help,
                    // .key_find => .key_find,
                    // .key_f9 => .key_f9,
                    // .key_f8 => .key_f8,
                    // .key_f7 => .key_f7,
                    // .key_f63 => .key_f63,
                    // .key_f62 => .key_f62,
                    // .key_f61 => .key_f61,
                    // .key_f60 => .key_f60,
                    // .key_f6 => .key_f6,
                    // .key_f59 => .key_f59,
                    // .key_f58 => .key_f58,
                    // .key_f57 => .key_f57,
                    // .key_f56 => .key_f56,
                    // .key_f55 => .key_f55,
                    // .key_f54 => .key_f54,
                    // .key_f53 => .key_f53,
                    // .key_f52 => .key_f52,
                    // .key_f51 => .key_f51,
                    // .key_f50 => .key_f50,
                    // .key_f5 => .key_f5,
                    // .key_f49 => .key_f49,
                    // .key_f48 => .key_f48,
                    // .key_f47 => .key_f47,
                    // .key_f46 => .key_f46,
                    // .key_f45 => .key_f45,
                    // .key_f44 => .key_f44,
                    // .key_f43 => .key_f43,
                    // .key_f42 => .key_f42,
                    // .key_f41 => .key_f41,
                    // .key_f40 => .key_f40,
                    // .key_f4 => .key_f4,
                    // .key_f39 => .key_f39,
                    // .key_f38 => .key_f38,
                    // .key_f37 => .key_f37,
                    // .key_f36 => .key_f36,
                    // .key_f35 => .key_f35,
                    // .key_f34 => .key_f34,
                    // .key_f33 => .key_f33,
                    // .key_f32 => .key_f32,
                    // .key_f31 => .key_f31,
                    // .key_f30 => .key_f30,
                    // .key_f3 => .key_f3,
                    // .key_f29 => .key_f29,
                    // .key_f28 => .key_f28,
                    // .key_f27 => .key_f27,
                    // .key_f26 => .key_f26,
                    // .key_f25 => .key_f25,
                    // .key_f24 => .key_f24,
                    // .key_f23 => .key_f23,
                    // .key_f22 => .key_f22,
                    // .key_f21 => .key_f21,
                    // .key_f20 => .key_f20,
                    // .key_f2 => .key_f2,
                    // .key_f19 => .key_f19,
                    // .key_f18 => .key_f18,
                    // .key_f17 => .key_f17,
                    // .key_f16 => .key_f16,
                    // .key_f15 => .key_f15,
                    // .key_f14 => .key_f14,
                    // .key_f13 => .key_f13,
                    // .key_f12 => .key_f12,
                    // .key_f11 => .key_f11,
                    // .key_f10 => .key_f10,
                    // .key_f1 => .key_f1,
                    // .key_f0 => .key_f0,
                    // .key_exit => .key_exit,
                    // .key_eos => .key_eos,
                    // .key_eol => .key_eol,
                    // .key_enter => .key_enter,
                    // .key_end => .key_end,
                    // .key_eic => .key_eic,
                    // .key_down => .key_down,
                    // .key_dl => .key_dl,
                    // .key_dc => .key_dc,
                    // .key_ctab => .key_ctab,
                    // .key_create => .key_create,
                    // .key_copy => .key_copy,
                    // .key_command => .key_command,
                    // .key_close => .key_close,
                    // .key_clear => .key_clear,
                    // .key_catab => .key_catab,
                    // .key_cancel => .key_cancel,
                    // .key_c3 => .key_c3,
                    // .key_c1 => .key_c1,
                    // .key_btab => .key_btab,
                    // .key_beg => .key_beg,
                    // .key_backspace => .key_backspace,
                    // .key_b2 => .key_b2,
                    // .key_a3 => .key_a3,
                    // .key_a1 => .key_a1,

                    .key_backspace => .backspace,
                    .key_btab => .tab,
                    .key_down => .down,
                    .key_up => .up,
                    .key_left => .left,
                    .key_right => .right,
                    .key_ic => .insert,
                    .key_dc => .delete,
                    // .key_delete => .key_delete,
                    .key_ppage => .page_up,
                    .key_npage => .page_down,
                    .key_home => .home,
                    .key_end => .end,
                    .key_ctab => .tab,
                    .key_enter => .enter,
                    .key_f1 => .f1,
                    .key_f2 => .f2,
                    .key_f3 => .f3,
                    .key_f4 => .f4,
                    .key_f5 => .f5,
                    .key_f6 => .f6,
                    .key_f7 => .f7,
                    .key_f8 => .f8,
                    .key_f9 => .f9,
                    .key_f10 => .f10,
                    .key_f11 => .f11,
                    .key_f12 => .f12,
                    .key_f13 => .f13,

                    else => |unhandled| {
                        if (std.mem.startsWith(u8, @tagName(unhandled), "key_")) {
                            logger.warn("unhandled key from terminfo: {s}\n", .{@tagName(unhandled)});
                        }
                        return .nomatch;
                    },
                };

                manager.emitNamed(named, .press, 0, buffer[position..cursor]);
                // found match
                return .{ .match = cursor - position + 1 };
            }
        } else {
            // no match
            return .nomatch;
        }
        // match but not a leaf yet
        // continue searching
        cursor += 1;
    }
    // if got this far, buffer ended with a partial match
    return .partial;
}

test "term info" {
    try expectEvents(
        @src(),
        std.testing.allocator,
        "xterm-ghostty",
        &.{
            "\x1b[1;3P",
        },
    );
}
