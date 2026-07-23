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
pub const ln = if (is_wasm or builtin_os.tag == .windows) struct {} else @import("linenoise.zig");
pub const ffi = @import("ffi.zig");
pub const primitives_ffi = @import("primitives_ffi.zig");
pub const primitives_srfi1 = @import("primitives_srfi1.zig");
pub const primitives_hashtable = @import("primitives_hashtable.zig");
pub const primitives_random = @import("primitives_random.zig");
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
pub const timings = @import("timings.zig");
pub const check = @import("check.zig");
pub const pipeline = @import("pipeline.zig");
pub const config = @import("config.zig");
pub const fmt = @import("fmt.zig");
pub const crash = @import("crash.zig");

pub const version = @import("build_options").version;

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

/// Set when a script (file or stdin) hit an uncaught read/compile/runtime
/// error that was reported but recovered from. Scripts must exit non-zero in
/// that case so callers (e.g. tests/scheme/run-all.sh) can detect the failure;
/// REPL sessions never set this.
var script_had_error: bool = false;

fn mainInner(init: std.process.Init.Minimal) void {
    mainImpl(init) catch {
        std.process.exit(1);
    };
    if (script_had_error) std.process.exit(1);
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
    // of that exists and exit. (Skipped on WASM, whose entry just runs a file.)
    if (comptime !is_wasm) {
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
    defer gc.deinit();

    const vm = try allocator.create(vm_mod.VM);
    vm.* = try vm_mod.VM.init(&gc);
    defer {
        vm.deinit();
        allocator.destroy(vm);
    }
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
        const file_path = wasi_args.next() orelse {
            writeStderr("kaappi-wasm: no file specified\n");
            return;
        };
        try runFile(vm, file_path);
        return;
    }

    const is_sandboxed = cli.preScanSandbox(init.args);

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

    var opts = cli.parse(init.args);
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
            script_had_error = true;
            return;
        } orelse {
            writeStderr("fatal: invalid embedded bytecode (wrong version or format)\n");
            script_had_error = true;
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
                            script_had_error = true;
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
                script_had_error = true;
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
    // Never freed: vm.lib_paths points in here and is read as late as the
    // deferred coverage report, so it must live for the whole run — like the
    // auto-discovered dir strings (klp/elp below) it aliases.
    const auto_discovered_max = 3;
    const lib_paths = try allocator.alloc([]const u8, opts.libPaths().len + auto_discovered_max);
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
            const path = allocator.alloc(u8, home.len + lib_suffix.len) catch break :blk null;
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
                    const new = allocator.alloc(u8, klp.len + 1 + ex_len + 1) catch null;
                    if (new) |n| {
                        @memcpy(n[0..klp.len], klp);
                        n[klp.len] = ':';
                        @memcpy(n[klp.len + 1 .. klp.len + 1 + ex_len], ex[0..ex_len]);
                        n[klp.len + 1 + ex_len] = 0;
                        _ = setenv(env_name, @ptrCast(n[0 .. klp.len + 1 + ex_len :0]), 1);
                    }
                } else {
                    const z = allocator.dupeZ(u8, klp) catch null;
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
            break :blk allocator.dupe(u8, elp) catch null;
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

/// SRFI 59/193: absolute-ize `path` without following symlinks -- a pure
/// lexical join+normalize (`.`/`..` collapsed) against the process's
/// starting cwd, never a `realpath`-style syscall. Returns `null` (rather
/// than propagating an allocation failure) on the rare case `getCwd` itself
/// fails; callers treat that identically to "not running a script".
fn resolveScriptPath(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    if (std.fs.path.isAbsolute(path)) {
        return allocator.dupe(u8, path) catch null;
    }
    var buf: [platform.PATH_MAX]u8 = undefined;
    const cwd = platform.getCwd(&buf) orelse return null;
    return std.fs.path.resolve(allocator, &.{ cwd, path }) catch null;
}

fn runFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    // SRFI 59/193: resolve the script's absolute path once, up front --
    // never freed (process-lifetime, same convention as command_line_args).
    vm.script_path = resolveScriptPath(allocator, path);

    // Crash breadcrumb (kaappi#1514): name the file once; stages update per-form.
    crash.noteFile(path);

    const source = readFileContents(allocator, path) catch {
        script_had_error = true;
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
        if (bytecode_file.readFileWithTopLevel(vm.gc, source_hash, sp) catch null) |loaded| {
            timings.cacheHit(sp);
            defer allocator.free(loaded.funcs);

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

            const top_count = @min(loaded.top_level_count, @as(u32, @intCast(loaded.funcs.len)));
            crash.noteStage(.executing);
            for (loaded.funcs[0..top_count]) |func| {
                var func_val = types.makePointer(&func.header);
                vm.gc.pushRoot(&func_val);
                timings.begin(.execute);
                const exec_result = vm.execute(func);
                timings.end();
                const result = exec_result catch |err| {
                    vm.gc.popRoot();
                    script_had_error = true;
                    const loc = toplevel_driver.vmErrorLocation(vm, path, 0);
                    toplevel_driver.reportRuntimeError(vm, err, loc);
                    if (loc.line > 0) toplevel_driver.printSourceSnippet(source, loc.line);
                    toplevel_driver.printStackTrace(vm);
                    continue;
                };
                vm.gc.popRoot();

                printTopLevelResult(allocator, result);
            }
            return;
        }
    }

    // No cache — compile from source. A non-null sbc_path here means the cache
    // was consulted and missed (kaappi#1515); the write below marks it written.
    if (sbc_path) |sp| timings.cacheMiss(sp);

    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);
    var has_imports = false;

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    crash.noteStage(.reading);
    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError(path, lc.line, lc.col, err);
        script_had_error = true;
        return;
    }) {
        crash.noteStage(.reading);
        const datum_lc = r.getLineCol();
        timings.begin(.read);
        const read_result = r.readDatum();
        timings.end();
        var expr = read_result catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError(path, lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // A top-level import/define-library/include runs library code here.
        crash.noteStage(.executing);
        timings.begin(.execute);
        const maybe_top = vm.handleTopLevelForm(expr);
        timings.end();
        if (maybe_top) |top_result| {
            has_imports = true;
            const result = top_result catch |err| {
                script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        crash.noteStage(.compiling);
        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, datum_lc.col, err);
            script_had_error = true;
            continue;
        };

        compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        vm.gc.extra_roots.append(allocator, types.makePointer(&func.header)) catch return error.OutOfMemory;

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        timings.begin(.execute);
        const exec_result = vm.execute(func);
        timings.end();
        const result = exec_result catch |err| {
            vm.gc.popRoot();
            script_had_error = true;
            const loc = toplevel_driver.vmErrorLocation(vm, path, datum_lc.line);
            toplevel_driver.reportRuntimeError(vm, err, loc);
            toplevel_driver.printSourceSnippet(source, loc.line);
            toplevel_driver.printStackTrace(vm);
            continue;
        };
        vm.gc.popRoot();

        printTopLevelResult(allocator, result);
    }

    // Cache compiled bytecode (skip when imports are used — GC may have freed
    // collected function pointers during library loading). Best-effort: a
    // failed write (read-only home, etc.) just means the next run recompiles.
    if (!has_imports and compiled_funcs.items.len > 0) {
        if (sbc_path) |sp| {
            cache.ensureDir();
            if (bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, path, sp)) |_| {
                timings.cacheWrote(); // kaappi#1515: the miss's bytecode is now cached
            } else |_| {}
        }
    } else if (has_imports and sbc_path != null) {
        // A miss was recorded, but imported programs are never cached — say so.
        timings.cacheReason("imports");
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
        script_had_error = false;
        return;
    };

    const start_ns = @import("vm_calls.zig").clockNs();
    script_had_error = false;
    runFile(vm, fp) catch {
        script_had_error = true;
    };
    const duration_ms = @as(f64, @floatFromInt(@import("vm_calls.zig").clockNs() -| start_ns)) / 1_000_000.0;

    // A file-level error is an *uncaught* read/compile/runtime error at top
    // level — SRFI-64 catches test failures internally, so those never set
    // this. A test file's `(exit 1)` failure epilogue is deliberately NOT an
    // error: it is redundant with the fail counts we already collected.
    const errored = script_had_error;
    test_runner.emitResult(vm, emit_path, fp, errored, null, duration_ms);
    // The result is emitted; don't let the file's error propagate to a nonzero
    // worker exit — the orchestrator uses the JSON.
    script_had_error = false;
}

