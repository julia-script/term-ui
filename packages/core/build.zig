const std = @import("std");

/// Connect multiple steps so that each depends on the previous one.
pub fn pipe(steps: anytype) void {
    var prev_step = steps[0];
    inline for (@as([steps.len]*std.Build.Step, steps)[1..]) |step| {
        step.dependOn(prev_step);
        prev_step = step;
    }
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build the WebAssembly module
    const wasm = b.addExecutable(.{
        .name = switch (optimize) {
            .Debug => "core-debug",
            else => "core",
        },
        .root_source_file = b.path("src/wasm.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .wasm32,
            .os_tag = .wasi,
        }),
        .optimize = optimize,
    });

    wasm.entry = .disabled;
    wasm.export_table = true;
    wasm.rdynamic = true;
    wasm.import_memory = true;

    wasm.import_symbols = true;
    pipe(.{
        &wasm.step,
        &b.addInstallArtifact(wasm, .{}).step,
        b.step("wasm", "Build the wasm executable"),
    });

    // Build and install the native executable
    const exe = b.addExecutable(.{
        .name = "core",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Run step depends on installation so resources are available
    const run_cmd = b.addRunArtifact(exe);

    // Primary entry point for running the binary
    const run_step = b.step("run", "Run the app");
    pipe(.{
        b.getInstallStep(),
        &run_cmd.step,
        run_step,
    });

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");
    const update_snapshots = b.option(bool, "update-snapshots", "Regenerate snapshot files");

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/wasm.zig"),
        .name = "test",

        .target = target,
        .optimize = optimize,
        .filter = test_filter,
        .test_runner = .{
            .path = b.path("test_runner.zig"),
            .mode = .simple,
        },
    });

    const install_step = b.addInstallArtifact(exe_unit_tests, .{});

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    if (update_snapshots orelse false) {
        run_exe_unit_tests.setEnvironmentVariable("UPDATE_SNAPSHOTS", "true");
    }

    // Expose steps for running and debugging tests
    const test_step = b.step("test", "Run unit tests");
    const test_debugger = b.step("debugbuild", "Run unit tests with debugger");

    pipe(.{
        &run_exe_unit_tests.step,
        test_step,
    });
    pipe(.{
        &install_step.step,
        test_debugger,
    });
}
