const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Default to ReleaseSafe rather than Debug: the interpreter exists to *run*
    // Scheme programs, and Debug is ~500x slower for allocation/continuation-
    // heavy workloads. ReleaseSafe matches ReleaseFast in throughput here while
    // keeping bounds/safety checks (fixnum overflow still wraps silently, as
    // documented). Override for development with `-Doptimize=Debug`.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size (default: ReleaseSafe)",
    ) orelse .ReleaseSafe;

    // Main module
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    main_mod.addCSourceFile(.{
        .file = b.path("vendor/linenoise/linenoise.c"),
        .flags = &.{"-std=c99"},
    });
    main_mod.addIncludePath(b.path("vendor/linenoise"));

    // Main executable
    const exe = b.addExecutable(.{
        .name = "kaappi",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the Kaappi Scheme REPL");
    run_step.dependOn(&run_cmd.step);

    // Benchmark executable (call/cc capture micro-benchmark)
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_mod,
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run the call/cc capture benchmark");
    bench_step.dependOn(&run_bench.step);

    // Unit tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{
        .name = "unit-tests",
        .root_module = test_mod,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
