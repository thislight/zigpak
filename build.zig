// SPDX: Apache-2.0
// This file is part of zigpak.
const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const bun = b.option([]const u8, "bun", "The bun name to run the test (default: \"bun\")") orelse "bun";

    const stepCheck = b.step("check", "Build but don't install");
    const stepTest = b.step("test", "Run library tests");
    const stepCompatTest = b.step("test-compat", "Run compatibility tests");

    const core = b.addModule("zigpak", .{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    {
        const lib = b.addStaticLibrary(.{
            .name = "zigpak",
            // In this case the main source file is merely a path, however, in more
            // complicated build scripts, this could be a generated file.
            .root_source_file = b.path("src/croot.zig"),
            .target = target,
            .optimize = optimize,
        });
        lib.root_module.addImport("zigpak", core);

        const headerStep = b.addInstallHeaderFile(b.path("src/zigpak.h"), "zigpak.h");
        headerStep.step.dependOn(&lib.step);
        b.getInstallStep().dependOn(&headerStep.step);

        // This declares intent for the library to be installed into the standard
        // location when the user invokes the "install" step (the default step when
        // running `zig build`).
        b.installArtifact(lib);
    }

    {
        const rewriter = b.addExecutable(.{
            .name = "zigpak-rewriter",
            .root_source_file = b.path("src/rewriter.zig"),
            .target = target,
            .optimize = optimize,
        });
        rewriter.root_module.addImport("zigpak", core);

        stepCheck.dependOn(&rewriter.step);

        const COMPAT_RUN_CMD = "ZIGPAK_REWRITER=$1 bun test";

        const runCompatTest = b.addSystemCommand(&.{ bun, "exec", COMPAT_RUN_CMD });
        runCompatTest.addArtifactArg(rewriter);
        runCompatTest.step.dependOn(&rewriter.step);
        stepCompatTest.dependOn(&runCompatTest.step);
    }

    {
        const tests = b.addTest(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_main_tests = b.addRunArtifact(tests);

        stepTest.dependOn(&run_main_tests.step);
    }
}
