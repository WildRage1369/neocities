const std = @import("std");

pub fn build(b: *std.Build) void {
    b.exe_dir = ""; // output wasm files to root (./lib/)

    // build wasm file with `zig build`
    const wasm = b.addExecutable(.{
        .name = "wasm_runner",
        .root_source_file = b.path("wasm_runner.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;
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
}
