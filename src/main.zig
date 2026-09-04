const std = @import("std");
const platform = @import("platform.zig");
const builtin_os = @import("builtin").os;
const is_wasm = builtin_os.tag == .wasi;
const is_linux = builtin_os.tag == .linux;
const file_utils = @import("file_utils.zig");
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

// Multiple values print one per line, matching other Scheme REPLs
// (Chez, Guile, Racket, Chibi). Void results print nothing.
fn printTopLevelResult(allocator: std.mem.Allocator, result: types.Value) void {
    if (types.isMultipleValues(result)) {
        const mv = types.toObject(result).as(types.MultipleValues);
        for (mv.values) |val| printSingleResult(allocator, val);
    } else {
        printSingleResult(allocator, result);
    }
}

fn printSingleResult(allocator: std.mem.Allocator, value: types.Value) void {
    if (value == types.VOID) return;
    const s = printer.valueToString(allocator, value, .write) catch return;
    defer allocator.free(s);
    writeStdout(s);
    writeStdout("\n");
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime !is_wasm) {
        const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
        defer allocator.free(path_z);
        if (platform.isDir(path_z)) {
            std.debug.print("Error: '{s}' is a directory\n", .{path});
            return error.IsDir;
        }
    }

    return file_utils.readWholeFile(allocator, path, 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => std.debug.print("Error opening file '{s}'\n", .{path}),
            error.StreamTooLong => std.debug.print("File too large\n", .{}),
            error.InputOutput => std.debug.print("Error reading file '{s}'\n", .{path}),
            else => std.debug.print("Error reading file '{s}'\n", .{path}),
        }
        return err;
    };
}

fn readAllStdin(allocator: std.mem.Allocator) ![]u8 {
    const max_size: usize = 10 * 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = platform.read(0, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (platform.errno(raw) == .INTR) continue;
            break;
        }
        const bytes_read: usize = @intCast(raw);
        if (result.items.len + bytes_read > max_size) return error.StreamTooLong;
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }
    return result.toOwnedSlice(allocator);
}

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

        try runFile(vm, file_path);
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

            printTopLevelResult(allocator, result);
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
            try disassembleFile(vm, fp);
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
            try compileFile(vm, fp, opts.compile_output);
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
                try runWorkerFile(vm, fp, emit_path);
                return;
            }
        }
        defer timings.report(.run); // kaappi#1515 (no-op unless --timings)
        try runFile(vm, fp);
    } else {
        if (is_wasm) {
            writeStderr("kaappi-wasm: no file specified\n");
            return;
        }
        if (!is_wasm and !platform.isatty(0)) {
            try runStdin(vm);
        } else {
            try repl_mod.repl(vm);
        }
    }
}

fn getSbcPath(allocator: std.mem.Allocator, scm_path: []const u8) ![]u8 {
    return bytecode_file.getSbcPath(allocator, scm_path);
}

/// `--compile` writes an artifact the user asked for by name, so a refused
/// constant (kaappi#2113) must fail loudly with the reason — the old behavior
/// wrote an artifact whose embedded bytecode the loader would reject at run
/// time, which surfaced as "invalid embedded bytecode" long after the fact.
fn reportBytecodeWriteError(err: anyerror) void {
    switch (err) {
        error.LimitExceeded => writeStderr("error: a constant exceeds the .sbc format limits (nesting deeper than 256, or an oversized literal) and cannot be serialized\n"),
        error.UnsupportedConstant => writeStderr("error: a constant cannot be represented in the .sbc format\n"),
        else => writeStderr("Error writing bytecode file\n"),
    }
}

