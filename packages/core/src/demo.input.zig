const std = @import("std");
const builtin = @import("builtin");
const input = @import("cmd/input.zig");
const AnyInputManager = @import("cmd/input/manager.zig").AnyInputManager;
const Event = @import("cmd/input/manager.zig").Event;

pub const std_options: std.Options = .{
    // .log_level = if (is_debug) .debug else .err,
    .log_level = .err,
};
var should_exist: bool = false;

const InputLogger = struct {
    fn emitEventFn(context: *anyopaque, event: Event) void {
        _ = context;
        const stdout = std.io.getStdOut().writer();
        stdout.print("{any}\r\n\r\n", .{event}) catch return;
        switch (event.data) {
            .key => |key| {
                if (key.codepoint == 'c' and event.modifiers & Event.mod.CTRL != 0) {
                    should_exist = true;
                }
            },
            else => {},
        }

        // switch (event.data) {
        //     .key => |key| {
        //         stdout.print("\rKey: ", .{}) catch return;
        //         if (key.key) |k| {
        //             stdout.print("{s} ", .{@tagName(k)}) catch return;
        //         }
        //         stdout.print("cp={} action={s} mods=0x{x:0>2}\r\n", .{
        //             key.codepoint,
        //             @tagName(key.action),
        //             event.modifiers,
        //         }) catch return;
        //     },
        //     .mouse => |mouse| {
        //         switch (mouse) {
        //             .normal => |m| {
        //                 stdout.print("\rMouse: action={s} x={} y={}\r\n", .{
        //                     @tagName(m.action),
        //                     m.x,
        //                     m.y,
        //                 }) catch return;
        //             },
        //             .extended => |m| {
        //                 stdout.print("\rMouse: button={s} action={s} x={} y={}\r\n", .{
        //                     @tagName(m.button),
        //                     @tagName(m.action),
        //                     m.x,
        //                     m.y,
        //                 }) catch return;
        //             },
        //         }
        //     },
        //     .focus => |focus| {
        //         stdout.print("\rFocus: {s}\r\n", .{@tagName(focus)}) catch return;
        //     },
        //     .paste_chunk => |paste| {
        //         stdout.print("\rPaste: kind={s} chunk=\"{s}\"\r\n", .{
        //             @tagName(paste.kind),
        //             paste.chunk,
        //         }) catch return;
        //     },
        //     else => {
        //         stdout.print("\rEvent: {}\r\n", .{event}) catch return;
        //     },
        // }
    }
};

// Simple raw mode implementation
fn enableRawMode(handle: std.posix.fd_t) !std.posix.termios {
    const old = try std.posix.tcgetattr(handle);
    var new = old;

    // Set raw mode by disabling various flags
    // Input modes - turn off: BRKINT, ICRNL, INPCK, ISTRIP, IXON
    new.iflag.BRKINT = false;
    // new.iflag.ICRNL = false;
    new.iflag.INPCK = false;
    new.iflag.ISTRIP = false;
    new.iflag.IXON = false;

    // Output modes - disable post processing
    new.oflag.OPOST = false;

    // Control modes - set 8 bit chars
    new.cflag.CSIZE = .CS8;

    // Local modes - turn off: ECHO, ICANON, IEXTEN, ISIG
    new.lflag.ECHO = false;
    new.lflag.ICANON = false;
    new.lflag.IEXTEN = false;
    new.lflag.ISIG = false;

    // Control chars - set return condition: min number of bytes and timer
    new.cc[6] = 1; // VMIN
    new.cc[5] = 0; // VTIME

    try std.posix.tcsetattr(handle, .FLUSH, new);
    return old;
}

fn restoreTerminalMode(handle: std.posix.fd_t, termios: std.posix.termios) !void {
    try std.posix.tcsetattr(handle, .FLUSH, termios);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Use stdin/stdout instead of /dev/tty for compatibility
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Set raw mode
    const old_termios = try enableRawMode(stdin.handle);
    defer restoreTerminalMode(stdin.handle, old_termios) catch {};

    // Initialize input manager
    var input_manager = AnyInputManager{
        .allocator = allocator,
    };
    defer input_manager.deinit();

    var logger = InputLogger{};
    try input_manager.subscribe(.{
        .context = @ptrCast(&logger),
        .emitFn = InputLogger.emitEventFn,
    });

    const writer = stdout.writer();

    // Clear screen and setup
    try writer.writeAll("\x1b[2J\x1b[H");
    try writer.writeAll("Input Demo - Press keys to see events (Ctrl+C to exit)\r\n");
    try writer.writeAll("----------------------------------------\r\n");

    // Enable mouse tracking
    try writer.writeAll("\x1b[?1000h"); // Enable mouse tracking
    try writer.writeAll("\x1b[?1006h"); // Enable SGR extended mouse mode
    defer {
        writer.writeAll("\x1b[?1000l") catch {}; // Disable mouse tracking
        writer.writeAll("\x1b[?1006l") catch {}; // Disable SGR extended mouse mode
    }
    // Enable kitty keyboard protocol
    try writer.writeAll("\x1b[>31u");
    defer writer.writeAll("\x1b[<31u") catch {};

    // Main loop
    var buffer: [1024]u8 = undefined;
    while (true) {
        if (should_exist) {
            break;
        }
        const bytes_read = try stdin.read(&buffer);
        if (bytes_read == 0) continue;

        _ = input.handleRawBuffer(&input_manager, buffer[0..bytes_read], 0);
        for (buffer[0..bytes_read]) |byte| {
            if (byte == 3) { // Ctrl+C
                should_exist = true;
            }
        }
        // Check for Ctrl+C

    }
}
