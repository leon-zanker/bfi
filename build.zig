const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "bfi",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const interpreter_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/Interpreter.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_interpreter_unit_tests = b.addRunArtifact(interpreter_unit_tests);
    const test_step = b.step("test", "Run interpreter unit tests");
    test_step.dependOn(&run_interpreter_unit_tests.step);
}
