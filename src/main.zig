const std = @import("std");
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
pub const ln = if (is_wasm) struct {} else @import("linenoise.zig");
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
pub const cli = @import("cli.zig");

pub const version = @import("build_options").version;

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result <= 0) {
            if (result < 0 and std.posix.errno(result) == .INTR) continue;
            break;
        }
        const written: usize = @intCast(result);
        total += written;
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

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
        const probe_fd = std.c.open(path_z, .{});
        if (probe_fd >= 0) {
            defer _ = std.c.close(probe_fd);
            const is_dir = if (comptime is_linux) blk: {
                const linux = std.os.linux;
                var sx: linux.Statx = undefined;
                const rc = linux.statx(probe_fd, "", 0x1000, .{ .TYPE = true }, &sx);
                break :blk rc <= @as(usize, std.math.maxInt(isize)) and (sx.mode & std.posix.S.IFMT == std.posix.S.IFDIR);
            } else blk: {
                var stat_buf: std.c.Stat = undefined;
                break :blk std.c.fstat(probe_fd, &stat_buf) == 0 and (stat_buf.mode & std.posix.S.IFMT == std.posix.S.IFDIR);
            };
            if (is_dir) {
                std.debug.print("Error: '{s}' is a directory\n", .{path});
                return error.IsDir;
            }
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
        const raw = std.c.read(0, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (std.posix.errno(raw) == .INTR) continue;
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
        try library.registerSandboxedLibraries(&vm.libraries, vm.globals);
        vm.sandbox_mode = true;
    } else {
        try primitives.registerAll(vm);
        memory.setGCInstance(&gc);
        try library.registerStandardLibraries(&vm.libraries, vm.globals);
    }

    const opts = cli.parse(init.args);
    if (opts.action == .exit_ok) return;

    // Apply parsed options to VM/GC
    if (opts.timeout_ms) |ms| {
        const clockNs = @import("vm_calls.zig").clockNs;
        vm.timeout_deadline_ns = clockNs() + ms * 1_000_000;
    }
    if (opts.max_memory) |limit| gc.memory_limit = limit;
    if (opts.coverage_xml_path) |p| vm.coverage_xml_path = p;
    vm.command_line_args = opts.scriptArgs();

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
                            if (detail.len > 0) {
                                writeStderr("preamble error: ");
                                writeStderr(detail);
                                writeStderr("\n");
                            } else {
                                var errbuf: [256]u8 = undefined;
                                const s = std.fmt.bufPrint(&errbuf, "preamble error: {}\n", .{err}) catch "preamble error\n";
                                writeStderr(s);
                            }
                            vm.last_error_detail_len = 0;
                        };
                    }
                }
            }
        }

        const top_count = @min(loaded.top_level_count, @as(u32, @intCast(loaded.funcs.len)));
        for (loaded.funcs[0..top_count]) |func| {
            var func_val = types.makePointer(@ptrCast(func));
            vm.gc.pushRoot(&func_val);
            const result = vm.execute(func) catch |err| {
                vm.gc.popRoot();
                script_had_error = true;
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    writeStderr(detail);
                    writeStderr("\n");
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "runtime error: {}\n", .{err}) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
                continue;
            };
            vm.gc.popRoot();

            printTopLevelResult(allocator, result);
        }
        return;
    }

    // Library path auto-discovery: script dir + ~/.kaappi/lib
    var lib_paths: [16][]const u8 = undefined;
    var lib_path_count: usize = 0;
    for (opts.libPaths()) |lp| {
        if (lib_path_count < 16) {
            lib_paths[lib_path_count] = lp;
            lib_path_count += 1;
        }
    }

    if (opts.file_path) |fp| {
        if (std.mem.lastIndexOfScalar(u8, fp, '/')) |pos| {
            if (lib_path_count < 16) {
                lib_paths[lib_path_count] = if (pos == 0) fp[0..1] else fp[0..pos];
                lib_path_count += 1;
            }
        }
    }

    if (!is_wasm) {
        const kaappi_lib_path = blk: {
            const kaappi_paths = @import("kaappi_paths.zig");
            var home_buf: [512]u8 = undefined;
            const home = kaappi_paths.getHome(&home_buf) orelse break :blk null;
            const lib_suffix = "/lib";
            const path = allocator.alloc(u8, home.len + lib_suffix.len) catch break :blk null;
            @memcpy(path[0..home.len], home);
            @memcpy(path[home.len..][0..lib_suffix.len], lib_suffix);
            break :blk path;
        };
        if (kaappi_lib_path) |klp| {
            if (lib_path_count < 16) {
                lib_paths[lib_path_count] = klp;
                lib_path_count += 1;
            }
            const env_name = if (@import("builtin").os.tag == .macos)
                "DYLD_LIBRARY_PATH"
            else
                "LD_LIBRARY_PATH";
            const existing = std.c.getenv(env_name);
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
            try native_compiler.compileNative(vm, fp, opts.compile_output);
        } else {
            usageError("Usage: kaappi compile <file.scm> [-o output]\n");
        }
        return;
    }

    if (opts.disassemble_mode) {
        if (opts.file_path) |fp| {
            try disassembleFile(vm, fp);
        } else {
            usageError("Usage: kaappi --disassemble <file.scm>\n");
        }
    } else if (opts.compile_mode) {
        if (opts.file_path) |fp| {
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
        try runFile(vm, fp);
    } else {
        if (is_wasm) {
            writeStderr("kaappi-wasm: no file specified\n");
            return;
        }
        if (!is_wasm and std.c.isatty(0) == 0) {
            try runStdin(vm);
        } else {
            try repl_mod.repl(vm);
        }
    }
}

