const mod = @import("mod.zig");
const LayoutResult = mod.LayoutResult;
const RunMode = mod.ContainerContext.RunMode;
const AvailableSpace = mod.constants.AvailableSpace;
const Point = @import("../point.zig").Point;
const std = @import("std");

const Cache = @This();

fn CacheEntry(comptime T: type) type {
    return struct {
        known_dimensions: Point(?f32),
        available_space: Point(AvailableSpace),
        content: T,
    };
}

const CACHE_SIZE: usize = 9;
final_layout_entry: ?CacheEntry(LayoutResult) = null,
measure_entries: [CACHE_SIZE]?CacheEntry(Point(f32)) = EMPTY_MEASURE_ENTRIES,

pub fn computeCacheSlot(known_dimensions: Point(?f32), available_space: Point(AvailableSpace)) usize {
    const has_known_width = known_dimensions.x != null;
    const has_known_height = known_dimensions.y != null;
    if (has_known_width and has_known_height) {
        return 0;
    }
    if (has_known_width and !has_known_height) {
        if (available_space.y == .min_content) {
            return 2;
        }
        return 1;
    }
    if (has_known_height and !has_known_width) {
        if (available_space.x == .min_content) {
            return 4;
        }
        return 3;
    }
    switch (available_space.x) {
        .max_content, .definite => {
            switch (available_space.y) {
                .max_content, .definite => return 5,
                .min_content => return 6,
            }
        },
        .min_content => {
            switch (available_space.y) {
                .max_content, .definite => return 7,
                .min_content => return 8,
            }
        },
    }
}

pub fn get(self: *Cache, known_dimensions: Point(?f32), available_space: Point(AvailableSpace), run_mode: RunMode) ?LayoutResult {
    switch (run_mode) {
        .perform_layout => {
            const entry = self.final_layout_entry orelse return null;
            const cached_size = entry.content.size;
            if ((known_dimensions.x == entry.known_dimensions.x or known_dimensions.x == cached_size.x) and
                (known_dimensions.y == entry.known_dimensions.y or known_dimensions.y == cached_size.y) and
                (known_dimensions.x != null or entry.available_space.x.isRoughlyEqual(available_space.x)) and
                (known_dimensions.y != null or entry.available_space.y.isRoughlyEqual(available_space.y)))
            {
                return entry.content;
            }
            return null;
        },
        .compute_size => {
            for (self.measure_entries) |entry_option| {
                const entry = entry_option orelse continue;
                const cached_size = entry.content;
                if ((known_dimensions.x == entry.known_dimensions.x or known_dimensions.x == cached_size.x) and
                    (known_dimensions.y == entry.known_dimensions.y or known_dimensions.y == cached_size.y) and
                    (known_dimensions.x != null or entry.available_space.x.isRoughlyEqual(available_space.x)) and
                    (known_dimensions.y != null or entry.available_space.y.isRoughlyEqual(available_space.y)))
                {
                    return LayoutResult{ .size = cached_size }; // other fields default zero
                }
            }
            return null;
        },
    }
}

pub fn store(self: *Cache, known_dimensions: Point(?f32), available_space: Point(AvailableSpace), run_mode: RunMode, layout_output: LayoutResult) void {
    switch (run_mode) {
        .perform_layout => {
            self.final_layout_entry = .{
                .known_dimensions = known_dimensions,
                .available_space = available_space,
                .content = layout_output,
            };
        },
        .compute_size => {
            const cache_slot = computeCacheSlot(known_dimensions, available_space);
            self.measure_entries[cache_slot] = .{
                .known_dimensions = known_dimensions,
                .available_space = available_space,
                .content = layout_output.size,
            };
        },
    }
}

const EMPTY_MEASURE_ENTRIES = [_]?CacheEntry(Point(f32)){null} ** CACHE_SIZE;
pub fn clear(self: *Cache) void {
    self.final_layout_entry = null;
    self.measure_entries = EMPTY_MEASURE_ENTRIES;
}

pub fn isEmpty(self: *Cache) bool {
    if (self.final_layout_entry != null) {
        return false;
    }
    for (self.measure_entries) |entry| {
        if (entry != null) {
            return false;
        }
    }
    return true;
}
