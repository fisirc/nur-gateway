const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libpq_dep = b.dependency("libpq", .{});
    const libpq = libpq_dep.artifact("pq");

    const dotenv_dep = b.dependency("dotenv", .{});
    const dotenv_mod = dotenv_dep.module("dotenv");

    const libthwomp_mod = b.createModule(.{
        .root_source_file = b.path("src/lib/stomp/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    check_mod.linkLibrary(libpq);
    check_mod.addImport("libthwomp", libthwomp_mod);
    check_mod.addImport("dotenv", dotenv_mod);

    const check_exe = b.addExecutable(.{
        .name = "cook_check",
        .root_module = check_mod,
    });

    const check_step = b.step("check", "zls check step");
    check_step.dependOn(&check_exe.step);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.linkLibrary(libpq);
    exe_mod.addImport("libthwomp", libthwomp_mod);
    exe_mod.addImport("dotenv", dotenv_mod);

    const exe = b.addExecutable(.{
        .name = "nur-gateway",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const libthwomp_unit_tests = b.addTest(.{
        .root_module = libthwomp_mod,
    });

    const run_libthwomp_unit_tests = b.addRunArtifact(libthwomp_unit_tests);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_libthwomp_unit_tests.step);
}
