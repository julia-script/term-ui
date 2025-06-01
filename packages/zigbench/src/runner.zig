//! Benchmark runner implementation

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const BenchmarkOptions = types.BenchmarkOptions;
const BenchmarkResult = types.BenchmarkResult;

const format = @import("format.zig");
const colors = format.colors;

const visualization = @import("visualization.zig");

// Import types
const Benchmark = types.Benchmark;
const BenchContext = types.BenchContext;

pub const Runner = struct {
    allocator: Allocator,
    stderr: std.fs.File.Writer,

    pub fn init(allocator: Allocator) !Runner {
        return .{
            .allocator = allocator,
            .stderr = std.io.getStdErr().writer(),
        };
    }

    pub fn deinit(self: *Runner) void {
        _ = self;
    }

    pub fn runBenchmarks(self: *Runner, benchmarks: []const Benchmark) !void {
        // Print header
        try self.stderr.print("\n", .{});
        try self.printSystemInfo();
        try self.stderr.print("\n", .{});

        // Store results for comparison
        var results = std.ArrayList(struct {
            name: []const u8,
            result: BenchmarkResult,
            is_baseline: bool,
        }).init(self.allocator);
        defer results.deinit();

        // Calculate max name length for alignment
        var max_name_len: usize = 28; // minimum width
        for (benchmarks) |bench| {
            if (bench.name.len > max_name_len) {
                max_name_len = bench.name.len;
            }
        }

        // Print table header
        try self.printTableHeader(max_name_len);

        // Run each benchmark
        for (benchmarks) |bench| {
            const result = try self.runSingleBenchmark(bench, max_name_len);

            // Check if this is a baseline benchmark
            const is_baseline = if (bench.options.baseline) |baseline_pattern|
                std.mem.indexOf(u8, bench.name, baseline_pattern) != null
            else
                false;

            try results.append(.{
                .name = bench.name,
                .result = result,
                .is_baseline = is_baseline,
            });
        }

        // Generate visualizations if enabled
        if (results.items.len > 1) {
            // Bar plot
            if (benchmarks.len > 0 and benchmarks[0].options.show_plot) {
                try visualization.generateBarPlot(self.allocator, results.items, self.stderr);
            }

            // Baseline comparisons
            try self.printBaselineComparisons(results.items);
        }
    }

    fn runSingleBenchmark(self: *Runner, bench: Benchmark, max_name_len: usize) !BenchmarkResult {
        const options = bench.options;

        // Create tracking allocator if needed
        var gpa = if (options.track_memory)
            std.heap.GeneralPurposeAllocator(.{}){}
        else
            undefined;
        defer {
            if (options.track_memory) {
                _ = gpa.deinit();
            }
        }

        const bench_allocator = if (options.track_memory) gpa.allocator() else self.allocator;

        // Create RNG with fixed seed for reproducibility
        var prng = std.Random.DefaultPrng.init(42);

        // Create timer
        var timer = try std.time.Timer.start();

        // Create benchmark context
        var bench_ctx = BenchContext{
            .allocator = bench_allocator,
            .timer = &timer,
            .rng = prng.random(),
        };

        // Run setup if provided
        if (bench.setupFn) |setup| {
            try setup(bench.context, &bench_ctx);
        }
        defer if (bench.cleanupFn) |cleanup| {
            cleanup(bench.context, &bench_ctx);
        };

        // Warmup phase
        if (options.verbose) {
            try self.stderr.print("  Warming up...", .{});
        }

        for (0..options.warmup_iterations) |_| {
            try bench.runFn(bench.context, &bench_ctx);
        }

        // Determine iteration count
        timer.reset();
        try bench.runFn(bench.context, &bench_ctx);
        const single_run_ns = timer.read();

        const min_duration_ns = options.min_time_ms * 1_000_000;
        var iterations: u64 = 1;

        if (single_run_ns > 0 and single_run_ns < min_duration_ns) {
            iterations = @min(min_duration_ns / single_run_ns, options.max_iterations);
            if (iterations < 1) iterations = 1;
        }

        if (options.verbose) {
            try self.stderr.print(" Running {d} iterations...\n", .{iterations});
        }

        // Run benchmark iterations
        var samples = try std.ArrayList(u64).initCapacity(self.allocator, iterations);
        defer samples.deinit();

        var total_ns: u64 = 0;
        const memory_stats = struct {
            total_allocated: u64 = 0,
            peak_allocated: u64 = 0,
            allocation_count: u64 = 0,
        }{};

        for (0..iterations) |i| {
            bench_ctx.iteration = i;

            timer.reset();
            try bench.runFn(bench.context, &bench_ctx);
            const elapsed = timer.read();

            if (options.track_memory) {
                // For now, we'll skip detailed memory tracking since GPA doesn't expose stats directly
                // TODO: Consider using a custom tracking allocator wrapper if detailed memory stats are needed
            }

            try samples.append(elapsed);
            total_ns += elapsed;
        }

        // Calculate statistics
        std.mem.sort(u64, samples.items, {}, std.sort.asc(u64));

        const result = BenchmarkResult{
            .name = bench.name,
            .iterations = iterations,
            .total_ns = total_ns,
            .min_ns = samples.items[0],
            .max_ns = samples.items[samples.items.len - 1],
            .mean_ns = @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations)),
            .median_ns = getPercentile(samples.items, 0.50),
            .stddev_ns = calculateStdDev(samples.items, @as(f64, @floatFromInt(total_ns)) / @as(f64, @floatFromInt(iterations))),
            .p25_ns = getPercentile(samples.items, 0.25),
            .p75_ns = getPercentile(samples.items, 0.75),
            .p99_ns = getPercentile(samples.items, 0.99),
            .p999_ns = getPercentile(samples.items, 0.999),
            .total_allocated = if (options.track_memory) memory_stats.total_allocated else null,
            .total_freed = null,
            .peak_allocated = if (options.track_memory) memory_stats.peak_allocated else null,
            .allocation_count = if (options.track_memory) memory_stats.allocation_count else null,
        };

        // Report results
        try self.reportBenchmark(self.stderr.any(), result, max_name_len, samples.items);

        return result;
    }

    fn printSystemInfo(self: *Runner) !void {
        // Estimate CPU frequency
        const cpu_freq = estimateCpuFrequency();
        if (cpu_freq > 0) {
            try self.stderr.print("{s}clk{s}: ~{d:.2} GHz\n", .{ colors.gray, colors.reset, cpu_freq / 1_000_000_000.0 });
        }

        // CPU info
        if (try getCpuModel(self.allocator)) |model| {
            defer self.allocator.free(model);
            try self.stderr.print("{s}cpu{s}: {s}\n", .{ colors.gray, colors.reset, model });
        }

        // Runtime info
        try self.stderr.print("{s}runtime{s}: zig {s} ({s}-{s})\n", .{
            colors.gray,
            colors.reset,
            builtin.zig_version_string,
            @tagName(builtin.cpu.arch),
            @tagName(builtin.os.tag),
        });
    }

    fn printTableHeader(self: *Runner, max_name_len: usize) !void {
        _ = max_name_len;
        try self.stderr.print("{s}benchmark{s}                   avg (min … max) p75   p99    (min … top 1%)\n", .{ colors.bold, colors.reset });
        try self.stderr.print("-------------------------------------------", .{});
        try self.stderr.print(" -------------------------------\n", .{});
    }
    const Alignment = enum {
        left,
        right,
    };
    pub fn printAligned(writer: std.io.AnyWriter, text: []const u8, width: usize, alignment: Alignment) !void {
        switch (alignment) {
            .right => {
                if (text.len > width) {
                    try writer.print("{s}…", .{text[0 .. width - 1]});
                } else {
                    const padding = width - text.len;
                    try writer.writeByteNTimes(' ', padding);
                    try writer.writeAll(text);
                }
            },
            .left => {
                // if (text.len > width) {
                //     try writer.print("{s}…", .{text[0 .. width - 1]});
                // } else {
                // const padding = width - text.len;
                try writer.print("{s}", .{text});
                // try writer.writeByteNTimes(' ', padding);
                // }
            },
        }
    }

    fn reportBenchmark(self: *Runner, writer: std.io.AnyWriter, result: BenchmarkResult, max_name_len: usize, samples: []const u64) !void {
        _ = self; // autofix
        _ = max_name_len;
        const LEFT_COLUMN_WIDTH: usize = 43;
        const RIGHT_COLUMN_WIDTH: usize = 20;

        try writer.print("{s}\n", .{result.name});
        var buf = try std.BoundedArray(u8, 1024).init(0);
        const buf_writer = buf.writer().any();

        try format.formatDurationCompact(result.mean_ns, buf_writer);
        try buf_writer.writeAll("/iter");
        try printAligned(writer, buf.slice(), LEFT_COLUMN_WIDTH, .right);
        buf.clear();

        try writer.writeAll("  ");

        try format.formatDurationCompact(result.p75_ns, buf_writer);

        if (samples.len >= 10) {
            try buf_writer.writeAll(" ");
            try visualization.generateSimpleHistogram(samples, buf_writer);
        }

        try printAligned(writer, buf.slice(), RIGHT_COLUMN_WIDTH, .left);
        try writer.writeAll("\n");

        buf.clear();
        // buf_writer

        // Line 2: (min … max) range on left, p99 + long histogram on right
        try buf_writer.writeAll("(");
        try format.formatDurationCompact(@as(f64, @floatFromInt(result.min_ns)), buf_writer);
        try buf_writer.writeAll("…");
        try format.formatDurationCompact(@as(f64, @floatFromInt(result.max_ns)), buf_writer);
        try buf_writer.writeAll(")");
        try printAligned(writer, buf.slice(), LEFT_COLUMN_WIDTH, .right);
        buf.clear();

        try writer.writeAll("  ");

        try format.formatDurationCompact(result.p99_ns, buf_writer);

        if (samples.len >= 20) {
            try buf_writer.writeAll(" ");
            try visualization.generateLongHistogram(samples, buf_writer);
        }

        try printAligned(writer, buf.slice(), RIGHT_COLUMN_WIDTH, .left);
        buf.clear();

        try writer.writeAll("\n");

        // // Line 3: operations per second on left, memory info on right
        const ops_per_sec = result.opsPerSecond();
        try format.formatOpsPerSec(ops_per_sec, buf_writer);
        try buf_writer.writeAll(" ops/s");
        try printAligned(writer, buf.slice(), LEFT_COLUMN_WIDTH, .right);
        buf.clear();

        try writer.writeAll("  ");

        // Memory info if available
        if (result.total_allocated) |total_alloc| {
            if (total_alloc > 0) {
                const per_iter = @as(f64, @floatFromInt(total_alloc)) / @as(f64, @floatFromInt(result.iterations));
                try format.formatBytes(per_iter, buf_writer);
                try buf_writer.writeAll("/iter allocated");
            }
        }

        try printAligned(writer, buf.slice(), RIGHT_COLUMN_WIDTH, .left);
        buf.clear();

        try writer.writeAll("\n\n");
    }

    fn printBaselineComparisons(self: *Runner, results: anytype) !void {
        // Find baseline benchmarks
        var has_baselines = false;
        for (results) |res| {
            if (res.is_baseline) {
                has_baselines = true;
                break;
            }
        }

        if (!has_baselines) return;

        try self.stderr.print("\n{s}summary{s}\n", .{ colors.bold, colors.reset });

        // Compare against baselines
        for (results) |baseline| {
            if (baseline.is_baseline) {
                try self.stderr.print("  {s}\n", .{baseline.name});

                for (results) |res| {
                    if (!res.is_baseline) {
                        const ratio = res.result.mean_ns / baseline.result.mean_ns;

                        try self.stderr.print("   ", .{});
                        if (ratio < 1.0) {
                            const speedup = 1.0 / ratio;
                            try self.stderr.print("{s}{d:.2}x faster{s} than {s}", .{
                                colors.green,
                                speedup,
                                colors.reset,
                                res.name,
                            });
                        } else if (ratio > 1.0) {
                            try self.stderr.print("{s}{d:.2}x slower{s} than {s}", .{
                                colors.red,
                                ratio,
                                colors.reset,
                                res.name,
                            });
                        } else {
                            try self.stderr.print("same speed as {s}", .{res.name});
                        }
                        try self.stderr.print("\n", .{});
                    }
                }
                break; // Only use first baseline for now
            }
        }
    }
};

