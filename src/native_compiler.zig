const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const compiler = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const ir_mod = @import("ir.zig");
const llvm_emit = @import("llvm_emit.zig");
const file_utils = @import("file_utils.zig");
const reporting = @import("reporting.zig");
const kaappi_paths = @import("kaappi_paths.zig");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

pub fn emitLlvmFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;
    const source = file_utils.readWholeFile(allocator, path, 1024 * 1024) catch |err| {
        var errbuf: [1088]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "Error opening file '{s}'\n", .{path}) catch "Error opening file\n";
        writeStderr(s);
        return err;
    };
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    var r = reader_mod.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(allocator);

    var ir_instance = ir_mod.IR.init(allocator);
    defer ir_instance.deinit();

    // Track names that are targets of define or set! in previous top-level
    // forms so constant folding does not inline primitive semantics for a
    // name that will be rebound at runtime (#822).
    var redefined_names = std.StringHashMap(void).init(allocator);
    defer redefined_names.deinit();
    ir_instance.set_targets = &redefined_names;

    // The IR nodes built below (passthrough forms, define/quote literals)
    // reference sexpr Values — including macro-expanded forms — that nothing
    // roots. A collection triggered by a later readDatum/lower/execute would
    // free them and the emitter would then walk dangling Values (#1401).
    // Defer collection for the whole read → lower → emit batch.
    vm.gc.no_collect += 1;
    defer vm.gc.no_collect -= 1;

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return err;
    }) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return err;
        };

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
                    const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch continue;
                    _ = vm.execute(func) catch {};
                    const passthrough_node = ir_instance.makePassthrough(expr) catch continue;
                    ir_nodes.append(allocator, passthrough_node) catch continue;
                    continue;
                }
            }
        }

        const root = ir_mod.lowerAndOptimize(&ir_instance, expr, &vm.macros, false) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "IR lowering error: {}\n", .{err}) catch "IR error\n";
            writeStderr(s);
            return err;
        };

        try ir_nodes.append(allocator, root);

        // Record any define/set! target from this form so that the next
        // form's constant folding does not assume the primitive is unmodified.
        collectRedefinedNames(expr, &redefined_names);
    }

    var emitter = llvm_emit.LLVMEmitter.init(allocator);
    defer emitter.deinit();
    emitter.emitProgram(ir_nodes.items) catch |err| {
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "LLVM emit error: {}\n", .{err}) catch "emit error\n";
        writeStderr(s);
        return err;
    };

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            const base = path[0 .. path.len - 4];
            break :blk try std.fmt.allocPrint(allocator, "{s}.ll", .{base});
        }
        break :blk try std.fmt.allocPrint(allocator, "{s}.ll", .{path});
    };
    const should_free = output_path == null;
    defer if (should_free) allocator.free(out_path);

    const fd = std.posix.openat(std.posix.AT.FDCWD, out_path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch |err| {
        writeStderr("Failed to create output file\n");
        return err;
    };
    defer _ = std.posix.system.close(fd);
    const data = emitter.toSlice();
    var total: usize = 0;
    while (total < data.len) {
        const result = std.posix.system.write(fd, data.ptr + total, data.len - total);
        if (result <= 0) {
            writeStderr("Failed to write output\n");
            return error.WriteFailed;
        }
        total += @as(usize, @intCast(result));
    }

    var msgbuf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&msgbuf, "Wrote {s}\n", .{out_path}) catch return;
    writeStdout(msg);
}

pub fn compileNative(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;

    const pid = std.c.getpid();
    var ll_buf: [64]u8 = undefined;
    var ll_w: std.Io.Writer = .fixed(&ll_buf);
    try ll_w.print("/tmp/kaappi_native_{d}.ll", .{pid});
    const ll_path = ll_w.buffered();
    ll_buf[ll_path.len] = 0;
    defer _ = std.posix.system.unlink(@ptrCast(ll_path.ptr));
    try emitLlvmFile(vm, path, ll_path);

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            break :blk path[0 .. path.len - 4];
        }
        break :blk path;
    };

    const lib_dir = findLibDir(allocator) orelse {
        writeStderr("Cannot find libkaappi_rt.a. Build it with: zig build lib\n");
        return error.RuntimeLibraryNotFound;
    };

    const lib_flag = try std.fmt.allocPrint(allocator, "-L{s}", .{lib_dir});
    defer allocator.free(lib_flag);

    var found_compiler = false;
    const compilers = [_][]const u8{ "zig", "cc", "clang", "gcc" };
    for (compilers) |cc| {
        const cc_path = findInPath(allocator, cc) orelse continue;
        defer allocator.free(cc_path);
        found_compiler = true;
        if (tryLink(allocator, cc_path, ll_path, out_path, lib_flag, std.mem.eql(u8, cc, "zig"))) {
            return;
        }
    }

    if (found_compiler) {
        writeStderr("Linking failed (see C compiler diagnostics above).\n");
        return error.LinkFailed;
    }
    writeStderr("No C compiler found. Install zig, clang, or gcc.\n");
    return error.NoCCompilerFound;
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
    var buf: [1024]u8 = undefined;
    const dir = kaappi_paths.getExeRelativeLibDir(&buf) orelse return null;
    if (!checkLibDir(allocator, dir)) return null;
    return allocator.dupe(u8, dir) catch null;
}

fn collectRedefinedNames(expr: types.Value, map: *std.StringHashMap(void)) void {
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return;
    const form = types.symbolName(head);

    if (std.mem.eql(u8, form, "define")) {
        const rest = types.cdr(expr);
        if (rest == types.NIL or !types.isPair(rest)) return;
        const target = types.car(rest);
        if (types.isSymbol(target)) {
            map.put(types.symbolName(target), {}) catch {};
        } else if (types.isPair(target) and types.isSymbol(types.car(target))) {
            map.put(types.symbolName(types.car(target)), {}) catch {};
        }
    } else if (std.mem.eql(u8, form, "set!")) {
        const rest = types.cdr(expr);
        if (rest == types.NIL or !types.isPair(rest)) return;
        const target = types.car(rest);
        if (types.isSymbol(target)) {
            map.put(types.symbolName(target), {}) catch {};
        }
    } else if (std.mem.eql(u8, form, "begin")) {
        var body = types.cdr(expr);
        while (body != types.NIL and types.isPair(body)) {
            collectRedefinedNames(types.car(body), map);
            body = types.cdr(body);
        }
    }
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

    // Compile the emitted IR at -O2. The emitter deliberately produces naive IR
    // (every immediate as `add i64 0, K`, pervasive alloca/load/store, long
    // br/phi chains) and relies on LLVM to clean it up — at -O0 none of that
    // runs. mem2reg/instcombine/simplifycfg collapse it; GC root-slot allocas
    // whose address escapes into kaappi_gc_push_root correctly stay in memory.
    // Malformed IR is caught by the -w-free verifier in tests/e2e/run-e2e.sh;
    // `-w` here only silences cosmetic warnings on generated IR for end users
    // (a hard verifier error still fails the compile regardless of -w). See #1492.
    argv_buf[argc] = "-O2";
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