fn runStdin(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;
    const source = readAllStdin(allocator) catch {
        writeStderr("error: failed to read stdin\n");
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    crash.note(.reading, "<stdin>");

    var r = reader.Reader.initWithName(vm.gc, source, "<stdin>");
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError("<stdin>", lc.line, lc.col, err);
        script_had_error = true;
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
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        crash.noteStage(.executing);
        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, null);
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        crash.noteStage(.compiling);
        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, "<stdin>", false) catch |err| {
            toplevel_driver.reportCompileError("<stdin>", datum_lc.line, datum_lc.col, err);
            script_had_error = true;
            return;
        };

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            script_had_error = true;
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
        script_had_error = true;
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
        script_had_error = true;
        return;
    }) {
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError(path, lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        if (vm.handleTopLevelForm(expr)) |top_result| {
            _ = top_result catch |err| {
                script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
            };
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, datum_lc.col, err);
            script_had_error = true;
            continue;
        };

        const disasm = @import("disassembler.zig");
        disasm.disassemble(func, allocator);
    }
}

fn compileFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch {
        script_had_error = true;
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
        script_had_error = true;
        return;
    }) {
        const datum_lc = r.getLineCol();
        timings.begin(.read); // kaappi#1515
        const read_result = r.readDatum();
        timings.end();
        var expr = read_result catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError(path, lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        if (vm.handleTopLevelForm(expr)) |top_result| {
            const form_src = printer.valueToString(allocator, expr, .write) catch continue;
            _ = top_result catch |err| {
                script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
            };
            preamble.append(allocator, form_src) catch {
                allocator.free(form_src);
            };
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, datum_lc.col, err);
            script_had_error = true;
            continue;
        };

        compiled_funcs.append(allocator, func) catch {};
    }

    if (compiled_funcs.items.len > 0 or preamble.items.len > 0) {
        const sbc_path = if (output_path) |op|
            allocator.dupe(u8, op) catch {
                writeStderr("Error creating output path\n");
                script_had_error = true;
                return;
            }
        else
            getSbcPath(allocator, path) catch {
                writeStderr("Error creating output path\n");
                script_had_error = true;
                return;
            };
        defer allocator.free(sbc_path);
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
            ) catch {
                writeStderr("Error writing bytecode file\n");
                script_had_error = true;
                return;
            };
        } else {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, path, sbc_path) catch {
                writeStderr("Error writing bytecode file\n");
                script_had_error = true;
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
    _ = ln;
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
