const std = @import("std");
const builtin = @import("builtin");


pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Exposing as a dependency for other projects
    const pkg = b.addModule("mongo", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize
    });

    pkg.addIncludePath(b.path("lib/include"));

    const main = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const app = "mongo";
    const exe = b.addExecutable(.{.name = app, .root_module = main});

    // Adding cross-platform dependency
    switch (target.query.os_tag orelse builtin.os.tag) {
        .linux => {
            exe.linkLibC();
            exe.linkSystemLibrary("z");
            exe.linkSystemLibrary("ssl");
            exe.linkSystemLibrary("zstd");
            exe.linkSystemLibrary("sasl2");
            exe.linkSystemLibrary("crypto");
            exe.linkSystemLibrary("resolv");
            exe.linkSystemLibrary("snappy");

            pkg.linkSystemLibrary("z", .{});
            pkg.linkSystemLibrary("ssl", .{});
            pkg.linkSystemLibrary("zstd", .{});
            pkg.linkSystemLibrary("sasl2", .{});
            pkg.linkSystemLibrary("crypto", .{});
            pkg.linkSystemLibrary("resolv", .{});
            pkg.linkSystemLibrary("snappy", .{});

            switch (target.query.cpu_arch orelse builtin.cpu.arch) {
                .aarch64 => {
                    pkg.addObjectFile(b.path("lib/linux/aarch64/libbson2.a"));
                    pkg.addObjectFile(b.path("lib/linux/aarch64/libmongoc2.a"));
                },
                .x86_64 => {
                    pkg.addObjectFile(b.path("lib/linux/x86_64/libbson2.a"));
                    pkg.addObjectFile(b.path("lib/linux/x86_64/libmongoc2.a"));
                },
                else => @panic("Unsupported architecture!")
            }
        },
        else => @panic("Codebase is not tailored for this platform!")
    }

    // Self importing package
    exe.root_module.addImport("mongo", pkg);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
