const std = @import("std");
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
pub const ln = @import("linenoise.zig");
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

pub const version = "0.1.0";

var repl_vm: ?*vm_mod.VM = null;

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        const written: usize = @intCast(result);
        if (written == 0) break;
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
            "  -o <file>          Output path for --compile\n" ++
            "  --disassemble      Disassemble bytecode\n" ++
            "  --no-jit           Disable JIT compilation\n" ++
            "  --sandbox          Restrict filesystem and process access\n" ++
            "  --experimental-threads  Enable OS threads (SRFI-18 thread-start!)\n" ++
            "  --gc-stats         Print GC statistics on exit\n" ++
            "  --profile          Enable profiling\n" ++
            "\n" ++
            "With no file argument, starts an interactive REPL.\n",
    );
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

fn printGcStats(gc: *@import("memory.zig").GC) void {
    const s = &gc.stats;
    const mark_ms = @as(f64, @floatFromInt(s.total_mark_ns)) / 1_000_000.0;
    const sweep_ms = @as(f64, @floatFromInt(s.total_sweep_ns)) / 1_000_000.0;
    var buf: [2048]u8 = undefined;

    const header = std.fmt.bufPrint(&buf,
        \\GC Statistics:
        \\  Collections:       {d}
        \\  Live objects:      {d} (peak: {d})
        \\  Heap size:         {d} bytes (peak: {d})
        \\  Freed:             {d} objects, {d} bytes
        \\  Mark time:         {d:.2} ms total
        \\  Sweep time:        {d:.2} ms total
        \\
    , .{
        s.collections,
        gc.object_count,
        s.peak_object_count,
        gc.bytes_allocated,
        s.peak_bytes_allocated,
        s.objects_freed,
        s.bytes_freed,
        mark_ms,
        sweep_ms,
    }) catch "";
    writeStderr(header);

    if (s.no_collect_deferred > 0) {
        const defer_line = std.fmt.bufPrint(&buf, "  No-collect defers: {d}\n", .{s.no_collect_deferred}) catch "";
        writeStderr(defer_line);
    }

    const type_names = [_][]const u8{
        "pair",      "symbol",    "string",    "closure",
        "native_fn", "vector",    "bytevec",   "port",
        "rec_type",  "function",  "flonum",    "xformer",
        "error",     "rec_inst",  "contin",    "multi_val",
        "complex",   "promise",   "parameter", "ffi_lib",
        "ffi_fn",    "hashtable", "bignum",    "rational",
        "file_info", "user_info", "grp_info",  "dir_obj",
        "rng",       "ffi_cb",    "fiber",     "channel",
        "mutex",     "condvar",   "time18",
    };

    writeStderr("  Allocations by type:\n");
    var col: usize = 0;
    for (type_names, 0..) |name, i| {
        const count = s.allocs_by_type[i];
        if (count == 0) continue;
        if (col == 0) writeStderr("    ");
        const entry = std.fmt.bufPrint(&buf, "{s: <10} {d: >8}  ", .{ name, count }) catch "";
        writeStderr(entry);
        col += 1;
        if (col >= 3) {
            writeStderr("\n");
            col = 0;
        }
    }
    if (col > 0) writeStderr("\n");
}

fn resetProfileCounters(gc: *memory.GC) void {
    var obj = gc.objects;
    while (obj) |o| {
        if (o.tag == .function) {
            const func = o.as(types.Function);
            func.profile_instrs = 0;
            func.profile_calls = 0;
            func.profile_time_ns = 0;
            func.profile_inclusive_ns = 0;
            func.profile_alloc_bytes = 0;
        } else if (o.tag == .native_fn) {
            const native = o.as(types.NativeFn);
            native.profile_calls = 0;
            native.profile_time_ns = 0;
            native.profile_alloc_bytes = 0;
        }
        obj = o.next;
    }
}

fn fmtMs(buf: []u8, ns: u64) []const u8 {
    if (ns == 0) return "       -";
    const ms_whole = ns / 1_000_000;
    const ms_frac = (ns % 1_000_000) / 100_000;
    return std.fmt.bufPrint(buf, "{d:>6}.{d}", .{ ms_whole, ms_frac }) catch "       ?";
}

fn fmtKb(buf: []u8, bytes: u64) []const u8 {
    if (bytes == 0) return "      -";
    const kb = bytes / 1024;
    if (kb > 0) {
        return std.fmt.bufPrint(buf, "{d:>6}", .{kb}) catch "      ?";
    }
    return std.fmt.bufPrint(buf, "   <1", .{}) catch "      ?";
}

