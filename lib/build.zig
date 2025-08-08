const std = @import("std");

pub fn build(b: *std.Build) void {
    b.exe_dir = ""; // output wasm files to root (./lib/)
    b.lib_dir = "";

    // build wasm file with `zig build`
    const wasm = b.addExecutable(.{
        .name = "wasm",
        .root_source_file = b.path("wasm.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;
    wasm.root_module.export_symbol_names = &.{ "init", "open", "write", "allocString", "close"};
    b.installArtifact(wasm);

    // run tests with `zig build test` or `zig build test --summary all`
    const test_step = b.step("test", "Run all tests");

    const fs_tests = b.addRunArtifact(b.addTest(.{
        .root_source_file = b.path("fs.zig"),
        .use_llvm = false
    }));
    const inode_tests = b.addRunArtifact(b.addTest(.{
        .root_source_file = b.path("INode.zig"),
        .use_llvm = false
    }));

    test_step.dependOn(&inode_tests.step);
    test_step.dependOn(&fs_tests.step);

    // build docs with `zig build docs`
    const fs = b.addStaticLibrary(.{
        .name = "fs",
        .root_source_file = b.path("fs.zig"),
        .target = b.graph.host,
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
    });
    const docs_step = b.step("docs", "Generate documentation");
    const lib_docs = b.addInstallDirectory(.{
        .source_dir = fs.getEmittedDocs(),
        .install_subdir = "",
        .install_dir = .{ .custom = "docs" },
    });
    docs_step.dependOn(&lib_docs.step);

}
