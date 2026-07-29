const std = @import("std");

pub fn parse(section: []const u8) [num_capabilities]bool {
    std.debug.assert(section.len < num_capabilities);
    var caps = std.mem.zeroes([num_capabilities]bool);
    for (section, 0..) |byte, i| {
        caps[i] = (byte == 1);
    }
    return caps;
}

/// Boolean capabilities in the same order as `<term.h>`.
pub const Capability = enum {
    auto_left_margin,
    auto_right_margin,
    no_esc_ctlc,
    ceol_standout_glitch,
    eat_newline_glitch,
    erase_overstrike,
    generic_type,
    hard_copy,
    has_meta_key,
    has_status_line,
    insert_null_glitch,
    memory_above,
    memory_below,
    move_insert_mode,
    move_standout_mode,
    over_strike,
    status_line_esc_ok,
    dest_tabs_magic_smso,
    tilde_glitch,
    transparent_underline,
    xon_xoff,
    needs_xon_xoff,
    prtr_silent,
    hard_cursor,
    non_rev_rmcup,
    no_pad_char,
    non_dest_scroll_region,
    can_change,
    back_color_erase,
    hue_lightness_saturation,
    col_addr_glitch,
    cr_cancels_micro_mode,
    has_print_wheel,
    row_addr_glitch,
    semi_auto_rigth_margin,
    cpi_changes_res,
    lpi_changes_res,
    backspaces_with_bs,
    crt_no_scrolling,
    no_correctly_working_cr,
    gnu_has_meta_key,
    linefeed_is_newline,
    has_hardware_tabs,
    return_does_clr_eol,
};

pub const num_capabilities = @typeInfo(Capability).@"enum".field_names.len;
