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

    // Standalone binary: embed compiled bytecode via -Dbundle=path/to/program.sbc
    const bundle = b.option([]const u8, "bundle",
        "Path to .sbc bytecode file to embed for standalone binary");
    // Single-step: compile and embed in one build
    const bundle_src = b.option([]const u8, "bundle-src",
        "Path to .scm source file to compile and embed for standalone binary");

    const max_frames = b.option(u32, "max-frames",
        "Maximum call frame depth (default: 512)") orelse 512;
    const max_registers = b.option(u32, "max-registers",
        "Maximum register count (default: 2048)") orelse 2048;

    const gc_threshold = b.option(u32, "gc-threshold",
        "Initial GC object threshold (default: 8192)") orelse 8192;

    const options = b.addOptions();
    options.addOption(u32, "max_frames", max_frames);
    options.addOption(u32, "max_registers", max_registers);
    options.addOption(u32, "gc_initial_threshold", gc_threshold);

    const wf = b.addWriteFiles();
    const null_embed = wf.add("embedded_bytecode.zig",
        "pub const bytecode: ?[]const u8 = null;\n");

    // Helper: create a kaappi module with a given embedded_bytecode import
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    main_mod.addImport("build_options", options.createModule());
    main_mod.addCSourceFile(.{
        .file = b.path("vendor/linenoise/linenoise.c"),
        .flags = &.{"-std=gnu99"},
    });
    main_mod.addIncludePath(b.path("vendor/linenoise"));

    if (bundle) |bp| {
        const bundle_path: std.Build.LazyPath = if (bp.len > 0 and bp[0] == '/')
            .{ .cwd_relative = bp }
        else
            b.path(bp);
        _ = wf.addCopyFile(bundle_path, "bundled.sbc");
        const bundle_embed = wf.add("embedded_bytecode_bundle.zig",
            "pub const bytecode: ?[]const u8 = @embedFile(\"bundled.sbc\");\n");
        main_mod.addAnonymousImport("embedded_bytecode", .{
            .root_source_file = bundle_embed,
            .target = target,
            .optimize = optimize,
        });
    } else if (bundle_src) |src_path| {
        // Single-step build: compile .scm with a plain kaappi, then embed.
        // Use a separate WriteFiles to avoid a dependency loop with the main wf.
        const compiler_wf = b.addWriteFiles();
        const compiler_null_embed = compiler_wf.add("embedded_bytecode.zig",
            "pub const bytecode: ?[]const u8 = null;\n");

        const compiler_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        compiler_mod.addImport("build_options", options.createModule());
        compiler_mod.addCSourceFile(.{
            .file = b.path("vendor/linenoise/linenoise.c"),
            .flags = &.{"-std=gnu99"},
        });
        compiler_mod.addIncludePath(b.path("vendor/linenoise"));
        compiler_mod.addAnonymousImport("embedded_bytecode", .{
            .root_source_file = compiler_null_embed,
            .target = target,
            .optimize = optimize,
        });

        const compiler_exe = b.addExecutable(.{
            .name = "kaappi-compiler",
            .root_module = compiler_mod,
        });

        const compile_run = b.addRunArtifact(compiler_exe);
        compile_run.addArg("--compile");
        compile_run.addArg("-o");
        const sbc_output = compile_run.addOutputFileArg("program.sbc");
        const src_lazy: std.Build.LazyPath = if (src_path.len > 0 and src_path[0] == '/')
            .{ .cwd_relative = src_path }
        else
            b.path(src_path);
        compile_run.addFileArg(src_lazy);

        _ = wf.addCopyFile(sbc_output, "bundled.sbc");
        const bundle_embed = wf.add("embedded_bytecode_bundle.zig",
            "pub const bytecode: ?[]const u8 = @embedFile(\"bundled.sbc\");\n");
        main_mod.addAnonymousImport("embedded_bytecode", .{
            .root_source_file = bundle_embed,
            .target = target,
            .optimize = optimize,
        });
    } else {
        main_mod.addAnonymousImport("embedded_bytecode", .{
            .root_source_file = null_embed,
            .target = target,
            .optimize = optimize,
        });
    }

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
    test_mod.addImport("build_options", options.createModule());
    test_mod.addAnonymousImport("embedded_bytecode", .{
        .root_source_file = null_embed,
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

    // Code coverage via kcov (always Debug for DWARF line info)
    const cov_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
    });
    cov_mod.addImport("build_options", options.createModule());
    cov_mod.addAnonymousImport("embedded_bytecode", .{
        .root_source_file = null_embed,
        .target = target,
        .optimize = .Debug,
    });

    const cov_tests = b.addTest(.{
        .name = "coverage-tests",
        .root_module = cov_mod,
    });

    const root = b.build_root.path orelse ".";
    const run_kcov = b.addSystemCommand(&.{"kcov"});
    run_kcov.addArg("--clean");
    run_kcov.addArg(b.fmt("--include-path={s}/src", .{root}));
    run_kcov.addArg(b.fmt("{s}/coverage", .{root}));
    run_kcov.addArtifactArg(cov_tests);

    const cov_step = b.step("coverage", "Run unit tests with kcov code coverage");
    cov_step.dependOn(&run_kcov.step);

    // Scheme file coverage via kcov (run .scm files under kcov)
    const cov_main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .Debug,
        .link_libc = true,
    });
    cov_main_mod.addImport("build_options", options.createModule());
    cov_main_mod.addCSourceFile(.{
        .file = b.path("vendor/linenoise/linenoise.c"),
        .flags = &.{"-std=gnu99"},
    });
    cov_main_mod.addIncludePath(b.path("vendor/linenoise"));
    cov_main_mod.addAnonymousImport("embedded_bytecode", .{
        .root_source_file = null_embed,
        .target = target,
        .optimize = .Debug,
    });

    const cov_exe = b.addExecutable(.{
        .name = "kaappi-cov",
        .root_module = cov_main_mod,
    });

    const run_kcov_scheme = b.addSystemCommand(&.{"kcov"});
    run_kcov_scheme.addArg(b.fmt("--include-path={s}/src", .{root}));
    run_kcov_scheme.addArg(b.fmt("{s}/coverage", .{root}));
    run_kcov_scheme.addArtifactArg(cov_exe);
    if (b.args) |args| {
        run_kcov_scheme.addArgs(args);
    }

    const cov_scheme_step = b.step("coverage-scheme", "Run a Scheme file with kcov code coverage");
    cov_scheme_step.dependOn(&run_kcov_scheme.step);
}