/// SRFI 59/193: absolute-ize `path` without following symlinks -- a pure
/// lexical join+normalize (`.`/`..` collapsed) against the process's
/// starting cwd, never a `realpath`-style syscall. Returns `null` (rather
/// than propagating an allocation failure) on the rare case `getCwd` itself
/// fails; callers treat that identically to "not running a script".
fn resolveScriptPath(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    if (std.fs.path.isAbsolute(path)) {
        // Still route through `resolve` -- an already-absolute input like
        // "/tmp/../app.scm" must still have its `.`/`..` collapsed to honor
        // the documented normalization contract; `resolve` is pure lexical
        // manipulation (no cwd needed, no symlink resolution) either way.
        return std.fs.path.resolve(allocator, &.{path}) catch null;
    }
    var buf: [platform.PATH_MAX]u8 = undefined;
    const cwd = platform.getCwd(&buf) orelse return null;
    return std.fs.path.resolve(allocator, &.{ cwd, path }) catch null;
}

/// Execute one cached top-level function and report its result/error exactly
/// as the fresh-compile loop does: the #1922 line fallback, the source
/// snippet, the stack trace, and `printTopLevelResult`. Shared by the v13
/// slot replay (kaappi#1888) and the pre-slot legacy path.
fn runCachedTopLevelFunc(vm: *vm_mod.VM, func: *types.Function, source: []const u8, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);
    timings.begin(.execute);
    const exec_result = vm.execute(func);
    timings.end();
    const result = exec_result catch |err| {
        vm.gc.popRoot();
        toplevel_driver.script_had_error = true;
        // kaappi#1922: fall back to the form's own line — serialized as
        // Function.source_line — exactly as the fresh-compile path passes
        // datum_lc.line, so an error with no line-table entry (raise,
        // division by zero) keeps its location and snippet on a cache HIT.
        const loc = toplevel_driver.vmErrorLocation(vm, path, func.source_line);
        toplevel_driver.reportRuntimeError(vm, err, loc);
        toplevel_driver.printSourceSnippet(source, loc.line);
        toplevel_driver.printStackTrace(vm);
        return;
    };
    vm.gc.popRoot();
    printTopLevelResult(allocator, result);
}

