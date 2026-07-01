const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
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

pub const version = "0.9.1";

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

fn printUsage() void {
    writeStdout(
        "Kaappi Scheme v" ++ version ++ "\n" ++
            "\n" ++
            "Usage: kaappi [options] [file] [script-args...]\n" ++
            "       kaappi compile <file.scm> [-o output]\n" ++
            "\n" ++
            "Commands:\n" ++
            "  compile <file>     Compile to native binary via LLVM\n" ++
            "\n" ++
            "Options:\n" ++
            "  -h, --help         Show this help message\n" ++
            "  --version          Show version\n" ++
            "  --lib-path <path>  Add library search path (up to 16)\n" ++
            "  --compile          Compile file to bytecode (.sbc)\n" ++
            "  --emit-llvm        Emit LLVM IR text (.ll)\n" ++
            "  -o <file>          Output path\n" ++
            "  --disassemble      Disassemble bytecode\n" ++
            "  --sandbox          Restrict filesystem and process access\n" ++
            "  --gc-stats         Print GC statistics on exit\n" ++
            "  --profile          Enable profiling\n" ++
            "  --coverage         Report library procedure coverage\n" ++
            "  --coverage-xml <f> Write Cobertura XML coverage to file\n" ++
            "  --timeout <ms>     Execution timeout in milliseconds\n" ++
            "  --max-memory <n>   Maximum heap memory in bytes\n" ++
            "  --completions <sh> Output completion script (bash, zsh, fish)\n" ++
            "\n" ++
            "Environment variables:\n" ++
            "  KAAPPI_LIB_DIR     Directory containing libkaappi_rt.a (for compile)\n" ++
            "\n" ++
            "With no file argument, starts an interactive REPL.\n",
    );
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

fn printSourceSnippet(source: []const u8, line: u32) void {
    if (line == 0 or source.len == 0) return;
    var current_line: u32 = 1;
    var line_start: usize = 0;
    for (source, 0..) |c, i| {
        if (current_line == line) {
            var line_end = i;
            while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
            const snippet = source[line_start..line_end];
            if (snippet.len > 0) {
                writeStderr("    ");
                writeStderr(snippet);
                writeStderr("\n");
            }
            return;
        }
        if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }
    if (current_line == line and line_start < source.len) {
        writeStderr("    ");
        writeStderr(source[line_start..]);
        writeStderr("\n");
    }
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
    defer allocator.free(path_z);

    const fd = if (comptime is_wasm) blk: {
        var result_fd: std.os.wasi.fd_t = undefined;
        const rc = std.os.wasi.path_open(3, .{ .SYMLINK_FOLLOW = true }, path.ptr, path.len, .{}, .{ .FD_READ = true, .FD_SEEK = true }, .{ .FD_READ = true }, .{}, &result_fd);
        if (rc != .SUCCESS) {
            std.debug.print("Error opening file '{s}': {}\n", .{ path, rc });
            break :blk @as(c_int, -1);
        }
        break :blk @as(c_int, @intCast(result_fd));
    } else blk: {
        break :blk std.c.open(path_z, .{});
    };
    if (fd < 0) {
        std.debug.print("Error opening file '{s}'\n", .{path});
        return error.FileNotFound;
    }
    defer _ = std.c.close(fd);

    const max_size: usize = 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = std.c.read(fd, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (std.posix.errno(raw) == .INTR) continue;
            break;
        }
        const bytes_read: usize = @intCast(raw);
        if (result.items.len + bytes_read > max_size) {
            std.debug.print("File too large\n", .{});
            return error.StreamTooLong;
        }
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }

    return result.toOwnedSlice(allocator);
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

fn mainInner(init: std.process.Init.Minimal) void {
    mainImpl(init) catch {};
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
        primitives.setGCInstance(&gc);
        try library.registerStandardLibraries(&vm.libraries, &vm.globals);

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

    // Pre-scan args for --sandbox (must happen before primitive registration)
    var is_sandboxed = false;
    {
        var pre_args = init.args.iterate();
        while (pre_args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--sandbox")) is_sandboxed = true;
        }
    }

    if (is_sandboxed) {
        try primitives.registerSandboxed(vm);
        primitives.setGCInstance(&gc);
        try library.registerSandboxedLibraries(&vm.libraries, &vm.globals);
        vm.sandbox_mode = true;
    } else {
        try primitives.registerAll(vm);
        primitives.setGCInstance(&gc);
        try library.registerStandardLibraries(&vm.libraries, &vm.globals);
    }

    // Standalone mode: run embedded bytecode and exit
    if (embedded_bytecode.bytecode) |bytecode_data| {
        // Parse flags before file arguments
        var sa: [64][]const u8 = undefined;
        var sa_count: usize = 0;
        var sa_gc_stats = false;
        var sa_profile = false;
        var sa_coverage = false;
        var sa_iter = init.args.iterate();
        _ = sa_iter.skip();
        while (sa_iter.next()) |arg| {
            if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
                printUsage();
                return;
            } else if (std.mem.eql(u8, arg, "--version")) {
                writeStdout("Kaappi Scheme v" ++ version ++ "\n");
                return;
            } else if (std.mem.eql(u8, arg, "--completions")) {
                if (sa_iter.next()) |shell| {
                    if (@import("completions.zig").kaappi(shell)) |script| {
                        writeStdout(script);
                    } else {
                        writeStderr("unknown shell: ");
                        writeStderr(shell);
                        writeStderr("\nSupported: bash, zsh, fish\n");
                    }
                } else {
                    writeStderr("--completions requires a shell name (bash, zsh, fish)\n");
                }
                return;
            } else if (std.mem.eql(u8, arg, "--gc-stats")) {
                sa_gc_stats = true;
            } else if (std.mem.eql(u8, arg, "--profile")) {
                sa_profile = true;
            } else if (std.mem.eql(u8, arg, "--coverage")) {
                sa_coverage = true;
            } else if (std.mem.eql(u8, arg, "--coverage-xml")) {
                sa_coverage = true;
                if (sa_iter.next()) |p| vm.coverage_xml_path = p;
            } else {
                if (sa_count < 64) {
                    sa[sa_count] = arg;
                    sa_count += 1;
                }
            }
        }
        vm.command_line_args = sa[0..sa_count];

        defer if (sa_gc_stats) reporting.printGcStats(&gc);
        if (sa_profile) vm.profile_mode = true;
        defer if (sa_profile) reporting.printProfileReport(&gc);
        if (sa_coverage) {
            vm.profile_mode = true;
            vm.coverage_mode = true;
        }
        defer if (sa_coverage) {
            reporting.printCoverageReport(vm);
            if (vm.coverage_xml_path) |p| reporting.writeCoverageXml(vm, p);
        };

        const loaded = bytecode_file.readFromBuffer(&gc, bytecode_data) catch {
            writeStderr("fatal: corrupted embedded bytecode\n");
            return;
        } orelse {
            writeStderr("fatal: invalid embedded bytecode (wrong version or format)\n");
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
                    const expr = pr.readDatum() catch break;
                    if (vm.handleTopLevelForm(expr)) |top_result| {
                        _ = top_result catch |err| {
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
            vm.gc.pushRoot(&func_val) catch return error.OutOfMemory;
            const result = vm.execute(func) catch |err| {
                vm.gc.popRoot();
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

            var display_result = result;
            if (types.isMultipleValues(display_result)) {
                const mv = types.toObject(display_result).as(types.MultipleValues);
                display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (display_result != types.VOID) {
                const s = printer.valueToString(allocator, display_result, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
        }
        return;
    }

    var args = init.args.iterate();
    _ = args.skip(); // skip program name

    var lib_paths: [16][]const u8 = undefined;
    var lib_path_count: usize = 0;
    var file_path: ?[]const u8 = null;
    var compile_mode = false;
    var native_compile_mode = false;
    var emit_llvm_mode = false;
    var compile_output: ?[]const u8 = null;
    var disassemble_mode = false;
    var gc_stats_mode = false;
    var profile_mode = false;
    var profile_json_path: ?[]const u8 = null;
    var coverage_mode = false;
    var sandbox_mode = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--gc-stats")) {
            gc_stats_mode = true;
        } else if (std.mem.eql(u8, arg, "--lib-path")) {
            if (args.next()) |lp| {
                if (lib_path_count < 16) {
                    lib_paths[lib_path_count] = lp;
                    lib_path_count += 1;
                }
            }
        } else if (std.mem.eql(u8, arg, "--profile")) {
            profile_mode = true;
        } else if (std.mem.eql(u8, arg, "--profile-json")) {
            profile_mode = true;
            profile_json_path = args.next();
        } else if (std.mem.eql(u8, arg, "--coverage")) {
            coverage_mode = true;
        } else if (std.mem.eql(u8, arg, "--coverage-xml")) {
            coverage_mode = true;
            if (args.next()) |p| vm.coverage_xml_path = p;
        } else if (std.mem.eql(u8, arg, "--sandbox")) {
            sandbox_mode = true;
        } else if (std.mem.eql(u8, arg, "compile")) {
            native_compile_mode = true;
        } else if (std.mem.eql(u8, arg, "--compile")) {
            compile_mode = true;
        } else if (std.mem.eql(u8, arg, "--emit-llvm")) {
            emit_llvm_mode = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            compile_output = args.next();
        } else if (std.mem.eql(u8, arg, "--disassemble")) {
            disassemble_mode = true;
        } else if (std.mem.eql(u8, arg, "--timeout")) {
            if (args.next()) |ms_str| {
                const ms = std.fmt.parseInt(u64, ms_str, 10) catch 0;
                if (ms > 0) {
                    const clockNs = @import("vm_calls.zig").clockNs;
                    vm.timeout_deadline_ns = clockNs() + ms * 1_000_000;
                }
            }
        } else if (std.mem.eql(u8, arg, "--max-memory")) {
            if (args.next()) |mem_str| {
                const limit = std.fmt.parseInt(usize, mem_str, 10) catch 0;
                if (limit > 0) gc.memory_limit = limit;
            }
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            writeStdout("Kaappi Scheme v" ++ version ++ "\n");
            return;
        } else if (std.mem.eql(u8, arg, "--completions")) {
            if (args.next()) |shell| {
                if (@import("completions.zig").kaappi(shell)) |script| {
                    writeStdout(script);
                } else {
                    writeStderr("unknown shell: ");
                    writeStderr(shell);
                    writeStderr("\nSupported: bash, zsh, fish\n");
                }
            } else {
                writeStderr("--completions requires a shell name (bash, zsh, fish)\n");
            }
            return;
        } else {
            file_path = arg;
            break;
        }
    }

    // Collect remaining args after the file path for (command-line).
    // Also check for -o which is valid after the file path for compile modes.
    var script_args: [64][]const u8 = undefined;
    var script_arg_count: usize = 0;
    if (file_path) |fp| {
        script_args[0] = fp;
        script_arg_count = 1;
        const consumes_output = compile_mode or native_compile_mode or disassemble_mode or emit_llvm_mode;
        while (args.next()) |extra| {
            if (consumes_output and std.mem.eql(u8, extra, "-o")) {
                if (compile_output == null) compile_output = args.next();
                continue;
            }
            if (script_arg_count < 64) {
                script_args[script_arg_count] = extra;
                script_arg_count += 1;
            }
        }
    }
    vm.command_line_args = script_args[0..script_arg_count];

    // Auto-add ~/.kaappi/lib as a default library search path
    if (!is_wasm) {
        const kaappi_lib_path = blk: {
            const home = std.c.getenv("HOME") orelse break :blk null;
            const home_len = std.mem.len(home);
            const suffix = "/.kaappi/lib";
            const path = allocator.alloc(u8, home_len + suffix.len) catch break :blk null;
            @memcpy(path[0..home_len], home[0..home_len]);
            @memcpy(path[home_len..], suffix);
            break :blk path;
        };
        if (kaappi_lib_path) |klp| {
            if (lib_path_count < 16) {
                lib_paths[lib_path_count] = klp;
                lib_path_count += 1;
            }
            // Set DYLD_LIBRARY_PATH / LD_LIBRARY_PATH for FFI dlopen
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

    defer if (gc_stats_mode) reporting.printGcStats(&gc);
    if (profile_mode) vm.profile_mode = true;
    defer if (profile_mode) {
        reporting.printProfileReport(&gc);
        if (profile_json_path) |jp| {
            reporting.writeProfileJson(&gc, jp);
        }
    };
    if (coverage_mode) {
        vm.profile_mode = true;
        vm.coverage_mode = true;
    }
    defer if (coverage_mode) {
        reporting.printCoverageReport(vm);
        if (vm.coverage_xml_path) |p| reporting.writeCoverageXml(vm, p);
    };

    if (native_compile_mode) {
        if (file_path) |fp| {
            try compileNative(vm, fp, compile_output);
        } else {
            writeStdout("Usage: kaappi compile <file.scm> [-o output]\n");
        }
        return;
    }

    if (disassemble_mode) {
        if (file_path) |fp| {
            try disassembleFile(vm, fp);
        } else {
            writeStdout("Usage: kaappi --disassemble <file.scm>\n");
        }
    } else if (compile_mode) {
        if (file_path) |fp| {
            try compileFile(vm, fp, compile_output);
        } else {
            writeStdout("Usage: kaappi --compile <file.scm> [-o output.sbc]\n");
        }
    } else if (emit_llvm_mode) {
        if (file_path) |fp| {
            try emitLlvmFile(vm, fp, compile_output);
        } else {
            writeStdout("Usage: kaappi --emit-llvm <file.scm> [-o output.ll]\n");
        }
    } else if (file_path) |fp| {
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
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Try loading cached bytecode
    const sbc_path = getSbcPath(allocator, path) catch null;
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
                        const expr = pr.readDatum() catch break;
                        if (vm.handleTopLevelForm(expr)) |top_result| {
                            _ = top_result catch {};
                        }
                    }
                }
            }

            const top_count = @min(loaded.top_level_count, @as(u32, @intCast(loaded.funcs.len)));
            for (loaded.funcs[0..top_count]) |func| {
                var func_val = types.makePointer(@ptrCast(func));
                vm.gc.pushRoot(&func_val) catch return error.OutOfMemory;
                const result = vm.execute(func) catch |err| {
                    vm.gc.popRoot();
                    const detail = vm.getErrorDetail();
                    if (detail.len > 0) {
                        var errbuf: [256]u8 = undefined;
                        const s = std.fmt.bufPrint(&errbuf, "{s}: error: {s}\n", .{ path, detail }) catch "runtime error\n";
                        writeStderr(s);
                    } else {
                        var errbuf: [256]u8 = undefined;
                        const s = std.fmt.bufPrint(&errbuf, "{s}: runtime error: {}\n", .{ path, err }) catch "runtime error\n";
                        writeStderr(s);
                    }
                    vm.last_error_detail_len = 0;
                    continue;
                };
                vm.gc.popRoot();

                var display_result = result;
                if (types.isMultipleValues(display_result)) {
                    const mv = types.toObject(display_result).as(types.MultipleValues);
                    display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
                }
                if (display_result != types.VOID) {
                    const s = printer.valueToString(allocator, display_result, .write) catch continue;
                    defer allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                }
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
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return;
    }) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        // Check for special top-level forms (import, define-library)
        if (vm.handleTopLevelForm(expr)) |top_result| {
            has_imports = true;
            const result = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: error: {s}\n", .{ path, datum_lc.line, detail }) catch "runtime error\n";
                    writeStderr(s);
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: runtime error: {}\n", .{ path, datum_lc.line, err }) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
                continue;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (dr != types.VOID) {
                const s = printer.valueToString(allocator, dr, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, datum_lc.line, path) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: compile error: {}\n", .{ path, datum_lc.line, err }) catch "compile error\n";
            writeStderr(s);
            continue;
        };

        // Collect for caching. Keep each collected function rooted for the rest
        // of the run: the .sbc cache writer walks compiled_funcs at the end, so
        // these pointers must survive GC triggered while executing later forms.
        // (A plain ArrayList of *Function is not a GC root.)
        compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        vm.gc.extra_roots.append(allocator, types.makePointer(@ptrCast(func))) catch return error.OutOfMemory;

        // Root the function to prevent GC from collecting it before execute wraps it in a closure
        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val) catch return error.OutOfMemory;

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            const detail = vm.getErrorDetail();
            const err_line = if (vm.last_error_line > 0) vm.last_error_line else datum_lc.line;
            const err_source = vm.last_error_source orelse path;
            if (detail.len > 0) {
                var errbuf: [512]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: error: {s}\n", .{ err_source, err_line, detail }) catch "runtime error\n";
                writeStderr(s);
            } else {
                var errbuf: [512]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: runtime error: {}\n", .{ err_source, err_line, err }) catch "runtime error\n";
                writeStderr(s);
            }
            printSourceSnippet(source, err_line);
            // Print stack trace for file execution
            const trace = vm.getLastStackTrace();
            if (trace.len > 1) {
                for (trace[1..]) |frame| {
                    var tbuf: [256]u8 = undefined;
                    if (frame.name) |name| {
                        const ts = std.fmt.bufPrint(&tbuf, "  in {s} ({s}:{d})\n", .{ name, frame.source orelse "?", frame.line }) catch continue;
                        writeStderr(ts);
                    } else if (frame.line > 0) {
                        const ts = std.fmt.bufPrint(&tbuf, "  called from {s}:{d}\n", .{ frame.source orelse "?", frame.line }) catch continue;
                        writeStderr(ts);
                    }
                }
            }
            vm.last_error_detail_len = 0;
            continue;
        };
        vm.gc.popRoot();

        // Unwrap MultipleValues for display (extract first value)
        var display_result = result;
        if (types.isMultipleValues(display_result)) {
            const mv = types.toObject(display_result).as(types.MultipleValues);
            display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
        }
        if (display_result != types.VOID) {
            const s = printer.valueToString(allocator, display_result, .write) catch continue;
            defer allocator.free(s);
            writeStdout(s);
            writeStdout("\n");
        }
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
        return;
    };
    defer allocator.free(source);

    var r = reader.Reader.initWithName(vm.gc, source, "<stdin>");
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "<stdin>:{d}:{d}: read error: {}\n", .{ lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return;
    }) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<stdin>:{d}:{d}: read error: {}\n", .{ lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    writeStderr("error: ");
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
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (dr != types.VOID) {
                const s = printer.valueToString(allocator, dr, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, 0, "<stdin>") catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<stdin>:{d}: compile error: {}\n", .{ lc.line, err }) catch "compile error\n";
            writeStderr(s);
            return;
        };

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val) catch {
            writeStderr("error: out of memory while rooting function\n");
            return;
        };

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            const detail = vm.getErrorDetail();
            if (detail.len > 0) {
                writeStderr("error: ");
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

        var display_result = result;
        if (types.isMultipleValues(display_result)) {
            const mv = types.toObject(display_result).as(types.MultipleValues);
            display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
        }
        if (display_result != types.VOID) {
            const s = printer.valueToString(allocator, display_result, .write) catch continue;
            defer allocator.free(s);
            writeStdout(s);
            writeStdout("\n");
        }
    }
}

