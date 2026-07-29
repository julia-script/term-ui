const std = @import("std");
const Strings = @This();

capabilities: [num_capabilities](?Sequence),
table: Table,

pub fn init(allocator: std.mem.Allocator, strings_section: []const u8, string_table_section: []const u8) std.mem.Allocator.Error!Strings {
    var strings: Strings = undefined;

    strings.table = try Table.init(allocator, string_table_section);

    const int_width = 2;

    @memset(&strings.capabilities, null);

    var byte_i: usize = 0;
    while (byte_i < strings_section.len) : (byte_i += int_width) {
        // make sure we don't read past the string section
        if (byte_i >= strings_section.len) {
            break;
        }

        // the bytes that contain the string index (little endian)
        const bytes = strings_section[byte_i..][0..int_width];
        // get the byte offset into the string table
        const str_i = std.mem.readInt(u16, bytes, .little);

        // if it is -1, it's not available
        if (str_i == 0xffff) {
            // this capability is not available, which is the default value
            continue;
        }

        // get the slice
        const slice = strings.table.getSliceFromByteOffset(@as(usize, str_i)) orelse continue;

        // we could consider logging an error somewhere, but logging to stdout
        // is not an option, since this library is intended to be used in TUI
        // applications
        if (slice.len == 0) {
            continue;
        }

        // std.log.info("parsing capability '{s}' with sequence '{s}'", .{ @tagName(@as(Capability, @enumFromInt(byte_i / int_width))), std.fmt.fmtSliceEscapeLower(slice) });
        const sequence = try Sequence.parse(allocator, slice);

        // get the capability index
        const capability = byte_i / int_width;

        strings.capabilities[capability] = sequence;
    }

    return strings;
}

/// Releases all allocated memory.
pub fn deinit(self: @This()) void {
    self.table.deinit();
}

pub fn get_value(self: *const Strings, capability: Capability) ?[]const u8 {
    const seq = self.capabilities[@backingInt(capability)] orelse return null;
    return switch (seq) {
        .regular => |bytes| bytes,
        .parameterized => null,
    };
}

pub fn get_value_with_args(self: *const Strings, alloc: std.mem.Allocator, capability: Capability, args: []const Parameter) std.mem.Allocator.Error!?[]const u8 {
    const seq = self.capabilities[@backingInt(capability)] orelse return null;
    var buf = std.ArrayList(u8).init(alloc);
    switch (seq) {
        .regular => |bytes| return try alloc.dupe(u8, bytes),
        .parameterized => |parameterized| {
            const writer = buf.writer();
            parameterized.write(alloc, writer, args) catch unreachable;
            return try buf.toOwnedSlice();
        },
    }
}

/// Returns an iterator over defined capabilities.
pub fn iter(self: *const Strings) Iter {
    return Iter{
        .strings = self,
        .index = 0,
    };
}

pub const Iter = struct {
    strings: *const Strings,
    index: usize,

    /// The item that is returned by next()
    pub const Item = struct {
        capability: Capability,
        value: []const u8,
    };

    pub fn next(self: *@This()) ?Item {
        // find next non-null capability
        const value = blk: while (self.index < num_capabilities) : (self.index += 1) {
            if (self.strings.capabilities[self.index]) |value| {
                switch (value) {
                    .regular => |slice| break :blk slice,
                    .parameterized => continue,
                }
            }
        } else {
            return null;
        };

        // make sure to skip past this capability
        defer self.index += 1;

        return Item{
            .capability = @fromBackingInt(@intCast(self.index)),
            .value = value,
        };
    }
};

