const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const compiler = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const ir_mod = @import("ir.zig");
const expander = @import("expander.zig");
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

/// Builds the #1656 refuse-loudly diagnostic naming the host arch and pointing
/// at the interpreter, into `buf`. Split out so a test can assert its content
/// without having to run on an interpreter-tier arch. Returns the written slice
/// (or a static fallback if `buf` cannot hold even the arch-less form).
fn nativeUnsupportedMessage(buf: []u8, arch_name: []const u8, path: []const u8) []const u8 {
    return std.fmt.bufPrint(
        buf,
        "error: native compilation is not supported on this architecture ({s}).\n" ++
            "The LLVM native backend targets aarch64 and x86_64 only; run the program with the interpreter instead:\n" ++
            "    kaappi {s}\n",
        .{ arch_name, path },
    ) catch "error: native compilation is not supported on this architecture\n";
}

/// #1743 refuse-loudly diagnostic: `files` is the set of library .sld files
/// this compile resolved from disk (see the call site's comment for why that
/// makes them unusable from the compiled binary's own runtime). Lists each
/// one and points at the two working alternatives instead of silently handing
/// back a binary that fails at runtime with "library not found" despite
/// compiling cleanly.
fn reportUnresolvableLibraryImports(path: []const u8, files: *std.StringHashMap([]const u8)) void {
    writeStderr("error: `kaappi compile` cannot produce a working binary for this program.\n\n");
    writeStderr("It imports the following library file(s), which are not built into kaappi\n");
    writeStderr("and were resolved from disk at compile time:\n");

    var it = files.keyIterator();
    while (it.next()) |key| {
        var buf: [600]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "    {s}\n", .{key.*}) catch continue;
        writeStderr(line);
    }

    writeStderr(
        "\nThe LLVM native backend does not embed library sources into the compiled\n" ++
            "binary, and the binary's own runtime has no library search path -- so this\n" ++
            "import fails with \"library not found\" at runtime even though compilation\n" ++
            "reports success.\n\n" ++
            "Run the program with the interpreter instead:\n",
    );
    var runbuf: [1088]u8 = undefined;
    writeStderr(std.fmt.bufPrint(&runbuf, "    kaappi {s}\n", .{path}) catch "");
    writeStderr("or produce a self-contained binary that embeds library sources:\n");
    var bundlebuf: [1088]u8 = undefined;
    writeStderr(std.fmt.bufPrint(&bundlebuf, "    zig build -Dbundle-src={s}\n", .{path}) catch "");
}

/// Print a read error the way `toplevel_driver.reportReadError` does, detail
/// channel included (kaappi#1723) -- kept as its own hand-rolled block since
/// this native-compile path has no `--diagnostics=json` mode and predates that
/// consolidation. Shared by both of `emitLlvmFile`'s read-loop error arms.
fn reportNativeReadError(path: []const u8, line: u32, col: u32, err: anyerror) void {
    const code = diagnostics.readErrorCode(err);
    const detail = reader_mod.getReadErrorDetail();
    const msg = if (detail.len > 0) detail else code.message();
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    var errbuf: [256]u8 = undefined;
    const prefix = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error[{s}]: ", .{ path, line, col, code.render(&cbuf) }) catch "read error: ";
    writeStderr(prefix);
    writeStderr(msg);
    writeStderr("\n");
    reader_mod.resetReadErrorDetail();
}

