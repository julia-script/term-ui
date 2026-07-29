const Dirs = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Dir = std.fs.Dir;
const File = std.fs.File;

alloc: Allocator,
dirs: []const Dir,

const known_directories = [_][]const u8{
    "/etc/terminfo",
    "/lib/terminfo",
    "/usr/share/terminfo",
    "/usr/lib/terminfo",
    "/usr/local/share/terminfo",
    "/usr/local/lib/terminfo",
};

pub fn init(alloc: Allocator) Allocator.Error!Dirs {
    var dirs = std.array_list.Managed(Dir).init(alloc);
    errdefer deinit_dirs(alloc, dirs.items);

    // add $TERMINFO dir first, because it's most likely to have the correct
    // terminfo db
    if (std.process.getEnvVarOwned(alloc, "TERMINFO")) |env| {
        defer alloc.free(env);
        if (std.fs.openDirAbsolute(env, .{}) catch null) |dir| {
            try dirs.append(dir);
        }
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {}, // other errors are recoverable
    }

    // add $TERMINFO_DIRS dirs
    if (std.process.getEnvVarOwned(alloc, "TERMINFO_DIRS")) |env| {
        defer alloc.free(env);
        var it = std.mem.splitScalar(u8, env, ':');
        while (it.next()) |path| {
            if (std.fs.openDirAbsolute(path, .{}) catch null) |dir| {
                try dirs.append(dir);
            }
        }
    } else |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {}, // other errors are recoverable
    }

    // add known directories, like /usr/share/terminfo
    for (known_directories) |dir_path| {
        const dir = std.fs.openDirAbsolute(dir_path, .{}) catch continue;
        try dirs.append(dir);
    }

    return Dirs{
        .alloc = alloc,
        .dirs = try dirs.toOwnedSlice(),
    };
}

/// Searches the loaded directories for the given terminfo database.
/// `entry` should be something like "xterm-256color", not "x/xterm-256color".
pub fn find_entry(self: *const Dirs, entry: []const u8) ?File {
    const first_char = entry[0];
    var path_buf: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{c}/{s}", .{ first_char, entry }) catch {
        // std.log.info("terminfo entry was invalid", .{});
        return null;
    };

    for (self.dirs) |dir| {
        return dir.openFile(path, File.OpenFlags{ .mode = .read_only }) catch continue;
    }

    return null;
}

fn deinit_dirs(alloc: Allocator, dirs: []const Dir) void {
    for (dirs) |dir| {
        // I can deinitialize my own memory, I don't need Dir.close() to do it
        // for me. It's weird that Dir.close() takes *Dir instead of Dir or *const Dir.
        // That makes it awkward to use in situations like this.
        var dir_var = dir;
        dir_var.close();
    }
    // I'm freeing `dirs` anyway, so I don't care about setting each dir to undefined.
    alloc.free(dirs);
}

pub fn deinit(self: Dirs) void {
    deinit_dirs(self.alloc, self.dirs.items);
}
