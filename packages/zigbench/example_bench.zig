const std = @import("std");
const zigbench = @import("zigbench");
const testing = std.testing;

test "bench: array sorting" {
    try zigbench.simple("array sorting", struct {
        fn run(bench_ctx: *zigbench.BenchContext) !void {
            _ = bench_ctx;
            var rng = std.Random.DefaultPrng.init(42);
            var array: [1000]u32 = undefined;
            
            // Generate random data
            for (&array) |*item| {
                item.* = rng.random().int(u32);
            }
            
            // Sort the array
            std.mem.sort(u32, &array, {}, std.sort.asc(u32));
            
            // Verify it's sorted
            for (array[0..array.len-1], array[1..]) |a, b| {
                if (a > b) return error.NotSorted;
            }
        }
    }.run, .{
        .min_time_ms = 200,
        .warmup_iterations = 20,
    });
}

test "bench: string concatenation" {
    try zigbench.simple("string concatenation", struct {
        fn run(bench_ctx: *zigbench.BenchContext) !void {
            var arena = std.heap.ArenaAllocator.init(bench_ctx.allocator);
            defer arena.deinit();
            
            const allocator = arena.allocator();
            var result = try allocator.alloc(u8, 0);
            
            for (0..100) |_| {
                const old_len = result.len;
                result = try allocator.realloc(result, old_len + 5);
                @memcpy(result[old_len..], "hello");
            }
            
            if (result.len != 500) return error.InvalidLength;
        }
    }.run, .{
        .track_memory = true,
    });
}

test "bench: hashmap with allocations" {
    const HashMapBench = struct {
        size: usize,
        
        pub fn setup(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) !void {
            _ = ctx;
            _ = bench_ctx;
            // Could pre-generate keys here if needed
        }
        
        pub fn run(ctx: *anyopaque, bench_ctx: *zigbench.BenchContext) !void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            
            var map = std.StringHashMap(i32).init(bench_ctx.allocator);
            defer map.deinit();
            
            var key_storage = std.ArrayList([]u8).init(bench_ctx.allocator);
            defer {
                for (key_storage.items) |key| {
                    bench_ctx.allocator.free(key);
                }
                key_storage.deinit();
            }
            
            for (0..self.size) |i| {
                const key = try std.fmt.allocPrint(bench_ctx.allocator, "key_{d}", .{i});
                try key_storage.append(key);
                try map.put(key, @intCast(i));
            }
            
            if (map.count() != self.size) return error.InvalidCount;
        }
    };
    
    var ctx = HashMapBench{ .size = 100 };
    
    try zigbench.run(testing.allocator, &.{
        .{
            .name = "hashmap 100 entries",
            .context = &ctx,
            .setupFn = HashMapBench.setup,
            .runFn = HashMapBench.run,
            .options = .{
                .track_memory = true,
                .min_time_ms = 100,
            },
        },
    });
}