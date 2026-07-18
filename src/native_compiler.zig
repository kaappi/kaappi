const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const compiler = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const ir_mod = @import("ir.zig");
const llvm_emit = @import("llvm_emit.zig");
const file_utils = @import("file_utils.zig");
const reporting = @import("reporting.zig");
const kaappi_paths = @import("kaappi_paths.zig");
const diagnostics = @import("diagnostics.zig");
const crash = @import("crash.zig");
const timings = @import("timings.zig");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

/// C-compiler discovery order for linking the emitted `.ll` — the driver
/// must be LLVM-based. On most platforms `cc` is clang (macOS, FreeBSD,
/// OpenBSD) or the fall-through finds a working driver, but NetBSD's base
/// cc is GCC — which rejects .ll outright — while an LLVM-capable clang
/// comes from pkgsrc. Probe clang before cc there so the common failure
/// (no pkgsrc clang yet) reports one clean miss instead of two GCC "file
/// format not recognized" spews. gcc stays last everywhere as a
/// deliberate long shot. Shared with doctor.zig so its c-compiler finding
/// reports the same driver `kaappi compile` will actually pick.
pub const cc_search_order = if (platform.is_netbsd)
    [_][]const u8{ "zig", "clang", "cc", "gcc" }
else
    [_][]const u8{ "zig", "cc", "clang", "gcc" };

