//! `kaappi check <file>` — compile-only static analysis (kaappi#1511, part of
//! the machine-legibility epic kaappi#1503).
//!
//! Answers "will this fail?" without running anything. `check` reads, expands,
//! and compiles every top-level form — surfacing the same read/expand/compile
//! diagnostics a real run would, with their stable `KP` codes — but executes no
//! program code. It then reports the reserved `KP4xxx` lint findings that a
//! plain compile does not:
//!
//!   * KP4001  unknown variable at top level        (warning)
//!   * KP4002  wrong arity on a direct built-in call (error)
//!   * KP4003  wrong-type literal to a built-in       (error)
//!
//! **Invariant.** `check` never rejects a program R7RS says is valid: anything
//! the spec permits is at most a warning. Forward references are legal, so an
//! unknown top-level variable is a warning; the arity/type errors fire only on
//! direct, unshadowed calls to genuine built-ins with a literal that is *always*
//! wrong (see check_lint.zig for how soundness is enforced).
//!
//! **What runs.** Only environment setup runs: `import` / `define-library` /
//! `include` / `define-record-type` are processed so later forms see the
//! bindings and macros they introduce (and so a use of an imported macro like
//! `test-error` is recognised as a macro, not linted as a call). Ordinary
//! `define`s and expressions are compiled and analysed, never executed — their
//! bound names are gathered structurally so a forward reference is not warned.

const std = @import("std");
const types = @import("types.zig");
const reader = @import("reader.zig");
const compiler = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const ir_mod = @import("ir.zig");
const diagnostics = @import("diagnostics.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");
const reporting = @import("reporting.zig");
const check_lint = @import("check_lint.zig");
const file_utils = @import("file_utils.zig");

const VM = vm_mod.VM;
const Value = types.Value;
const Code = diagnostics.Code;
const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

pub const Options = struct {
    json: bool = false,
    deny_warnings: bool = false,
};

/// Run `kaappi check` on `path` with the VM `main` already set up (all built-ins
/// registered, standard libraries loaded, library search path configured).
/// Returns the process exit code: nonzero if any finding is an error — or, under
/// `--deny-warnings`, if there is any finding at all.
pub fn run(vm: *VM, path: []const u8, opts: Options) u8 {
    const allocator = vm.gc.allocator;

    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const source = file_utils.readWholeFile(allocator, path, 4 * 1024 * 1024) catch {
        writeStderr("kaappi check: cannot read '");
        writeStderr(path);
        writeStderr("'\n");
        return 1;
    };
    defer allocator.free(source);

    // Resolve top-level `(include ...)`/import paths relative to the file.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    // Names bound by top-level define / define-values / define-syntax anywhere in
    // the file — the "known" set for the unbound-variable warning (so a forward
    // reference is legal) and the "leave it alone" set for the built-in checks
    // (a redefined built-in is not the built-in). Collected before analysis so
    // ordering within the file does not matter.
    var user_defined = std.StringHashMap(void).init(arena);
    collectTopLevelDefines(&user_defined, arena, vm.gc, source);

    var ctx: check_lint.Context = .{ .arena = arena, .user_defined = &user_defined };

    // `check` discards bytecode, so folding buys nothing — and disabling it keeps
    // every call visible to the lint (no `(car 5 6)` folded away before the walk).
    const saved_opt = ir_mod.optimize_enabled;
    ir_mod.optimize_enabled = false;
    check_lint.active = &ctx;
    defer {
        check_lint.active = null;
        ir_mod.optimize_enabled = saved_opt;
    }

    analyze(vm, &ctx, arena, source, path);

    std.mem.sort(check_lint.Finding, ctx.findings.items, {}, findingLess);
    report(arena, ctx.findings.items, opts);

    var errors: usize = 0;
    for (ctx.findings.items) |f| {
        if (isError(f.code, opts.deny_warnings)) errors += 1;
    }
    return if (errors > 0) 1 else 0;
}

/// True when a finding counts against the exit code: any registry error, plus
/// any warning once `--deny-warnings` promotes warnings.
fn isError(code: Code, deny_warnings: bool) bool {
    return switch (code.info().severity) {
        .err => true,
        .warning => deny_warnings,
    };
}

// ── Per-form analysis ──────────────────────────────────────────────────────

/// Test-only: analyse `source` into `ctx` exactly as `run` does (optimization
/// off, lint active, no file I/O or reporting). The caller owns `ctx.arena` and
/// inspects `ctx.findings` directly.
pub fn analyzeForTest(vm: *VM, ctx: *check_lint.Context, source: []const u8) void {
    const saved_opt = ir_mod.optimize_enabled;
    ir_mod.optimize_enabled = false;
    check_lint.active = ctx;
    defer {
        check_lint.active = null;
        ir_mod.optimize_enabled = saved_opt;
    }
    analyze(vm, ctx, ctx.arena, source, "<test>");
}