fn disassembleFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch return;
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return;
    }) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        if (vm.handleTopLevelForm(expr)) |top_result| {
            _ = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: error: {s}\n", .{ path, datum_lc.line, detail }) catch "runtime error\n";
                    writeStderr(s);
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: runtime error: {}\n", .{ path, datum_lc.line, err }) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
            };
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, datum_lc.line, path) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: compile error: {}\n", .{ path, datum_lc.line, err }) catch "compile error\n";
            writeStderr(s);
            continue;
        };

        const disasm = @import("disassembler.zig");
        disasm.disassemble(func, allocator);
    }
}

fn compileFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch {
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
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return;
    }) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        if (vm.handleTopLevelForm(expr)) |top_result| {
            _ = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: error: {s}\n", .{ path, datum_lc.line, detail }) catch "runtime error\n";
                    writeStderr(s);
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: runtime error: {}\n", .{ path, datum_lc.line, err }) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
                continue;
            };
            const form_src = printer.valueToString(allocator, expr, .write) catch continue;
            preamble.append(allocator, form_src) catch {
                allocator.free(form_src);
            };
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, datum_lc.line, path) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: compile error: {}\n", .{ path, datum_lc.line, err }) catch "compile error\n";
            writeStderr(s);
            continue;
        };

        compiled_funcs.append(allocator, func) catch {};
    }

    if (compiled_funcs.items.len > 0 or preamble.items.len > 0) {
        const sbc_path = if (output_path) |op|
            allocator.dupe(u8, op) catch {
                writeStderr("Error creating output path\n");
                return;
            }
        else
            getSbcPath(allocator, path) catch {
                writeStderr("Error creating output path\n");
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
                return;
            };
        } else {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, sbc_path) catch {
                writeStderr("Error writing bytecode file\n");
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

fn emitLlvmFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch return;
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(allocator);

    var ir_instance = ir_mod.IR.init(allocator);
    defer ir_instance.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return;
    }) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        // Handle top-level forms (import, define-library) at compile time
        // so subsequent expressions can reference imported bindings.
        // Also emit them as kaappi_eval calls for runtime execution.
        if (types.isPair(expr)) {
            const head = types.car(expr);
            if (types.isSymbol(head)) {
                const form_name = types.symbolName(head);
                if (std.mem.eql(u8, form_name, "import") or
                    std.mem.eql(u8, form_name, "define-library"))
                {
                    if (vm.handleTopLevelForm(expr)) |result| {
                        _ = result catch {};
                    }
                    const passthrough_node = ir_instance.makePassthrough(expr) catch continue;
                    ir_nodes.append(allocator, passthrough_node) catch continue;
                    continue;
                }
                if (std.mem.eql(u8, form_name, "define-syntax") or
                    std.mem.eql(u8, form_name, "define-record-type"))
                {
                    const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch continue;
                    _ = vm.execute(func) catch {};
                    const passthrough_node = ir_instance.makePassthrough(expr) catch continue;
                    ir_nodes.append(allocator, passthrough_node) catch continue;
                    continue;
                }
            }
        }

        var root = ir_mod.lowerWithMacros(&ir_instance, expr, &vm.macros) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "IR lowering error: {}\n", .{err}) catch "IR error\n";
            writeStderr(s);
            return;
        };

        ir_mod.markTailPositions(root, false);
        ir_mod.identifyPrimitives(root);
        ir_mod.markConstants(root);
        root = ir_mod.foldConstants(&ir_instance, root);
        root = ir_mod.eliminateDeadBranches(&ir_instance, root);
        root = ir_mod.simplifyBooleans(&ir_instance, root);
        root = ir_mod.eliminateIdentity(&ir_instance, root);
        root = ir_mod.simplifyBegin(&ir_instance, root);

        ir_nodes.append(allocator, root) catch return;
    }

    var emitter = llvm_emit.LLVMEmitter.init(allocator);
    defer emitter.deinit();
    emitter.emitProgram(ir_nodes.items) catch |err| {
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "LLVM emit error: {}\n", .{err}) catch "emit error\n";
        writeStderr(s);
        return;
    };

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            const base = path[0 .. path.len - 4];
            break :blk std.fmt.allocPrint(allocator, "{s}.ll", .{base}) catch return;
        }
        break :blk std.fmt.allocPrint(allocator, "{s}.ll", .{path}) catch return;
    };
    const should_free = output_path == null;
    defer if (should_free) allocator.free(out_path);

    const fd = std.posix.openat(std.posix.AT.FDCWD, out_path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch {
        writeStderr("Failed to create output file\n");
        return;
    };
    defer _ = std.posix.system.close(fd);
    const data = emitter.toSlice();
    var total: usize = 0;
    while (total < data.len) {
        const result = std.posix.system.write(fd, data.ptr + total, data.len - total);
        if (result <= 0) {
            writeStderr("Failed to write output\n");
            return;
        }
        total += @as(usize, @intCast(result));
    }

    var msgbuf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&msgbuf, "Wrote {s}\n", .{out_path}) catch return;
    writeStdout(msg);
}