fn runFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;

    // Per-run include/dependency records for this file's cache entry
    // (kaappi#1888 review): every file-backed library it imports and every
    // file a top-level include reads. Cleared again once the entry is
    // written (or the run declines).
    vm_library_cache_mod.beginRunRecording(vm);
    defer vm_library_cache_mod.clearRunRecords(vm);

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    // SRFI 59/193: resolve the script's absolute path once, up front. Free
    // any previous value first -- runFile only ever runs on the root VM
    // (owns_globals == true; threads run a thunk, never a file), so this
    // never races a child VM's borrowed reference (see the field doc in
    // vm.zig), but a future caller running more than one file per process
    // must not leak the prior allocation.
    if (vm.script_path) |old| allocator.free(old);
    vm.script_path = resolveScriptPath(allocator, path);

    // Crash breadcrumb (kaappi#1514): name the file once; stages update per-form.
    crash.noteFile(path);

    const source = readFileContents(allocator, path) catch {
        toplevel_driver.script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Try loading cached bytecode from the central cache (~/.kaappi/cache).
    // Skipped in sandbox mode (no filesystem side effects) and under
    // --no-ir-opt (cache keys don't include the flag, so a no-opt run must
    // neither reuse optimized bytecode nor write unoptimized bytecode that a
    // later optimized run would load). pathForSource returns null when there
    // is no home dir to cache in — then this run just compiles from source.
    const sbc_path = if (vm.sandbox_mode or !ir_mod.optimize_enabled) null else cache.pathForSource(allocator, path);
    defer if (sbc_path) |p| allocator.free(p);

    // `--timings` (kaappi#1515): record why caching was skipped entirely, so the
    // report never leaves the cache line blank. HIT/MISS are recorded below.
    if (sbc_path == null) {
        if (vm.sandbox_mode) {
            timings.cacheOff("sandbox");
        } else if (!ir_mod.optimize_enabled) {
            timings.cacheOff("--no-ir-opt");
        } else {
            timings.cacheOff("no home dir");
        }
    }

    if (sbc_path) |sp| {
        if (bytecode_file.readFileWithTopLevel(vm.gc, source_hash, sp) catch null) |loaded_const| {
            var loaded = loaded_const;
            // Kind check (#1888 review): a LIBRARY entry shares this cache key
            // with running the .sld directly, and its functions are library
            // body thunks — replaying them as a program would run them with
            // no env and no transformer registrations. Only a program entry
            // with a slot stream is replayable here.
            if (loaded.entry_kind != bytecode_file.ENTRY_PROGRAM or loaded.slots == null) {
                vm_library_cache_mod.dropDeserializeRoots(vm.gc, &loaded);
                bytecode_file.freeDeserializeResult(allocator, &loaded);
            } else if (!vm_library_cache_mod.recordsValid(
                vm,
                loaded.includes orelse &.{},
                loaded.deps orelse &.{},
            )) {
                // Stale program entry: a file-backed library it imported, or a
                // top-level include file it read, changed since the entry was
                // written. The compiled slots embed those macro expansions, so
                // this must be an ordinary miss (nothing has executed yet).
                timings.cacheReason("stale dependency");
                vm_library_cache_mod.dropDeserializeRoots(vm.gc, &loaded);
                bytecode_file.freeDeserializeResult(allocator, &loaded);
            } else {
                timings.cacheHit(sp);
                defer bytecode_file.freeDeserializeResult(allocator, &loaded);

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

                if (loaded.preamble) |preamble| {
                    defer {
                        for (preamble) |p| allocator.free(p);
                        allocator.free(preamble);
                    }
                    for (preamble) |src| {
                        var pr = reader.Reader.init(vm.gc, src);
                        defer pr.deinit();
                        while (pr.hasMore() catch break) {
                            var expr = pr.readDatum() catch break;
                            vm.gc.pushRoot(&expr);
                            defer vm.gc.popRoot();
                            timings.begin(.execute); // preamble replay re-runs imports (kaappi#1515)
                            const top = vm.handleTopLevelForm(expr);
                            timings.end();
                            if (top) |top_result| {
                                _ = top_result catch {};
                            }
                        }
                    }
                }

                // Set source_name on all loaded functions — the path is valid
                // for the entire runFile scope, matching the fresh-compile path
                // where the compiler sets source_name to the same pointer.
                for (loaded.funcs) |func| {
                    func.source_name = path;
                }

                crash.noteStage(.executing);

                // v13 program entries (kaappi#1888) replay through positional
                // slots: a compiled function, or a declaration's verbatim source
                // re-dispatched through handleTopLevelForm — in the exact
                // top-level order, so an `import` between two defines stays
                // between them (no preamble hoisting, the #2200 reorder class).
                // Older-format entries are unreachable: the VERSION check
                // rejects them, and the kind/slots check above is what admits a
                // replayable entry.
                {
                    for (loaded.slots.?) |slot| {
                        switch (slot) {
                            .function => |idx| {
                                if (idx >= loaded.top_level_count) continue;
                                const func = loaded.funcs[idx];
                                try runCachedTopLevelFunc(vm, func, source, path);
                            },
                            .declaration => |decl| {
                                var dr = reader.Reader.init(vm.gc, decl.src);
                                // A `#!fold-case` directive falls inside an earlier
                                // form's span; the slot carries the reader state
                                // that applied when the form was read (#1888
                                // review).
                                dr.fold_case = decl.fold_case;
                                defer dr.deinit();
                                while (dr.hasMore() catch break) {
                                    var dexpr = dr.readDatum() catch break;
                                    vm.gc.pushRoot(&dexpr);
                                    defer vm.gc.popRoot();
                                    crash.noteStage(.executing);
                                    timings.begin(.execute);
                                    // The cold run recorded this slot because
                                    // handleTopLevelForm claimed the form; the
                                    // replayed imports restore the same macro
                                    // state, so it is claimed again. The
                                    // compile-and-run fallback keeps an unclaimed
                                    // form correct rather than silently dropped.
                                    if (vm.topLevelHead(dexpr)) |head| {
                                        const result = vm.runTopLevelHead(head, dexpr) catch |err| {
                                            timings.end();
                                            toplevel_driver.script_had_error = true;
                                            toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = decl.line });
                                            continue;
                                        };
                                        timings.end();
                                        printTopLevelResult(allocator, result);
                                        continue;
                                    }
                                    const func = compiler.compileExpressionWithMacrosAt(vm.gc, dexpr, &vm.macros, vm.globals, decl.line, path, false) catch |err| {
                                        timings.end();
                                        toplevel_driver.script_had_error = true;
                                        toplevel_driver.reportCompileError(path, decl.line, 1, err);
                                        continue;
                                    };
                                    timings.end();
                                    try runCachedTopLevelFunc(vm, func, source, path);
                                }
                            },
                        }
                    }
                    return;
                } // slot replay
            } // kind/records-validated replay (else branch)
        }
    }

    // No cache — compile from source. A non-null sbc_path here means the cache
    // was consulted and missed (kaappi#1515); the write below marks it written.
    if (sbc_path) |sp| timings.cacheMiss(sp);

    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);
    // The positional replay stream (kaappi#1888): one slot per top-level form,
    // function or declaration, in order. Owned src slices freed with the list.
    var slots: std.ArrayList(bytecode_file.Slot) = .empty;
    defer {
        for (slots.items) |*s| {
            if (s.* == .declaration) allocator.free(s.declaration.src);
        }
        slots.deinit(allocator);
    }
    var defines_syntax = false;
    var had_compile_error = false;

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    crash.noteStage(.reading);
    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError(path, lc.line, lc.col, err);
        toplevel_driver.script_had_error = true;
        return;
    }) {
        crash.noteStage(.reading);
        const datum_lc = r.getLineCol();
        // Byte span of this form (leading trivia included — it re-parses to
        // the same datum), for the declaration replay slot (kaappi#1888).
        const span_start = r.pos;
        timings.begin(.read);
        const read_result = r.readDatum();
        timings.end();
        const span_end = r.pos;
        var expr = read_result catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError(path, lc.line, lc.col, err);
            toplevel_driver.script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // A top-level declaration — import/define-library/include runs library
        // code here; the other five heads are interpreted directly. Classify
        // before dispatching: evaluating one form can change how the next is
        // classified, so the head and its handler must be read from the same
        // moment (#2114). Since #1888 these are cacheable as declaration
        // slots: the HIT re-reads the verbatim source span and re-dispatches
        // it, positionally — library loads hit their own .sld entries.
        if (vm.topLevelHead(expr)) |head| {
            // Structure flag: a top-level include reached from here is the
            // MAIN file's structure, so its file feeds the run recorder (the
            // macro an included file defines is baked into later compiled
            // slots — kaappi#1888 review). A runtime `(eval "(include …)")`
            // inside a function keeps depth 0 and records nothing.
            vm.lib_structure_depth += 1;
            defer vm.lib_structure_depth -= 1;
            if (sbc_path != null and !defines_syntax and !had_compile_error) {
                const src_copy = allocator.dupe(u8, source[span_start..span_end]) catch return error.OutOfMemory;
                slots.append(allocator, .{ .declaration = .{ .line = datum_lc.line, .src = src_copy, .fold_case = r.fold_case } }) catch {
                    allocator.free(src_copy);
                    return error.OutOfMemory;
                };
            }
            crash.noteStage(.executing);
            timings.begin(.execute);
            const top_result = vm.runTopLevelHead(head, expr);
            timings.end();
            const result = top_result catch |err| {
                toplevel_driver.script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        crash.noteStage(.compiling);
        // kaappi#2112: `define-syntax` / `define-property` register into the
        // VM's macro and syntax-property tables as a side effect of
        // *compilation* and emit no bytecode that would replay them, so a
        // cache HIT (which compiles nothing) leaves both tables empty and a
        // run-time `eval` diverges from the cold run. Detect the side effect
        // semantically — did compiling this form grow either table? — which
        // also covers a macro use that expands into a `define-syntax`.
        const macros_before = vm.macros.count();
        const props_before = vm.syntax_properties.count();
        const compile_result = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path, false);
        if (vm.macros.count() != macros_before or vm.syntax_properties.count() != props_before)
            defines_syntax = true;
        const func = compile_result catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, datum_lc.col, err);
            toplevel_driver.script_had_error = true;
            had_compile_error = true;
            continue;
        };

        compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        vm.gc.extra_roots.append(allocator, types.makePointer(&func.header)) catch return error.OutOfMemory;
        if (sbc_path != null and !defines_syntax and !had_compile_error) {
            slots.append(allocator, .{ .function = @intCast(compiled_funcs.items.len - 1) }) catch return error.OutOfMemory;
        }

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        timings.begin(.execute);
        const exec_result = vm.execute(func);
        timings.end();
        const result = exec_result catch |err| {
            vm.gc.popRoot();
            toplevel_driver.script_had_error = true;
            const loc = toplevel_driver.vmErrorLocation(vm, path, datum_lc.line);
            toplevel_driver.reportRuntimeError(vm, err, loc);
            toplevel_driver.printSourceSnippet(source, loc.line);
            toplevel_driver.printStackTrace(vm);
            continue;
        };
        vm.gc.popRoot();

        printTopLevelResult(allocator, result);
    }

    // Cache compiled bytecode. Skipped in three cases.
    //
    // No compiled form AND no declaration (an empty or comment-only file).
    //
    // A form that registered a macro or syntax property at compile time (a HIT
    // would not replay the registration and run-time `eval` would diverge —
    // kaappi#2112), and any form that failed to compile (a HIT would silently
    // run the partial program with exit 0 where the cold run reported the error
    // with exit 1). Both also stop SLOT RECORDING mid-file (the guards in the
    // loop above), so a poisoned prefix can never pair with a clean suffix.
    //
    // The eight top-level declaration heads no longer refuse anything
    // (kaappi#1888): each becomes a declaration slot — its verbatim source
    // span, replayed positionally through the same dispatch on a HIT — while
    // `import`/`define-library`/`include` inside them hit the per-.sld library
    // cache. Best-effort: a failed write (read-only home, etc.) just means the
    // next run recompiles.
    // vm.run_cache_ok is false when some imported library declined caching
    // or could not write its entry: no record would ever validate it, so a
    // program entry here would serve stale compiled slots forever (#1888
    // review).
    if (!vm_library_cache_mod.runCacheOk(vm) and sbc_path != null) {
        timings.cacheReason("uncacheable dependency");
    }
    if (vm_library_cache_mod.runCacheOk(vm) and !defines_syntax and !had_compile_error and (compiled_funcs.items.len > 0 or slots.items.len > 0)) {
        if (sbc_path) |sp| {
            cache.ensureDir();
            if (bytecode_file.writeFileWithSlots(allocator, compiled_funcs.items, slots.items, vm.run_cache_includes.items, vm.run_cache_deps.items, source_hash, path, sp)) |_| {
                timings.cacheWrote(); // kaappi#1515: the miss's bytecode is now cached
            } else |err| switch (err) {
                // kaappi#2113: the writer refuses entries the reader would
                // reject rather than truncating them, so a permanent-miss
                // entry is never written — record why for `--timings`.
                error.LimitExceeded => timings.cacheReason("constant exceeds .sbc limits"),
                error.UnsupportedConstant => timings.cacheReason("unsupported constant"),
                else => {},
            }
        }
    } else if (sbc_path != null) {
        // A miss was recorded but nothing will be written — say why (#2114).
        if (defines_syntax) {
            timings.cacheReason("define-syntax");
        } else if (had_compile_error) {
            timings.cacheReason("compile error");
        }
    }
}

