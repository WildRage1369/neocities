const std = @import("std");

pub fn build(b: *std.Build) void {
    b.exe_dir = ""; // output wasm files to root (./lib/)
    
    // build wasm file with `zig build`
    const wasm = b.addExecutable(.{
        .name = "fs",
        .root_source_file = b.path("fs.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;
    b.installArtifact(wasm);

    // run tests with `zig build test` or `zig build test --summary all`
    const test_step = b.step("test", "Run all tests");
    const tests = b.addRunArtifact(b.addTest(.{
        .root_source_file = b.path("fs.zig"),
    }));
    test_step.dependOn(&tests.step);
}
