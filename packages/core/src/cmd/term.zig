const std = @import("std");

fn csi(comptime cmd: []const u8) []const u8 {
    return "\x1b[" ++ cmd;
}

const KittyMode = struct {
    pub const disambiguate: u8 = 0b1;
    pub const report_events: u8 = 0b10;
    pub const report_alternates: u8 = 0b100;
    pub const report_all_keys: u8 = 0b1000;
    pub const report_text: u8 = 0b10000;
    pub const all: u8 = 0b11111;

    pub const KittyOp = enum(u8) {
        enable = '>',
        disable = '<',
    };
    pub inline fn op(comptime operation: KittyOp, comptime mode: u8) []const u8 {
        const operation_char: u8 = @backingInt(operation);
        return (std.fmt.comptimePrint("{c}{d}h", .{ operation_char, mode }));
    }
    pub const query = csi("?u");
};
// Kitty

test "KittyMode" {
    // std.debug.print(
    //     "KittyMode.disambiguate: {s}\n",
    //     .{
    //         KittyMode.op(.enable, KittyMode.all),
    //     },
    // );
    std.debug.print("{s}", .{KittyMode.query});

    // const kitty_mode = KittyMode.disambiguate;
}
