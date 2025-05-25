const std = @import("std");

pub inline fn expectMatchSnapshot(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    description: []const u8,
    actual: []const u8,
) !void {
    try expectMatchSnapshotImpl(loc, allocator, description, actual);
}

fn expectMatchSnapshotImpl(
    comptime loc: std.builtin.SourceLocation,
    allocator: std.mem.Allocator,
    description: []const u8,
    actual: []const u8,
) !void {
    const sanitized = try sanitizeDescription(allocator, description);
    defer allocator.free(sanitized);

    var file_path: []const u8 = loc.file;
    const allocated_path = if (!std.mem.startsWith(u8, file_path, "src/")) blk: {
        file_path = try std.fs.path.join(allocator, &.{ "src", file_path });
        break :blk true;
    } else false;
    defer if (allocated_path) allocator.free(file_path);

    const test_dir = std.fs.path.dirname(file_path) orelse ".";
    const snapshot_dir = try std.fs.path.join(allocator, &.{ test_dir, "__snapshots__" });
    defer allocator.free(snapshot_dir);
    const snapshot_path = try std.fs.path.join(allocator, &.{ snapshot_dir, sanitized });
    defer allocator.free(snapshot_path);

    var update = false;
    if (std.process.getEnvVarOwned(allocator, "UPDATE_SNAPSHOTS")) |val| {
        update = std.ascii.eqlIgnoreCase(val, "true");
        allocator.free(val);
    } else |err| {
        if (err != error.EnvironmentVariableNotFound) return err;
    }

    var file = std.fs.cwd().openFile(snapshot_path, .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) {
            update = true;
            return writeSnapshot(snapshot_path, actual);
        } else {
            return err;
        }
    };
    defer file.close();

    if (update) {
        return writeSnapshot(snapshot_path, actual);
    }

    const stat = try file.stat();
    const buf = try file.readToEndAlloc(allocator, stat.size);
    defer allocator.free(buf);

    if (!std.mem.eql(u8, buf, actual)) {
        std.debug.print("Snapshot mismatch for {s}\n", .{snapshot_path});
    }
    try std.testing.expectEqualStrings(buf, actual);
}

fn writeSnapshot(path: []const u8, data: []const u8) !void {
    const dir = std.fs.path.dirname(path) orelse ".";
    std.fs.cwd().makePath(dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(data);
}

fn sanitizeDescription(allocator: std.mem.Allocator, desc: []const u8) ![]u8 {
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    for (desc) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_') {
            try buf.append(c);
        } else {
            try buf.append('_');
        }
    }
    try buf.appendSlice(".snap");
    return buf.toOwnedSlice();
}
