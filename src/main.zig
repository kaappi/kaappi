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
pub const ir_mod = @import("ir.zig");
pub const llvm_emit = @import("llvm_emit.zig");

pub const version = "0.6.6";

var repl_vm: ?*vm_mod.VM = null;

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
            "\n" ++
            "Options:\n" ++
            "  -h, --help         Show this help message\n" ++
            "  --version          Show version\n" ++
            "  --lib-path <path>  Add library search path (up to 16)\n" ++
            "  --compile          Compile file to bytecode\n" ++
            "  --emit-llvm        Emit LLVM IR text (.ll)\n" ++
            "  -o <file>          Output path for --compile or --emit-llvm\n" ++
            "  --disassemble      Disassemble bytecode\n" ++
            "  --no-jit           Disable JIT compilation\n" ++
            "  --sandbox          Restrict filesystem and process access\n" ++
            "  --gc-stats         Print GC statistics on exit\n" ++
            "  --profile          Enable profiling\n" ++
            "  --coverage         Report library procedure coverage\n" ++
            "  --coverage-xml <f> Write Cobertura XML coverage to file\n" ++
            "  --timeout <ms>     Execution timeout in milliseconds\n" ++
            "  --max-memory <n>   Maximum heap memory in bytes\n" ++
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
        if (raw <= 0) break;
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
        if (raw <= 0) break;
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
            } else if (std.mem.eql(u8, arg, "--gc-stats")) {
                sa_gc_stats = true;
            } else if (std.mem.eql(u8, arg, "--profile")) {
                sa_profile = true;
            } else if (std.mem.eql(u8, arg, "--coverage")) {
                sa_coverage = true;
            } else if (std.mem.eql(u8, arg, "--coverage-xml")) {
                sa_coverage = true;
                if (sa_iter.next()) |p| vm.coverage_xml_path = p;
            } else if (std.mem.eql(u8, arg, "--no-jit")) {
                vm.jit_disabled = true;
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
                while (pr.hasMore()) {
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
    var emit_llvm_mode = false;
    var compile_output: ?[]const u8 = null;
    var disassemble_mode = false;
    var gc_stats_mode = false;
    var profile_mode = false;
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
        } else if (std.mem.eql(u8, arg, "--coverage")) {
            coverage_mode = true;
        } else if (std.mem.eql(u8, arg, "--coverage-xml")) {
            coverage_mode = true;
            if (args.next()) |p| vm.coverage_xml_path = p;
        } else if (std.mem.eql(u8, arg, "--sandbox")) {
            sandbox_mode = true;
        } else if (std.mem.eql(u8, arg, "--compile")) {
            compile_mode = true;
        } else if (std.mem.eql(u8, arg, "--emit-llvm")) {
            emit_llvm_mode = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            compile_output = args.next();
        } else if (std.mem.eql(u8, arg, "--disassemble")) {
            disassemble_mode = true;
        } else if (std.mem.eql(u8, arg, "--no-jit")) {
            vm.jit_disabled = true;
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
        } else {
            file_path = arg;
            break;
        }
    }

    // Collect remaining args after the file path for (command-line).
    var script_args: [64][]const u8 = undefined;
    var script_arg_count: usize = 0;
    if (file_path) |fp| {
        script_args[0] = fp;
        script_arg_count = 1;
        while (args.next()) |extra| {
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
    defer if (profile_mode) reporting.printProfileReport(&gc);
    if (coverage_mode) {
        vm.profile_mode = true;
        vm.coverage_mode = true;
    }
    defer if (coverage_mode) {
        reporting.printCoverageReport(vm);
        if (vm.coverage_xml_path) |p| reporting.writeCoverageXml(vm, p);
    };

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
            try repl(vm);
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

    while (r.hasMore()) {
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

    while (r.hasMore()) {
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

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore()) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        if (vm.handleTopLevelForm(expr)) |_| continue;

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

    while (r.hasMore()) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        if (vm.handleTopLevelForm(expr)) |_| {
            // Capture the top-level form as source text for preamble
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

fn completionCallback(buf: [*c]const u8, lc: [*c]ln.c.linenoiseCompletions) callconv(.c) void {
    const vm = repl_vm orelse return;
    const b: ?[*:0]const u8 = @ptrCast(buf);
    const prefix = if (b) |bp| std.mem.span(bp) else return;
    if (prefix.len == 0) return;

    if (prefix[0] == ',') {
        const commands = [_][*:0]const u8{
            ",time ",  ",type ",       ",describe ", ",apropos ",
            ",env ",   ",profile ",    ",expand ",   ",gc",
            ",break ", ",breakpoints", ",delete ",   ",step ",
            ",help",   ",quit",        ",exit",      ",version",
            ",load ",  ",import ",     ",dis ",
        };
        for (&commands) |cmd| {
            if (std.mem.startsWith(u8, std.mem.span(cmd), prefix)) {
                ln.addCompletion(lc, cmd);
            }
        }
        return;
    }

    var it = vm.globals.keyIterator();
    while (it.next()) |key| {
        if (std.mem.startsWith(u8, key.*, prefix)) {
            ln.addCompletion(lc, @ptrCast(key.*.ptr));
        }
    }
}

fn parenDepth(src: []const u8) i32 {
    var depth: i32 = 0;
    var in_string = false;
    var in_escape = false;
    var in_line_comment = false;
    var block_comment_depth: i32 = 0;
    var i: usize = 0;
    while (i < src.len) : (i += 1) {
        const ch = src[i];
        if (in_line_comment) {
            if (ch == '\n') in_line_comment = false;
            continue;
        }
        if (block_comment_depth > 0) {
            if (ch == '#' and i + 1 < src.len and src[i + 1] == '|') {
                block_comment_depth += 1;
                i += 1;
            } else if (ch == '|' and i + 1 < src.len and src[i + 1] == '#') {
                block_comment_depth -= 1;
                i += 1;
            }
            continue;
        }
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (in_string) {
            if (ch == '\\') in_escape = true else if (ch == '"') in_string = false;
            continue;
        }
        if (ch == '#' and i + 1 < src.len and src[i + 1] == '|') {
            block_comment_depth += 1;
            i += 1;
            continue;
        }
        switch (ch) {
            '"' => in_string = true,
            ';' => in_line_comment = true,
            '(' => depth += 1,
            ')' => depth -= 1,
            else => {},
        }
    }
    if (in_string) depth += 1;
    if (block_comment_depth > 0) depth += 1;
    return depth;
}

fn repl(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;

    writeStdout("Kaappi Scheme v" ++ version ++ "\n");
    writeStdout("Type ,help for commands, ,quit to exit.\n\n");

    repl_vm = vm;
    ln.setMultiLine(true);
    ln.historySetMaxLen(1000);

    var hist_path_buf: [512]u8 = undefined;
    const hist_path: ?[*:0]const u8 = blk: {
        const home_ptr: ?[*:0]const u8 = std.c.getenv("HOME");
        const home = if (home_ptr) |p| std.mem.span(p) else break :blk null;
        const dir = std.fmt.bufPrintZ(hist_path_buf[0..500], "{s}/.kaappi", .{home}) catch break :blk null;
        _ = std.c.mkdir(dir.ptr, 0o755);
        const path = std.fmt.bufPrintZ(&hist_path_buf, "{s}/.kaappi/history", .{home}) catch break :blk null;
        break :blk path;
    };
    if (hist_path) |p| ln.historyLoad(p);

    ln.setCompletionCallback(&completionCallback);

    var input_buf: std.ArrayList(u8) = .empty;
    defer input_buf.deinit(allocator);

    while (true) {
        const prompt: [*:0]const u8 = if (input_buf.items.len > 0) "  ... " else "kaappi> ";
        const line_ptr = ln.linenoise(prompt) orelse {
            if (input_buf.items.len > 0) {
                input_buf.clearRetainingCapacity();
                writeStdout("\n");
                continue;
            }
            break;
        };
        defer ln.free(@ptrCast(line_ptr));

        const line = std.mem.span(line_ptr);
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (input_buf.items.len == 0 and trimmed.len == 0) continue;
        if (input_buf.items.len == 0 and std.mem.eql(u8, trimmed, "(exit)")) break;

        // If pasted text contains newlines, echo it clearly
        const has_newlines = std.mem.indexOf(u8, line, "\n") != null;
        if (has_newlines and input_buf.items.len == 0) {
            writeStdout(line);
            writeStdout("\n");
        }

        if (input_buf.items.len > 0) {
            input_buf.append(allocator, '\n') catch continue;
        }
        input_buf.appendSlice(allocator, line) catch continue;

        if (parenDepth(input_buf.items) > 0) continue;

        const full_input = input_buf.items;
        const debug_trimmed = std.mem.trim(u8, full_input, " \t\r\n");

        // Debug commands (comma-prefixed)
        if (std.mem.startsWith(u8, debug_trimmed, ",break ")) {
            const bp_name = std.mem.trim(u8, debug_trimmed[7..], " ");
            if (vm.breakpoint_count < 16) {
                vm.breakpoints[vm.breakpoint_count] = bp_name;
                vm.breakpoint_count += 1;
                vm.debug_mode = true;
                vm.step_mode = .continue_to_break;
            }
            writeStdout("Breakpoint set on ");
            writeStdout(bp_name);
            writeStdout("\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",breakpoints")) {
            for (vm.breakpoints[0..vm.breakpoint_count], 0..) |bp, idx| {
                var dbuf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&dbuf, "  [{d}] ", .{idx}) catch "";
                writeStdout(s);
                writeStdout(bp);
                writeStdout("\n");
            }
            if (vm.breakpoint_count == 0) {
                writeStdout("  (no breakpoints)\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",delete all")) {
            vm.breakpoint_count = 0;
            vm.debug_mode = false;
            vm.step_mode = .none;
            writeStdout("All breakpoints deleted\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",step ")) {
            const step_expr = debug_trimmed[6..];
            vm.debug_mode = true;
            vm.step_mode = .step;
            evalInput(vm, allocator, step_expr);
            vm.debug_mode = false;
            vm.step_mode = .none;
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",time ")) {
            const time_expr = debug_trimmed[6..];
            var ts: std.c.timespec = undefined;
            _ = std.c.clock_gettime(.MONOTONIC, &ts);
            evalInput(vm, allocator, time_expr);
            var te: std.c.timespec = undefined;
            _ = std.c.clock_gettime(.MONOTONIC, &te);
            const secs = @as(f64, @floatFromInt(te.sec - ts.sec)) +
                @as(f64, @floatFromInt(te.nsec - ts.nsec)) / 1_000_000_000.0;
            var tbuf: [64]u8 = undefined;
            const ts_str = std.fmt.bufPrint(&tbuf, "; {d:.3} seconds\n", .{secs}) catch "; ? seconds\n";
            writeStdout(ts_str);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",profile ")) {
            const profile_expr = debug_trimmed[9..];
            reporting.resetProfileCounters(vm.gc);
            vm.profile_mode = true;
            evalInput(vm, allocator, profile_expr);
            vm.profile_mode = false;
            reporting.printProfileReport(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",gc")) {
            reporting.printGcStats(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",quit") or std.mem.eql(u8, debug_trimmed, ",exit")) {
            break;
        }
        if (std.mem.eql(u8, debug_trimmed, ",version")) {
            writeStdout("Kaappi Scheme v" ++ version ++ "\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",load ")) {
            const load_path = std.mem.trim(u8, debug_trimmed[6..], " ");
            if (load_path.len == 0) {
                writeStderr(",load requires a file path\n");
            } else {
                var load_buf: [1024]u8 = undefined;
                const load_expr = std.fmt.bufPrint(&load_buf, "(load \"{s}\")", .{load_path}) catch {
                    writeStderr("path too long\n");
                    input_buf.clearRetainingCapacity();
                    continue;
                };
                evalInput(vm, allocator, load_expr);
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",import ")) {
            const import_expr = debug_trimmed[8..];
            const reader_mod = @import("reader.zig");
            var ir = reader_mod.Reader.init(vm.gc, import_expr);
            defer ir.deinit();
            var import_list = types.NIL;
            var import_root = import_list;
            vm.gc.pushRoot(&import_root) catch {
                writeStderr("out of memory\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            var read_ok = true;
            while (ir.hasMore()) {
                const datum = ir.readDatum() catch {
                    writeStderr("read error in import spec\n");
                    read_ok = false;
                    break;
                };
                var pair = vm.gc.allocPair(datum, types.NIL) catch {
                    writeStderr("out of memory\n");
                    read_ok = false;
                    break;
                };
                if (import_root == types.NIL) {
                    import_root = pair;
                    import_list = pair;
                } else {
                    types.toObject(import_list).as(types.Pair).cdr = pair;
                    import_list = pair;
                }
                _ = &pair;
            }
            if (read_ok and import_root != types.NIL) {
                _ = vm_library.handleImport(vm, import_root) catch {
                    const detail = vm.getErrorDetail();
                    if (detail.len > 0) {
                        writeStderr("import error: ");
                        writeStderr(detail);
                        writeStderr("\n");
                    } else {
                        writeStderr("import error\n");
                    }
                };
            }
            vm.gc.popRoot();
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",dis ")) {
            const dis_expr = debug_trimmed[5..];
            var dis_buf: [1024]u8 = undefined;
            const dis_call = std.fmt.bufPrint(&dis_buf, "(disassemble {s})", .{dis_expr}) catch {
                writeStderr("expression too long\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            evalInput(vm, allocator, dis_call);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",help")) {
            writeStdout(
                \\Commands:
                \\  ,help             Show this message
                \\  ,quit             Exit the REPL
                \\
                \\ -- Evaluation:
                \\  ,time <expr>      Measure execution time
                \\  ,type <expr>      Show result type
                \\  ,expand <expr>    Show macro expansion
                \\  ,profile <expr>   Profile timing, calls, and allocations
                \\  ,dis <expr>       Disassemble a procedure
                \\
                \\ -- Inspection:
                \\  ,describe <sym>   Show procedure arity and type
                \\  ,apropos <str>    Search bindings by substring
                \\  ,env [prefix]     List bindings (optionally filtered by prefix)
                \\
                \\ -- Debugging:
                \\  ,break <name>     Set breakpoint on function
                \\  ,breakpoints      List active breakpoints
                \\  ,delete all       Clear all breakpoints
                \\  ,step <expr>      Evaluate with single-stepping
                \\
                \\ -- System:
                \\  ,gc               Show GC statistics
                \\  ,version          Show Kaappi version
                \\  ,load <file>      Load and run a Scheme file
                \\  ,import <lib>     Import a library (e.g. ,import (srfi 1))
                \\
                \\The variable _ holds the last result.
                \\
            );
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",type ")) {
            const type_expr = debug_trimmed[6..];
            evalInputTyped(vm, allocator, type_expr, .show_type);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",describe ")) {
            const sym_name = std.mem.trim(u8, debug_trimmed[10..], " ");
            describeSymbol(vm, allocator, sym_name);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",apropos ")) {
            const needle = std.mem.trim(u8, debug_trimmed[9..], " ");
            var env_count: usize = 0;
            var git3 = vm.globals.keyIterator();
            while (git3.next()) |key| {
                if (needle.len == 0 or containsSubstring(key.*, needle)) {
                    writeStdout("  ");
                    writeStdout(key.*);
                    writeStdout("\n");
                    env_count += 1;
                }
            }
            var cbuf2: [64]u8 = undefined;
            const cs2 = std.fmt.bufPrint(&cbuf2, "; {d} matches\n", .{env_count}) catch "\n";
            writeStdout(cs2);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",expand ")) {
            const expand_src = debug_trimmed[8..];
            const reader_mod = @import("reader.zig");
            var er = reader_mod.Reader.init(vm.gc, expand_src);
            defer er.deinit();
            const expr = er.readDatum() catch {
                writeStderr("read error\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
                const ename = types.symbolName(types.car(expr));
                if (vm.macros.get(ename)) |transformer| {
                    const exp_mod = @import("expander.zig");
                    const expanded = exp_mod.expandMacro(vm.gc, expr, transformer, &vm.globals, &vm.macros) catch {
                        writeStderr("expansion error\n");
                        input_buf.clearRetainingCapacity();
                        continue;
                    };
                    const s = printer.valueToString(allocator, expanded, .write) catch "";
                    defer if (s.len > 0) allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                } else {
                    writeStderr("not a macro: ");
                    writeStderr(ename);
                    writeStderr("\n");
                }
            } else {
                writeStderr("not a macro invocation\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",env") or std.mem.startsWith(u8, debug_trimmed, ",env ")) {
            const prefix = if (debug_trimmed.len > 5) std.mem.trim(u8, debug_trimmed[5..], " ") else "";
            var env_count: usize = 0;
            var git2 = vm.globals.keyIterator();
            while (git2.next()) |key| {
                if (prefix.len == 0 or std.mem.startsWith(u8, key.*, prefix)) {
                    writeStdout("  ");
                    writeStdout(key.*);
                    writeStdout("\n");
                    env_count += 1;
                }
            }
            var cbuf: [64]u8 = undefined;
            const cs = std.fmt.bufPrint(&cbuf, "; {d} bindings\n", .{env_count}) catch "\n";
            writeStdout(cs);
            input_buf.clearRetainingCapacity();
            continue;
        }

        // Catch-all for unrecognized or incomplete comma commands
        if (debug_trimmed.len > 0 and debug_trimmed[0] == ',') {
            const usage = getCommandUsage(debug_trimmed);
            if (usage) |msg| {
                writeStderr(msg);
            } else {
                writeStderr("unknown command: ");
                const end = std.mem.indexOfScalar(u8, debug_trimmed, ' ') orelse debug_trimmed.len;
                writeStderr(debug_trimmed[0..end]);
                writeStderr("\nType ,help for available commands.\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }

        // Add to history with newlines replaced by spaces for clean display
        var hist_buf: std.ArrayList(u8) = .empty;
        defer hist_buf.deinit(allocator);
        hist_buf.appendSlice(allocator, full_input) catch {};
        for (hist_buf.items) |*ch| {
            if (ch.* == '\n') ch.* = ' ';
        }
        hist_buf.append(allocator, 0) catch {};
        ln.historyAdd(@ptrCast(hist_buf.items.ptr));

        evalInputTyped(vm, allocator, full_input, .store_last);

        input_buf.clearRetainingCapacity();
    }

    if (hist_path) |p| ln.historySave(p);
    repl_vm = null;
}

fn getCommandUsage(input: []const u8) ?[]const u8 {
    const cmd = blk: {
        const end = std.mem.indexOfScalar(u8, input, ' ') orelse input.len;
        break :blk input[0..end];
    };
    const commands = [_]struct { name: []const u8, usage: []const u8 }{
        .{ .name = ",time", .usage = "usage: ,time <expr>\n" },
        .{ .name = ",type", .usage = "usage: ,type <expr>\n" },
        .{ .name = ",describe", .usage = "usage: ,describe <symbol>\n" },
        .{ .name = ",apropos", .usage = "usage: ,apropos <string>\n" },
        .{ .name = ",expand", .usage = "usage: ,expand <expr>\n" },
        .{ .name = ",profile", .usage = "usage: ,profile <expr>\n" },
        .{ .name = ",step", .usage = "usage: ,step <expr>\n" },
        .{ .name = ",break", .usage = "usage: ,break <name>\n" },
        .{ .name = ",load", .usage = "usage: ,load <file>\n" },
        .{ .name = ",import", .usage = "usage: ,import <lib>  (e.g. ,import (srfi 1))\n" },
        .{ .name = ",dis", .usage = "usage: ,dis <expr>\n" },
        .{ .name = ",delete", .usage = "usage: ,delete all\n" },
    };
    for (&commands) |entry| {
        if (std.mem.eql(u8, cmd, entry.name)) return entry.usage;
    }
    return null;
}

fn containsSubstring(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

fn getTypeName(val: types.Value) []const u8 {
    if (types.isFixnum(val)) return "integer";
    if (val == types.NIL) return "nil";
    if (val == types.TRUE or val == types.FALSE) return "boolean";
    if (val == types.VOID) return "void";
    if (val == types.EOF) return "eof-object";
    if (types.isChar(val)) return "char";
    if (!types.isPointer(val)) return "unknown";
    const obj = types.toObject(val);
    return switch (obj.tag) {
        .pair => "pair",
        .symbol => "symbol",
        .string => "string",
        .closure => "procedure",
        .native_fn => "procedure",
        .function => "function",
        .vector => "vector",
        .bytevector => "bytevector",
        .port => "port",
        .flonum => "number",
        .complex => "complex",
        .transformer => "syntax",
        .error_object => "error",
        .record_type => "record-type",
        .record_instance => "record",
        .continuation => "continuation",
        .multiple_values => "values",
        .promise => "promise",
        .parameter => "parameter",
        .rational => "rational",
        .bignum => "integer",
        .hash_table => "hash-table",
        else => "object",
    };
}

fn describeSymbol(vm: *vm_mod.VM, allocator: std.mem.Allocator, name: []const u8) void {
    const val_opt = vm.globals.get(name);
    if (val_opt == null) {
        writeStdout("  not found: ");
        writeStdout(name);
        writeStdout("\n");
        return;
    }
    const val = val_opt.?;
    writeStdout("  ");
    writeStdout(name);
    writeStdout("\n    type: ");
    writeStdout(getTypeName(val));
    writeStdout("\n");

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        if (obj.tag == .native_fn) {
            const nfn = obj.as(types.NativeFn);
            var abuf: [64]u8 = undefined;
            switch (nfn.arity) {
                .exact => |n| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}\n", .{n}) catch "";
                    writeStdout(s);
                },
                .variadic => |min| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}+\n", .{min}) catch "";
                    writeStdout(s);
                },
            }
        } else if (obj.tag == .closure) {
            const cls = obj.as(types.Closure);
            const func = cls.func;
            var abuf: [128]u8 = undefined;
            const s = std.fmt.bufPrint(&abuf, "    arity: {d}, locals: {d}\n", .{ func.arity, func.locals_count }) catch "";
            writeStdout(s);
            if (func.source_name) |src| {
                writeStdout("    source: ");
                writeStdout(src);
                var lbuf: [32]u8 = undefined;
                const ls = std.fmt.bufPrint(&lbuf, ":{d}\n", .{func.source_line}) catch "\n";
                writeStdout(ls);
            }
        } else if (obj.tag == .transformer) {
            writeStdout("    (syntax transformer)\n");
        }
    }
    _ = allocator;
}

const EvalMode = enum { normal, store_last, show_type };

fn evalInputTyped(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    evalInputInner(vm, allocator, input, mode);
}

fn evalInput(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) void {
    evalInputInner(vm, allocator, input, .normal);
}

fn evalInputInner(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    var r = reader.Reader.initWithName(vm.gc, input, "<repl>");
    defer r.deinit();

    while (r.hasMore()) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<repl>:{d}:{d}: read error: {}\n", .{ lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            break;
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
                break;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (dr != types.VOID) {
                if (mode == .show_type) {
                    writeStdout("; ");
                    writeStdout(getTypeName(dr));
                    writeStdout("\n");
                } else {
                    const s = printer.valueToString(allocator, dr, .write) catch continue;
                    defer allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                }
                if (mode == .store_last) {
                    vm.globals.put("_", dr) catch {};
                }
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, 0, "<repl>") catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<repl>:{d}: compile error: {}\n", .{ lc.line, err }) catch "compile error\n";
            writeStderr(s);
            break;
        };

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val) catch {
            writeStderr("error: out of memory while rooting function\n");
            break;
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
            const trace = vm.getLastStackTrace();
            if (trace.len > 1) {
                for (trace[1..]) |sf| {
                    var tbuf: [256]u8 = undefined;
                    if (sf.name) |name| {
                        const ts = std.fmt.bufPrint(&tbuf, "  in {s} ({s}:{d})\n", .{ name, sf.source orelse "?", sf.line }) catch continue;
                        writeStderr(ts);
                    } else if (sf.line > 0) {
                        const ts = std.fmt.bufPrint(&tbuf, "  called from {s}:{d}\n", .{ sf.source orelse "?", sf.line }) catch continue;
                        writeStderr(ts);
                    }
                }
            }
            vm.last_error_detail_len = 0;
            break;
        };
        vm.gc.popRoot();

        if (result != types.VOID) {
            if (mode == .show_type) {
                writeStdout("; ");
                writeStdout(getTypeName(result));
                writeStdout("\n");
            } else {
                const s = printer.prettyPrint(allocator, result, 80) catch
                    (printer.valueToString(allocator, result, .write) catch continue);
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            if (mode == .store_last) {
                vm.globals.put("_", result) catch {};
            }
        }
    }
}

fn emitLlvmFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch return;
    defer allocator.free(source);

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(allocator);

    var ir_instance = ir_mod.IR.init(allocator);
    defer ir_instance.deinit();

    while (r.hasMore()) {
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
}