fn analyze(vm: *VM, ctx: *check_lint.Context, arena: std.mem.Allocator, source: []const u8, path: []const u8) void {
    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        addReadError(ctx, err, lc.line, lc.col);
        return;
    }) {
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            addReadError(ctx, err, lc.line, lc.col);
            return;
        };
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();
        checkForm(vm, ctx, arena, expr, path, datum_lc.line, datum_lc.col);
    }
}

/// Analyse one top-level form: process env-establishing forms for their effect,
/// splice top-level `begin`, and compile-but-not-run everything else.
fn checkForm(vm: *VM, ctx: *check_lint.Context, arena: std.mem.Allocator, expr: Value, path: []const u8, line: u32, col: u32) void {
    if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
        const name = types.symbolName(types.car(expr));

        // Top-level `begin` splices as top-level forms (R7RS 5.1) — recurse so
        // its expressions are analysed, never executed.
        if (std.mem.eql(u8, name, "begin")) {
            var rest = types.cdr(expr);
            while (types.isPair(rest)) : (rest = types.cdr(rest)) {
                checkForm(vm, ctx, arena, types.car(rest), path, line, col);
            }
            return;
        }

        // Environment setup that later forms depend on: run it (suppressing lint
        // over the library/record code it compiles), so imported names/macros and
        // record accessors are in scope for the rest of the file.
        if (isEnvSetupForm(name)) {
            ctx.suppress_depth += 1;
            defer ctx.suppress_depth -= 1;
            if (vm.handleTopLevelForm(expr)) |result| {
                _ = result catch |err| addRuntimeOrCompileError(vm, ctx, arena, err, line, col);
            }
            return;
        }
    }

    // Everything else — define, define-syntax, define-values, expressions —
    // is compiled (registering any define-syntax macro, surfacing compile
    // errors, and driving the lint walk) but not executed. The Function is
    // discarded.
    _ = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, line, path, false) catch |err| {
        addCompileError(ctx, arena, err, line, col);
    };
}

/// Forms `check` processes for their environment effect rather than compiling as
/// ordinary expressions. `define-values` is deliberately absent: it is compiled
/// (so its initializer is linted) and its names are gathered structurally.
fn isEnvSetupForm(name: []const u8) bool {
    return std.mem.eql(u8, name, "import") or
        std.mem.eql(u8, name, "define-library") or
        std.mem.eql(u8, name, "include") or
        std.mem.eql(u8, name, "include-ci") or
        std.mem.eql(u8, name, "define-record-type");
}

// ── Structural collection of top-level define names ────────────────────────

/// Gather the names introduced by top-level `define` / `define-values` /
/// `define-syntax` (recursing into top-level `begin`). Keys are duped into the
/// arena so they outlive the transient data read here.
pub fn collectTopLevelDefines(set: *std.StringHashMap(void), arena: std.mem.Allocator, gc: *@import("memory.zig").GC, source: []const u8) void {
    var r = reader.Reader.init(gc, source);
    defer r.deinit();
    while (r.hasMore() catch false) {
        var expr = r.readDatum() catch break;
        gc.pushRoot(&expr);
        collectFromForm(set, arena, expr);
        gc.popRoot();
    }
}

fn collectFromForm(set: *std.StringHashMap(void), arena: std.mem.Allocator, expr: Value) void {
    if (!types.isPair(expr) or !types.isSymbol(types.car(expr))) return;
    const head = types.symbolName(types.car(expr));
    const rest = types.cdr(expr);

    if (std.mem.eql(u8, head, "define") or std.mem.eql(u8, head, "define-syntax")) {
        // (define name ...) or (define (name . args) ...)
        if (types.isPair(rest)) addDefineTarget(set, arena, types.car(rest));
    } else if (std.mem.eql(u8, head, "define-values")) {
        // (define-values (a b . rest) expr) — every formal is bound.
        if (types.isPair(rest)) addFormals(set, arena, types.car(rest));
    } else if (std.mem.eql(u8, head, "begin")) {
        var cur = rest;
        while (types.isPair(cur)) : (cur = types.cdr(cur)) {
            collectFromForm(set, arena, types.car(cur));
        }
    }
}

/// The target of a `define`: a bare symbol, or the head of a possibly-curried
/// procedure form `((name a) b)` — peel the leading pairs to the name symbol.
fn addDefineTarget(set: *std.StringHashMap(void), arena: std.mem.Allocator, target: Value) void {
    var t = target;
    while (types.isPair(t)) t = types.car(t);
    if (types.isSymbol(t)) addName(set, arena, types.symbolName(t));
}

fn addFormals(set: *std.StringHashMap(void), arena: std.mem.Allocator, formals: Value) void {
    var f = formals;
    while (types.isPair(f)) : (f = types.cdr(f)) {
        if (types.isSymbol(types.car(f))) addName(set, arena, types.symbolName(types.car(f)));
    }
    if (types.isSymbol(f)) addName(set, arena, types.symbolName(f)); // rest formal
}