pub const Table = struct {
    // The table stores the string table section data and an array of slices to the
    // data that divide the string table into the strings that it contains.

    allocator: std.mem.Allocator,
    data: []const u8,
    slices: [][]const u8,

    /// Returns the slice for the given byte offset.
    /// For a well-defined terminfo, this function should never return `null`.
    pub fn getSliceFromByteOffset(self: *const @This(), byte_offset: usize) ?[]const u8 {
        const S = struct {
            target_ptr: usize,
            pub fn cmp(ctx: @This(), mid_item: []const u8) std.math.Order {
                return std.math.order(ctx.target_ptr, @intFromPtr(mid_item.ptr));
            }
        };
        const target_ptr = @intFromPtr(self.data.ptr) + byte_offset;
        const index = std.sort.binarySearch([]const u8, self.slices, S{ .target_ptr = target_ptr }, S.cmp) orelse return null;
        return self.slices[index];
    }

    /// Initialize and parse the string table.
    pub fn init(allocator: std.mem.Allocator, section: []const u8) std.mem.Allocator.Error!@This() {
        // alloc space for section data
        var data = try allocator.alloc(u8, section.len);
        errdefer allocator.free(data);

        // move the section data into the allocated region
        @memcpy(data, section);

        // create arraylist for slices
        var slices: std.ArrayList([]const u8) = .empty;
        // we'll eventually call .toOwnedSlice() on this array, so we only need
        // to deinit on error
        errdefer slices.deinit(allocator);

        var start: usize = 0;
        for (data, 0..) |char, end| {
            if (char == 0) {
                // we've found a string
                try slices.append(allocator, data[start..end]);
                // move start to the char after the sentinel
                start = end + 1;
            }
        }

        return .{
            .allocator = allocator,
            .data = data,
            .slices = try slices.toOwnedSlice(allocator),
        };
    }

    // Deinitializes the string table.
    // Note: the string capabilities rely on the string table.
    pub fn deinit(self: @This()) void {
        self.allocator.free(self.data);
        self.allocator.free(self.slices);
    }
};

