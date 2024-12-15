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

    const enableDocs = b.option(
        bool,
        "emit-docs",
        "Emit documents to <zig-out>/docs (default: false)",
    ) orelse false;

    const stepCheck = b.step("check", "Build but don't install");
    const stepTest = b.step("test", "Run library tests");
    const stepCompatTest = b.step("test-compat", "Run compatibility tests");

    const core = b.addModule("zigpak", .{
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });

    { // Docs for the module
        const docs = b.addStaticLibrary(.{
            .name = "zigpak",
            .root_source_file = core.root_source_file.?,
            .optimize = core.optimize.?,
            .target = core.resolved_target.?,
        });

        if (enableDocs) {
            const path = docs.getEmittedDocs();

            const instDocs = b.addInstallDirectory(.{
                .source_dir = path,
                .install_dir = .{ .custom = "docs" },
                .install_subdir = "zigpak",
            });
            instDocs.step.dependOn(&docs.step);

            b.getInstallStep().dependOn(&instDocs.step);
        }
    }

    { // The static library for C
        const lib = b.addStaticLibrary(.{
            .name = "zigpak",
            .root_source_file = b.path("src/croot.zig"),
            .target = target,
            .optimize = optimize,
        });
        lib.root_module.addImport("zigpak", core);

        const headerStep = b.addInstallHeaderFile(b.path("src/zigpak.h"), "zigpak.h");
        headerStep.step.dependOn(&lib.step);
        b.getInstallStep().dependOn(&headerStep.step);

        b.installArtifact(lib);

        if (enableDocs) {
            const docsPath = lib.getEmittedDocs();

            const instDocs = b.addInstallDirectory(.{
                .source_dir = docsPath,
                .install_dir = .{ .custom = "docs" },
                .install_subdir = "libzigpak",
            });
            instDocs.step.dependOn(&lib.step);

            b.getInstallStep().dependOn(&instDocs.step);
        }
    }

    { // zigpak-rewriter for testing
        const rewriter = b.addExecutable(.{
            .name = "zigpak-rewriter",
            .root_source_file = b.path("src/rewriter.zig"),
            .target = target,
            .optimize = optimize,
        });
        rewriter.root_module.addImport("zigpak", core);

        stepCheck.dependOn(&rewriter.step);

        const COMPAT_RUN_CMD = "ZIGPAK_REWRITER=$1 bun test";

        const runCompatTest = b.addSystemCommand(&.{ "bun", "exec", COMPAT_RUN_CMD });
        runCompatTest.addArtifactArg(rewriter);
        stepCompatTest.dependOn(&runCompatTest.step);
    }

    {
        const tests = b.addTest(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        });

        const run_main_tests = b.addRunArtifact(tests);

        stepTest.dependOn(&run_main_tests.step);
    }
}