test "cc_search_order: zig first, gcc last, clang before NetBSD's base GCC" {
    try std.testing.expectEqualStrings("zig", cc_search_order[0]);
    try std.testing.expectEqualStrings("gcc", cc_search_order[cc_search_order.len - 1]);
    var clang_idx: usize = cc_search_order.len;
    var cc_idx: usize = cc_search_order.len;
    for (cc_search_order, 0..) |name, i| {
        if (std.mem.eql(u8, name, "clang")) clang_idx = i;
        if (std.mem.eql(u8, name, "cc")) cc_idx = i;
    }
    try std.testing.expect(clang_idx < cc_search_order.len);
    try std.testing.expect(cc_idx < cc_search_order.len);
    if (platform.is_netbsd) {
        // NetBSD's base cc is GCC, which cannot consume the .ll link
        // input — an LLVM-capable clang must be probed before it
        // (docs/dev/netbsd.md). This runs on the NetBSD unit-test leg,
        // so a reordering regression fails there.
        try std.testing.expect(clang_idx < cc_idx);
    } else {
        try std.testing.expect(cc_idx < clang_idx);
    }
}

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

    crash.note(.compiling, path); // native backend: read → lower → emit LLVM IR

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
        const code = diagnostics.readErrorCode(err);
        var cbuf: [diagnostics.Code.render_width]u8 = undefined;
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error[{s}]: {s}\n", .{ path, lc.line, lc.col, code.render(&cbuf), code.message() }) catch "read error\n";
        writeStderr(s);
        return err;
    }) {
        timings.begin(.read); // kaappi#1515
        const read_result = r.readDatum();
        timings.end();
        const expr = read_result catch |err| {
            const lc = r.getLineCol();
            const code = diagnostics.readErrorCode(err);
            var cbuf: [diagnostics.Code.render_width]u8 = undefined;
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error[{s}]: {s}\n", .{ path, lc.line, lc.col, code.render(&cbuf), code.message() }) catch "read error\n";
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
            const code = diagnostics.compileErrorCode(err);
            var cbuf: [diagnostics.Code.render_width]u8 = undefined;
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "compile error[{s}]: {s}\n", .{ code.render(&cbuf), code.message() }) catch "compile error\n";
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
    // Native cond/case/do lowering consults the macro table so a macro use is
    // sent to the interpreter (which expands it) instead of being mis-compiled
    // as a call to a same-named global (#1496).
    emitter.macros = &vm.macros;
    timings.begin(.llvm_emit); // kaappi#1515: IR → LLVM IR text codegen
    emitter.emitProgram(ir_nodes.items) catch |err| {
        timings.end();
        const code = diagnostics.Code.internal_error;
        var cbuf: [diagnostics.Code.render_width]u8 = undefined;
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "error[{s}]: LLVM emit failed: {s}\n", .{ code.render(&cbuf), code.message() }) catch "internal error\n";
        writeStderr(s);
        return err;
    };
    timings.end(); // llvm_emit

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            const base = path[0 .. path.len - 4];
            break :blk try std.fmt.allocPrint(allocator, "{s}.ll", .{base});
        }
        break :blk try std.fmt.allocPrint(allocator, "{s}.ll", .{path});
    };
    const should_free = output_path == null;
    defer if (should_free) allocator.free(out_path);

    const out_path_z = try allocator.dupeZ(u8, out_path);
    defer allocator.free(out_path_z);
    const fd = platform.openWriteTrunc(out_path_z, 0o644) catch |err| {
        writeStderr("Failed to create output file\n");
        return err;
    };
    defer _ = platform.close(fd);
    const data = emitter.toSlice();
    var total: usize = 0;
    while (total < data.len) {
        const result = platform.write(fd, data.ptr + total, data.len - total);
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

    const pid = platform.getPid();
    var tmp_buf: [512]u8 = undefined;
    const tmp_dir: []const u8 = if (comptime platform.is_windows)
        (if (platform.getenv("TEMP")) |t| std.mem.sliceTo(t, 0) else "C:/Windows/Temp")
    else
        "/tmp";
    var ll_w: std.Io.Writer = .fixed(&tmp_buf);
    try ll_w.print("{s}/kaappi_native_{d}.ll", .{ tmp_dir, pid });
    const ll_path = ll_w.buffered();
    tmp_buf[ll_path.len] = 0;
    defer _ = platform.unlink(tmp_buf[0..ll_path.len :0]);
    try emitLlvmFile(vm, path, ll_path);

    const out_path = output_path orelse try deriveOutputPath(allocator, path);
    const should_free = output_path == null;
    defer if (should_free) allocator.free(out_path);
    timings.setOutput(out_path); // kaappi#1515

    const lib_dir = findLibDir(allocator) orelse {
        writeStderr("Cannot find " ++ platform.rt_lib_name ++ ". Build it with: zig build lib\n");
        return error.RuntimeLibraryNotFound;
    };

    const lib_flag = try std.fmt.allocPrint(allocator, "-L{s}", .{lib_dir});
    defer allocator.free(lib_flag);

    var found_compiler = false;
    {
        // kaappi#1515: external C-compiler link step. `defer` fires on the
        // success `return` inside the loop too, so the stage is always recorded.
        timings.begin(.link);
        defer timings.end();
        for (cc_search_order) |cc| {
            const cc_path = findInPath(allocator, cc) orelse continue;
            defer allocator.free(cc_path);
            found_compiler = true;
            if (tryLink(allocator, cc_path, ll_path, out_path, lib_flag, std.mem.eql(u8, cc, "zig"))) {
                return;
            }
        }
    }

    if (found_compiler) {
        writeStderr("Linking failed (see C compiler diagnostics above).\n");
        return error.LinkFailed;
    }
    writeStderr("No C compiler found. Install zig, clang, or gcc.\n");
    return error.NoCCompilerFound;
}

/// Default output path for `kaappi compile <path>` with no `-o`: the source
/// name minus any `.scm` suffix, plus the platform executable suffix —
/// `foo.scm` → `foo` on POSIX, `foo.exe` on Windows, where PATH lookup and
/// double-click need the extension (#1610). Caller frees.
fn deriveOutputPath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const base = if (std.mem.endsWith(u8, path, ".scm")) path[0 .. path.len - 4] else path;
    return std.fmt.allocPrint(allocator, "{s}{s}", .{ base, platform.exe_suffix });
}

fn findInPath(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const path_env = platform.getenv("PATH") orelse return null;
    const path_str = std.mem.span(path_env);
    var iter = std.mem.splitScalar(u8, path_str, platform.path_list_sep);
    while (iter.next()) |dir| {
        const full = std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ dir, name, platform.exe_suffix }) catch continue;
        const full_z = allocator.dupeZ(u8, full) catch {
            allocator.free(full);
            continue;
        };
        allocator.free(full);
        const fd = platform.openRead(full_z) catch {
            allocator.free(full_z);
            continue;
        };
        _ = platform.close(fd);
        return full_z;
    }
    return null;
}

