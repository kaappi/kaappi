const std = @import("std");
const zon = @import("build.zig.zon");

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
    const gc_stress = b.option(bool, "gc-stress", "Force GC on every allocation (stress testing)") orelse false;

    // KEP-0002 Phase 7 gate campaign (kaappi#1472): compile in the parent-side
    // copy-time counters (T_submit_copy / T_result_copy / T_reassembly) and the
    // runtime-selectable envelope elision levers (none / C / C+D). Off in the
    // shipped default so release builds pay nothing (protocol §3: "compiled out
    // in release builds"); the campaign builds ONE binary with this on and
    // selects the lever at runtime (protocol §4.4, one binary for all modes).
    const channel_instrument = b.option(bool, "channel-instrument", "Compile in KEP-0002 Phase 7 channel copy-time counters + elision levers (off in shipped builds)") orelse false;

    // KEP-0002 Phase 7 lever B (kaappi#1472): a reusable per-channel recycled-GC
    // arena behind the Envelope interface, promoted to the shipped default. On,
    // cross-thread sends reuse one buffer-warm GC per channel instead of
    // malloc/free-ing the ~8 KiB root buffer every message (~50-63% faster
    // small-pointer-message round-trips, low-contention). -Dchannel-arena=false
    // restores lever A (a fresh per-message heap); the gate instrument build
    // forces lever A regardless so the frozen protocol baseline is unperturbed.
    const channel_arena = b.option(bool, "channel-arena", "KEP-0002 Phase 7 lever-B per-channel recycled-GC arena (kaappi#1472); shipped default -- pass -Dchannel-arena=false to restore lever A. Forced off under -Dchannel-instrument so the frozen gate baseline stays lever A.") orelse true;

    const test_filters = b.option([]const []const u8, "test-filter", "Only run unit tests whose names match the filter (repeatable)") orelse &.{};

    // A cross-compiled test binary runs under an emulator: CI cross-compiles to
    // riscv64-linux and runs the unit tests under QEMU user-mode (~10-30x slower
    // than native). The fuzz generator "programs evaluate without error" gates in
    // tests_fuzz.zig bound each program by a 100 ms wall clock, so under emulation
    // a correct-but-slow program blows that deadline and the gates fail spuriously
    // (kaappi#1573). Flag a non-native target so those gates bound by instruction
    // count instead -- speed-independent, exactly as they already do under
    // -Dgc-stress (#1447/#1449). Test-only: never affects the shipped binary.
    const host = b.graph.host.result;
    const emulated_target = target.result.cpu.arch != host.cpu.arch or
        target.result.os.tag != host.os.tag;

    const options = b.addOptions();
    options.addOption(u32, "max_frames", max_frames);
    options.addOption(u32, "max_registers", max_registers);
    options.addOption(u32, "gc_initial_threshold", gc_threshold);
    options.addOption(bool, "gc_stress", gc_stress);
    options.addOption(bool, "emulated_target", emulated_target);
    options.addOption(bool, "channel_instrument", channel_instrument);
    options.addOption(bool, "channel_arena", channel_arena);
    options.addOption([]const u8, "version", zon.version);
    // Machine-legibility (kaappi#1517): `kaappi features` reports the git build
    // id and the portable-SRFI list. Both are computed here at configure time so
    // the running binary never has to shell out to git or scan lib/srfi on disk
    // (an installed binary may have neither). The SRFI list is *generated* from
    // the actual .sld files, so adding a portable SRFI updates `features`
    // automatically -- no second hardcoded list to drift.
    options.addOption([]const u8, "git_build_id", gitBuildId(b));
    options.addOption([]const u16, "portable_srfis", scanPortableSrfis(b));
    const options_mod = options.createModule();

    const wf = b.addWriteFiles();
    const null_embed = wf.add("embedded_bytecode.zig", "pub const bytecode: ?[]const u8 = null;\n");

    const is_wasm_target = target.result.os.tag == .wasi;
    // linenoise is POSIX-only (termios); the Windows REPL uses a plain
    // stdin line loop instead (repl.zig).
    const use_linenoise = !is_wasm_target and target.result.os.tag != .windows;

    // OpenBSD enforces BTCFI: an indirect branch must land on a `bti`
    // instruction, but Zig 0.16 emits no landing pads, so every Zig-linked
    // binary would SIGILL on its first function-pointer call. This host tool
    // adds the PT_OPENBSD_NOBTCFI opt-out marker post-link; `installExe`
    // below runs it on each installed executable for OpenBSD targets, so
    // `zig build -Dtarget=<arch>-openbsd` produces working binaries directly.
    // The `kaappi compile` native backend opts out honestly via `-z nobtcfi`
    // (native_compiler.zig). See docs/dev/openbsd.md.
    const nobtcfi_tool: ?*std.Build.Step.Compile = if (target.result.os.tag == .openbsd) b.addExecutable(.{
        .name = "openbsd_nobtcfi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/openbsd_nobtcfi.zig"),
            .target = b.graph.host,
            .optimize = .ReleaseSafe,
        }),
    }) else null;

    // Main module (embedded_bytecode added below based on bundle mode)
    const main_mod = kaappiModule(b, options_mod, .{
        .target = target,
        .optimize = optimize,
        .linenoise = use_linenoise,
        .strip = strip,
        .single_threaded = if (is_wasm_target) true else null,
    });

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

        const compiler_mod = kaappiModule(b, options_mod, .{
            .target = target,
            .optimize = optimize,
            .linenoise = use_linenoise,
            .embed = compiler_null_embed,
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
    exe.stack_size = 64 * 1024 * 1024; // 64 MB — u16 register widening increases compiler frame sizes
    installExe(b, exe, nobtcfi_tool);

    // Portable library sources (.sld/.scm), installed next to the exe so a
    // from-source build can resolve them via the exe-relative <exe_dir>/../lib
    // search path (kaappi_paths.getExeRelativeLibDir) with no --lib-path and
    // no ~/.kaappi/lib (#1523). Mirrors where `zig build lib` puts
    // libkaappi_rt.a.
    b.installDirectory(.{
        .source_dir = b.path("lib"),
        .install_dir = .lib,
        .install_subdir = "",
        .include_extensions = &.{ ".sld", ".scm" },
    });

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the Kaappi Scheme REPL");
    run_step.dependOn(&run_cmd.step);

    // Runtime static library (for LLVM native backend)
    const lib_step = b.step("lib", "Build libkaappi_rt.a (runtime for native backend)");
    const lib_mod = kaappiModule(b, options_mod, .{
        .root = "src/runtime_exports.zig",
        .target = target,
        .optimize = optimize,
        .linenoise = use_linenoise,
        .embed = null_embed,
    });
    const lib = b.addLibrary(.{
        .name = "kaappi_rt",
        .root_module = lib_mod,
        .linkage = .static,
    });
    // The archive is consumed by whatever C compiler `kaappi compile`
    // finds — often the system cc, not `zig cc` (the FreeBSD port's
    // whole native-backend story, docs/dev/freebsd.md). Bundle Zig's
    // compiler-rt so Zig-internal references like x86's
    // __zig_probe_stack resolve inside the archive itself instead of
    // failing the link under plain clang/gcc.
    lib.bundle_compiler_rt = true;
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
        // Optimize the emitted IR — the emitter relies on LLVM to clean up its
        // deliberately naive output; -O0 leaves it all in place (#1492).
        cc_run.addArg("-O2");
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
    const wasm_mod = kaappiModule(b, options_mod, .{
        .target = wasm_target,
        .optimize = .ReleaseSmall,
        .single_threaded = true,
        .embed = null_embed,
    });
    const wasm_exe = b.addExecutable(.{
        .name = "kaappi",
        .root_module = wasm_mod,
    });
    const wasm_install = b.addInstallArtifact(wasm_exe, .{});
    wasm_step.dependOn(&wasm_install.step);

    // Benchmark executable (call/cc capture micro-benchmark)
    const bench_mod = kaappiModule(b, options_mod, .{
        .root = "src/bench.zig",
        .target = target,
        .optimize = optimize,
    });
    const bench_exe = b.addExecutable(.{
        .name = "bench",
        .root_module = bench_mod,
    });
    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run the call/cc capture benchmark");
    bench_step.dependOn(&run_bench.step);

    // Benchmark executable (per-fiber memory & switch-time, KEP-0001 P7 Q5)
    const bench_fibers_mod = kaappiModule(b, options_mod, .{
        .root = "src/bench_fibers.zig",
        .target = target,
        .optimize = optimize,
    });
    const bench_fibers_exe = b.addExecutable(.{
        .name = "bench-fibers",
        .root_module = bench_fibers_mod,
    });
    const run_bench_fibers = b.addRunArtifact(bench_fibers_exe);
    const bench_fibers_step = b.step("bench-fibers", "Run the per-fiber memory & switch-time benchmark");
    bench_fibers_step.dependOn(&run_bench_fibers.step);

    // Benchmark executable (reactor wake-all/re-arm/timer costs, KEP-0001 P7 Q1/Q2/Q3)
    const bench_reactor_mod = kaappiModule(b, options_mod, .{
        .root = "src/bench_reactor.zig",
        .target = target,
        .optimize = optimize,
    });
    const bench_reactor_exe = b.addExecutable(.{
        .name = "bench-reactor",
        .root_module = bench_reactor_mod,
    });
    const run_bench_reactor = b.addRunArtifact(bench_reactor_exe);
    const bench_reactor_step = b.step("bench-reactor", "Run the reactor wake-all/re-arm/timer benchmark");
    bench_reactor_step.dependOn(&run_bench_reactor.step);

    // Benchmark executable (local fast-path + promoted envelope cost, KEP-0002 P1)
    const bench_channel_mod = kaappiModule(b, options_mod, .{
        .root = "src/bench_channel.zig",
        .target = target,
        .optimize = optimize,
    });
    const bench_channel_exe = b.addExecutable(.{
        .name = "bench-channel",
        .root_module = bench_channel_mod,
    });
    const run_bench_channel = b.addRunArtifact(bench_channel_exe);
    const bench_channel_step = b.step("bench-channel", "Run the channel local fast-path & envelope-cost benchmark");
    bench_channel_step.dependOn(&run_bench_channel.step);

    // PCT-style randomized scheduling stress test (KEP-0002 P2 method step 2, Phase 3)
    const stress_channel_mod = kaappiModule(b, options_mod, .{
        .root = "src/stress_channel.zig",
        .target = target,
        .optimize = optimize,
    });
    const stress_channel_exe = b.addExecutable(.{
        .name = "stress-channel",
        .root_module = stress_channel_mod,
    });
    const run_stress_channel = b.addRunArtifact(stress_channel_exe);
    if (b.args) |args| {
        run_stress_channel.addArgs(args);
    }
    const stress_channel_step = b.step("stress-channel", "Run the SharedChannel/ThreadNotifier PCT-style randomized scheduling stress test (optional: -- <seed> <producers> <consumers> <per-producer>)");
    stress_channel_step.dependOn(&run_stress_channel.step);

    // Package manager (thottam)
    const thottam_mod = kaappiModule(b, options_mod, .{
        .root = "src/thottam.zig",
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    const thottam_exe = b.addExecutable(.{
        .name = "thottam",
        .root_module = thottam_mod,
    });
    thottam_exe.stack_size = 64 * 1024 * 1024;
    installExe(b, thottam_exe, nobtcfi_tool);

    // Language server (kaappi-lsp)
    const lsp_mod = kaappiModule(b, options_mod, .{
        .root = "src/kaappi_lsp.zig",
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .embed = null_embed,
    });
    const lsp_exe = b.addExecutable(.{
        .name = "kaappi-lsp",
        .root_module = lsp_mod,
    });
    lsp_exe.stack_size = 64 * 1024 * 1024;
    installExe(b, lsp_exe, nobtcfi_tool);

    // Fuzz program generator (driver for the offline differential harness,
    // tests/fuzz/native-diff.sh). Dev/CI tool: installed only by this step,
    // never by the default install, so it stays out of release artifacts.
    const fuzz_gen_mod = kaappiModule(b, options_mod, .{
        .root = "src/fuzz_gen_main.zig",
        .target = target,
        .optimize = optimize,
    });
    const fuzz_gen_exe = b.addExecutable(.{
        .name = "kaappi-fuzz-gen",
        .root_module = fuzz_gen_mod,
    });
    const fuzz_gen_step = b.step("fuzz-gen", "Build the fuzz program generator (zig-out/bin/kaappi-fuzz-gen)");
    fuzz_gen_step.dependOn(&b.addInstallArtifact(fuzz_gen_exe, .{}).step);

    // Unit tests
    const test_mod = kaappiModule(b, options_mod, .{
        .target = target,
        .optimize = optimize,
        .embed = null_embed,
    });
    const unit_tests = b.addTest(.{
        .name = "unit-tests",
        .root_module = test_mod,
        .filters = test_filters,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    // Cross-compiled test binaries the host can't execute (no emulator
    // registered — e.g. aarch64-windows) skip cleanly instead of failing,
    // so `zig build test -Dtarget=aarch64-windows` is a compile gate CI
    // can run anywhere. Native runs and QEMU-backed riscv64 are
    // unaffected (the binary is executable there, so it still runs).
    run_unit_tests.skip_foreign_checks = true;
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const thottam_test_mod = kaappiModule(b, options_mod, .{
        .root = "src/thottam.zig",
        .target = target,
        .optimize = optimize,
    });
    const thottam_tests = b.addTest(.{
        .name = "thottam-tests",
        .root_module = thottam_test_mod,
        .filters = test_filters,
    });
    const run_thottam_tests = b.addRunArtifact(thottam_tests);
    run_thottam_tests.skip_foreign_checks = true;
    test_step.dependOn(&run_thottam_tests.step);

    // Code coverage via kcov (always Debug for DWARF line info)
    const cov_mod = kaappiModule(b, options_mod, .{
        .target = target,
        .optimize = .Debug,
        .embed = null_embed,
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
    const cov_main_mod = kaappiModule(b, options_mod, .{
        .target = target,
        .optimize = .Debug,
        .linenoise = use_linenoise,
        .embed = null_embed,
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

/// Installs `exe` to the bin dir, then — for OpenBSD targets — marks the
/// installed binary PT_OPENBSD_NOBTCFI so it survives BTCFI enforcement
/// (see the `nobtcfi_tool` comment in `build`). `has_side_effects` keeps the
/// patch running on every build, since the install step re-copies the raw
/// (unmarked) binary each time. A no-op wrapper around `installArtifact` on
/// every other target.
fn installExe(b: *std.Build, exe: *std.Build.Step.Compile, nobtcfi_tool: ?*std.Build.Step.Compile) void {
    const tool = nobtcfi_tool orelse {
        b.installArtifact(exe);
        return;
    };
    const inst = b.addInstallArtifact(exe, .{});
    const patch = b.addRunArtifact(tool);
    patch.addArg(b.getInstallPath(.bin, exe.out_filename));
    patch.has_side_effects = true;
    patch.step.dependOn(&inst.step);
    b.getInstallStep().dependOn(&patch.step);
}

fn kaappiModule(b: *std.Build, options_mod: *std.Build.Module, opts: struct {
    root: []const u8 = "src/main.zig",
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    link_libc: bool = true,
    linenoise: bool = false,
    embed: ?std.Build.LazyPath = null,
    strip: ?bool = null,
    single_threaded: ?bool = null,
}) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path(opts.root),
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = opts.link_libc,
        .strip = opts.strip,
        .single_threaded = opts.single_threaded,
    });
    mod.addImport("build_options", options_mod);
    // (kaappi parallel) must stay importable under --sandbox, which blocks
    // every file-backed library load (vm_library.zig's tryLoadLibraryFromFile)
    // to keep sandboxed code from probing the host filesystem via crafted
    // import paths. lib/ isn't inside src/'s package boundary, so a plain
    // @embedFile from vm_library.zig can't reach lib/kaappi/parallel.sld
    // directly; copying it alongside a tiny generated wrapper (the same
    // shape as the embedded_bytecode_bundle.zig trick above) sidesteps that.
    // The .sld file on disk stays the single source of truth for both the
    // sandboxed (embedded) and normal (file) load paths.
    const parallel_sld_wf = b.addWriteFiles();
    _ = parallel_sld_wf.addCopyFile(b.path("lib/kaappi/parallel.sld"), "parallel.sld");
    const parallel_sld_embed = parallel_sld_wf.add("kaappi_parallel_sld.zig", "pub const source = @embedFile(\"parallel.sld\");\n");
    mod.addAnonymousImport("kaappi_parallel_sld", .{
        .root_source_file = parallel_sld_embed,
        .target = opts.target,
        .optimize = opts.optimize,
    });
    if (opts.linenoise) {
        mod.addCSourceFile(.{
            .file = b.path("vendor/linenoise/linenoise.c"),
            .flags = &.{"-std=gnu99"},
        });
        mod.addIncludePath(b.path("vendor/linenoise"));
    }
    if (opts.embed) |embed_file| {
        mod.addAnonymousImport("embedded_bytecode", .{
            .root_source_file = embed_file,
            .target = opts.target,
            .optimize = opts.optimize,
        });
    }
    return mod;
}

/// Best-effort git build id for `kaappi features` (kaappi#1517): the short HEAD
/// hash, with a `-dirty` suffix when the working tree has uncommitted changes.
/// Runs at configure time; any failure (no git, not a checkout, a shallow CI
/// tarball) falls back to "unknown" so the build never depends on git.
fn gitBuildId(b: *std.Build) []const u8 {
    const cwd = b.build_root.path orelse ".";
    var code: u8 = undefined;
    const head = b.runAllowFail(&.{ "git", "-C", cwd, "rev-parse", "--short", "HEAD" }, &code, .ignore) catch return "unknown";
    const hash = std.mem.trim(u8, head, " \t\r\n");
    if (hash.len == 0) return "unknown";

    // Mark a dirty tree so a build id can't imply a clean commit it doesn't
    // match. `git status --porcelain` exits 0 and prints one line per change, so
    // it composes with runAllowFail (which treats a nonzero exit as an error)
    // where `git diff --quiet` (nonzero when dirty) would not.
    const status = b.runAllowFail(&.{ "git", "-C", cwd, "status", "--porcelain" }, &code, .ignore) catch "";
    const dirty = std.mem.trim(u8, status, " \t\r\n").len != 0;
    return if (dirty) b.fmt("{s}-dirty", .{hash}) else b.dupe(hash);
}

/// Numbers of the portable SRFIs shipped as `lib/srfi/<n>.sld`, sorted
/// ascending. Generated by scanning the directory so `kaappi features` can
/// never disagree with what actually ships (kaappi#1517). A scan failure
/// yields an empty list rather than breaking the build.
fn scanPortableSrfis(b: *std.Build) []const u16 {
    const io = b.graph.io;
    var dir = b.build_root.handle.openDir(io, "lib/srfi", .{ .iterate = true }) catch return &.{};
    defer dir.close(io);

    var list: std.ArrayList(u16) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch return &.{}) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".sld")) continue;
        const stem = entry.name[0 .. entry.name.len - ".sld".len];
        const n = std.fmt.parseInt(u16, stem, 10) catch continue;
        list.append(b.allocator, n) catch return &.{};
    }
    const slice = list.toOwnedSlice(b.allocator) catch return &.{};
    std.mem.sort(u16, slice, {}, std.sort.asc(u16));
    return slice;
}
