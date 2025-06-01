//! zigbench - A benchmarking library for Zig
//!
//! This library provides utilities for writing and running benchmarks in Zig.
//! Uses a context-based API similar to std.sort for maximum flexibility.
//!
//! ## Usage
//!
//! ```zig
//! test "bench: my function" {
//!     try zigbench.simple("addition", struct {
//!         fn run(bench_ctx: *BenchContext) !void {
//!             var x: i32 = 0;
//!             for (0..1000) |_| {
//!                 x = x +% 1;
//!             }
//!             std.mem.doNotOptimizeAway(x);
//!         }
//!     }.run, .{});
//! }
//! ```

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

// Re-export key types
pub const BenchmarkOptions = @import("types.zig").BenchmarkOptions;
pub const BenchmarkResult = @import("types.zig").BenchmarkResult;
pub const BenchContext = @import("types.zig").BenchContext;
pub const Benchmark = @import("types.zig").Benchmark;
pub const formatDuration = @import("format.zig").formatDuration;

/// Simple benchmark function signature for convenience
pub const SimpleBenchFn = *const fn (bench_ctx: *BenchContext) anyerror!void;

/// Run a set of benchmarks
pub fn run(allocator: Allocator, benchmarks: []const Benchmark) !void {
    var runner = try Runner.init(allocator);
    defer runner.deinit();
    
    try runner.runBenchmarks(benchmarks);
}

/// Run a simple benchmark without setup/cleanup
pub fn simple(name: []const u8, comptime func: SimpleBenchFn, options: BenchmarkOptions) !void {
    const bench = Benchmark{
        .name = name,
        .context = undefined, // No context needed
        .runFn = struct {
            fn run(_: *anyopaque, bench_ctx: *BenchContext) anyerror!void {
                return @call(.auto, func, .{bench_ctx});
            }
        }.run,
        .options = options,
    };
    
    try run(std.testing.allocator, &.{bench});
}

// Internal runner implementation
const Runner = @import("runner.zig").Runner;

// Example benchmarks for testing
const testing = std.testing;

test "bench: simple addition" {
    try simple("simple addition", struct {
        fn run(bench_ctx: *BenchContext) !void {
            _ = bench_ctx;
            var x: i32 = 0;
            for (0..1000) |_| {
                x = x +% 1;
            }
            std.mem.doNotOptimizeAway(&x);
        }
    }.run, .{});
}

test "bench: memory allocation" {
    try simple("memory allocation", struct {
        fn run(bench_ctx: *BenchContext) !void {
            var list = std.ArrayList(i32).init(bench_ctx.allocator);
            defer list.deinit();

            try list.ensureTotalCapacity(1000);
            for (0..1000) |i| {
                try list.append(@intCast(i));
            }
        }
    }.run, .{ .track_memory = true });
}

test "bench: string formatting" {
    try simple("string formatting", struct {
        fn run(bench_ctx: *BenchContext) !void {
            _ = bench_ctx;
            var buf: [256]u8 = undefined;
            const result = try std.fmt.bufPrint(&buf, "Hello, {s}! The answer is {d}.", .{ "World", 42 });
            std.mem.doNotOptimizeAway(result.ptr);
        }
    }.run, .{});
}

test "bench: hash map operations" {
    const HashMapBench = struct {
        size: usize,
        
        pub fn run(ctx: *anyopaque, bench_ctx: *BenchContext) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            var map = std.AutoHashMap(u32, u32).init(bench_ctx.allocator);
            defer map.deinit();

            for (0..self.size) |i| {
                try map.put(@intCast(i), @intCast(i * 2));
            }

            for (0..self.size) |i| {
                const value = map.get(@intCast(i));
                if (value.? != i * 2) return error.InvalidValue;
            }
        }
    };
    
    var ctx = HashMapBench{ .size = 100 };
    
    try run(testing.allocator, &.{
        .{
            .name = "hashmap 100 entries",
            .context = &ctx,
            .runFn = HashMapBench.run,
            .options = .{ .track_memory = true },
        },
    });
}