fn getPercentile(sorted_samples: []const u64, percentile: f64) f64 {
    const n = sorted_samples.len;
    const index = percentile * @as(f64, @floatFromInt(n - 1));
    const lower_index = @as(usize, @intFromFloat(@floor(index)));
    const upper_index = @min(lower_index + 1, n - 1);
    const fraction = index - @as(f64, @floatFromInt(lower_index));

    const lower_value = @as(f64, @floatFromInt(sorted_samples[lower_index]));
    const upper_value = @as(f64, @floatFromInt(sorted_samples[upper_index]));

    return lower_value + (upper_value - lower_value) * fraction;
}

fn calculateStdDev(samples: []const u64, mean: f64) f64 {
    var variance: f64 = 0;
    for (samples) |sample| {
        const diff = @as(f64, @floatFromInt(sample)) - mean;
        variance += diff * diff;
    }
    variance /= @as(f64, @floatFromInt(samples.len));
    return @sqrt(variance);
}

fn estimateCpuFrequency() f64 {
    if (builtin.os.tag == .macos) {
        var freq: u64 = 0;
        var size: usize = @sizeOf(u64);

        var result = std.c.sysctlbyname("hw.cpufrequency_max", &freq, &size, null, 0);
        if (result == 0 and freq > 0) {
            return @as(f64, @floatFromInt(freq));
        }

        result = std.c.sysctlbyname("hw.cpufrequency", &freq, &size, null, 0);
        if (result == 0 and freq > 0) {
            return @as(f64, @floatFromInt(freq));
        }

        // For Apple Silicon, hardcode for now
        return 3.2e9;
    }

    return 0;
}

fn getCpuModel(allocator: Allocator) !?[]u8 {
    if (builtin.os.tag == .macos) {
        var cpu_brand_buf: [256]u8 = undefined;
        var size: usize = cpu_brand_buf.len;
        const result = std.c.sysctlbyname("machdep.cpu.brand_string", &cpu_brand_buf, &size, null, 0);
        if (result == 0 and size > 0) {
            const cpu_brand = std.mem.sliceTo(&cpu_brand_buf, 0);
            return try allocator.dupe(u8, cpu_brand);
        }
    }

    return null;
}