fn compileNative(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;

    const pid = std.c.getpid();
    var ll_buf: [64]u8 = undefined;
    var ll_w: std.Io.Writer = .fixed(&ll_buf);
    ll_w.print("/tmp/kaappi_native_{d}.ll", .{pid}) catch return;
    const ll_path = ll_w.buffered();
    ll_buf[ll_path.len] = 0;
    emitLlvmFile(vm, path, ll_path) catch return;
    defer _ = std.posix.system.unlink(@ptrCast(ll_path.ptr));

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            break :blk path[0 .. path.len - 4];
        }
        break :blk path;
    };

    const lib_dir = findLibDir(allocator) orelse {
        writeStderr("Cannot find libkaappi_rt.a. Build it with: zig build lib\n");
        return;
    };

    const lib_flag = std.fmt.allocPrint(allocator, "-L{s}", .{lib_dir}) catch return;
    defer allocator.free(lib_flag);

    const compilers = [_][]const u8{ "zig", "cc", "clang", "gcc" };
    for (compilers) |cc| {
        const cc_path = findInPath(allocator, cc) orelse continue;
        defer allocator.free(cc_path);
        if (tryLink(allocator, cc_path, ll_path, out_path, lib_flag, std.mem.eql(u8, cc, "zig"))) {
            return;
        }
    }

    writeStderr("No C compiler found. Install zig, clang, or gcc.\n");
}

