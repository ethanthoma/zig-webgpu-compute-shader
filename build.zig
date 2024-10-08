const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "default",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    addWgpuNative(b, exe);
    addShader(b, exe);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn addWgpuNative(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.linkLibC();
    exe.linkLibCpp();
    exe.addIncludePath(b.path("wgpu_native"));
    exe.addObjectFile(b.path("wgpu_native/libwgpu_native.a"));
    exe.linkSystemLibrary("gcc_s");
}

fn addShader(b: *std.Build, exe: *std.Build.Step.Compile) void {
    exe.root_module.addAnonymousImport("compute-shader", .{
        .root_source_file = b.path("src/compute-shader.wgsl"),
    });
}
