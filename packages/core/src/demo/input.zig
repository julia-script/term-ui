const std = @import("std");
const term = @import("../cmd/term.zig");
const input = @import("../cmd/input.zig");
const AnyInputManager = @import("../cmd/input/manager.zig").AnyInputManager;
const Event = @import("../cmd/input/manager.zig").Event;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize terminal
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    // Save terminal state and enable raw mode
    const old_termios = try term.enableRawMode(stdin.handle);
    defer term.restoreTerminalMode(stdin.handle, old_termios) catch {};

    // Clear screen and position cursor
    try stdout.writer().print("\x1b[2J\x1b[H", .{});
    try stdout.writer().print("Input Demo - Press keys to see events (Ctrl+C to exit)\n\r", .{});
    try stdout.writer().print("----------------------------------------\n\r", .{});

    // Create input manager
    var input_manager = AnyInputManager{
        .allocator = allocator,
    };
    defer input_manager.deinit();

    // Simple event subscriber for printing
    const Printer = struct {
        fn printEvent(_: *anyopaque, event: Event) void {
            const writer = std.io.getStdOut().writer();

            switch (event.data) {
                .key => |key_event| {
                    writer.print("\rKey Event: ", .{}) catch {};
                    if (key_event.key) |k| {
                        writer.print("key={s} ", .{@tagName(k)}) catch {};
                    }
                    writer.print("codepoint={} action={s} mods=0x{x:0>2}\n\r", .{
                        key_event.codepoint,
                        @tagName(key_event.action),
                        event.modifiers,
                    }) catch {};

                    // Exit on Ctrl+C
                    if (key_event.codepoint == 3) { // Ctrl+C
                        writer.print("\rExiting...\n\r", .{}) catch {};
                        std.process.exit(0);
                    }
                },
                .mouse => |mouse| {
                    switch (mouse) {
                        .normal => |m| {
                            writer.print("\rMouse Event: action={s} x={} y={}\n\r", .{
                                @tagName(m.action),
                                m.x,
                                m.y,
                            }) catch {};
                        },
                        .extended => |m| {
                            writer.print("\rMouse Event: button={s} action={s} x={} y={}\n\r", .{
                                @tagName(m.button),
                                @tagName(m.action),
                                m.x,
                                m.y,
                            }) catch {};
                        },
                    }
                },
                .focus => |focus| {
                    writer.print("\rFocus Event: {s}\n\r", .{@tagName(focus)}) catch {};
                },
                .paste_chunk => |paste| {
                    writer.print("\rPaste Event: kind={s} chunk=\"{s}\"\n\r", .{
                        @tagName(paste.kind),
                        paste.chunk,
                    }) catch {};
                },
                else => {
                    writer.print("\rOther Event: {}\n\r", .{event}) catch {};
                },
            }
        }
    };

    // Subscribe to events
    var printer = {};
    try input_manager.subscribe(.{
        .context = &printer,
        .emitFn = Printer.printEvent,
    });

    // Enable mouse tracking
    try stdout.writer().print("\x1b[?1000h", .{}); // Enable mouse tracking
    try stdout.writer().print("\x1b[?1006h", .{}); // Enable SGR extended mouse mode
    defer {
        stdout.writer().print("\x1b[?1000l", .{}) catch {}; // Disable mouse tracking
        stdout.writer().print("\x1b[?1006l", .{}) catch {}; // Disable SGR extended mouse mode
    }

    // Read input buffer
    var buffer: [1024]u8 = undefined;

    // Main loop
    while (true) {
        const bytes_read = try stdin.read(&buffer);
        if (bytes_read == 0) continue;

        // Process input through the input system
        _ = input.handleRawBuffer(&input_manager, buffer[0..bytes_read], 0);
    }
}
