const std = @import("std");
const platform = @import("platform.zig");
const builtin_os = @import("builtin").os;
const is_wasm = builtin_os.tag == .wasi;
const is_linux = builtin_os.tag == .linux;
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
pub const types = @import("types.zig");
pub const memory = @import("memory.zig");
pub const reader = @import("reader.zig");
pub const compiler = @import("compiler.zig");
pub const compiler_forms = @import("compiler_forms.zig");
pub const vm_mod = @import("vm.zig");
pub const vm_eval = @import("vm_eval.zig");
pub const primitives = @import("primitives.zig");
pub const primitives_arithmetic = @import("primitives_arithmetic.zig");
pub const primitives_io = @import("primitives_io.zig");
pub const primitives_control = @import("primitives_control.zig");
pub const primitives_vector = @import("primitives_vector.zig");
pub const primitives_string = @import("primitives_string.zig");
pub const primitives_char = @import("primitives_char.zig");
pub const primitives_cxr = @import("primitives_cxr.zig");
pub const primitives_bytevector = @import("primitives_bytevector.zig");
pub const primitives_lazy = @import("primitives_lazy.zig");
pub const primitives_r7rs = @import("primitives_r7rs.zig");
pub const printer = @import("printer.zig");
pub const expander = @import("expander.zig");
pub const library = @import("library.zig");
// WASI only, matching build.zig's `use_isocline` and repl.zig's. The extra
// `.windows` arm here was linenoise's POSIX-only gate, left behind: isocline
// drives the Windows console API, so that target builds and links it like any
// other. repl.zig imports isocline.zig directly and is reachable from here, so
// the wrapper was still compiled on Windows either way — but this file's
// import block is what makes a module's own tests reachable, and a stale
// exclusion here would silently drop them if any were ever added.
pub const ic = if (is_wasm) struct {} else @import("isocline.zig");

