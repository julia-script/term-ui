//! Example of using zigbench programmatically
//!
//! This demonstrates how to manually run benchmarks and process results
//! without using the test runner.

const std = @import("std");
const zigbench = @import("zigbench_lib");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("\nzigbench Example - Manual Benchmark Runner\n", .{});
    try stdout.print("==========================================\n\n", .{});
    
    // Example 1: Simple benchmark
    try stdout.print("Running simple benchmarks...\n\n", .{});
    
    // Benchmark array sorting
    try benchmarkSort();
    
    // Benchmark string operations
    try benchmarkStrings();
    
    // Example 2: Using zigbench's test runner
    try stdout.print("\nTo run all benchmarks with statistics, use:\n", .{});
    try stdout.print("  zig build bench\n\n", .{});
    
    try stdout.print("To run specific benchmarks:\n", .{});
    try stdout.print("  zig build bench -- --bench-filter=sort\n\n", .{});
    
    try stdout.print("Configuration options:\n", .{});
    try stdout.print("  --bench-verbose     Show verbose output (default: true)\n", .{});
    try stdout.print("  --bench-warmup      Number of warmup iterations (default: 10)\n", .{});
    try stdout.print("  --bench-min-time    Minimum time per benchmark in ms (default: 100)\n", .{});
    try stdout.print("  --bench-max-iter    Maximum iterations (default: 1,000,000)\n\n", .{});
}

fn benchmarkSort() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;
    
    const sizes = [_]usize{ 10, 100, 1000, 10000 };
    
    for (sizes) |size| {
        // Prepare data
        const data = try allocator.alloc(i32, size);
        defer allocator.free(data);
        
        // Fill with random data
        var prng = std.Random.DefaultPrng.init(12345);
        const random = prng.random();
        for (data) |*item| {
            item.* = random.int(i32);
        }
        
        // Benchmark
        var timer = try std.time.Timer.start();
        const iterations: usize = @max(1, 1_000_000 / size);
        
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            // Copy data for each iteration
            const data_copy = try allocator.alloc(i32, size);
            defer allocator.free(data_copy);
            @memcpy(data_copy, data);
            
            // Sort
            std.mem.sort(i32, data_copy, {}, comptime std.sort.asc(i32));
        }
        
        const elapsed_ns = timer.read();
        const per_op_ns = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));
        
        try stdout.print("Sort {d} elements: ", .{size});
        try zigbench.formatDuration(per_op_ns, stdout.any());
        try stdout.print("/op ({d} iterations)\n", .{iterations});
    }
    try stdout.print("\n", .{});
}

fn benchmarkStrings() !void {
    const stdout = std.io.getStdOut().writer();
    const allocator = std.heap.page_allocator;
    
    try stdout.print("String operations:\n", .{});
    
    // Benchmark string concatenation
    {
        var timer = try std.time.Timer.start();
        const iterations = 10000;
        
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const str1 = "Hello, ";
            const str2 = "World!";
            const result = try std.fmt.allocPrint(allocator, "{s}{s}", .{ str1, str2 });
            defer allocator.free(result);
        }
        
        const elapsed_ns = timer.read();
        const per_op_ns = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));
        
        try stdout.print("String concatenation: ", .{});
        try zigbench.formatDuration(per_op_ns, stdout.any());
        try stdout.print("/op\n", .{});
    }
    
    // Benchmark string parsing
    {
        var timer = try std.time.Timer.start();
        const iterations = 100000;
        
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            const str = "12345";
            const num = try std.fmt.parseInt(i32, str, 10);
            _ = num;
        }
        
        const elapsed_ns = timer.read();
        const per_op_ns = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(iterations));
        
        try stdout.print("Parse integer: ", .{});
        try zigbench.formatDuration(per_op_ns, stdout.any());
        try stdout.print("/op\n", .{});
    }
    try stdout.print("\n", .{});
}

// Benchmark tests that will be picked up by the benchmark runner
test "bench: array sort small" {
    var data = [_]i32{ 5, 2, 8, 1, 9, 3, 7, 4, 6, 0 };
    std.mem.sort(i32, &data, {}, comptime std.sort.asc(i32));
    try std.testing.expect(data[0] == 0);
    try std.testing.expect(data[9] == 9);
}

test "bench: array sort medium" {
    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();
    
    var data: [100]i32 = undefined;
    for (&data) |*item| {
        item.* = random.int(i32);
    }
    
    std.mem.sort(i32, &data, {}, comptime std.sort.asc(i32));
    
    // Verify sorted
    var i: usize = 1;
    while (i < data.len) : (i += 1) {
        try std.testing.expect(data[i - 1] <= data[i]);
    }
}
