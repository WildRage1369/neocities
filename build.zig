const std = @import("std");

pub fn build(b: *std.Build) void {
    // output wasm files to public/
    b.exe_dir = "public";
    b.lib_dir = "public";

    // explicitly compile the kernel
    const kernel_exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel.zig"),
            .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
            .optimize = std.builtin.OptimizeMode.Debug,
        }),
    });
    kernel_exe.entry = .disabled;
    kernel_exe.rdynamic = true;
    const artifact = b.addInstallArtifact(
        kernel_exe,
        .{ .dest_dir = .{ .override = .{ .custom = "../public" } } },
    );
    b.getInstallStep().dependOn(&artifact.step);

    buildPrograms(b) catch unreachable;

    // run tests with `zig build test` or `zig build test --summary all`
    const test_step = b.step("test", "Run all tests");
    const fs_tests = b.addRunArtifact(b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/fs.zig"),
        .target = b.standardTargetOptions(.{}),
    }) }));
    test_step.dependOn(&fs_tests.step);

    // build docs with `zig build docs`
    // const fs = b.addStaticLibrary(.{
    //     .name = "fs",
    //     .root_source_file = b.path("fs.zig"),
    //     .target = b.graph.host,
    //     .optimize = std.builtin.OptimizeMode.ReleaseSmall,
    // });
    // const docs_step = b.step("docs", "Generate documentation");
    // const lib_docs = b.addInstallDirectory(.{
    //     .source_dir = fs.getEmittedDocs(),
    //     .install_subdir = "",
    //     .install_dir = .{ .custom = "docs" },
    // });
    // docs_step.dependOn(&lib_docs.step);
}

// build all zig programs found in src/programs and install them into public/programs
fn buildPrograms(b: *std.Build) !void {
    // output wasm files to programs folder
    b.exe_dir = "public/programs";
    b.lib_dir = "public/programs";

    var dir = try std.fs.cwd().openDir("src/programs/", .{ .iterate = true });
    defer dir.close();
    var iter = dir.iterate();

    while (try iter.next()) |file| {
        if (!std.mem.endsWith(u8, file.name, ".zig")) continue;

        const file_path = try std.fs.path.join(b.allocator, &[_][]const u8{ "src/programs/", file.name });

        const file_exe = b.addExecutable(.{
            .name = file.name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(file_path),
                .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
                .optimize = std.builtin.OptimizeMode.Debug,
            }),
        });

        file_exe.entry = .disabled;
        file_exe.rdynamic = true;

        b.installArtifact(file_exe);
    }
}
