const std = @import("std");
const builtin = @import("builtin");

pub const Options = struct {
    iterations: usize = 100,
};

fn percentile(samples: []u64, perc: f64) u64 {
    const idx = @as(usize, @intFromFloat(perc * @as(f64, @floatFromInt(samples.len - 1))));
    return samples[idx];
}

fn runBench(name: []const u8, func: *const fn() anyerror!void, opts: Options) !void {
    const samples = try std.heap.page_allocator.alloc(u64, opts.iterations);
    defer std.heap.page_allocator.free(samples);

    var timer = try std.time.Timer.start();
    for (samples, 0..) |*s, i| {
        _ = i;
        const start = timer.read();
        try func();
        const end = timer.read();
        s.* = end - start;
    }

    std.sort.heap(u64, samples, {}, std.sort.asc(u64));

    var total: u128 = 0;
    for (samples) |s| total += s;

    const avg = total / samples.len;
    const min = samples[0];
    const max = samples[samples.len - 1];
    const p75 = percentile(samples, 0.75);
    const p99 = percentile(samples, 0.99);

    std.debug.print("{s}: avg {d} ns (min {d}, p75 {d}, p99 {d}, max {d})\n", .{ name, avg, min, p75, p99, max });
}


pub fn main() !void {
    // Print discovered test names
    for (builtin.test_functions) |t| {
        std.debug.print("found test: {s}\n", .{t.name});
    }

    for (builtin.test_functions) |t| {
        if (std.mem.indexOf(u8, t.name, "bench") == null) continue;
        try runBench(t.name, t.func, .{});
    }
}
