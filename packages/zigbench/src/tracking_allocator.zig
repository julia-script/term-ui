//! Memory tracking allocator for benchmarks

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Allocator that tracks memory usage
pub const TrackingAllocator = struct {
    child_allocator: Allocator,
    total_allocated: u64 = 0,
    total_freed: u64 = 0,
    current_allocated: u64 = 0,
    peak_allocated: u64 = 0,
    allocation_count: u64 = 0,

    const Self = @This();

    pub fn init(child_allocator: Allocator) Self {
        return .{
            .child_allocator = child_allocator,
        };
    }

    pub fn allocator(self: *Self) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.child_allocator.rawAlloc(len, ptr_align, ret_addr);
        if (result) |ptr| {
            self.total_allocated += len;
            self.current_allocated += len;
            self.allocation_count += 1;

            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }

            return ptr;
        }

        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @ptrCast(@alignCast(ctx));

        const result = self.child_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            if (new_len > buf.len) {
                const increase = new_len - buf.len;
                self.total_allocated += increase;
                self.current_allocated += increase;
            } else {
                const decrease = buf.len - new_len;
                self.total_freed += decrease;
                self.current_allocated -= decrease;
            }

            if (self.current_allocated > self.peak_allocated) {
                self.peak_allocated = self.current_allocated;
            }
        }

        return result;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *Self = @ptrCast(@alignCast(ctx));

        self.total_freed += buf.len;
        self.current_allocated -= buf.len;

        self.child_allocator.rawFree(buf, buf_align, ret_addr);
    }

    pub fn reset(self: *Self) void {
        self.total_allocated = 0;
        self.total_freed = 0;
        self.current_allocated = 0;
        self.peak_allocated = 0;
        self.allocation_count = 0;
    }
};