/// `kaappi test` worker path: install the collecting SRFI-64 runner, run the
/// file, then emit its one JSON result object. `suppress_exit` lets a file's
/// `(exit 1)` epilogue be recorded instead of terminating the worker before it
/// reports. The worker always exits 0 — the orchestrator reads pass/fail from
/// the emitted JSON, not from this process's status (a missing/empty result is
/// what signals a crash).
fn runWorkerFile(vm: *vm_mod.VM, fp: []const u8, emit_path: []const u8) !void {
    vm.suppress_exit = true;
    test_runner.installCollector(vm) catch {
        test_runner.emitResult(vm, emit_path, fp, true, "test collector setup failed", 0);
        toplevel_driver.script_had_error = false;
        return;
    };

    const start_ns = @import("vm_calls.zig").clockNs();
    toplevel_driver.script_had_error = false;
    runFile(vm, fp) catch {
        toplevel_driver.script_had_error = true;
    };
    const duration_ms = @as(f64, @floatFromInt(@import("vm_calls.zig").clockNs() -| start_ns)) / 1_000_000.0;

    // `toplevel_driver.script_had_error` means an *uncaught*
    // read/compile/runtime error at top level — SRFI-64 catches test
    // failures internally, so those never set it. Whether that makes the
    // file errored is `test_runner.resolveVerdict`'s call, not ours:
    // `suppress_exit` above swallowed any `(exit)` the file made, and that
    // call's semantics still have to be applied (kaappi#1903).
    test_runner.emitResult(vm, emit_path, fp, toplevel_driver.script_had_error, null, duration_ms);
    // The result is emitted; don't let the file's error propagate to a nonzero
    // worker exit — the orchestrator uses the JSON.
    toplevel_driver.script_had_error = false;
}