fn addName(set: *std.StringHashMap(void), arena: std.mem.Allocator, name: []const u8) void {
    if (set.contains(name)) return;
    const owned = arena.dupe(u8, name) catch return;
    set.put(owned, {}) catch {};
}

// ── Error findings from read / compile / env-setup ─────────────────────────

fn addReadError(ctx: *check_lint.Context, err: anyerror, line: u32, col: u32) void {
    const code = diagnostics.readErrorCode(err);
    ctx.addFinding(code, .{ .line = line, .col = col }, code.message());
}

fn addCompileError(ctx: *check_lint.Context, arena: std.mem.Allocator, err: anyerror, line: u32, col: u32) void {
    const detail = compiler.getSyntaxErrorDetail();
    const code = if (detail.len > 0) Code.syntax_error else diagnostics.compileErrorCode(err);
    const span = compiler.getCompileErrorSpan() orelse types.Span{ .line = line, .col = col };
    const msg: []const u8 = if (detail.len > 0) (arena.dupe(u8, detail) catch code.message()) else code.message();
    ctx.addFinding(code, span, msg);
    if (detail.len > 0) compiler.syntax_error_detail_len = 0;
    compiler.resetCompileErrorSpan();
}

fn addRuntimeOrCompileError(vm: *VM, ctx: *check_lint.Context, arena: std.mem.Allocator, err: anyerror, line: u32, col: u32) void {
    const detail = vm.getErrorDetail();
    const code = if (vm.last_error_code != .uncategorized) vm.last_error_code else diagnostics.runtimeErrorCode(err);
    const msg: []const u8 = if (detail.len > 0) (arena.dupe(u8, detail) catch code.message()) else code.message();
    ctx.addFinding(code, .{ .line = line, .col = col }, msg);
    vm.last_error_detail_len = 0;
    vm.last_error_code = .uncategorized;
}

// ── Reporting ──────────────────────────────────────────────────────────────

fn findingLess(_: void, a: check_lint.Finding, b: check_lint.Finding) bool {
    if (a.span.line != b.span.line) return a.span.line < b.span.line;
    return a.span.col < b.span.col;
}

fn report(arena: std.mem.Allocator, findings: []const check_lint.Finding, opts: Options) void {
    if (opts.json) {
        reportJson(arena, findings);
    } else {
        reportText(findings, opts);
    }
}

/// One LSP `Diagnostic` per line on stdout — the same shape and serializer as
/// `--diagnostics=json` and the language server (kaappi#1505), so nothing new to
/// parse. Registry severity is preserved; `--deny-warnings` changes the exit
/// code, not a warning's nature.
fn reportJson(arena: std.mem.Allocator, findings: []const check_lint.Finding) void {
    var aw: std.Io.Writer.Allocating = .init(arena);
    defer aw.deinit();
    for (findings) |f| {
        var cbuf: [Code.render_width]u8 = undefined;
        const diag: lsp_diagnostic.Diagnostic = .{
            .range = lsp_diagnostic.spanRange(f.span),
            .severity = lsp_diagnostic.severityOf(f.code.info().severity),
            .code = f.code.render(&cbuf),
            .message = f.message,
        };
        aw.clearRetainingCapacity();
        diag.writeJson(&aw.writer) catch continue;
        aw.writer.writeByte('\n') catch continue;
        writeStdout(aw.written());
    }
}

fn reportText(findings: []const check_lint.Finding, opts: Options) void {
    var errors: usize = 0;
    var warnings: usize = 0;
    var buf: [1024]u8 = undefined;
    for (findings) |f| {
        var cbuf: [Code.render_width]u8 = undefined;
        const sev = f.code.info().severity;
        if (sev == .err) errors += 1 else warnings += 1;
        const label = sev.label();
        const line = if (f.span.col > 0)
            std.fmt.bufPrint(&buf, "{d}:{d}: {s}[{s}]: {s}\n", .{ f.span.line, f.span.col, label, f.code.render(&cbuf), f.message }) catch continue
        else if (f.span.line > 0)
            std.fmt.bufPrint(&buf, "{d}: {s}[{s}]: {s}\n", .{ f.span.line, label, f.code.render(&cbuf), f.message }) catch continue
        else
            std.fmt.bufPrint(&buf, "{s}[{s}]: {s}\n", .{ label, f.code.render(&cbuf), f.message }) catch continue;
        writeStdout(line);
    }

    const summary = if (errors == 0 and warnings == 0)
        std.fmt.bufPrint(&buf, "check: no issues found\n", .{}) catch return
    else
        std.fmt.bufPrint(&buf, "check: {d} error{s}, {d} warning{s}{s}\n", .{
            errors,                                                                plural(errors),
            warnings,                                                              plural(warnings),
            if (opts.deny_warnings and warnings > 0) " (warnings denied)" else "",
        }) catch return;
    writeStdout(summary);
}

fn plural(n: usize) []const u8 {
    return if (n == 1) "" else "s";
}
