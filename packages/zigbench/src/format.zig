//! Formatting utilities for zigbench

const std = @import("std");

// ANSI color codes for mitata-style formatting
pub const colors = struct {
    pub const bold = "\x1b[1m";
    pub const reset = "\x1b[0m";
    pub const red = "\x1b[31m";
    pub const cyan = "\x1b[36m";
    pub const blue = "\x1b[34m";
    pub const gray = "\x1b[90m";
    pub const white = "\x1b[37m";
    pub const black = "\x1b[30m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const magenta = "\x1b[35m";
};

/// Format a duration in nanoseconds to a human-readable string
pub fn formatDuration(ns: f64, writer: anytype) !void {
    if (ns < 1000) {
        try writer.print("{d:.2} ns", .{ns});
    } else if (ns < 1_000_000) {
        try writer.print("{d:.2} µs", .{ns / 1000});
    } else if (ns < 1_000_000_000) {
        try writer.print("{d:.2} ms", .{ns / 1_000_000});
    } else {
        try writer.print("{d:.2} s", .{ns / 1_000_000_000});
    }
}

/// Compact duration format with fixed width for alignment
pub fn formatDurationCompact(ns: f64, writer: anytype) !void {
    if (ns < 1000) {
        try writer.print("{d:.2} ns", .{ns});
    } else if (ns < 1_000_000) {
        try writer.print("{d:.2} µs", .{ns / 1000});
    } else if (ns < 1_000_000_000) {
        try writer.print("{d:.2} ms", .{ns / 1_000_000});
    } else {
        try writer.print("{d:>.2} s", .{ns / 1_000_000_000});
    }
}

/// Format operations per second with fixed width
pub fn formatOpsPerSec(ops: f64, writer: anytype) !void {
    if (ops >= 1_000_000_000) {
        try writer.print("{d:.2}G", .{ops / 1_000_000_000});
    } else if (ops >= 1_000_000) {
        try writer.print("{d:.2}M", .{ops / 1_000_000});
    } else if (ops >= 1000) {
        try writer.print("{d:.2}K", .{ops / 1000});
    } else {
        try writer.print("{d:.2}", .{ops});
    }
}

/// Format bytes with appropriate units
pub fn formatBytes(bytes: f64, writer: anytype) !void {
    if (bytes < 1024) {
        try writer.print("{d:.0}B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        try writer.print("{d:.1}KB", .{bytes / 1024});
    } else if (bytes < 1024 * 1024 * 1024) {
        try writer.print("{d:.1}MB", .{bytes / (1024 * 1024)});
    } else {
        try writer.print("{d:.1}GB", .{bytes / (1024 * 1024 * 1024)});
    }
}