fn runStdin(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;
    const source = readAllStdin(allocator) catch {
        writeStderr("error: failed to read stdin\n");
        toplevel_driver.script_had_error = true;
        return;
    };
    defer allocator.free(source);

    crash.note(.reading, "<stdin>");

    var r = reader.Reader.initWithName(vm.gc, source, "<stdin>");
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError("<stdin>", lc.line, lc.col, err);
        toplevel_driver.script_had_error = true;
        return;
    }) {
        crash.noteStage(.reading);
        // Capture the datum's start position before reading it, so a compile
        // error with no recorded span still falls back to the form's start
        // column (not the post-datum position) — kaappi#1506.
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError("<stdin>", lc.line, lc.col, err);
            toplevel_driver.script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        crash.noteStage(.executing);
        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                toplevel_driver.script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, null);
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        crash.noteStage(.compiling);
        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, "<stdin>", false) catch |err| {
            toplevel_driver.reportCompileError("<stdin>", datum_lc.line, datum_lc.col, err);
            toplevel_driver.script_had_error = true;
            return;
        };

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            toplevel_driver.script_had_error = true;
            toplevel_driver.reportRuntimeError(vm, err, null);
            continue;
        };
        vm.gc.popRoot();

        printTopLevelResult(allocator, result);
    }
}

