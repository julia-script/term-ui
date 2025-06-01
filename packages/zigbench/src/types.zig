//! Common types for zigbench

const std = @import("std");
const Allocator = std.mem.Allocator;


/// Options for running a benchmark
pub const BenchmarkOptions = struct {
    /// Number of warmup iterations
    warmup_iterations: u64 = 10,

    /// Minimum time to run each benchmark (in milliseconds)
    min_time_ms: u64 = 100,

    /// Maximum iterations per benchmark
    max_iterations: u64 = 1_000_000,

    /// Show verbose output
    verbose: bool = false,

    /// Track memory allocations
    track_memory: bool = false,
    
    /// Baseline benchmark pattern - benchmarks matching this will be marked as baseline
    baseline: ?[]const u8 = null,
    
    /// Show bar plot visualization
    show_plot: bool = true,
};

/// Result of running a benchmark
pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: u64,
    total_ns: u64,
    min_ns: u64,
    max_ns: u64,
    mean_ns: f64,
    median_ns: f64,
    stddev_ns: f64,
    p25_ns: f64,
    p75_ns: f64,
    p99_ns: f64,
    p999_ns: f64,
    // Memory tracking
    total_allocated: ?u64,
    total_freed: ?u64,
    peak_allocated: ?u64,
    allocation_count: ?u64,

    /// Get the mean time per operation in nanoseconds
    pub fn meanNanoseconds(self: BenchmarkResult) f64 {
        return self.mean_ns;
    }

    /// Get the mean time per operation in microseconds
    pub fn meanMicroseconds(self: BenchmarkResult) f64 {
        return self.mean_ns / 1000.0;
    }

    /// Get the mean time per operation in milliseconds
    pub fn meanMilliseconds(self: BenchmarkResult) f64 {
        return self.mean_ns / 1_000_000.0;
    }

    /// Get operations per second based on mean time
    pub fn opsPerSecond(self: BenchmarkResult) f64 {
        return 1_000_000_000.0 / self.mean_ns;
    }

    /// Format the result as a string
    pub fn format(
        self: BenchmarkResult,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("{s}: ", .{self.name});
        try @import("format.zig").formatDuration(self.mean_ns, writer);
        try writer.print("/op", .{});
    }
};

/// Context provided to benchmark functions
pub const BenchContext = struct {
    /// Allocator for the benchmark to use - wrapped for tracking
    allocator: Allocator,
    
    /// Current iteration number (useful for varying behavior)
    iteration: usize = 0,
    
    /// Timer for custom measurements (if needed)
    timer: *std.time.Timer,
    
    /// Random number generator (for deterministic randomness)
    rng: std.Random,
    
};

/// Benchmark definition using context pattern
pub const Benchmark = struct {
    /// Name of the benchmark
    name: []const u8,
    
    /// User-provided context pointer
    context: *anyopaque,
    
    /// Optional setup function that can fail
    setupFn: ?*const fn (context: *anyopaque, bench_ctx: *BenchContext) anyerror!void = null,
    
    /// Main benchmark function
    runFn: *const fn (context: *anyopaque, bench_ctx: *BenchContext) anyerror!void,
    
    /// Cleanup function (should not fail)
    cleanupFn: ?*const fn (context: *anyopaque, bench_ctx: *BenchContext) void = null,
    
    /// Options for this benchmark
    options: BenchmarkOptions = .{},
};