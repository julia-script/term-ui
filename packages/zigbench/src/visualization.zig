//! Visualization utilities for benchmark results

const std = @import("std");
const Allocator = std.mem.Allocator;
const format = @import("format.zig");
const colors = format.colors;

/// Generate a simple ASCII histogram
pub fn generateHistogram(samples: []const u64, mean_ns: f64, writer: anytype) !void {
    if (samples.len < 10) return;
    
    const histogram_width = 20;
    const blocks = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
    
    // Create bins
    const min = samples[0];
    const max = samples[samples.len - 1];
    if (min == max) return;
    
    var bins: [histogram_width]u32 = [_]u32{0} ** histogram_width;
    const bin_width = @as(f64, @floatFromInt(max - min)) / @as(f64, @floatFromInt(histogram_width));
    
    // Count samples in each bin
    for (samples) |sample| {
        const bin_idx = @min(
            @as(usize, @intFromFloat((@as(f64, @floatFromInt(sample - min)) / bin_width))),
            histogram_width - 1,
        );
        bins[bin_idx] += 1;
    }
    
    // Find max count for scaling
    var max_count: u32 = 0;
    for (bins) |count| {
        if (count > max_count) max_count = count;
    }
    
    if (max_count == 0) return;
    
    // Print histogram
    try writer.print(" ", .{});
    for (bins, 0..) |count, i| {
        const height = (count * 7) / max_count;
        const block_idx = @min(height, blocks.len - 1);
        
        // Color based on position relative to mean
        const bin_center = @as(f64, @floatFromInt(min)) + (@as(f64, @floatFromInt(i)) + 0.5) * bin_width;
        if (bin_center < mean_ns * 0.8) {
            try writer.print("{s}", .{colors.cyan});
        } else if (bin_center > mean_ns * 1.2) {
            try writer.print("{s}", .{colors.magenta});
        } else {
            try writer.print("{s}", .{colors.yellow});
        }
        
        try writer.print("{s}", .{blocks[block_idx]});
        try writer.print("{s}", .{colors.reset});
    }
}

/// Generate a horizontal bar plot for benchmark comparisons
pub fn generateBarPlot(allocator: Allocator, results: anytype, writer: anytype) !void {
    if (results.len == 0) return;
    
    // Structure for storing benchmark data for bar plots
    const BarPlotData = struct {
        name: []const u8,
        value: f64,
        color_index: usize,
    };
    
    // Prepare data for bar plot
    var plot_data = try std.ArrayList(BarPlotData).initCapacity(allocator, results.len);
    defer plot_data.deinit();
    
    for (results, 0..) |res, idx| {
        try plot_data.append(.{
            .name = res.name,
            .value = res.result.mean_ns,
            .color_index = idx,
        });
    }
    
    // Sort by performance (fastest first)
    std.mem.sort(BarPlotData, plot_data.items, {}, struct {
        fn lessThan(_: void, a: BarPlotData, b: BarPlotData) bool {
            return a.value < b.value;
        }
    }.lessThan);
    
    try writer.print("\n{s}Performance Comparison{s}\n", .{ colors.bold, colors.reset });
    
    // Find the maximum value for scaling
    var max_value: f64 = 0;
    var max_name_len: usize = 0;
    for (plot_data.items) |item| {
        if (item.value > max_value) max_value = item.value;
        if (item.name.len > max_name_len) max_name_len = item.name.len;
    }
    
    if (max_value == 0) return;
    
    const bar_width = 50;
    const bar_colors = [_][]const u8{ colors.green, colors.blue, colors.yellow, colors.magenta, colors.cyan, colors.red };
    
    // Calculate total width
    const total_width = max_name_len + bar_width + 20;
    
    // Draw the plot
    try writer.print("┌", .{});
    for (0..total_width) |_| {
        try writer.print("─", .{});
    }
    try writer.print("┐\n", .{});
    
    for (plot_data.items) |item| {
        // Print the label with padding
        try writer.print("│ {s}", .{item.name});
        const padding = max_name_len -| item.name.len;
        for (0..padding) |_| {
            try writer.print(" ", .{});
        }
        try writer.print(" │ ", .{});
        
        // Calculate bar length
        const bar_len = @as(usize, @intFromFloat((item.value / max_value) * @as(f64, @floatFromInt(bar_width))));
        const color = bar_colors[item.color_index % bar_colors.len];
        
        // Draw the bar
        try writer.print("{s}", .{color});
        for (0..bar_len) |_| {
            try writer.print("■", .{});
        }
        try writer.print("{s}", .{colors.reset});
        
        // Pad to align values
        for (bar_len..bar_width) |_| {
            try writer.print(" ", .{});
        }
        
        // Add value at the end
        try writer.print(" ", .{});
        try format.formatDurationCompact(item.value, writer);
        try writer.print("\n", .{});
    }
    
    // Draw bottom border
    try writer.print("└", .{});
    for (0..total_width) |_| {
        try writer.print("─", .{});
    }
    try writer.print("┘\n", .{});
}