fn disassembleFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch {
        toplevel_driver.script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError(path, lc.line, lc.col, err);
        toplevel_driver.script_had_error = true;
        return;
    }) {
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError(path, lc.line, lc.col, err);
            toplevel_driver.script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // Same compile-only discipline as `--compile` (#2156): splice
        // `begin` / `cond-expand` so their bodies are disassembled rather than
        // run, and evaluate only the declarations the compiler depends on.
        var forms = toplevel_driver.TopLevelForms.init(vm, allocator, expr);
        defer forms.deinit();
        while (forms.next()) |form_result| {
            const form = form_result catch |err| {
                toplevel_driver.script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };

            if (vm.topLevelHead(form)) |head| {
                if (!head.isEnvSetup()) continue;
                _ = vm.runTopLevelHead(head, form) catch |err| {
                    toplevel_driver.script_had_error = true;
                    toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                };
                continue;
            }

            const func = compiler.compileExpressionWithMacrosAt(vm.gc, form, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
                toplevel_driver.reportCompileError(path, datum_lc.line, datum_lc.col, err);
                toplevel_driver.script_had_error = true;
                continue;
            };

            const disasm = @import("disassembler.zig");
            disasm.disassemble(func, allocator);
        }
    }
}

fn compileFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;

    // The artifact target is decided up front so a failure anywhere below can
    // still leave the target clean (#2513): a failed compile must leave NO
    // file at the exact -o / derived-.sbc path — not the truncated one a
    // failed write leaves behind, and not a stale one from a previous good
    // build that the build step would then embed as if it were current.
    const sbc_path = if (output_path) |op|
        allocator.dupe(u8, op) catch {
            writeStderr("Error creating output path\n");
            toplevel_driver.script_had_error = true;
            return;
        }
    else
        getSbcPath(allocator, path) catch {
            writeStderr("Error creating output path\n");
            toplevel_driver.script_had_error = true;
            return;
        };
    defer allocator.free(sbc_path);
    // Runs before the free above (LIFO): best-effort, and deliberately only
    // the exact target — the error itself was already reported at its site,
    // so a removal failure (permissions) has nothing further to add.
    defer if (toplevel_driver.script_had_error) {
        var pbuf: [platform.PATH_MAX]u8 = undefined;
        if (std.fmt.bufPrintZ(&pbuf, "{s}", .{sbc_path})) |pz| {
            _ = platform.unlink(pz);
        } else |_| {}
    };

    const source = readFileContents(allocator, path) catch {
        toplevel_driver.script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    // Collect library files for bundling
    var collect_files = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = collect_files.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        collect_files.deinit();
    }
    vm.compile_collect_files = &collect_files;
    defer vm.compile_collect_files = null;

    // Collect preamble (top-level forms: import, include, define-library)
    var preamble: std.ArrayList([]const u8) = .empty;
    defer {
        for (preamble.items) |p| allocator.free(p);
        preamble.deinit(allocator);
    }

    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError(path, lc.line, lc.col, err);
        toplevel_driver.script_had_error = true;
        return;
    }) {
        const datum_lc = r.getLineCol();
        timings.begin(.read); // kaappi#1515
        const read_result = r.readDatum();
        timings.end();
        var expr = read_result catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError(path, lc.line, lc.col, err);
            toplevel_driver.script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // Splice top-level `begin` / `cond-expand` instead of evaluating them:
        // their bodies are ordinary program code and belong in the bytecode,
        // not in this process (#2156).
        var forms = toplevel_driver.TopLevelForms.init(vm, allocator, expr);
        defer forms.deinit();
        while (forms.next()) |form_result| {
            const form = form_result catch |err| {
                toplevel_driver.script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };

            if (vm.topLevelHead(form)) |head| {
                // Only the env-setup declarations belong in the preamble, which
                // the artifact replays *before* any compiled form. `import` /
                // `include` / `include-ci` / `define-library` /
                // `define-record-type` establish the environment later forms
                // are compiled against, so hoisting them ahead of the compiled
                // stream is exactly what a preamble is for.
                //
                // `define-values` is NOT env setup: its producer is arbitrary
                // program code that can depend on earlier forms, so hoisting it
                // into the preamble reorders execution and can fail where the
                // interpreter succeeds (#2200). It has a compilable lowering
                // (`compileDefineValues`), so let it fall through to ordinary
                // compilation and keep its position in the compiled stream.
                // `begin` and `cond-expand` never reach here; TopLevelForms
                // already spliced them.
                if (head.isEnvSetup()) {
                    // Record the declaration for replay when the artifact runs.
                    // Propagate an allocation failure rather than dropping the
                    // form: silently continuing here writes an artifact missing
                    // an `import`, then prints `Compiled ... -> ...` and exits 0.
                    // `runFile`'s equivalent site returns error.OutOfMemory too.
                    const form_src = try printer.valueToString(allocator, form, .write);
                    preamble.append(allocator, form_src) catch {
                        allocator.free(form_src);
                        return error.OutOfMemory;
                    };
                    _ = vm.runTopLevelHead(head, form) catch |err| {
                        toplevel_driver.script_had_error = true;
                        toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                    };
                    continue;
                }
            }

            const func = compiler.compileExpressionWithMacrosAt(vm.gc, form, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
                toplevel_driver.reportCompileError(path, datum_lc.line, datum_lc.col, err);
                toplevel_driver.script_had_error = true;
                continue;
            };

            // Likewise: dropping a compiled top-level form here would emit an
            // artifact silently missing that code.
            compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        }
    }

    // A run that reported any uncaught error must not write an artifact or
    // claim success (#2513): the driver recovers from each error and keeps
    // compiling, so `compiled_funcs` here can be a plausible-looking partial
    // bundle — an import that failed at evaluation time, everything after it
    // missing or uncompilable. The exit-status rule already fails the run;
    // writing the artifact anyway would replace a previous good build at the
    // target with the broken one (or leave a stale one, via the defer above)
    // and the `Compiled ... -> ...` line would tell a stdout-reading build
    // step that it worked.
    if (toplevel_driver.script_had_error) return;

    if (compiled_funcs.items.len > 0 or preamble.items.len > 0) {
        timings.setOutput(sbc_path); // kaappi#1515: the named .sbc artifact

        const has_bundle = collect_files.count() > 0 or preamble.items.len > 0;
        if (has_bundle) {
            bytecode_file.writeFileWithBundle(
                allocator,
                compiled_funcs.items,
                source_hash,
                path,
                &collect_files,
                preamble.items,
                sbc_path,
            ) catch |err| {
                reportBytecodeWriteError(err);
                toplevel_driver.script_had_error = true;
                return;
            };
        } else {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, path, sbc_path) catch |err| {
                reportBytecodeWriteError(err);
                toplevel_driver.script_had_error = true;
                return;
            };
        }

        writeStdout("Compiled ");
        writeStdout(path);
        writeStdout(" -> ");
        writeStdout(sbc_path);
        writeStdout("\n");
    }
}