fn findInPath(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const path_env = std.c.getenv("PATH") orelse return null;
    const path_str = std.mem.span(path_env);
    var iter = std.mem.splitScalar(u8, path_str, ':');
    while (iter.next()) |dir| {
        const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name }) catch continue;
        const full_z = allocator.dupeZ(u8, full) catch {
            allocator.free(full);
            continue;
        };
        allocator.free(full);
        const fd = std.posix.openat(std.posix.AT.FDCWD, full_z, .{ .ACCMODE = .RDONLY }, 0) catch {
            allocator.free(full_z);
            continue;
        };
        _ = std.posix.system.close(fd);
        return full_z;
    }
    return null;
}

fn findLibDir(allocator: std.mem.Allocator) ?[]const u8 {
    if (std.c.getenv("KAAPPI_LIB_DIR")) |env| {
        const dir = std.mem.span(env);
        if (checkLibDir(allocator, dir)) return dir;
    }

    if (getExeRelativeLibDir(allocator)) |dir| return dir;

    const candidates = [_][]const u8{
        "zig-out/lib",
        "/usr/local/lib",
    };

    for (candidates) |dir| {
        if (checkLibDir(allocator, dir)) return dir;
    }
    return null;
}

fn getExeRelativeLibDir(allocator: std.mem.Allocator) ?[]const u8 {
    var path_buf: [1024]u8 = undefined;
    const exe_path: []const u8 = blk: {
        if (comptime @import("builtin").os.tag == .linux) {
            const n: isize = std.posix.system.readlink(
                "/proc/self/exe",
                &path_buf,
                path_buf.len,
            );
            if (n > 0) break :blk path_buf[0..@intCast(n)];
        }

        if (comptime @import("builtin").os.tag == .macos) {
            var size: u32 = path_buf.len;
            const rc = std.c._NSGetExecutablePath(&path_buf, &size);
            if (rc == 0) {
                const len = std.mem.indexOfScalar(u8, &path_buf, 0) orelse path_buf.len;
                break :blk path_buf[0..len];
            }
        }

        break :blk "";
    };
    if (exe_path.len == 0) return null;

    const last_slash = std.mem.lastIndexOfScalar(u8, exe_path, '/') orelse return null;
    if (last_slash == 0) return null;
    const bin_dir = exe_path[0..last_slash];
    const parent_slash = std.mem.lastIndexOfScalar(u8, bin_dir, '/') orelse return null;
    const parent = exe_path[0..parent_slash];

    const lib_dir = std.fmt.allocPrint(allocator, "{s}/lib", .{parent}) catch return null;
    if (checkLibDir(allocator, lib_dir)) return lib_dir;
    allocator.free(lib_dir);
    return null;
}