pub fn emitLlvmFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;

    // #1656: refuse loudly on an arch the LLVM backend can't target, before any
    // file I/O. Otherwise emitPreamble emits an unknown-triple module and the
    // `-w` link silently overrides it with the host default, handing the user a
    // binary that segfaults. Both entry points — `kaappi compile` (compileNative
    // calls this first) and `--emit-llvm` — funnel through here, so one guard
    // covers both. See docs/dev/decisions/native-backend-architecture-scope.md.
    if (!llvm_emit.native_backend_supported) {
        var errbuf: [2048]u8 = undefined;
        writeStderr(nativeUnsupportedMessage(&errbuf, @tagName(@import("builtin").cpu.arch), path));
        return error.NativeBackendUnsupported;
    }

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

    // #1743: the compiled binary's own runtime (kaappi_runtime_init in
    // runtime_exports.zig) starts a fresh VM with no library search path, and
    // the native backend never bundles .sld sources into the binary the way
    // the --compile/-Dbundle-src .sbc pathway does. So any import that this
    // (compiling) VM resolves from a file — a third-party package or one of
    // the 159 portable SRFIs, as opposed to a library built into the Zig
    // binary — compiles cleanly here but reliably fails at runtime with
    // "library not found", since the runtime's fresh VM can never find it.
    // Reuse the .sbc bundler's own file-collection hook purely to detect this:
    // processImportSet (vm_library.zig) checks the built-in registry first and
    // only records a file here when a library is resolved from disk, so a
    // built-in library never appears in this map.
    var collect_files = std.StringHashMap([]const u8).init(allocator);
    defer {
        var cit = collect_files.iterator();
        while (cit.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        collect_files.deinit();
    }
    vm.compile_collect_files = &collect_files;
    defer vm.compile_collect_files = null;

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(allocator);

    var ir_instance = ir_mod.IR.init(allocator);
    defer ir_instance.deinit();
    // Lowered forms are already macro-expanded and may contain hygiene-
    // renamed identifiers inside quoted data; lowerQuote needs the owning GC
    // to strip those back to their base names (#1801).
    ir_instance.gc = vm.gc;

    // Track names that are targets of define or set! in previous top-level
    // forms so constant folding does not inline primitive semantics for a
    // name that will be rebound at runtime (#822), plus every `set!` target
    // nested anywhere inside the form about to be lowered — a `set!` in a
    // lambda body runs before a call in that same body, so the primitive's
    // compile-time value is already stale there (#2117 route 1). The
    // interpreter gets the second half from Compiler.compile's own per-form
    // pre-scan; this is the same scan, minus macro expansion.
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
        reportNativeReadError(path, lc.line, lc.col, err);
        return err;
    }) {
        timings.begin(.read); // kaappi#1515
        const read_result = r.readDatum();
        timings.end();
        const expr = read_result catch |err| {
            const lc = r.getLineCol();
            reportNativeReadError(path, lc.line, lc.col, err);
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

        // `try`, not a swallowed error: the only failure is OOM growing the
        // map, and continuing with a partial set would silently fold a call
        // the scan had not finished proving unsafe.
        try compiler.scanSetTargetsWithoutMacros(expr, &redefined_names);

        const root = ir_mod.lowerAndOptimize(&ir_instance, expr, &vm.macros, false) catch |err| {
            const code = diagnostics.compileErrorCode(err);
            var cbuf: [diagnostics.Code.render_width]u8 = undefined;
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "compile error[{s}]: {s}\n", .{ code.render(&cbuf), code.message() }) catch "compile error\n";
            writeStderr(s);
            return err;
        };

        // #2119: a top-level form whose own evaluation may capture a full
        // (re-entrant) continuation must run entirely in the VM, as one
        // eval unit. The native backend otherwise lowers the form's outer
        // structure — a `set!`, a `define`'s value store, a plain call — to
        // straight-line native code and eval-fallbacks *only* the call/cc
        // subexpression. The continuation captured inside that subexpression
        // then spans just it, so invoking the continuation after the form
        // returned (from a later top-level form) re-runs only the
        // subexpression and delivers its value to a native context that has
        // already completed and cannot re-run: the enclosing `set!`/`define`
        // store never fires again, silently keeping the pre-capture value
        // (`(set! result (+ 100 (call/cc …)))` kept 100 instead of 142).
        // Emitting the whole raw form as a single passthrough — evaluated by
        // the interpreter, which owns continuation capture/restore — makes the
        // captured continuation span the whole form, so a later resume re-runs
        // its tail exactly as the pure-VM tier does. A form that already
        // lowered to a whole-form passthrough (root.tag == .passthrough, e.g.
        // a bare `(call/cc …)` or a `(define (f …) …)` whose body reaches one)
        // needs no change — it is already one VM eval unit.
        const node_to_emit: *ir_mod.Node = if (root.tag != .passthrough and exprMayCaptureContinuation(expr))
            (ir_instance.makePassthrough(expr) catch return error.OutOfMemory)
        else
            root;
        try ir_nodes.append(allocator, node_to_emit);

        // Record any define/set! target from this form so that the next
        // form's constant folding does not assume the primitive is unmodified.
        // Macro-aware (#2212): a top-level macro use whose expansion contains a
        // `(set! + -)` rebinds a primitive exactly as a literal `set!` would,
        // but `kaappi compile` never executes program forms, so without
        // expanding it here the rebinding stays invisible and a later `(+ ...)`
        // folds against the stale primitive.
        collectRedefinedNamesMacroAware(vm, expr, &redefined_names, MAX_TOPLEVEL_MACRO_SCAN_DEPTH);
    }

    if (collect_files.count() > 0) {
        reportUnresolvableLibraryImports(path, &collect_files);
        return error.UnresolvableLibraryImport;
    }

    var emitter = llvm_emit.LLVMEmitter.init(allocator);
    defer emitter.deinit();
    // Native cond/case/do lowering consults the macro table so a macro use is
    // sent to the interpreter (which expands it) instead of being mis-compiled
    // as a call to a same-named global (#1496).
    emitter.macros = &vm.macros;
    // Threaded into every scratch IR the emitter lowers, so lowerQuote can
    // strip hygiene renames from a macro-produced quoted datum (#1801).
    emitter.gc = vm.gc;
    // Likewise for the `set!` targets: by now the read loop above has seen
    // every top-level form, so this map covers the whole program — and the
    // emitter re-lowers lambda/let bodies from here on (#2117).
    emitter.set_targets = &redefined_names;
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