// Bounded-step execution (kaappi#2283): the wasm32-wasi build additionally
// exports a C-ABI stepping surface (kaappi_step_*) the browser playground drives
// instead of the blocking `_start`. Referencing the module here keeps its
// `export fn`s in the wasm binary; on every other target the branch is
// comptime-dead, so no native symbols are emitted.
comptime {
    if (is_wasm) {
        // `export fn`s in a non-root imported file are only analyzed (and thus
        // emitted/exported) when referenced, so name each one explicitly.
        const ws = @import("wasm_step.zig");
        _ = &ws.kaappi_step_alloc;
        _ = &ws.kaappi_step_setup;
        _ = &ws.kaappi_step_run;
        _ = &ws.kaappi_step_stop;
        _ = &ws.kaappi_step_reset;
    }
}
pub const ffi = @import("ffi.zig");
pub const primitives_ffi = @import("primitives_ffi.zig");
pub const primitives_srfi1 = @import("primitives_srfi1.zig");
pub const primitives_hashtable = @import("primitives_hashtable.zig");
pub const primitives_random = @import("primitives_random.zig");
pub const primitives_srfi18 = @import("primitives_srfi18.zig");
pub const bytecode_file = @import("bytecode_file.zig");
pub const ffi_callback = @import("ffi_callback.zig");
pub const embedded_bytecode = @import("embedded_bytecode");
pub const fiber_mod = @import("fiber.zig");
pub const primitives_fiber = @import("primitives_fiber.zig");
pub const reporting = @import("reporting.zig");
pub const vm_library = @import("vm_library.zig");
pub const repl_mod = @import("repl.zig");
pub const ir_mod = @import("ir.zig");
pub const llvm_emit = @import("llvm_emit.zig");
pub const native_compiler = @import("native_compiler.zig");
pub const toplevel_driver = @import("toplevel_driver.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const lsp_diagnostic = @import("lsp_diagnostic.zig");
pub const cli = @import("cli.zig");
pub const explain = @import("explain.zig");
pub const features = @import("features.zig");
pub const test_runner = @import("test_runner.zig");
pub const doctor = @import("doctor.zig");
pub const cache = @import("cache.zig");
const vm_library_cache_mod = @import("vm_library_cache.zig");
pub const timings = @import("timings.zig");
pub const check = @import("check.zig");
pub const pipeline = @import("pipeline.zig");
pub const config = @import("config.zig");
pub const fmt = @import("fmt.zig");
pub const crash = @import("crash.zig");

pub const version = @import("build_options").version;
const build_options = @import("build_options");

/// Custom panic handler (kaappi#1514): prints version/target/build-mode, the
/// pipeline breadcrumb, and a report URL before the standard message + trace.
/// Picked up by the Zig compiler as the root `panic` namespace.
pub const panic = crash.PanicHandler("kaappi");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

const usageError = cli.usageError;

const DESIRED_STACK: usize = 64 * 1024 * 1024; // 64 MB

pub fn main(init: std.process.Init.Minimal) !void {
    platform.initStandardStreams();
    // Hardens the fallback path below (and any OpenBSD build): if the worker
    // thread can't be spawned we run mainInner on the main thread, whose stack
    // is RLIMIT_STACK-bound — only 4 MiB by default on OpenBSD. No-op
    // elsewhere. See docs/dev/openbsd.md.
    platform.raiseStackLimitBestEffort();
    // NetBSD/aarch64 boots processes with flush-to-zero set; restore the
    // IEEE default FP mode before any thread spawns (threads inherit it).
    platform.normalizeFpEnvBestEffort();
    if (comptime !is_wasm) {
        // The compiler's recursive descent needs more than the default 8 MB
        // stack for deeply nested Scheme forms (e.g. cond chains that desugar
        // to nested if/let). Always run on a worker thread with a 64 MB stack.
        const t = std.Thread.spawn(.{ .stack_size = DESIRED_STACK }, mainInner, .{init}) catch return mainInner(init);
        t.join();
        return;
    }
    return mainInner(init);
}

fn mainInner(init: std.process.Init.Minimal) void {
    mainImpl(init) catch {
        std.process.exit(1);
    };
    if (toplevel_driver.script_had_error) std.process.exit(1);
}

fn mainImpl(init: std.process.Init.Minimal) !void {
    const is_debug = @import("builtin").mode == .Debug;
    var da = if (is_debug) std.heap.DebugAllocator(.{}).init;
    defer if (is_debug) {
        _ = da.deinit();
    };
    const allocator = if (is_wasm) std.heap.wasm_allocator else if (is_debug) da.allocator() else std.heap.c_allocator;

    // `kaappi explain <code>` is a pure query over the static diagnostic
    // registry — no VM, GC, or library setup needed — so handle it before any
    // of that exists and exit. (Skipped on WASM, whose entry just runs a file;
    // and on a bundled standalone, whose argv belongs to the bundled program,
    // kaappi#2010 — a first argument spelling "explain" or "doctor" must
    // reach (command-line), not kaappi's own dispatch.)
    if (comptime !is_wasm and embedded_bytecode.bytecode == null) {
        // Internal, undocumented hook (kaappi#1514): `--panic-test` deliberately
        // panics so CI can verify the crash banner on a real build. Dispatched
        // first, before any setup, and never returns when the flag is present.
        crash.maybePanicTest(init.args);
        if (explain.maybeRun(allocator, init.args)) |exit_code| {
            std.process.exit(exit_code);
        }
        // `kaappi features` is a pure query over static build/registry data
        // (like explain, no VM needed), so dispatch it before any setup too.
        if (features.maybeRun(allocator, init.args)) |exit_code| {
            std.process.exit(exit_code);
        }
        // `kaappi test` is an orchestrator over worker subprocesses; like
        // explain it needs no VM of its own, so dispatch it before any setup.
        // (The worker children are ordinary `kaappi <file>` runs; they are
        // recognized later by KAAPPI_TEST_EMIT in the file-run path.)
        if (test_runner.maybeRun(allocator, init.args)) |exit_code| {
            std.process.exit(exit_code);
        }
        // `kaappi doctor` inspects the environment (paths, PATH, native
        // toolchain, FFI libraries) and runs no user code, so it likewise
        // dispatches before any VM/GC/library setup exists.
        if (doctor.maybeRun(allocator, init.args)) |exit_code| {
            std.process.exit(exit_code);
        }
        // `kaappi cache status|clear` is a pure filesystem query over
        // ~/.kaappi/cache — no VM, no user code — so it dispatches here too.
        if (cache.maybeRun(allocator, init.args)) |exit_code| {
            std.process.exit(exit_code);
        }
    }

    var gc = memory.GC.init(allocator);

    const vm = try allocator.create(vm_mod.VM);
    vm.* = try vm_mod.VM.init(&gc);
    // kaappi#1792: a thread-start!ed OS thread still alive at process exit may
    // be concurrently reading/writing the parent's shared symbol table and
    // globals map (both aliased into the child's own GC/VM). Freeing them out
    // from under it is a data race that corrupts the allocator's heap
    // metadata, so skip our own teardown entirely in that case.
    //
    // That alone isn't sufficient: since kaappi links libc, both a normal
    // return from `main` and `std.process.exit` route through glibc's real
    // `exit()`, which runs atexit handlers and dynamic-loader finalizers —
    // process-wide teardown machinery that can itself race a thread that is
    // still genuinely executing (observed as a rare SIGSEGV distinct from the
    // heap-corruption abort this fix's first half addresses). `_exit` skips
    // all of that and goes straight to the `exit_group` syscall, so no
    // teardown logic ever runs concurrently with the live child at all.
    defer if (primitives_srfi18.hasLiveChildThreads()) {
        std.c._exit(if (toplevel_driver.script_had_error) 1 else 0);
    } else {
        vm.deinit();
        allocator.destroy(vm);
        gc.deinit();
    };
    vm_mod.setVMInstance(vm);

    // WASM: simplified entry — just run the file specified as argv[1]
    if (comptime is_wasm) {
        try primitives.registerAll(vm);
        memory.setGCInstance(&gc);
        try vm_mod.vm_bootstrap.install(vm);
        try library.registerStandardLibraries(&vm.libraries, vm.globals);

        var wasi_args = try init.args.iterateAllocator(allocator);
        defer wasi_args.deinit();
        _ = wasi_args.skip(); // skip argv[0]

        // The non-WASM path below populates vm.command_line_args (from
        // opts.scriptArgs()) and vm.lib_paths (script dir + --lib-path +
        // auto-discovered dirs), but this branch returns before either, so
        // both keep their empty defaults. Repopulate them from the WASI argv
        // the branch already iterates: (command-line) must report the script
        // path (R7RS 6.14) and a sibling .sld must resolve via the script's
        // own directory. (kaappi#2109)
        var cmd_args: std.ArrayList([]const u8) = .empty;
        defer cmd_args.deinit(allocator);
        while (wasi_args.next()) |arg| {
            try cmd_args.append(allocator, arg);
        }
        if (cmd_args.items.len == 0) {
            writeStderr("kaappi-wasm: no file specified\n");
            return;
        }
        const file_path = cmd_args.items[0];
        vm.command_line_args = cmd_args.items;

        var script_dir_buf: [1][]const u8 = undefined;
        var script_dir_count: usize = 0;
        if (std.mem.lastIndexOfScalar(u8, file_path, '/')) |pos| {
            script_dir_buf[0] = if (pos == 0) file_path[0..1] else file_path[0..pos];
            script_dir_count = 1;
        }
        vm.lib_paths = script_dir_buf[0..script_dir_count];

        try toplevel_driver.runFile(vm, file_path);
        return;
    }

    // Same argument-ownership rule as the parse above: --sandbox is a kaappi
    // flag, so it cannot be interpreted for a bundled binary either.
    const is_sandboxed = if (comptime embedded_bytecode.bytecode == null)
        cli.preScanSandbox(init.args)
    else
        false;

    if (is_sandboxed) {
        try primitives.registerSandboxed(vm);
        memory.setGCInstance(&gc);
        try vm_mod.vm_bootstrap.install(vm);
        try library.registerSandboxedLibraries(&vm.libraries, vm.globals);
        vm.sandbox_mode = true;
    } else {
        try primitives.registerAll(vm);
        memory.setGCInstance(&gc);
        try vm_mod.vm_bootstrap.install(vm);
        try library.registerStandardLibraries(&vm.libraries, vm.globals);
    }

    // Bundled standalone (kaappi#2010): the binary *is* the bundled program,
    // so no kaappi flag or subcommand is interpreted — parseBundled hands the
    // whole argv after argv[0] to (command-line) verbatim, whatever it looks
    // like, including words that cli.parse would otherwise swallow as
    // subcommands ("check", "fmt", "ast", "compile") or as --flags.
    var opts = if (comptime embedded_bytecode.bytecode == null)
        cli.parse(init.args)
    else
        cli.parseBundled(init.args);
    if (opts.action == .exit_ok) return;

    // Windows argv paths arrive with backslashes, but every internal path
    // operation — script-relative includes, sibling-library resolution,
    // cache keys — splits and joins on '/'. Win32 accepts '/' everywhere,
    // so normalize the script path once at the boundary.
    if (comptime platform.is_windows) {
        if (opts.file_path) |fp| {
            const dup = allocator.dupe(u8, fp) catch fp;
            if (dup.ptr != fp.ptr) {
                const mutable = @constCast(dup);
                for (mutable) |*ch| {
                    if (ch.* == '\\') ch.* = '/';
                }
                opts.file_path = dup;
            }
        }
    }

    // Apply parsed options to VM/GC
    if (opts.no_ir_opt) ir_mod.optimize_enabled = false;
    // `--timings` (kaappi#1515): arm per-stage timing on this (main) thread
    // before any pipeline work runs. A no-op elsewhere unless armed here.
    if (opts.timings_enabled) timings.enable(if (opts.timings_json) .json else .text);
    if (opts.timeout_ms) |ms| {
        const clockNs = @import("vm_calls.zig").clockNs;
        vm.timeout_deadline_ns = clockNs() + ms * 1_000_000;
    }
    if (opts.max_memory) |limit| gc.memory_limit = limit;
    if (opts.coverage_xml_path) |p| vm.coverage_xml_path = p;
    vm.command_line_args = opts.scriptArgs();
    toplevel_driver.setDiagnosticFormat(switch (opts.diagnostics_format) {
        .text => .text,
        .json => .json,
    });

    // Standalone mode: run embedded bytecode and exit
    if (embedded_bytecode.bytecode) |bytecode_data| {
        defer if (opts.gc_stats_mode) reporting.printGcStats(&gc);
        if (opts.profile_mode) vm.profile_mode = true;
        defer if (opts.profile_mode) reporting.printProfileReport(&gc);
        if (opts.coverage_mode) {
            vm.profile_mode = true;
            vm.coverage_mode = true;
        }
        defer if (opts.coverage_mode) {
            reporting.printCoverageReport(vm);
            if (vm.coverage_xml_path) |p| reporting.writeCoverageXml(vm, p);
        };

        const loaded = bytecode_file.readFromBuffer(&gc, bytecode_data) catch {
            writeStderr("fatal: corrupted embedded bytecode\n");
            toplevel_driver.script_had_error = true;
            return;
        } orelse {
            // The loader collapses every header mismatch into null (kaappi#1930).
            // The most common cause for a bundled binary is a *stale* bundle:
            // the .sbc's compiler hash folds in the build id, so a tree that
            // moved (new commit, or clean<->dirty) between producing the .sbc
            // and building the bundler makes the binary reject its own payload
            // as foreign. Say that when the header names it, instead of
            // "wrong version or format".
            switch (bytecode_file.classifyEmbeddedRejection(bytecode_data)) {
                .foreign_build => {
                    const info = bytecode_file.readHeaderInfo(bytecode_data).?;
                    writeStderr("fatal: embedded bytecode was produced by a different build (build id ");
                    writeStderr(info.build_id);
                    writeStderr("); this binary is ");
                    writeStderr(build_options.git_build_id);
                    writeStderr(". Rebuild the bundle from current source.\n");
                },
                .invalid => writeStderr("fatal: invalid embedded bytecode (wrong version or format)\n"),
            }
            toplevel_driver.script_had_error = true;
            return;
        };
        defer allocator.free(loaded.funcs);

        // Set up bundled files for library resolution
        var bundled_files_map = loaded.bundled_files orelse std.StringHashMap([]const u8).init(allocator);
        defer {
            var bfit = bundled_files_map.iterator();
            while (bfit.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            bundled_files_map.deinit();
        }
        if (loaded.bundled_files != null) {
            vm.bundled_files = &bundled_files_map;
        }
        defer vm.bundled_files = null;

        // Everything from here runs the bundled program (kaappi#1514 breadcrumb).
        crash.note(.executing, "<bundled program>");

        // Replay preamble (import, include, define-library forms)
        if (loaded.preamble) |preamble| {
            defer {
                for (preamble) |p| allocator.free(p);
                allocator.free(preamble);
            }
            const reader_mod = @import("reader.zig");
            for (preamble) |src| {
                var pr = reader_mod.Reader.init(&gc, src);
                defer pr.deinit();
                while (pr.hasMore() catch break) {
                    var expr = pr.readDatum() catch break;
                    gc.pushRoot(&expr);
                    defer gc.popRoot();
                    if (vm.handleTopLevelForm(expr)) |top_result| {
                        _ = top_result catch |err| {
                            toplevel_driver.script_had_error = true;
                            const detail = vm.getErrorDetail();
                            const code = toplevel_driver.runtimeCode(vm, err);
                            const msg = if (detail.len > 0) detail else code.message();
                            var cbuf: [diagnostics.Code.render_width]u8 = undefined;
                            var errbuf: [256]u8 = undefined;
                            const s = std.fmt.bufPrint(&errbuf, "preamble error[{s}]: {s}\n", .{ code.render(&cbuf), msg }) catch "preamble error\n";
                            writeStderr(s);
                            vm.last_error_detail_len = 0;
                            vm.last_error_code = .uncategorized;
                        };
                    }
                }
            }
        }

        const top_count = @min(loaded.top_level_count, @as(u32, @intCast(loaded.funcs.len)));
        for (loaded.funcs[0..top_count]) |func| {
            var func_val = types.makePointer(&func.header);
            vm.gc.pushRoot(&func_val);
            const result = vm.execute(func) catch |err| {
                vm.gc.popRoot();
                toplevel_driver.script_had_error = true;
                const detail = vm.getErrorDetail();
                const code = toplevel_driver.runtimeCode(vm, err);
                const msg = if (detail.len > 0) detail else code.message();
                var cbuf: [diagnostics.Code.render_width]u8 = undefined;
                var errbuf: [256]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "error[{s}]: {s}\n", .{ code.render(&cbuf), msg }) catch "runtime error\n";
                writeStderr(s);
                vm.last_error_detail_len = 0;
                vm.last_error_code = .uncategorized;
                continue;
            };
            vm.gc.popRoot();

            toplevel_driver.printTopLevelResult(allocator, result);
        }
        return;
    }

    // Library search path: the explicit --lib-path entries (any count) plus up
    // to three auto-discovered dirs added below — the script's own directory,
    // ~/.kaappi/lib, and the exe-relative fallback lib. Sized to hold them all;
    // the old fixed [16] silently dropped a 17th path (or an auto-discovered dir
    // once 16 explicit ones existed), same silent-drop shape as #1652 (#1653).
    // These allocations (lib_paths itself, and the auto-discovered dir strings
    // klp/elp below) must live for the whole run — vm.lib_paths is read as
    // late as the deferred coverage report — so they come from a dedicated
    // arena freed by one defer here, rather than the general allocator: a
    // Debug build's leak-tracking allocator would otherwise report these
    // intentionally-never-individually-freed strings as leaked on every exit
    // (kaappi#1748).
    var lib_paths_arena = std.heap.ArenaAllocator.init(allocator);
    defer lib_paths_arena.deinit();
    const lib_paths_alloc = lib_paths_arena.allocator();

    const auto_discovered_max = 3;
    const lib_paths = try lib_paths_alloc.alloc([]const u8, opts.libPaths().len + auto_discovered_max);
    var lib_path_count: usize = 0;
    for (opts.libPaths()) |lp| {
        lib_paths[lib_path_count] = lp;
        lib_path_count += 1;
    }

    if (opts.file_path) |fp| {
        if (std.mem.lastIndexOfScalar(u8, fp, '/')) |pos| {
            lib_paths[lib_path_count] = if (pos == 0) fp[0..1] else fp[0..pos];
            lib_path_count += 1;
        }
    }

    if (!is_wasm) {
        const kaappi_paths = @import("kaappi_paths.zig");

        const kaappi_lib_path = blk: {
            var home_buf: [512]u8 = undefined;
            const home = kaappi_paths.getHome(&home_buf) orelse break :blk null;
            const lib_suffix = "/lib";
            const path = lib_paths_alloc.alloc(u8, home.len + lib_suffix.len) catch break :blk null;
            @memcpy(path[0..home.len], home);
            @memcpy(path[home.len..][0..lib_suffix.len], lib_suffix);
            break :blk path;
        };
        if (kaappi_lib_path) |klp| {
            lib_paths[lib_path_count] = klp;
            lib_path_count += 1;
            // The dynamic-linker search path is a POSIX concept; Windows
            // resolves DLLs via PATH and ffi-open's own explicit
            // ~/.kaappi/lib probe, so there is nothing to export there.
            if (comptime !platform.is_windows) {
                const env_name = if (@import("builtin").os.tag == .macos)
                    "DYLD_LIBRARY_PATH"
                else
                    "LD_LIBRARY_PATH";
                const existing = platform.getenv(env_name);
                if (existing) |ex| {
                    const ex_len = std.mem.len(ex);
                    const new = lib_paths_alloc.alloc(u8, klp.len + 1 + ex_len + 1) catch null;
                    if (new) |n| {
                        @memcpy(n[0..klp.len], klp);
                        n[klp.len] = ':';
                        @memcpy(n[klp.len + 1 .. klp.len + 1 + ex_len], ex[0..ex_len]);
                        n[klp.len + 1 + ex_len] = 0;
                        _ = setenv(env_name, @ptrCast(n[0 .. klp.len + 1 + ex_len :0]), 1);
                    }
                } else {
                    const z = lib_paths_alloc.dupeZ(u8, klp) catch null;
                    if (z) |zz| _ = setenv(env_name, zz, 1);
                }
            }
        }

        // Last-resort fallback: <exe_dir>/../lib, so a from-source build
        // (`zig build`, no installer, no ~/.kaappi/lib) can still resolve
        // portable SRFI .sld sources when run from outside the checkout
        // (#1523). Checked after ~/.kaappi/lib so an existing install is
        // never shadowed by whatever the running binary was built from.
        const exe_lib_path = blk: {
            var exe_lib_buf: [1024]u8 = undefined;
            const elp = kaappi_paths.getExeRelativeLibDir(&exe_lib_buf) orelse break :blk null;
            break :blk lib_paths_alloc.dupe(u8, elp) catch null;
        };
        if (exe_lib_path) |elp| {
            lib_paths[lib_path_count] = elp;
            lib_path_count += 1;
        }
    }

    vm.lib_paths = lib_paths[0..lib_path_count];

    defer if (opts.gc_stats_mode) reporting.printGcStats(&gc);
    if (opts.profile_mode) vm.profile_mode = true;
    defer if (opts.profile_mode) {
        reporting.printProfileReport(&gc);
        if (opts.profile_json_path) |jp| {
            reporting.writeProfileJson(&gc, jp);
        }
    };
    if (opts.coverage_mode) {
        vm.profile_mode = true;
        vm.coverage_mode = true;
    }
    defer if (opts.coverage_mode) {
        reporting.printCoverageReport(vm);
        if (vm.coverage_xml_path) |p| reporting.writeCoverageXml(vm, p);
    };

    if (opts.native_compile_mode) {
        if (opts.file_path) |fp| {
            defer timings.report(.native); // kaappi#1515 (no-op unless --timings)
            try native_compiler.compileNative(vm, fp, opts.compile_output);
        } else {
            usageError("Usage: kaappi compile <file.scm> [-o output]\n");
        }
        return;
    }

    if (opts.check_mode) {
        const fp = opts.file_path orelse usageError("Usage: kaappi check <file.scm>\n");
        std.process.exit(check.run(vm, fp, .{
            .json = opts.diagnostics_format == .json,
            .deny_warnings = opts.deny_warnings,
        }));
    }

    // Pipeline-stage dumps (kaappi#1512): read-only introspection into the
    // reader / expander / IR stages between source and bytecode.
    if (opts.ast_mode) {
        const fp = opts.file_path orelse usageError("Usage: kaappi ast <file.scm>\n");
        std.process.exit(pipeline.runAst(vm, fp));
    }
    if (opts.expand_mode) {
        const fp = opts.file_path orelse usageError("Usage: kaappi expand <file.scm>\n");
        std.process.exit(pipeline.runExpand(vm, fp));
    }
    if (opts.ir_mode) {
        const fp = opts.file_path orelse usageError("Usage: kaappi ir <file.scm> [--no-opt]\n");
        std.process.exit(pipeline.runIr(vm, fp, opts.ir_no_opt));
    }

    // Canonical formatter (kaappi#1518). Reads and re-lays-out source; no
    // program code runs. With no files it formats stdin to stdout.
    if (opts.fmt_mode) {
        std.process.exit(fmt.run(&gc, .{ .check = opts.fmt_check, .files = opts.scriptArgs() }));
    }

    if (opts.disassemble_mode) {
        if (opts.file_path) |fp| {
            try toplevel_driver.disassembleFile(vm, fp);
        } else {
            usageError("Usage: kaappi --disassemble <file.scm>\n");
        }
    } else if (opts.compile_mode) {
        if (opts.file_path) |fp| {
            // `--compile` writes an explicit artifact the user named — never
            // the auto-run cache, which lives in ~/.kaappi/cache keyed by a
            // hash of the source path (kaappi#1516). So `--no-ir-opt --compile`
            // can't poison a plain run's cache, and needs no output guard.
            defer timings.report(.compile); // kaappi#1515 (no-op unless --timings)
            try toplevel_driver.compileFile(vm, fp, opts.compile_output);
        } else {
            usageError("Usage: kaappi --compile <file.scm> [-o output.sbc]\n");
        }
    } else if (opts.emit_llvm_mode) {
        if (opts.file_path) |fp| {
            try native_compiler.emitLlvmFile(vm, fp, opts.compile_output);
        } else {
            usageError("Usage: kaappi --emit-llvm <file.scm> [-o output.ll]\n");
        }
    } else if (opts.file_path) |fp| {
        if (comptime !is_wasm) {
            if (test_runner.workerEmitPath()) |emit_path| {
                try toplevel_driver.runWorkerFile(vm, fp, emit_path);
                return;
            }
        }
        defer timings.report(.run); // kaappi#1515 (no-op unless --timings)
        try toplevel_driver.runFile(vm, fp);
    } else {
        if (is_wasm) {
            writeStderr("kaappi-wasm: no file specified\n");
            return;
        }
        if (!is_wasm and !platform.isatty(0)) {
            try toplevel_driver.runStdin(vm);
        } else {
            try repl_mod.repl(vm);
        }
    }
}

test {
    _ = platform;
    _ = types;
    _ = memory;
    _ = reader;
    _ = compiler;
    _ = compiler_forms;
    _ = vm_mod;
    _ = primitives;
    _ = primitives_arithmetic;
    _ = primitives_io;
    _ = primitives_control;
    _ = primitives_vector;
    _ = primitives_string;
    _ = primitives_char;
    _ = primitives_cxr;
    _ = primitives_bytevector;
    _ = primitives_lazy;
    _ = primitives_r7rs;
    _ = printer;
    _ = expander;
    _ = library;
    _ = ic;
    _ = ffi;
    _ = primitives_ffi;
    _ = primitives_srfi1;
    _ = primitives_hashtable;
    _ = primitives_random;
    _ = bytecode_file;
    _ = embedded_bytecode;
    _ = fiber_mod;
    _ = primitives_fiber;
    _ = ir_mod;
    _ = llvm_emit;
    _ = native_compiler;
    _ = toplevel_driver;
    _ = diagnostics;
    _ = lsp_diagnostic;
    _ = repl_mod;
    _ = cli;
    _ = explain;
    _ = features;
    _ = test_runner;
    _ = doctor;
    _ = check;
    _ = @import("check_lint.zig");
    _ = @import("tests_check.zig");
    _ = @import("test_selection.zig");
    _ = pipeline;
    _ = @import("tests_pipeline.zig");
    _ = config;
    _ = fmt;
    _ = @import("fmt_print.zig");
    _ = crash;
    _ = cache;
    _ = timings;
}