fn getSbcPath(allocator: std.mem.Allocator, scm_path: []const u8) ![]u8 {
    return bytecode_file.getSbcPath(allocator, scm_path);
}

fn runFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    const source = readFileContents(allocator, path) catch {
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Try loading cached bytecode (skip in sandbox mode — no filesystem side effects)
    const sbc_path = if (vm.sandbox_mode) null else getSbcPath(allocator, path) catch null;
    defer if (sbc_path) |p| allocator.free(p);

    if (sbc_path) |sp| {
        if (bytecode_file.readFileWithTopLevel(vm.gc, source_hash, sp) catch null) |loaded| {
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
                        if (vm.handleTopLevelForm(expr)) |top_result| {
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
            for (loaded.funcs[0..top_count]) |func| {
                var func_val = types.makePointer(@ptrCast(func));
                vm.gc.pushRoot(&func_val);
                const result = vm.execute(func) catch |err| {
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

    // No cache — compile from source
    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);
    var has_imports = false;

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
            has_imports = true;
            const result = top_result catch |err| {
                script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path) catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, err);
            script_had_error = true;
            continue;
        };

        compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        vm.gc.extra_roots.append(allocator, types.makePointer(@ptrCast(func))) catch return error.OutOfMemory;

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

        const result = vm.execute(func) catch |err| {
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
    // collected function pointers during library loading)
    if (!has_imports and compiled_funcs.items.len > 0) {
        if (sbc_path) |sp| {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, sp) catch {};
        }
    }
}

fn runStdin(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;
    const source = readAllStdin(allocator) catch {
        writeStderr("error: failed to read stdin\n");
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    var r = reader.Reader.initWithName(vm.gc, source, "<stdin>");
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError("<stdin>", lc.line, lc.col, err);
        script_had_error = true;
        return;
    }) {
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError("<stdin>", lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                script_had_error = true;
                toplevel_driver.reportRuntimeError(vm, err, null);
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, 0, "<stdin>") catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportCompileError("<stdin>", lc.line, err);
            script_had_error = true;
            return;
        };

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

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

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path) catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, err);
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
        var expr = r.readDatum() catch |err| {
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

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path) catch |err| {
            toplevel_driver.reportCompileError(path, datum_lc.line, err);
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

        const has_bundle = collect_files.count() > 0 or preamble.items.len > 0;
        if (has_bundle) {
            bytecode_file.writeFileWithBundle(
                allocator,
                compiled_funcs.items,
                source_hash,
                &collect_files,
                preamble.items,
                sbc_path,
            ) catch {
                writeStderr("Error writing bytecode file\n");
                script_had_error = true;
                return;
            };
        } else {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, sbc_path) catch {
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
    _ = repl_mod;
    _ = cli;
}
