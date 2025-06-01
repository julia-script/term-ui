const std = @import("std");
const zigbench = @import("zigbench");
const testing = std.testing;

// Example: comparing different sorting algorithms
// Use one as baseline and compare others against it

test "bench: sorting comparison" {
    const SortBench = struct {
        array: []u32,
        original: []const u32,
        
        pub fn setup(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            
            // Allocate working array
            self.array = try bench_ctx.allocator.alloc(u32, self.original.len);
        }
        
        pub fn bubbleSort(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = bench_ctx;
            
            // Copy original data
            @memcpy(self.array, self.original);
            
            // Bubble sort (intentionally slow for baseline)
            for (0..self.array.len - 1) |i| {
                for (0..self.array.len - i - 1) |j| {
                    if (self.array[j] > self.array[j + 1]) {
                        const temp = self.array[j];
                        self.array[j] = self.array[j + 1];
                        self.array[j + 1] = temp;
                    }
                }
            }
            
            // Verify it's sorted
            for (self.array[0..self.array.len-1], self.array[1..]) |a, b| {
                if (a > b) return error.NotSorted;
            }
        }
        
        pub fn stdSort(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = bench_ctx;
            
            // Copy original data
            @memcpy(self.array, self.original);
            
            // Standard library sort
            std.mem.sort(u32, self.array, {}, std.sort.asc(u32));
            
            // Verify it's sorted
            for (self.array[0..self.array.len-1], self.array[1..]) |a, b| {
                if (a > b) return error.NotSorted;
            }
        }
        
        pub fn insertionSort(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            _ = bench_ctx;
            
            // Copy original data
            @memcpy(self.array, self.original);
            
            // Insertion sort
            for (1..self.array.len) |i| {
                const key = self.array[i];
                var j: isize = @intCast(i - 1);
                while (j >= 0 and self.array[@intCast(j)] > key) : (j -= 1) {
                    self.array[@intCast(j + 1)] = self.array[@intCast(j)];
                }
                self.array[@intCast(j + 1)] = key;
            }
            
            // Verify it's sorted
            for (self.array[0..self.array.len-1], self.array[1..]) |a, b| {
                if (a > b) return error.NotSorted;
            }
        }
        
        pub fn cleanup(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            bench_ctx.allocator.free(self.array);
        }
    };
    
    // Test data
    var original: [100]u32 = undefined;
    
    // Initialize with reproducible random data
    var rng = std.Random.DefaultPrng.init(42);
    for (&original) |*item| {
        item.* = rng.random().int(u32);
    }
    
    var ctx = SortBench{ 
        .array = undefined,
        .original = &original,
    };
    
    try zigbench.run(testing.allocator, &.{
        .{
            .name = "baseline sort (bubble sort)",
            .context = &ctx,
            .setupFn = SortBench.setup,
            .runFn = SortBench.bubbleSort,
            .cleanupFn = SortBench.cleanup,
            .options = .{
                .min_time_ms = 100,
                .warmup_iterations = 50,
                .baseline = "baseline sort", // Mark this as baseline
            },
        },
        .{
            .name = "std sort",
            .context = &ctx,
            .setupFn = SortBench.setup,
            .runFn = SortBench.stdSort,
            .cleanupFn = SortBench.cleanup,
            .options = .{
                .min_time_ms = 100,
                .warmup_iterations = 50,
            },
        },
        .{
            .name = "insertion sort",
            .context = &ctx,
            .setupFn = SortBench.setup,
            .runFn = SortBench.insertionSort,
            .cleanupFn = SortBench.cleanup,
            .options = .{
                .min_time_ms = 100,
                .warmup_iterations = 50,
            },
        },
    });
}