/// Generate a simple histogram for the first line (shorter version)
pub fn generateSimpleHistogram(samples: []const u64, writer: anytype) !void {
    if (samples.len < 10) {
        try writer.print("█                    ", .{});
        return;
    }
    
    const histogram_width = 10;
    const blocks = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
    
    // Create bins
    const min = samples[0];
    const max = samples[samples.len - 1];
    if (min == max) {
        try writer.print("█                    ", .{});
        return;
    }
    
    var bins: [histogram_width]u32 = [_]u32{0} ** histogram_width;
    const bin_width = @as(f64, @floatFromInt(max - min)) / @as(f64, @floatFromInt(histogram_width));
    
    // Count samples in each bin
    for (samples) |sample| {
        const bin_idx = @min(
            @as(usize, @intFromFloat((@as(f64, @floatFromInt(sample - min)) / bin_width))),
            histogram_width - 1,
        );
        bins[bin_idx] += 1;
    }
    
    // Find max count for scaling
    var max_count: u32 = 0;
    for (bins) |count| {
        if (count > max_count) max_count = count;
    }
    
    if (max_count == 0) {
        try writer.print("█                    ", .{});
        return;
    }
    
    // Print histogram
    for (bins) |count| {
        const height = (count * 7) / max_count;
        const block_idx = @min(height, blocks.len - 1);
        try writer.print("{s}", .{blocks[block_idx]});
    }
    
    // Pad to fixed width when writing to buffer
    for (histogram_width..20) |_| {
        try writer.print(" ", .{});
    }
}

/// Generate a longer histogram for the second line (mitata style)
pub fn generateLongHistogram(samples: []const u64, writer: anytype) !void {
    if (samples.len < 20) {
        try writer.print("██▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁", .{});
        return;
    }
    
    const histogram_width = 21;
    const blocks = [_][]const u8{ "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
    
    // Create bins
    const min = samples[0];
    const max = samples[samples.len - 1];
    if (min == max) {
        try writer.print("██▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁", .{});
        return;
    }
    
    var bins: [histogram_width]u32 = [_]u32{0} ** histogram_width;
    const bin_width = @as(f64, @floatFromInt(max - min)) / @as(f64, @floatFromInt(histogram_width));
    
    // Count samples in each bin
    for (samples) |sample| {
        const bin_idx = @min(
            @as(usize, @intFromFloat((@as(f64, @floatFromInt(sample - min)) / bin_width))),
            histogram_width - 1,
        );
        bins[bin_idx] += 1;
    }
    
    // Find max count for scaling
    var max_count: u32 = 0;
    for (bins) |count| {
        if (count > max_count) max_count = count;
    }
    
    if (max_count == 0) {
        try writer.print("██▂▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁", .{});
        return;
    }
    
    // Print histogram - exactly 21 characters
    for (bins) |count| {
        const height = (count * 7) / max_count;
        const block_idx = @min(height, blocks.len - 1);
        try writer.print("{s}", .{blocks[block_idx]});
    }
}