fn printProfileReport(gc: *memory.GC) void {
    const Entry = struct {
        name: []const u8,
        source: ?[]const u8,
        line: u32,
        instrs: u64,
        calls: u64,
        self_ns: u64,
        total_ns: u64,
        alloc_bytes: u64,
    };

    var entries: [256]Entry = undefined;
    var count: usize = 0;
    var total_instrs: u64 = 0;
    var total_calls: u64 = 0;

    var obj = gc.objects;
    while (obj) |o| {
        if (o.tag == .function) {
            const func = o.as(types.Function);
            if (func.profile_instrs > 0 or func.profile_calls > 0) {
                total_instrs += func.profile_instrs;
                total_calls += func.profile_calls;
                if (count < 256) {
                    entries[count] = .{
                        .name = func.name orelse "(lambda)",
                        .source = func.source_name,
                        .line = func.source_line,
                        .instrs = func.profile_instrs,
                        .calls = func.profile_calls,
                        .self_ns = func.profile_time_ns,
                        .total_ns = func.profile_inclusive_ns,
                        .alloc_bytes = func.profile_alloc_bytes,
                    };
                    count += 1;
                }
            }
        } else if (o.tag == .native_fn) {
            const native = o.as(types.NativeFn);
            if (native.profile_calls > 0) {
                total_calls += native.profile_calls;
                if (count < 256) {
                    entries[count] = .{
                        .name = native.name,
                        .source = null,
                        .line = 0,
                        .instrs = 0,
                        .calls = native.profile_calls,
                        .self_ns = native.profile_time_ns,
                        .total_ns = native.profile_time_ns,
                        .alloc_bytes = native.profile_alloc_bytes,
                    };
                    count += 1;
                }
            }
        }
        obj = o.next;
    }

    if (count == 0) return;

    std.mem.sortUnstable(Entry, entries[0..count], {}, struct {
        fn lessThan(_: void, a: Entry, b: Entry) bool {
            if (a.self_ns != b.self_ns) return a.self_ns > b.self_ns;
            if (a.instrs != b.instrs) return a.instrs > b.instrs;
            return a.calls > b.calls;
        }
    }.lessThan);

    var buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "\nProfile ({d} instructions, {d} calls):\n", .{ total_instrs, total_calls }) catch return;
    writeStderr(header);
    writeStderr("  Self ms  Total ms    Calls  Alloc KB  Function\n");

    const limit = @min(count, 20);
    for (entries[0..limit]) |e| {
        var line: [512]u8 = undefined;
        var loc_buf: [128]u8 = undefined;
        const location: []const u8 = if (e.source) |src|
            std.fmt.bufPrint(&loc_buf, " ({s}:{d})", .{ src, e.line }) catch ""
        else
            " (built-in)";

        var self_buf: [16]u8 = undefined;
        var total_buf: [16]u8 = undefined;
        var alloc_buf: [16]u8 = undefined;
        const self_ms = fmtMs(&self_buf, e.self_ns);
        const total_ms = fmtMs(&total_buf, e.total_ns);
        const alloc_kb = fmtKb(&alloc_buf, e.alloc_bytes);

        const s = std.fmt.bufPrint(&line, "  {s}  {s} {d:>8}  {s}    {s}{s}\n", .{
            self_ms, total_ms, e.calls, alloc_kb, e.name, location,
        }) catch continue;
        writeStderr(s);
    }
}