pub const Capability = enum(u16) {
    back_tab = 0,
    zero_motion,
    xon_character,
    xoff_character,
    wait_tone,
    user9,
    user8,
    user7,
    user6,
    user5,
    user4,
    user3,
    user2,
    user1,
    user0,
    up_half_line,
    underline_char,
    tone,
    to_status_line,
    these_cause_cr,
    termcap_reset,
    termcap_init2,
    tab,
    superscript_characters,
    subscript_characters,
    stop_char_set_def,
    stop_bit_image,
    start_char_set_def,
    start_bit_image,
    set3_des_seq,
    set2_des_seq,
    set1_des_seq,
    set0_des_seq,
    set_window,
    set_top_margin,
    set_top_margin_parm,
    set_tb_margin,
    set_tab,
    set_right_margin,
    set_right_margin_parm,
    set_pglen_inch,
    set_page_length,
    set_lr_margin,
    set_left_margin,
    set_left_margin_parm,
    set_foreground,
    set_color_pair,
    set_color_band,
    set_clock,
    set_bottom_margin,
    set_bottom_margin_parm,
    set_background,
    set_attributes,
    set_a_foreground,
    set_a_background,
    set_a_attributes,
    select_char_set,
    scroll_reverse,
    scroll_forward,
    scancode_escape,
    save_cursor,
    row_address,
    restore_cursor,
    reset_file,
    reset_3string,
    reset_2string,
    reset_1string,
    req_mouse_pos,
    req_for_input,
    repeat_char,
    remove_clock,
    quick_dial,
    pulse,
    prtr_on,
    prtr_off,
    prtr_non,
    print_screen,
    plab_norm,
    pkey_xmit,
    pkey_plab,
    pkey_local,
    pkey_key,
    pc_term_options,
    parm_up_micro,
    parm_up_cursor,
    parm_rindex,
    parm_right_micro,
    parm_right_cursor,
    parm_left_micro,
    parm_left_cursor,
    parm_insert_line,
    parm_index,
    parm_ich,
    parm_down_micro,
    parm_down_cursor,
    parm_delete_line,
    parm_dch,
    pad_char,
    other_non_function_keys,
    orig_pair,
    orig_colors,
    order_of_pins,
    newline,
    mouse_info,
    micro_up,
    micro_row_address,
    micro_right,
    micro_left,
    micro_down,
    micro_column_address,
    meta_on,
    meta_off,
    memory_unlock,
    memory_lock,
    linefeed_if_not_lf,
    label_on,
    label_off,
    label_format,
    lab_f9,
    lab_f8,
    lab_f7,
    lab_f6,
    lab_f5,
    lab_f4,
    lab_f3,
    lab_f2,
    lab_f10,
    lab_f1,
    lab_f0,
    keypad_xmit,
    keypad_local,
    key_up,
    key_undo,
    key_suspend,
    key_sundo,
    key_stab,
    key_ssuspend,
    key_ssave,
    key_srsume,
    key_sright,
    key_sreplace,
    key_sredo,
    key_sr,
    key_sprint,
    key_sprevious,
    key_soptions,
    key_snext,
    key_smove,
    key_smessage,
    key_sleft,
    key_sic,
    key_shome,
    key_shelp,
    key_sfind,
    key_sf,
    key_sexit,
    key_seol,
    key_send,
    key_select,
    key_sdl,
    key_sdc,
    key_screate,
    key_scopy,
    key_scommand,
    key_scancel,
    key_sbeg,
    key_save,
    key_right,
    key_resume,
    key_restart,
    key_replace,
    key_refresh,
    key_reference,
    key_redo,
    key_print,
    key_previous,
    key_ppage,
    key_options,
    key_open,
    key_npage,
    key_next,
    key_move,
    key_mouse,
    key_message,
    key_mark,
    key_ll,
    key_left,
    key_il,
    key_ic,
    key_home,
    key_help,
    key_find,
    key_f9,
    key_f8,
    key_f7,
    key_f63,
    key_f62,
    key_f61,
    key_f60,
    key_f6,
    key_f59,
    key_f58,
    key_f57,
    key_f56,
    key_f55,
    key_f54,
    key_f53,
    key_f52,
    key_f51,
    key_f50,
    key_f5,
    key_f49,
    key_f48,
    key_f47,
    key_f46,
    key_f45,
    key_f44,
    key_f43,
    key_f42,
    key_f41,
    key_f40,
    key_f4,
    key_f39,
    key_f38,
    key_f37,
    key_f36,
    key_f35,
    key_f34,
    key_f33,
    key_f32,
    key_f31,
    key_f30,
    key_f3,
    key_f29,
    key_f28,
    key_f27,
    key_f26,
    key_f25,
    key_f24,
    key_f23,
    key_f22,
    key_f21,
    key_f20,
    key_f2,
    key_f19,
    key_f18,
    key_f17,
    key_f16,
    key_f15,
    key_f14,
    key_f13,
    key_f12,
    key_f11,
    key_f10,
    key_f1,
    key_f0,
    key_exit,
    key_eos,
    key_eol,
    key_enter,
    key_end,
    key_eic,
    key_down,
    key_dl,
    key_dc,
    key_ctab,
    key_create,
    key_copy,
    key_command,
    key_close,
    key_clear,
    key_catab,
    key_cancel,
    key_c3,
    key_c1,
    key_btab,
    key_beg,
    key_backspace,
    key_b2,
    key_a3,
    key_a1,
    insert_padding,
    insert_line,
    insert_character,
    initialize_pair,
    initialize_color,
    init_prog,
    init_file,
    init_3string,
    init_2string,
    init_1string,
    hangup,
    goto_window,
    get_mouse,
    from_status_line,
    form_feed,
    flash_screen,
    flash_hook,
    fixed_pause,
    exit_xon_mode,
    exit_upward_mode,
    exit_underline_mode,
    exit_superscript_mode,
    exit_subscript_mode,
    exit_standout_mode,
    exit_shadow_mode,
    exit_scancode_mode,
    exit_pc_charset_mode,
    exit_micro_mode,
    exit_leftward_mode,
    exit_italics_mode,
    exit_insert_mode,
    exit_doublewide_mode,
    exit_delete_mode,
    exit_ca_mode,
    exit_attribute_mode,
    exit_am_mode,
    exit_alt_charset_mode,
    erase_chars,
    enter_xon_mode,
    enter_vertical_hl_mode,
    enter_upward_mode,
    enter_underline_mode,
    enter_top_hl_mode,
    enter_superscript_mode,
    enter_subscript_mode,
    enter_standout_mode,
    enter_shadow_mode,
    enter_secure_mode,
    enter_scancode_mode,
    enter_right_hl_mode,
    enter_reverse_mode,
    enter_protected_mode,
    enter_pc_charset_mode,
    enter_normal_quality,
    enter_near_letter_quality,
    enter_micro_mode,
    enter_low_hl_mode,
    enter_leftward_mode,
    enter_left_hl_mode,
    enter_italics_mode,
    enter_insert_mode,
    enter_horizontal_hl_mode,
    enter_draft_quality,
    enter_doublewide_mode,
    enter_dim_mode,
    enter_delete_mode,
    enter_ca_mode,
    enter_bold_mode,
    enter_blink_mode,
    enter_am_mode,
    enter_alt_charset_mode,
    end_bit_image_region,
    ena_acs,
    down_half_line,
    display_pc_char,
    display_clock,
    dis_status_line,
    dial_phone,
    device_type,
    delete_line,
    delete_character,
    define_char,
    define_bit_image_region,
    cursor_visible,
    cursor_up,
    cursor_to_ll,
    cursor_right,
    cursor_normal,
    cursor_mem_address,
    cursor_left,
    cursor_invisible,
    cursor_home,
    cursor_down,
    cursor_address,
    create_window,
    command_character,
    column_address,
    color_names,
    code_set_init,
    clr_eos,
    clr_eol,
    clr_bol,
    clear_screen,
    clear_margins,
    clear_all_tabs,
    char_set_names,
    char_padding,
    change_scroll_region,
    change_res_vert,
    change_res_horz,
    change_line_pitch,
    change_char_pitch,
    carriage_return,
    box_chars_1,
    bit_image_repeat,
    bit_image_newline,
    bit_image_carriage_return,
    bell,
    backspace_if_not_bs,
    arrow_key_map,
    alt_scancode_esc,
    acs_vline,
    acs_urcorner,
    acs_ulcorner,
    acs_ttee,
    acs_rtee,
    acs_plus,
    acs_ltee,
    acs_lrcorner,
    acs_llcorner,
    acs_hline,
    acs_chars,
    acs_btee,
    // internal capabilities
};