fn findLibDir(allocator: std.mem.Allocator) ?[]const u8 {
    if (platform.getenv("KAAPPI_LIB_DIR")) |env| {
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
    const path = std.fmt.allocPrintSentinel(allocator, "{s}/" ++ platform.rt_lib_name, .{dir}, 0) catch return false;
    defer allocator.free(path);
    const fd = platform.openRead(path) catch return false;
    _ = platform.close(fd);
    return true;
}

test "deriveOutputPath strips .scm and appends the platform exe suffix" {
    const a = std.testing.allocator;
    const derived = try deriveOutputPath(a, "dir/foo.scm");
    defer a.free(derived);
    try std.testing.expectEqualStrings("dir/foo" ++ platform.exe_suffix, derived);

    const noext = try deriveOutputPath(a, "prog");
    defer a.free(noext);
    try std.testing.expectEqualStrings("prog" ++ platform.exe_suffix, noext);
}

test "checkLibDir looks for the platform-named runtime archive" {
    const a = std.testing.allocator;
    const dir = try std.fmt.allocPrint(a, "{s}/kaappi-nctest-{d}", .{ platform.tempDir(), platform.getPid() });
    defer a.free(dir);
    const dir_z = try a.dupeZ(u8, dir);
    defer a.free(dir_z);
    try std.testing.expect(platform.mkdir(dir_z, 0o700) == 0);
    defer _ = platform.rmdir(dir_z);

    try std.testing.expect(!checkLibDir(a, dir));

    const lib_path = try std.fmt.allocPrintSentinel(a, "{s}/" ++ platform.rt_lib_name, .{dir}, 0);
    defer a.free(lib_path);
    const fd = try platform.openWriteTrunc(lib_path, 0o600);
    _ = platform.close(fd);
    defer _ = platform.unlink(lib_path);
    try std.testing.expect(checkLibDir(a, dir));
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
    if (comptime platform.is_windows) {
        // The runtime lib's fd-readiness backends (#1608) call Winsock via
        // `extern "ws2_32"` declarations. Zig applies that link dependency
        // only when it links the final binary itself; a foreign `zig cc`
        // link of kaappi_rt.lib never sees it, so the import lib must be
        // named explicitly (#1610).
        argv_buf[argc] = "-lws2_32";
        argc += 1;
    } else {
        argv_buf[argc] = "-lpthread";
        argc += 1;
    }
    if (comptime platform.is_openbsd) {
        // OpenBSD/arm64 enforces BTCFI: an indirect branch must land on a
        // `bti` instruction. The Zig-built libkaappi_rt.a carries no landing
        // pads (Zig 0.16 can't emit them), so the linked native binary opts
        // out via the PT_OPENBSD_NOBTCFI marker that `-z nobtcfi` emits — the
        // system cc/ld supports the flag natively. Kaappi's own binaries get
        // the same marker post-link (build.zig). See docs/dev/openbsd.md.
        argv_buf[argc] = "-z";
        argc += 1;
        argv_buf[argc] = "nobtcfi";
        argc += 1;
    }
    argv_buf[argc] = null;

    const link_ok = blk: {
        if (comptime platform.is_windows) {
            var argv_slices: [16][]const u8 = undefined;
            for (argv_buf[0..argc], 0..) |arg, i| argv_slices[i] = std.mem.sliceTo(arg.?, 0);
            const code = platform.winSpawnPassthrough(allocator, argv_slices[0..argc], null) catch break :blk false;
            break :blk code == 0;
        }
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
        if (!exited) break :blk false;
        const exit_code = (raw >> 8) & 0xff;
        break :blk exit_code == 0;
    };
    if (link_ok) {
        var msgbuf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msgbuf, "Compiled {s}\n", .{out_path}) catch return true;
        writeStdout(msg);
        return true;
    }
    return false;
}