fn readLine(buf: []u8) ?[]const u8 {
    const fd: std.posix.fd_t = 0;
    var i: usize = 0;
    while (i < buf.len) {
        const result = std.posix.system.read(fd, buf.ptr + i, 1);
        const n: usize = @intCast(result);
        if (n == 0) {
            if (i == 0) return null;
            return buf[0..i];
        }
        if (buf[i] == '\n') return buf[0..i];
        i += 1;
    }
    return buf[0..i];
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ path, err });
        return err;
    };
    defer _ = std.posix.system.close(fd);

    // Read file contents into a buffer
    const max_size: usize = 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const bytes_read = std.posix.read(fd, &tmp) catch |err| {
            std.debug.print("Error reading file: {}\n", .{err});
            return err;
        };
        if (bytes_read == 0) break;
        if (result.items.len + bytes_read > max_size) {
            std.debug.print("File too large\n", .{});
            return error.StreamTooLong;
        }
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }

    return result.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init.Minimal) !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gc = memory.GC.init(allocator);
    defer gc.deinit();

    var vm = try vm_mod.VM.init(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);

    // Pre-scan args for flags that must be set before primitive registration
    var is_sandboxed = false;
    var experimental_threads = false;
    {
        var pre_args = init.args.iterate();
        while (pre_args.next()) |arg| {
            if (std.mem.eql(u8, arg, "--sandbox")) is_sandboxed = true;
            if (std.mem.eql(u8, arg, "--experimental-threads")) experimental_threads = true;
        }
    }

    vm.experimental_threads = experimental_threads;

    if (is_sandboxed) {
        try primitives.registerSandboxed(&vm);
        primitives.setGCInstance(&gc);
        try library.registerSandboxedLibraries(&vm.libraries, &vm.globals);
        vm.sandbox_mode = true;
    } else {
        try primitives.registerAll(&vm);
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

        defer if (sa_gc_stats) printGcStats(&gc);
        if (sa_profile) vm.profile_mode = true;
        defer if (sa_profile) printProfileReport(&gc);

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
    var compile_output: ?[]const u8 = null;
    var disassemble_mode = false;
    var gc_stats_mode = false;
    var profile_mode = false;
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
        } else if (std.mem.eql(u8, arg, "--sandbox")) {
            sandbox_mode = true;
        } else if (std.mem.eql(u8, arg, "--experimental-threads")) {
            // handled in pre-scan
        } else if (std.mem.eql(u8, arg, "--compile")) {
            compile_mode = true;
        } else if (std.mem.eql(u8, arg, "-o")) {
            compile_output = args.next();
        } else if (std.mem.eql(u8, arg, "--disassemble")) {
            disassemble_mode = true;
        } else if (std.mem.eql(u8, arg, "--no-jit")) {
            vm.jit_disabled = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            // future: disable caching
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

    vm.lib_paths = lib_paths[0..lib_path_count];

    defer if (gc_stats_mode) printGcStats(&gc);
    if (profile_mode) vm.profile_mode = true;
    defer if (profile_mode) printProfileReport(&gc);

    if (disassemble_mode) {
        if (file_path) |fp| {
            try disassembleFile(&vm, fp);
        } else {
            writeStdout("Usage: kaappi --disassemble <file.scm>\n");
        }
    } else if (compile_mode) {
        if (file_path) |fp| {
            try compileFile(&vm, fp, compile_output);
        } else {
            writeStdout("Usage: kaappi --compile <file.scm> [-o output.sbc]\n");
        }
    } else if (file_path) |fp| {
        try runFile(&vm, fp);
    } else {
        try repl(&vm);
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
    writeStdout("Type (exit) to quit.\n\n");

    repl_vm = vm;
    ln.setMultiLine(true);
    ln.historySetMaxLen(1000);
    ln.historyLoad(".kaappi_history");
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
            resetProfileCounters(vm.gc);
            vm.profile_mode = true;
            evalInput(vm, allocator, profile_expr);
            vm.profile_mode = false;
            printProfileReport(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",gc")) {
            printGcStats(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",help")) {
            writeStdout(
                \\Commands:
                \\  ,time <expr>      Measure execution time
                \\  ,profile <expr>   Profile timing, calls, and allocations
                \\  ,expand <expr>    Show macro expansion
                \\  ,env [prefix]     List global bindings
                \\  ,gc               Show GC statistics
                \\  ,break <name>     Set breakpoint on function
                \\  ,breakpoints      List active breakpoints
                \\  ,delete all       Clear all breakpoints
                \\  ,step <expr>      Evaluate with single-stepping
                \\  ,help             This message
                \\
            );
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

        // Add to history with newlines replaced by spaces for clean display
        var hist_buf: std.ArrayList(u8) = .empty;
        defer hist_buf.deinit(allocator);
        hist_buf.appendSlice(allocator, full_input) catch {};
        for (hist_buf.items) |*ch| {
            if (ch.* == '\n') ch.* = ' ';
        }
        hist_buf.append(allocator, 0) catch {};
        ln.historyAdd(@ptrCast(hist_buf.items.ptr));

        evalInput(vm, allocator, full_input);

        input_buf.clearRetainingCapacity();
    }

    ln.historySave(".kaappi_history");
    repl_vm = null;
}

fn evalInput(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) void {
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
                const s = printer.valueToString(allocator, dr, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
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
            const s = printer.prettyPrint(allocator, result, 80) catch
                (printer.valueToString(allocator, result, .write) catch continue);
            defer allocator.free(s);
            writeStdout(s);
            writeStdout("\n");
        }
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
}