const num_capabilities = @typeInfo(Capability).@"enum".field_names.len;

pub const ParameterKind = enum {
    integer,
    string,
};

pub const Parameter = union(ParameterKind) {
    integer: i32,
    string: []const u8,
};

fn eat_integer(bytes: []const u8) struct { value: u32, rem: []const u8 } {
    var value: u32 = 0;
    var rem = bytes;
    while (rem.len > 0 and std.ascii.isDigit(rem[0])) {
        const digit_val = rem[0] - '0';
        value *= 10;
        value += digit_val;
        rem = rem[1..];
    }

    return .{
        .value = value,
        .rem = rem,
    };
}

pub const Formatted = struct {
    flags: Flags,
    width: u32,
    precision: u32,
    conversion: Conversion,

    pub const Conversion = enum {
        decimal,
        octal,
        lower_hex,
        upper_hex,
        string,
    };

    pub fn parse(input: []const u8) ?struct { formatted: Formatted, rem: []const u8 } {
        var rem = input;

        // skip leading colon
        if (rem[0] == ':') {
            rem = rem[1..];
        }

        // flags
        const parsed_flags = Flags.parse(rem);
        const flags = parsed_flags.flags;
        rem = parsed_flags.rem;

        // width
        const eaten_width = eat_integer(rem);
        // defaults to zero
        const width = eaten_width.value;
        rem = eaten_width.rem;

        // precision
        const precision = if (rem.len > 0 and rem[0] == '.') blk: {
            rem = rem[1..];
            const eaten_prec = eat_integer(rem);
            // defaults to zero
            const precision = eaten_prec.value;
            rem = eaten_prec.rem;
            break :blk precision;
        } else 0;

        if (rem.len == 0) {
            return null;
        }

        const conversion: Conversion = switch (rem[0]) {
            'd' => .decimal,
            'o' => .octal,
            'x' => .lower_hex,
            'X' => .upper_hex,
            's' => .string,
            else => return null,
        };
        rem = rem[1..];

        return .{
            .formatted = .{
                .flags = flags,
                .width = width,
                .precision = precision,
                .conversion = conversion,
            },
            .rem = rem,
        };
    }

    pub const WriteError = error{ InvalidFormatValue, WriterError } || std.mem.Allocator.Error;
    pub fn write(self: *const Formatted, alloc: std.mem.Allocator, writer: anytype, param: Parameter) WriteError!void {
        switch (param) {
            .integer => |value| {
                var buf = try std.ArrayList(u8).initCapacity(alloc, self.width);
                switch (self.conversion) {
                    .decimal => try std.fmt.format(buf.writer(), "{d}", .{value}),
                    .lower_hex => try std.fmt.format(buf.writer(), "{x}", .{value}),
                    .upper_hex => try std.fmt.format(buf.writer(), "{X}", .{value}),
                    .octal => try std.fmt.format(buf.writer(), "{o}", .{value}),
                    .string => return error.InvalidFormatValue,
                }

                if (self.flags.alternate) {
                    switch (self.conversion) {
                        .octal => if (buf.items[0] != '0') {
                            try buf.insert(0, '0');
                        },
                        .lower_hex => try buf.insertSlice(0, "0x"),
                        .upper_hex => try buf.insertSlice(0, "0x"),
                        else => unreachable,
                    }
                }

                if (value < 0) {
                    try buf.insert(0, '-');
                } else if (self.flags.print_sign) {
                    try buf.insert(0, '+');
                } else if (self.flags.space_before_signed and value >= 0) {
                    try buf.insert(0, ' ');
                }

                if (buf.items.len < self.width) {
                    if (self.flags.left_justified) {
                        for (buf.items.len..self.width) |_| {
                            try buf.append(' ');
                        }
                    } else {
                        for (buf.items.len..self.width) |_| {
                            try buf.insert(0, ' ');
                        }
                    }
                }
                _ = writer.write(buf.items) catch return error.WriterError;
            },
            .string => |value| {
                if (self.conversion != .string) {
                    return error.InvalidFormatValue;
                }

                _ = writer.write(value) catch return error.WriterError;
            },
        }
    }

    const Flags = packed struct {
        alternate: bool,
        // printf(3) specifies a zero-padding flag, but terminfo(5) does not
        left_justified: bool,
        space_before_signed: bool,
        // overrides `space_before_signed` if true
        print_sign: bool,

        pub fn parse(input: []const u8) struct { flags: Flags, rem: []const u8 } {
            var rem = input;
            var flags = Flags{
                .alternate = false,
                .left_justified = false,
                .space_before_signed = false,
                .print_sign = false,
            };

            while (rem.len > 0) {
                const char = rem[0];

                switch (char) {
                    '#' => flags.alternate = true,
                    '-' => flags.left_justified = true,
                    ' ' => flags.space_before_signed = true,
                    '+' => flags.print_sign = true,
                    else => break,
                }

                rem = rem[1..];
            }

            return .{
                .flags = flags,
                .rem = rem,
            };
        }
    };
};

