const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Default to ReleaseSafe rather than Debug: the interpreter exists to *run*
    // Scheme programs, and Debug is ~500x slower for allocation/continuation-
    // heavy workloads. ReleaseSafe matches ReleaseFast in throughput here while
    // keeping bounds/safety checks (fixnum overflow auto-promotes to bignum).
    // Override for development with `-Doptimize=Debug`.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "optimize",
        "Prioritize performance, safety, or binary size (default: ReleaseSafe)",
    ) orelse .ReleaseSafe;

    // Standalone binary: embed compiled bytecode via -Dbundle=path/to/program.sbc
    const bundle = b.option([]const u8, "bundle", "Path to .sbc bytecode file to embed for standalone binary");
    // Single-step: compile and embed in one build
    const bundle_src = b.option([]const u8, "bundle-src", "Path to .scm source file to compile and embed for standalone binary");

    const do_strip = b.option(bool, "strip", "Strip debug info from binaries (for release builds)") orelse false;
    const strip: ?bool = if (do_strip) true else null;

    const max_frames = b.option(u32, "max-frames", "Initial call frame capacity (default: 480, grows to 32768)") orelse 480;
    const max_registers = b.option(u32, "max-registers", "Initial register count (default: 2048, grows to 65536)") orelse 2048;

    const gc_threshold = b.option(u32, "gc-threshold", "Initial GC object threshold (default: 8192)") orelse 8192;

    const options = b.addOptions();
    options.addOption(u32, "max_frames", max_frames);
    options.addOption(u32, "max_registers", max_registers);
    options.addOption(u32, "gc_initial_threshold", gc_threshold);

    const wf = b.addWriteFiles();
    const null_embed = wf.add("embedded_bytecode.zig", "pub const bytecode: ?[]const u8 = null;\n");

    const is_wasm_target = target.result.os.tag == .wasi;

    // Helper: create a kaappi module with a given embedded_bytecode import
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
        .single_threaded = if (is_wasm_target) true else null,
    });
    main_mod.addImport("build_options", options.createModule());
    if (!is_wasm_target) {
        main_mod.addCSourceFile(.{
            .file = b.path("vendor/linenoise/linenoise.c"),
            .flags = &.{"-std=gnu99"},
        });
        main_mod.addIncludePath(b.path("vendor/linenoise"));
    }

    if (bundle) |bp| {
        const bundle_path: std.Build.LazyPath = if (bp.len > 0 and bp[0] == '/')
            .{ .cwd_relative = bp }
        else
            b.path(bp);
        _ = wf.addCopyFile(bundle_path, "bundled.sbc");
        const bundle_embed = wf.add("embedded_bytecode_bundle.zig", "pub const bytecode: ?[]const u8 = @embedFile(\"bundled.sbc\");\n");
        main_mod.addAnonymousImport("embedded_bytecode", .{
            .root_source_file = bundle_embed,
            .target = target,
            .optimize = optimize,
        });
    } else if (bundle_src) |src_path| {
        // Single-step build: compile .scm with a plain kaappi, then embed.
        // Use a separate WriteFiles to avoid a dependency loop with the main wf.
        const compiler_wf = b.addWriteFiles();
        const compiler_null_embed = compiler_wf.add("embedded_bytecode.zig", "pub const bytecode: ?[]const u8 = null;\n");

        const compiler_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        compiler_mod.addImport("build_options", options.createModule());
        if (!is_wasm_target) {
            compiler_mod.addCSourceFile(.{
                .file = b.path("vendor/linenoise/linenoise.c"),
                .flags = &.{"-std=gnu99"},
            });
            compiler_mod.addIncludePath(b.path("vendor/linenoise"));
        }
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
        const bundle_embed = wf.add("embedded_bytecode_bundle.zig", "pub const bytecode: ?[]const u8 = @embedFile(\"bundled.sbc\");\n");
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
    exe.stack_size = 64 * 1024 * 1024; // 16 MB — u16 register widening increases compiler frame sizes
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the Kaappi Scheme REPL");
    run_step.dependOn(&run_cmd.step);

    // Runtime static library (for LLVM native backend)
    const lib_step = b.step("lib", "Build libkaappi_rt.a (runtime for native backend)");
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/runtime_exports.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addImport("build_options", options.createModule());
    if (!is_wasm_target) {
        lib_mod.addCSourceFile(.{
            .file = b.path("vendor/linenoise/linenoise.c"),
            .flags = &.{"-std=gnu99"},
        });
        lib_mod.addIncludePath(b.path("vendor/linenoise"));
    }
    lib_mod.addAnonymousImport("embedded_bytecode", .{
        .root_source_file = null_embed,
        .target = target,
        .optimize = optimize,
    });
    const lib = b.addLibrary(.{
        .name = "kaappi_rt",
        .root_module = lib_mod,
        .linkage = .static,
    });
    const lib_install = b.addInstallArtifact(lib, .{});
    lib_step.dependOn(&lib_install.step);

    // Native compilation: compile .scm to native binary via LLVM IR
    const native_src = b.option([]const u8, "native-src", "Path to .scm source file to compile to native binary");
    if (native_src) |src_path| {
        const native_step = b.step("native", "Compile Scheme source to native binary via LLVM IR");
        native_step.dependOn(&lib_install.step);

        const src_lazy: std.Build.LazyPath = if (src_path.len > 0 and src_path[0] == '/')
            .{ .cwd_relative = src_path }
        else
            b.path(src_path);

        const emit_run = b.addRunArtifact(exe);
        emit_run.step.dependOn(b.getInstallStep());
        emit_run.addArg("--emit-llvm");
        emit_run.addArg("-o");
        const ll_output = emit_run.addOutputFileArg("program.ll");
        emit_run.addFileArg(src_lazy);

        const cc_run = b.addSystemCommand(&.{"zig"});
        cc_run.addArg("cc");
        cc_run.addArg("-w");
        cc_run.addFileArg(ll_output);
        cc_run.addArg("-o");
        const native_output = cc_run.addOutputFileArg("program");
        cc_run.addPrefixedDirectoryArg("-L", lib.getEmittedBinDirectory());
        cc_run.addArgs(&.{ "-lkaappi_rt", "-lc", "-lm", "-lpthread" });
        cc_run.step.dependOn(&emit_run.step);

        const native_install = b.addInstallBinFile(native_output, "program");
        native_step.dependOn(&native_install.step);
    }

    // WebAssembly (WASI) build
    const wasm_step = b.step("wasm", "Build kaappi.wasm (wasm32-wasi)");
    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const wasm_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .link_libc = true,
        .single_threaded = true,
    });
    wasm_mod.addImport("build_options", options.createModule());
    wasm_mod.addAnonymousImport("embedded_bytecode", .{
        .root_source_file = null_embed,
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });
    const wasm_exe = b.addExecutable(.{
        .name = "kaappi",
        .root_module = wasm_mod,
    });
    const wasm_install = b.addInstallArtifact(wasm_exe, .{});
    wasm_step.dependOn(&wasm_install.step);

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

    // Package manager (thottam)
    const thottam_mod = b.createModule(.{
        .root_source_file = b.path("src/thottam.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
    });
    const thottam_exe = b.addExecutable(.{
        .name = "thottam",
        .root_module = thottam_mod,
    });
    thottam_exe.stack_size = 64 * 1024 * 1024;
    b.installArtifact(thottam_exe);

    // Language server (kaappi-lsp)
    const lsp_mod = b.createModule(.{
        .root_source_file = b.path("src/kaappi_lsp.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .strip = strip,
    });
    lsp_mod.addImport("build_options", options.createModule());
    lsp_mod.addAnonymousImport("embedded_bytecode", .{
        .root_source_file = null_embed,
        .target = target,
        .optimize = optimize,
    });
    const lsp_exe = b.addExecutable(.{
        .name = "kaappi-lsp",
        .root_module = lsp_mod,
    });
    lsp_exe.stack_size = 64 * 1024 * 1024;
    b.installArtifact(lsp_exe);

    // Unit tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
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

    const thottam_tests = b.addTest(.{
        .name = "thottam-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/thottam.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    const run_thottam_tests = b.addRunArtifact(thottam_tests);
    test_step.dependOn(&run_thottam_tests.step);

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
    if (!is_wasm_target) {
        cov_main_mod.addCSourceFile(.{
            .file = b.path("vendor/linenoise/linenoise.c"),
            .flags = &.{"-std=gnu99"},
        });
        cov_main_mod.addIncludePath(b.path("vendor/linenoise"));
    }
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
