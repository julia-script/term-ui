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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
            }),
            .optimize = optimize,
        }),
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
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

    run_cmd.addPassthruArgs();

    const test_filter = b.option([]const u8, "filter", "Skip tests that do not match filter");
    const update_snapshots = b.option(bool, "update", "Regenerate snapshot files") orelse false;
    const scopes = b.option([]const []const u8, "scopes", "Run tests with these scopes");
    const options = b.addOptions();
    options.addOption([]const u8, "filter", test_filter orelse "");
    options.addOption(bool, "update", update_snapshots);
    options.addOption([]const []const u8, "scopes", scopes orelse &[0][]const u8{});

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .name = "test",

        // .filter = test_filter,
        .test_runner = .{
            .path = b.path("test_runner.zig"),
            .mode = .simple,
        },
    });

    exe_unit_tests.root_module.addOptions("test_options", options);

    const install_step = b.addInstallArtifact(exe_unit_tests, .{});

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    if (update_snapshots) {
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

    // playground
    const playground = b.addExecutable(.{
        .name = "playground",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/playground.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    pipe(.{
        &playground.step,
        &b.addInstallArtifact(playground, .{}).step,
        &b.addRunArtifact(playground).step,
        b.step("playground", "Run the playground executable"),
    });

    // demo system
    const demo_name = b.option([]const u8, "demo", "Name of the demo to run");
    if (demo_name) |name| {
        // const main_module = b.createModule(.{ .root_source_file = b.path("src/main.zig") });
        // _ = main_module; // autofix

        // const demo_module = b.createModule(.{ .root_source_file = b.path(b.fmt("src/demo/{s}.zig", .{name})) });
        const demo = b.addExecutable(.{
            .name = b.fmt("demo-{s}", .{name}),
            // .root_source_file = b.path(demo_path),

            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/demo.{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
            }),
            // .target = target,
            // .optimize = optimize,
        });

        // demo.import

        const run_demo = b.addRunArtifact(demo);

        const demo_step = b.step("demo", "Run a demo");
        pipe(.{
            &demo.step,
            &b.addInstallArtifact(demo, .{}).step,
            &run_demo.step,
            demo_step,
        });
    }
}