const Action = union(enum) {
    print_char: u8,
    print_formatted: Formatted,
    push_nth_arg: u8,
    pop_string,
    print_int: u32,
    increment_first_two_params,
    push_strlen_pop,
    bin_op: BinOp,
    unary_op: UnaryOp,
    begin_conditional,
    test_expr,
    else_branch,
    end_conditional,
};

const BinOp = enum {
    add,
    sub,
    mul,
    div,
    mod,
    bit_and,
    bit_or,
    bit_xor,
    eq,
    gt,
    lt,
    log_and,
    log_or,
};

const UnaryOp = enum {
    log_not,
    bit_not,
};

pub const Sequence = union(enum) {
    regular: []const u8,
    parameterized: ParameterizedSequence,

    pub fn parse(alloc: std.mem.Allocator, seq: []const u8) std.mem.Allocator.Error!Sequence {
        const param_seq = try ParameterizedSequence.parse(alloc, seq);
        if (param_seq.n_params == 0) {
            return .{
                .regular = seq,
            };
        } else {
            return .{
                .parameterized = param_seq,
            };
        }
    }
};

pub const ParameterizedSequence = struct {
    n_params: u8,
    actions: []const Action,

    pub fn parse(alloc: std.mem.Allocator, seq: []const u8) std.mem.Allocator.Error!ParameterizedSequence {
        var n_params: u8 = 0;
        var actions: std.ArrayList(Action) = .empty;
        var rem = seq;
        while (rem.len > 0) {
            if (rem[0] == '%') {
                rem = rem[1..];

                if (rem[0] == '\'') {
                    const ch = rem[1];
                    try actions.append(alloc, .{
                        .print_char = ch,
                    });
                    rem = rem[3..];
                } else if (rem[0] == '%') {
                    try actions.append(alloc, .{
                        .print_char = '%',
                    });
                    rem = rem[1..];
                } else if (rem[0] == 'p') {
                    // argument
                    const index_char = rem[1];
                    std.debug.assert(std.ascii.isDigit(index_char));
                    const index = index_char - '0';
                    try actions.append(alloc, .{
                        .push_nth_arg = index,
                    });
                    n_params = @max(n_params, index + 1);
                    rem = rem[2..];
                } else if (rem[0] == 'c' or rem[1] == 's') {
                    try actions.append(alloc, .pop_string);
                    rem = rem[1..];
                } else if (rem[0] == '{') {
                    const eaten = eat_integer(rem[1..]);

                    try actions.append(alloc, .{
                        .print_int = eaten.value,
                    });
                    rem = eaten.rem[1..];
                } else if (rem[0] == 'l') {
                    try actions.append(alloc, .push_strlen_pop);
                    rem = rem[1..];
                } else if (rem[0] == 'i') {
                    try actions.append(alloc, .increment_first_two_params);
                    rem = rem[1..];
                } else if (rem[0] == '+') {
                    try actions.append(alloc, .{ .bin_op = .add });
                    rem = rem[1..];
                } else if (rem[0] == '-') {
                    try actions.append(alloc, .{ .bin_op = .sub });
                    rem = rem[1..];
                } else if (rem[0] == '*') {
                    try actions.append(alloc, .{ .bin_op = .mul });
                    rem = rem[1..];
                } else if (rem[0] == '/') {
                    try actions.append(alloc, .{ .bin_op = .div });
                    rem = rem[1..];
                } else if (rem[0] == 'm') {
                    try actions.append(alloc, .{ .bin_op = .mod });
                    rem = rem[1..];
                } else if (rem[0] == '&') {
                    try actions.append(alloc, .{ .bin_op = .bit_and });
                    rem = rem[1..];
                } else if (rem[0] == '|') {
                    try actions.append(alloc, .{ .bin_op = .bit_or });
                    rem = rem[1..];
                } else if (rem[0] == '^') {
                    try actions.append(alloc, .{ .bin_op = .bit_xor });
                    rem = rem[1..];
                } else if (rem[0] == '=') {
                    try actions.append(alloc, .{ .bin_op = .eq });
                    rem = rem[1..];
                } else if (rem[0] == '>') {
                    try actions.append(alloc, .{ .bin_op = .gt });
                    rem = rem[1..];
                } else if (rem[0] == '<') {
                    try actions.append(alloc, .{ .bin_op = .lt });
                    rem = rem[1..];
                } else if (rem[0] == 'A') {
                    try actions.append(alloc, .{ .bin_op = .log_and });
                    rem = rem[1..];
                } else if (rem[0] == 'O') {
                    try actions.append(alloc, .{ .bin_op = .log_or });
                    rem = rem[1..];
                } else if (rem[0] == '!') {
                    try actions.append(alloc, .{ .unary_op = .log_not });
                    rem = rem[1..];
                } else if (rem[0] == '~') {
                    try actions.append(alloc, .{ .unary_op = .bit_not });
                    rem = rem[1..];
                } else if (rem[0] == '?') {
                    try actions.append(alloc, .begin_conditional);
                    rem = rem[1..];
                } else if (rem[0] == 't') {
                    try actions.append(alloc, .test_expr);
                    rem = rem[1..];
                } else if (rem[0] == 'e') {
                    try actions.append(alloc, .else_branch);
                    rem = rem[1..];
                } else if (rem[0] == ';') {
                    try actions.append(alloc, .end_conditional);
                    rem = rem[1..];
                } else {
                    const formatted = Formatted.parse(rem) orelse {
                        // this isn't specified in terminfo(5) or
                        // curs_terminfo(3X), but this is the behavior of
                        // `tparm`.
                        // Cap "user8" of "xterm-256color" contains "%[" which,
                        // as far as I can tell, is undefined behavior.
                        rem = rem[1..];
                        continue;
                    };
                    try actions.append(alloc, .{
                        .print_formatted = formatted.formatted,
                    });
                    rem = formatted.rem;
                }
            } else {
                try actions.append(alloc, .{
                    .print_char = rem[0],
                });
                rem = rem[1..];
            }
        }

        // std.log.info("actions:", .{});
        // for (actions.items) |action| {
        //     std.log.info("\t{}", .{action});
        // }

        return .{
            .n_params = n_params,
            .actions = try actions.toOwnedSlice(alloc),
        };
    }

    pub const WriteError = error{WriterError} || std.mem.Allocator.Error;
    pub fn write(self: *const ParameterizedSequence, alloc: std.mem.Allocator, writer: anytype, args: []const Parameter) WriteError!void {
        var stack = Stack(Parameter){ .allocator = alloc };
        var incremented = false;
        var skip_after_then = false;
        var skip_until_cond_end = false;
        var skip_until_else = false;
        for (self.actions) |action| {
            if (skip_until_else and action != .else_branch) {
                continue;
            }

            if (skip_until_cond_end and action != .end_conditional) {
                continue;
            }

            switch (action) {
                .print_char => |ch| {
                    _ = try writer.write(&[_]u8{ch});
                },
                .print_formatted => |formatted| {
                    const param = stack.pop().?;
                    formatted.write(alloc, writer, param) catch return error.WriterError;
                },
                .push_nth_arg => |n| {
                    if (incremented and n < 3) {
                        const arg = switch (args[n - 1]) {
                            .string => unreachable,
                            .integer => |val| Parameter{
                                .integer = val + 1,
                            },
                        };
                        try stack.push(arg);
                    } else {
                        try stack.push(args[n - 1]);
                    }
                },
                .pop_string => {
                    const param = stack.pop().?;
                    const val: []const u8 = switch (param) {
                        .string => |val| val,
                        .integer => unreachable,
                    };
                    _ = writer.write(val) catch return error.WriterError;
                },
                .print_int => |val| {
                    var buf: [16]u8 = undefined;
                    const slice = std.fmt.bufPrint(&buf, "{d}", .{val}) catch unreachable;
                    _ = writer.write(slice) catch return error.WriterError;
                },
                .increment_first_two_params => {
                    incremented = true;
                },
                .push_strlen_pop => {
                    const val = stack.pop().?;
                    const str = val.string;
                    try stack.push(.{ .integer = @intCast(str.len) });
                },
                .bin_op => |op| {
                    const lhs = stack.pop().?;
                    const rhs = stack.pop().?;
                    try stack.push(switch (op) {
                        .add => .{ .integer = lhs.integer + rhs.integer },
                        .sub => .{ .integer = lhs.integer - rhs.integer },
                        .mul => .{ .integer = lhs.integer * rhs.integer },
                        .div => .{ .integer = @divFloor(lhs.integer, rhs.integer) },
                        .mod => .{ .integer = @mod(lhs.integer, rhs.integer) },
                        .bit_and => .{ .integer = lhs.integer & rhs.integer },
                        .bit_or => .{ .integer = lhs.integer | rhs.integer },
                        .bit_xor => .{ .integer = lhs.integer ^ rhs.integer },
                        .log_and => .{ .integer = if ((lhs.integer != 0) and (rhs.integer != 0)) @as(i32, 1) else 0 },
                        .log_or => .{ .integer = if ((rhs.integer != 0) or (rhs.integer != 0)) @as(i32, 1) else 0 },
                        .eq => .{ .integer = switch (lhs) {
                            .string => if (std.mem.eql(u8, lhs.string, rhs.string)) @as(i32, 1) else 0,
                            .integer => if (lhs.integer == rhs.integer) @as(i32, 1) else 0,
                        } },
                        .gt => .{ .integer = if (lhs.integer > rhs.integer) @as(i32, 1) else 0 },
                        .lt => .{ .integer = if (lhs.integer < rhs.integer) @as(i32, 1) else 0 },
                    });
                },
                .unary_op => |op| {
                    const val = stack.pop().?;
                    try stack.push(switch (op) {
                        .bit_not => .{ .integer = ~val.integer },
                        .log_not => .{ .integer = if (val.integer != 0) @as(i32, 1) else 0 },
                    });
                },
                .begin_conditional => {
                    // no-op
                },
                .test_expr => {
                    const val = stack.pop().?;
                    const int = val.integer;
                    if (int != 0) {
                        // then
                        skip_after_then = true;
                    } else {
                        // else
                        skip_until_else = true;
                    }
                },
                .else_branch => {
                    if (skip_after_then) {
                        skip_until_cond_end = true;
                    }

                    if (skip_until_else) {
                        skip_until_else = false;
                    }
                },
                .end_conditional => {
                    skip_after_then = false;
                    skip_until_cond_end = false;
                    skip_until_else = false;
                },
            }
        }
    }
};

pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();
        const List = std.SinglyLinkedList;
        const ListNode = struct {
            data: T,
            node: std.SinglyLinkedList.Node = .{},
        };

        allocator: std.mem.Allocator,
        list: List = List{},

        pub fn push(self: *Self, value: T) std.mem.Allocator.Error!void {
            const node_ptr = try self.allocator.create(ListNode);
            node_ptr.data = value;
            self.list.prepend(&node_ptr.node);
        }

        pub fn pop(self: *Self) ?T {
            const node_ptr = self.list.popFirst() orelse return null;
            const l: *ListNode = @fieldParentPtr("node", node_ptr);
            const data = l.data;
            self.allocator.destroy(l);
            return data;
        }

        pub fn peek(self: *const Self) ?*T {
            const node_ptr = self.list.first orelse return null;
            const l: *ListNode = @fieldParentPtr("node", node_ptr);
            return &l.data;
        }
    };
}