fn checkLibDir(allocator: std.mem.Allocator, dir: []const u8) bool {
    const path = std.fmt.allocPrint(allocator, "{s}/libkaappi_rt.a", .{dir}) catch return false;
    defer allocator.free(path);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return false;
    _ = std.posix.system.close(fd);
    return true;
}

fn tryLink(allocator: std.mem.Allocator, cc: []const u8, ll_path: []const u8, out_path: []const u8, lib_flag: []const u8, is_zig: bool) bool {
    var argv_buf: [16]?[*:0]const u8 = .{null} ** 16;
    var argc: usize = 0;

    const cc_z = allocator.dupeZ(u8, cc) catch return false;
    defer allocator.free(cc_z);
    argv_buf[argc] = cc_z;
    argc += 1;

    if (is_zig) {
        argv_buf[argc] = "cc";
        argc += 1;
    }

    argv_buf[argc] = "-w";
    argc += 1;

    const ll_z = allocator.dupeZ(u8, ll_path) catch return false;
    defer allocator.free(ll_z);
    argv_buf[argc] = ll_z;
    argc += 1;

    argv_buf[argc] = "-o";
    argc += 1;

    const out_z = allocator.dupeZ(u8, out_path) catch return false;
    defer allocator.free(out_z);
    argv_buf[argc] = out_z;
    argc += 1;

    const lib_z = allocator.dupeZ(u8, lib_flag) catch return false;
    defer allocator.free(lib_z);
    argv_buf[argc] = lib_z;
    argc += 1;

    argv_buf[argc] = "-lkaappi_rt";
    argc += 1;
    argv_buf[argc] = "-lc";
    argc += 1;
    argv_buf[argc] = "-lm";
    argc += 1;
    argv_buf[argc] = "-lpthread";
    argc += 1;
    argv_buf[argc] = null;

    const pid = std.posix.system.fork();
    if (pid < 0) return false;

    if (pid == 0) {
        _ = std.posix.system.execve(
            @ptrCast(argv_buf[0].?),
            @ptrCast(&argv_buf),
            @ptrCast(std.c.environ),
        );
        std.process.exit(127);
    }

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const exited = (raw & 0x7f) == 0;
    if (!exited) return false;
    const exit_code = (raw >> 8) & 0xff;
    if (exit_code == 0) {
        var msgbuf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msgbuf, "Compiled {s}\n", .{out_path}) catch return true;
        writeStdout(msg);
        return true;
    }
    return false;
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
    _ = repl_mod;
}