// ── #2513 regression tests ──────────────────────────────────────────────────
//
// Drive the real `--compile` driver loop over real files. The shell-level
// twin, which also asserts the exit status and the missing `Compiled ...`
// line, is tests/scheme/errors/compile-failure-signals-2513.sh.

test "compileFile: failed compile leaves no artifact and sets the flag (#2513)" {
    if (comptime is_wasm) return error.SkipZigTest; // writes real files
    const th = @import("testing_helpers.zig");
    const testing = std.testing;

    var tc: th.TestContext = undefined;
    try tc.init();
    defer tc.deinit();
    const allocator = tc.vm.gc.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir_path);

    // The import fails at evaluation time while the display form still
    // compiles — exactly the shape that used to fall out the loop with a
    // partial function list, write the artifact anyway, and print `Compiled`.
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "bad.scm",
        .data = "(import (nonexistent-library-2513))\n(display \"this form still compiles\")\n",
    });
    const bad_path = try std.fs.path.join(allocator, &.{ dir_path, "bad.scm" });
    defer allocator.free(bad_path);
    const out_path = try std.fs.path.join(allocator, &.{ dir_path, "out.sbc" });
    defer allocator.free(out_path);

    toplevel_driver.script_had_error = false;
    defer toplevel_driver.script_had_error = false;

    try compileFile(tc.vm, bad_path, out_path);
    try testing.expect(toplevel_driver.script_had_error);
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(testing.io, "out.sbc", .{}));

    // A stale artifact at the target from a previous good build must be
    // removed by the failed run, not silently kept looking current.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "out.sbc", .data = "stale artifact" });
    toplevel_driver.script_had_error = false;
    try compileFile(tc.vm, bad_path, out_path);
    try testing.expect(toplevel_driver.script_had_error);
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(testing.io, "out.sbc", .{}));
}

test "compileFile: successful compile still writes the artifact (#2513 control)" {
    if (comptime is_wasm) return error.SkipZigTest; // writes real files
    const th = @import("testing_helpers.zig");
    const testing = std.testing;

    var tc: th.TestContext = undefined;
    try tc.init();
    defer tc.deinit();
    const allocator = tc.vm.gc.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir_path);

    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "good.scm",
        .data = "(import (scheme base))\n(display \"fine\")\n",
    });
    const good_path = try std.fs.path.join(allocator, &.{ dir_path, "good.scm" });
    defer allocator.free(good_path);
    const out_path = try std.fs.path.join(allocator, &.{ dir_path, "out.sbc" });
    defer allocator.free(out_path);

    toplevel_driver.script_had_error = false;
    defer toplevel_driver.script_had_error = false;

    try compileFile(tc.vm, good_path, out_path);
    try testing.expect(!toplevel_driver.script_had_error);
    _ = try tmp.dir.statFile(testing.io, "out.sbc", .{});
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