/// True when evaluating `expr` may itself capture a full (re-entrant)
/// continuation — i.e. `call/cc` / `call-with-current-continuation` appears
/// somewhere in `expr` outside quoted data. Drives the #2119 whole-form VM
/// fallback in the read loop above; see the comment there for why a top-level
/// form matching this must not have its outer structure lowered natively.
///
/// Conservative by construction: it descends into every non-`quote` sub-list,
/// including lambda and define bodies, so it over-matches a `call/cc` that is
/// only reached by a *later* call rather than by the form's own evaluation
/// (e.g. `(define f (lambda () (call/cc …)))`). Over-matching is safe — it
/// only forces one more top-level form onto the (correct, slower) interpreter
/// path, never changes a result — while under-matching would reintroduce the
/// silent-wrong-value bug. Macro-hidden uses are not expanded here; the direct
/// uses this catches cover the divergence the issue documents.
fn exprMayCaptureContinuation(expr: types.Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.stripHygienicPrefix(types.symbolName(head));
        // Quoted data is inert — a `call/cc` symbol inside it is never called.
        if (std.mem.eql(u8, name, "quote")) return false;
        if (std.mem.eql(u8, name, "call/cc") or
            std.mem.eql(u8, name, "call-with-current-continuation")) return true;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (exprMayCaptureContinuation(types.car(cur))) return true;
    }
    return false;
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

/// Cap on how deep a top-level head-position macro chain the redefined-names
/// scan will expand (a macro whose expansion is another macro use, ...). Well
/// above any real program; only guards against a macro that expands to itself.
const MAX_TOPLEVEL_MACRO_SCAN_DEPTH: u8 = 32;

