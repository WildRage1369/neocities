const std = @import("std");

pub fn build(b: *std.Build) void {
    b.exe_dir = ""; // output wasm files to root (./libraries/)
    const wasm = b.addExecutable(.{
        .name = "fs",
        .root_source_file = b.path("fs.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = std.builtin.OptimizeMode.ReleaseSmall,
    });

    wasm.entry = .disabled;
    wasm.rdynamic = true;
    b.installArtifact(wasm);
}
