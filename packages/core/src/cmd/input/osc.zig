const std = @import("std");
const fmt = @import("../../fmt.zig");
pub const Osc = struct {
    pub const ParameterSelector = enum(u8) {

        // Set Text Parameters. For colors and font, if P t is a "?", the control sequence elicits a response which consists of the control sequence which would set the corresponding value. The dtterm control sequences allow you to determine the icon name and window title.

        // P s = 0 → Change Icon Name and Window Title to P t
        change_window_icon_and_title = 0,
        // P s = 1 → Change Icon Name to P t
        change_window_icon = 1,
        // P s = 2 → Change Window Title to P t
        change_window_title = 2,
        // P s = 3 → Set X property on top-level window. P t should be in the form "prop=value", or just "prop" to delete the property
        set_x_property = 3,
        // P s = 4 ; c ; spec → Change Color Number c to the color specified by spec, i.e., a name or RGB specification as per XParseColor. Any number of c name pairs may be given. The color numbers correspond to the ANSI colors 0-7, their bright versions 8-15, and if supported, the remainder of the 88-color or 256-color table.
        //If a "?" is given rather than a name or RGB specification, xterm replies with a control sequence of the same form which can be used to set the corresponding color. Because more than one pair of color number and specification can be given in one control sequence, xterm can make more than one reply.

        // The 8 colors which may be set using 1 0 through 1 7 are denoted dynamic colors, since the corresponding control sequences were the first means for setting xterm’s colors dynamically, i.e., after it was started. They are not the same as the ANSI colors. One or more parameters is expected for P t . Each successive parameter changes the next color in the list. The value of P s tells the starting point in the list. The colors are specified by name or RGB specification as per XParseColor.

        // If a "?" is given rather than a name or RGB specification, xterm replies with a control sequence of the same form which can be used to set the corresponding dynamic color. Because more than one pair of color number and specification can be given in one control sequence, xterm can make more than one reply.
        change_color_number = 4,
        // P s = 1 0 → Change VT100 text foreground color to P t
        change_foreground_color = 10,
        // P s = 1 1 → Change VT100 text background color to P t
        change_background_color = 11,
        // P s = 1 2 → Change text cursor color to P t
        change_cursor_color = 12,
        // P s = 1 3 → Change mouse foreground color to P t
        change_mouse_foreground_color = 13,
        // P s = 1 4 → Change mouse background color to P t
        change_mouse_background_color = 14,
        // P s = 1 5 → Change Tektronix foreground color to P t
        change_tektronix_foreground_color = 15,
        // P s = 1 6 → Change Tektronix background color to P t
        change_tektronix_background_color = 16,
        // P s = 1 7 → Change highlight color to P t
        change_highlight_color = 17,
        // P s = 1 8 → Change Tektronix cursor color to P t
        change_tektronix_cursor_color = 18,

        // P s = 4 6 → Change Log File to P t (normally disabled by a compile-time option)
        change_log_file = 46,

        // P s = 5 0 → Set Font to P t If P t begins with a "#", index in the font menu, relative (if the next character is a plus or minus sign) or absolute. A number is expected but not required after the sign (the default is the current entry for relative, zero for absolute indexing).
        change_font = 50,

        // P s = 5 1 (reserved for Emacs shell)
        change_emacs_shell = 51,

        // P s = 5 2 → Manipulate Selection Data. These controls may be disabled using the allowWindowOps resource. The parameter P t is parsed as
        change_selection_data = 52,

        // A non-xterm extension is the hyperlink, ESC ]8;;link ST from 2017
        hyperlink = 8,
        _,
    };
    parameter_selector: ParameterSelector,
    parameter_text: []const u8,

    pub fn parse(sequence: []const u8) ?Osc {
        const start_bytes: usize = switch (sequence[0]) {
            '\x1b' => switch (sequence[1]) {
                ']' => 2,
                else => return null,
            },
            0x92 => 1,
            else => return null,
        };
        // Control strings (like OSC and DCS) can be terminated in three different ways:
        // BEL (0x07) - A single bell character
        // ST (0x9C) - A single "String Terminator" character
        // ESC \ (0x1B 0x5C) - A two-byte sequence with ESC followed by backslash
        const end_bytes_len: usize = switch (sequence[sequence.len - 1]) {
            '\\' => switch (sequence[sequence.len - 2]) {
                0x1b => 2,
                else => return null,
            },
            0x07, 0x9c => 1,
            else => return null,
        };
        var command_bytes_end = start_bytes + 1;
        while (command_bytes_end < sequence.len) {
            if (sequence[command_bytes_end] == ';') {
                break;
            }
            command_bytes_end += 1;
        }
        const command: u8 = std.fmt.parseUnsigned(u8, sequence[start_bytes..command_bytes_end], 10) catch return null;
        const body_bytes = sequence[command_bytes_end + 1 .. sequence.len - end_bytes_len];
        return .{
            .parameter_selector = @fromBackingInt(@intCast(command)),
            .parameter_text = body_bytes,
        };
    }
};