/// Macro-aware variant of `collectRedefinedNames` for the native top-level read
/// loop (#2212). A top-level *macro use* that expands to `(set! + -)` rebinds a
/// primitive exactly as a literal `set!` does, but the syntactic tracker never
/// sees the `set!`: `kaappi compile` does not execute program forms, so a later
/// `(+ ...)` folds against the stale primitive (native 7 vs interpreter 3). The
/// interpreter is immune for an unrelated reason — it has already *executed*
/// the rebinding form, so `IR.isRedefined`'s globals check sees the new value.
///
/// The compiling VM still holds `vm.macros`, `vm.gc`, and `vm.globals`, so when
/// the form's head names a `syntax-rules` macro we expand it (best-effort, the
/// same expansion lowering runs anyway) and scan the expansion for the
/// `define`/`set!` targets it introduces. Names are recorded stripped of any
/// hygiene prefix so they match the raw name the folder looks up at the use
/// site.
///
/// This stays bounded, unlike the speculative per-subform scan whose cost cliff
/// #1802 documents: it expands a macro only in *head* position and recurses
/// only through `begin` — it never descends into expression positions
/// (lambda/let bodies, call arguments), so its reach is the program's own
/// top-level structure plus a head-macro chain that `depth` caps. Only
/// `syntax-rules` transformers are expanded, so no procedural (SRFI 211) macro
/// re-runs its arbitrary Scheme here. Over-recording a name is always safe (it
/// only *declines* a fold); a divergent best-effort expansion at worst misses a
/// target, exactly as before this fix.
fn collectRedefinedNamesMacroAware(vm: *vm_mod.VM, expr: types.Value, map: *std.StringHashMap(void), depth: u8) void {
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return;
    const form = types.stripHygienicPrefix(types.symbolName(head));

    if (std.mem.eql(u8, form, "define")) {
        const rest = types.cdr(expr);
        if (rest == types.NIL or !types.isPair(rest)) return;
        const target = types.car(rest);
        if (types.isSymbol(target)) {
            map.put(types.stripHygienicPrefix(types.symbolName(target)), {}) catch {};
        } else if (types.isPair(target) and types.isSymbol(types.car(target))) {
            map.put(types.stripHygienicPrefix(types.symbolName(types.car(target))), {}) catch {};
        }
    } else if (std.mem.eql(u8, form, "set!")) {
        const rest = types.cdr(expr);
        if (rest == types.NIL or !types.isPair(rest)) return;
        const target = types.car(rest);
        if (types.isSymbol(target)) {
            map.put(types.stripHygienicPrefix(types.symbolName(target)), {}) catch {};
        }
    } else if (std.mem.eql(u8, form, "begin")) {
        var body = types.cdr(expr);
        while (body != types.NIL and types.isPair(body)) {
            collectRedefinedNamesMacroAware(vm, types.car(body), map, depth);
            body = types.cdr(body);
        }
    } else {
        // A non-special head: expand it if it names a syntax-rules macro, then
        // scan the expansion. `depth` bounds a macro-to-macro chain.
        if (depth == 0) return;
        const transformer = vm.macros.get(types.symbolName(head)) orelse return;
        if (!types.isPointer(transformer)) return;
        const tobj = types.toObject(transformer);
        if (tobj.tag != .transformer) return;
        if (tobj.as(types.Transformer).kind != .syntax_rules) return;

        // Best-effort expansion with an empty use-site check (no locals at top
        // level), mirroring compiler.collectSetTargets' pre-scan path. Held in
        // the batch's existing no_collect window; take an extra guard anyway so
        // this is correct independent of the caller.
        vm.gc.no_collect += 1;
        defer vm.gc.no_collect -= 1;
        const expanded = expander.expandMacro(vm.gc, expr, transformer, vm.globals, &vm.macros, .{}) catch return;
        collectRedefinedNamesMacroAware(vm, expanded, map, depth - 1);
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

test "nativeUnsupportedMessage names the arch and points at the interpreter (#1656)" {
    var buf: [512]u8 = undefined;
    const msg = nativeUnsupportedMessage(&buf, "riscv64", "hello.scm");
    // Names the offending arch and the interpreter fallback command...
    try std.testing.expect(std.mem.indexOf(u8, msg, "riscv64") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "not supported") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "kaappi hello.scm") != null);
    // ...and the two arches that *are* supported, so the user sees the boundary.
    try std.testing.expect(std.mem.indexOf(u8, msg, "aarch64") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "x86_64") != null);
}

test "nativeUnsupportedMessage falls back safely when the buffer is tiny" {
    var buf: [8]u8 = undefined;
    const msg = nativeUnsupportedMessage(&buf, "riscv64", "hello.scm");
    // Too small for the formatted form, but still a non-empty honest message.
    try std.testing.expect(std.mem.indexOf(u8, msg, "not supported") != null);
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
        if (comptime platform.is_wasm) break :blk false; // no process creation on WASI p1 (kaappi#2153)
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
