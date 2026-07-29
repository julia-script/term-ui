const std = @import("std");

pub fn parse(comptime N: type, section: []const u8) [num_capabilities]?i32 {
    const int_width = @divExact(@typeInfo(N).int.bits, 8);
    var caps: [num_capabilities]?i32 = undefined;
    @memset(&caps, null);
    var i: usize = 0;
    while (i < section.len) : (i += int_width) {
        const cap_index = i / int_width;
        const int = std.mem.readInt(N, section[i..][0..int_width], .little);
        caps[cap_index] = if (int == -1) null else @as(?i32, int);
    }
    return caps;
}

pub const Capability = enum {
    columns,
    init_tabs,
    lines,
    lines_of_memory,
    magic_cookie_glitch,
    padding_baud_rate,
    virtual_terminal,
    width_status_line,
    num_labels,
    label_height,
    label_width,
    max_attributes,
    maximum_windows,
    max_colors,
    max_pairs,
    no_color_video,
    buffer_capacity,
    dot_vert_spacing,
    dot_horz_spacing,
    max_micro_address,
    max_micro_jump,
    micro_col_size,
    micro_line_size,
    number_of_pins,
    output_res_char,
    output_res_line,
    output_res_horz_inch,
    output_res_vert_inch,
    print_rate,
    wide_char_size,
    buttons,
    bit_image_entwining,
    bit_image_type,
    magic_cookie_glitch_ul,
    carriage_return_delay,
    new_line_delay,
    backspace_delay,
    horizontal_tab_delay,
    number_of_function_keys,
};

pub const num_capabilities = @typeInfo(Capability).@"enum".field_names.len;

/// Numeric capabilities in the same order as `<term.h>`.
pub const NumericCapabilities = struct {
    const Self = @This();

    columns: ?i32,
    init_tabs: ?i32,
    lines: ?i32,
    lines_of_memory: ?i32,
    magic_cookie_glitch: ?i32,
    padding_baud_rate: ?i32,
    virtual_terminal: ?i32,
    width_status_line: ?i32,
    num_labels: ?i32,
    label_height: ?i32,
    label_width: ?i32,
    max_attributes: ?i32,
    maximum_windows: ?i32,
    max_colors: ?i32,
    max_pairs: ?i32,
    no_color_video: ?i32,
    buffer_capacity: ?i32,
    dot_vert_spacing: ?i32,
    dot_horz_spacing: ?i32,
    max_micro_address: ?i32,
    max_micro_jump: ?i32,
    micro_col_size: ?i32,
    micro_line_size: ?i32,
    number_of_pins: ?i32,
    output_res_char: ?i32,
    output_res_line: ?i32,
    output_res_horz_inch: ?i32,
    output_res_vert_inch: ?i32,
    print_rate: ?i32,
    wide_char_size: ?i32,
    buttons: ?i32,
    bit_image_entwining: ?i32,
    bit_image_type: ?i32,

    pub fn init(comptime N: type, section: []const u8) Self {
        const int_width = @divExact(@typeInfo(N).Int.bits, 8);
        var capabilities: NumericCapabilities = std.mem.zeroes(NumericCapabilities);
        const fields = @typeInfo(NumericCapabilities).Struct.fields;
        var int_i: usize = 0;
        inline for (fields) |field| {
            if (int_i >= section.len) {
                break;
            }
            const bytes = section[int_i..][0..int_width];
            const value = std.mem.readInt(N, bytes, .little);

            if (value == -1) {
                // value of -1 means capability isn't supported
                @field(capabilities, field.name) = null;
            } else {
                @field(capabilities, field.name) = @as(i32, value);
            }

            int_i += int_width;
        }
        return capabilities;
    }
};
