# zigbench

A benchmarking framework for Zig that integrates with Zig's test runner.

## Features

- **Test Runner Integration**: Write benchmarks as regular Zig tests with "bench" in the name
- **Statistical Analysis**: Automatically calculates mean, median, min, max, and standard deviation
- **Automatic Iteration Scaling**: Determines the optimal number of iterations to reach a minimum runtime
- **Warmup Phase**: Runs warmup iterations before measurement to ensure stable results
- **Filtering**: Run specific benchmarks using pattern matching
- **Configurable**: Control warmup iterations, minimum runtime, and maximum iterations

## Quick Start

### Writing Benchmarks

Write benchmarks as regular Zig tests with "bench" in the name:

```zig
test "bench: my algorithm" {
    // Your benchmark code here
    var result: i32 = 0;
    for (0..1000) |i| {
        result += @intCast(i);
    }
    try std.testing.expect(result > 0);
}
```

### Running Benchmarks

```bash
# Run all benchmarks
zig build bench

# Run benchmarks matching a filter
zig build bench -Dbench-filter=sort

# Configure benchmark parameters
zig build bench -Dbench-warmup=20 -Dbench-min-time=200
```

## Configuration Options

- `-Dbench-filter=<pattern>`: Only run benchmarks containing this string
- `-Dbench-verbose=<true/false>`: Show verbose output (default: true)
- `-Dbench-warmup=<n>`: Number of warmup iterations (default: 10)
- `-Dbench-min-time=<ms>`: Minimum time to run each benchmark in milliseconds (default: 100)
- `-Dbench-max-iter=<n>`: Maximum iterations per benchmark (default: 1,000,000)

## Example Output

```
================================================================================
Running benchmarks...
================================================================================

  Warming up... Running 171526 iterations...
bench: array sort small:
  Iterations: 171526
  Mean:       555.84 ns
  Median:     500.00 ns
  Min:        375.00 ns
  Max:        1.05 ms
  Std Dev:    2.58 µs (463.6%)

================================================================================
Ran 1 benchmark in 194.42ms
================================================================================
```

## Advanced Usage

### Using zigbench as a Library

You can also use zigbench programmatically:

```zig
const zigbench = @import("zigbench");

// Format durations
var writer = std.io.getStdOut().writer();
try zigbench.formatDuration(1234.5, writer.any()); // Outputs: "1.23 µs"
```

### Integration with Existing Projects

1. Copy `benchmark_runner.zig` to your project
2. Update your `build.zig` to add a benchmark step:

```zig
const bench_tests = b.addTest(.{
    .root_module = your_module,
    .test_runner = .{
        .path = b.path("benchmark_runner.zig"),
        .mode = .simple,
    },
});

const run_bench = b.addRunArtifact(bench_tests);
const bench_step = b.step("bench", "Run benchmarks");
bench_step.dependOn(&run_bench.step);
```

## Benchmark Best Practices

1. **Use meaningful operations**: Ensure your benchmark code isn't optimized away
2. **Include assertions**: Verify correctness within benchmarks using `try std.testing.expect()`
3. **Avoid setup in loops**: Do expensive setup outside the measured code
4. **Consider variance**: High standard deviation (>50%) may indicate unstable measurements
5. **Use appropriate data sizes**: Test with realistic input sizes for your use case

## How It Works

zigbench leverages Zig's test runner infrastructure by:

1. Iterating over `builtin.test_functions` to find benchmark functions
2. Running a warmup phase to stabilize performance
3. Automatically determining iteration count based on runtime
4. Collecting timing samples for each iteration
5. Computing statistical metrics from the samples
6. Presenting results in a readable format

The benchmark runner ensures each benchmark runs for at least the configured minimum time (default 100ms) to get stable measurements while avoiding excessive runtime for fast operations.