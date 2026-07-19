//! `kaappi ast` / `kaappi expand` / `kaappi ir` — read-only pipeline-stage dumps
//! (kaappi#1512, part of the machine-legibility epic kaappi#1503).
//!
//! `--disassemble` already exposes the bytecode stage and `--no-ir-opt` gives an
//! A/B lever, but the stages between source and bytecode had no dumps. These
//! three subcommands make every stage described in `docs/dev/ir.md` observable:
//!
//!   * `ast`    — the datums the reader produced, pretty-printed (`read` + `write`).
//!                Answers "how did the reader parse this?" — fold-case, datum
//!                labels, quote abbreviations, numeric and character literals.
//!   * `expand` — the program after full macro expansion, as S-expressions. The
//!                single most useful stage dump for debugging `syntax-rules`.
//!   * `ir`     — the IR tree the compiler lowers each form to, optimized by
//!                default or (with `--no-opt`) straight after lowering, so the
//!                five optimization passes are observable as a before/after diff.
//!
//! All output is S-expressions / structured text — already machine-readable.
//!
//! **Read-only.** `ast` runs no program code at all. `expand` and `ir` establish
//! only the macro environment later forms depend on — `import` / `define-library`
//! / `include` are processed so imported macros are in scope, and a
//! `define-syntax` transformer is compiled (never executed) so it is registered.
//! Everything else — ordinary `define`s, expressions, `define-record-type`,
//! `define-values` — is shown as-is and never executed.

const std = @import("std");
const types = @import("types.zig");
const reader = @import("reader.zig");
const compiler = @import("compiler.zig");
const expander = @import("expander.zig");
const printer = @import("printer.zig");
const vm_mod = @import("vm.zig");
const ir_mod = @import("ir.zig");
const reporting = @import("reporting.zig");
const file_utils = @import("file_utils.zig");
const toplevel_driver = @import("toplevel_driver.zig");
const crash = @import("crash.zig");

const VM = vm_mod.VM;
const Value = types.Value;
const Node = ir_mod.Node;
const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

/// Guard against a runaway or cyclic macro expansion (a datum label can build a
/// cycle the walker would otherwise chase forever). Matches the spirit of the
/// compiler's own MAX_MACRO_EXPANSION_DEPTH.
const MAX_EXPAND_DEPTH: u16 = 500;

// ── ast ─────────────────────────────────────────────────────────────────────

/// `kaappi ast <file>` — print each post-read datum with `write`, one per line.
/// Pure `read` + `write`; no macros, no compilation, no execution.
pub fn runAst(vm: *VM, path: []const u8) u8 {
    const allocator = vm.gc.allocator;
    const source = readSource(allocator, path) orelse return 1;
    defer allocator.free(source);

    crash.note(.reading, path); // pure read + write

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| return reportRead(&r, path, err)) {
        var expr = r.readDatum() catch |err| return reportRead(&r, path, err);
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();
        printDatum(allocator, expr);
    }
    return 0;
}

// ── expand ───────────────────────────────────────────────────────────────────

/// `kaappi expand <file>` — print the program after full macro expansion. Each
/// top-level form is expanded to S-expressions and written; the expansion output
/// round-trips (feeding it back through kaappi preserves behavior).
pub fn runExpand(vm: *VM, path: []const u8) u8 {
    const allocator = vm.gc.allocator;
    const source = readSource(allocator, path) orelse return 1;
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = dirOf(path);
    defer vm.current_lib_dir = saved_lib_dir;

    crash.noteFile(path);

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| return reportRead(&r, path, err)) {
        crash.noteStage(.reading);
        var expr = r.readDatum() catch |err| return reportRead(&r, path, err);
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();
        crash.noteStage(.expanding);
        expandTopLevel(vm, expr, path);
    }
    return 0;
}

/// Process one top-level form for `expand`: splice a top-level `begin` (R7RS
/// 5.1) so an interior `define-syntax` is registered before a later sibling uses
/// it, print the fully expanded form, then register any environment effect the
/// rest of the file depends on. A macro that fails to expand is left in place
/// (sound — the compiler expands it on a real run) rather than failing the dump.
fn expandTopLevel(vm: *VM, expr: Value, path: []const u8) void {
    if (headIs(expr, "begin")) {
        var rest = types.cdr(expr);
        while (types.isPair(rest)) : (rest = types.cdr(rest)) {
            expandTopLevel(vm, types.car(rest), path);
        }
        return;
    }

    // Expand for display under a collection freeze: the reconstructed spine and
    // every `expandMacro` result are unrooted while being built, so a GC in the
    // middle could free them. The compiler expands macros under the same freeze.
    vm.gc.no_collect += 1;
    const expanded = expandForm(vm, expr, 0) catch expr;
    vm.gc.no_collect -= 1;

    var rooted = expanded;
    vm.gc.pushRoot(&rooted);
    printDatum(vm.gc.allocator, rooted);
    vm.gc.popRoot();

    registerEnvForExpand(vm, expr, path);
}

/// Establish the environment effects `expand` needs from a top-level form so
/// later forms expand correctly: run macro-importing forms, and register a
/// `define-syntax` transformer by compiling (never executing) the form. Ordinary
/// `define`s / expressions and value-defining forms are deliberately left alone.
fn registerEnvForExpand(vm: *VM, expr: Value, path: []const u8) void {
    if (!types.isPair(expr) or !types.isSymbol(types.car(expr))) return;
    const name = types.symbolName(types.car(expr));

    if (std.mem.eql(u8, name, "import") or
        std.mem.eql(u8, name, "define-library") or
        std.mem.eql(u8, name, "include") or
        std.mem.eql(u8, name, "include-ci"))
    {
        if (vm.handleTopLevelForm(expr)) |result| {
            _ = result catch {};
            clearErr(vm);
        }
        return;
    }

    if (std.mem.eql(u8, name, "define-syntax")) {
        _ = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, 0, path, false) catch {};
    }
}

// ── The structural macro expander ────────────────────────────────────────────

/// Fully expand one form to S-expressions. A macro use at the head is expanded
/// (best-effort, via the same engine the compiler uses) and its result
/// re-expanded; sub-expressions are expanded structurally so `syntax-rules`
/// literals, `quote`d data and `case` datums are never touched. When in doubt a
/// form is returned unchanged — an unexpanded macro use is still expanded at
/// compile time, so leaving it is always sound and round-trips.
///
/// Best-effort fidelity: like the compiler's own set-target pre-scan, the
/// expander is called with an empty use-site binding check, so a top-level
/// `syntax-rules` macro expands exactly and a macro capturing use-site locals
/// (only reachable inside a `lambda`/`let` body) may not. Local macros bound by
/// `let-syntax`/`letrec-syntax` are not built, so their uses are left in place.
fn expandForm(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    if (depth >= MAX_EXPAND_DEPTH) return expr;
    if (!types.isPair(expr)) return expr;

    const head = types.car(expr);
    if (!types.isSymbol(head)) {
        // Operator position is itself a form, e.g. ((lambda (x) x) 1): every
        // element is an expression.
        return mapExpand(vm, expr, depth);
    }

    const name = types.symbolName(head);

    // A macro use: expand once (best-effort) then re-expand the result. Checked
    // before special forms so an imported macro that shadows a keyword wins,
    // mirroring the compiler's lowering order.
    if (lookupMacro(vm, name)) |transformer| {
        const expanded = expander.expandMacro(vm.gc, expr, transformer, vm.globals, &vm.macros, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            // NoMatchingPattern / limits: a real use-site error or a case the
            // best-effort expander can't reach — leave the form for the compiler
            // to expand and diagnose.
            else => return expr,
        };
        var stripped = expanded;
        if (expander.isUsertextPair(stripped)) stripped = expander.unwrapUsertext(stripped);
        if (types.isPair(stripped) or types.isVector(stripped)) expander.stripUsertextMarkers(vm.gc, stripped);
        return expandForm(vm, stripped, depth + 1);
    }

    const kw = types.stripHygienicPrefix(name);

    // Opaque forms: their bodies are literal data or a transformer spec, never
    // expression code — return unchanged.
    if (isOpaqueForm(kw)) return expr;

    // Binding and clause forms: recurse only into expression positions, keeping
    // binder names, formals and datum lists intact.
    if (streq(kw, "lambda")) return expandLambda(vm, expr, depth);
    if (streq(kw, "let") or streq(kw, "let*") or streq(kw, "letrec") or streq(kw, "letrec*"))
        return expandLet(vm, expr, depth);
    if (streq(kw, "let-syntax") or streq(kw, "letrec-syntax")) return expandSyntaxLet(vm, expr, depth);
    if (streq(kw, "define")) return expandDefine(vm, expr, depth);
    if (streq(kw, "define-values")) return expandDefineValues(vm, expr, depth);
    if (streq(kw, "cond")) return expandCond(vm, expr, depth);
    if (streq(kw, "guard")) return expandGuard(vm, expr, depth);
    if (streq(kw, "case")) return expandCase(vm, expr, depth);
    if (streq(kw, "do")) return expandDo(vm, expr, depth);
    if (streq(kw, "case-lambda")) return expandCaseLambda(vm, expr, depth);
    if (streq(kw, "parameterize")) return expandParameterize(vm, expr, depth);
    if (streq(kw, "let-values") or streq(kw, "let*-values")) return expandLetValues(vm, expr, depth);

    // if / begin / and / or / when / unless / set! / delay and ordinary
    // procedure calls: every element is an expression.
    return mapExpand(vm, expr, depth);
}

/// Forms whose sub-structure is data or a transformer spec, not code.
fn isOpaqueForm(kw: []const u8) bool {
    return streq(kw, "quote") or
        streq(kw, "quasiquote") or // conservative: unquoted parts left in place
        streq(kw, "syntax-rules") or
        streq(kw, "define-syntax") or
        streq(kw, "define-record-type") or
        streq(kw, "import") or
        streq(kw, "define-library") or
        streq(kw, "include") or
        streq(kw, "include-ci") or
        streq(kw, "cond-expand");
}

/// Expand every element of a list (the whole form, including its head symbol —
/// which expands to itself). Used for forms where every position is an
/// expression. Preserves an improper tail unchanged.
fn mapExpand(vm: *VM, list: Value, depth: u16) error{OutOfMemory}!Value {
    if (!types.isPair(list)) return list;
    const new_car = try expandForm(vm, types.car(list), depth);
    const new_cdr = try mapExpand(vm, types.cdr(list), depth);
    return vm.gc.allocPair(new_car, new_cdr);
}

/// `(lambda formals body...)` — keep `lambda` and `formals`, expand the body.
fn expandLambda(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const body = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), types.car(rest), body);
}

/// `(let bindings body...)` or named `(let name bindings body...)` — keep the
/// binder names, expand every init expression and the body.
fn expandLet(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;

    if (types.isSymbol(types.car(rest))) { // named let
        const rest2 = types.cdr(rest);
        if (!types.isPair(rest2)) return expr;
        const bindings = try expandBindings(vm, types.car(rest2), depth);
        const body = try mapExpand(vm, types.cdr(rest2), depth);
        const tail = try vm.gc.allocPair(bindings, body);
        return cons3Tail(vm, types.car(expr), types.car(rest), tail);
    }

    const bindings = try expandBindings(vm, types.car(rest), depth);
    const body = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), bindings, body);
}

/// `let-syntax` / `letrec-syntax`: the transformer bindings are left in place
/// (they are `syntax-rules` specs), and the body is expanded against the global
/// macro set — uses of the locally-bound syntax stay unexpanded and round-trip.
fn expandSyntaxLet(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const body = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), types.car(rest), body);
}

/// `(define x init)` or `(define (f . args) body...)` — keep the target, expand
/// the init expression or the procedure body.
fn expandDefine(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const target = types.car(rest);
    const rest_expanded = try mapExpand(vm, types.cdr(rest), depth); // init exprs / body
    return cons3Tail(vm, types.car(expr), target, rest_expanded);
}

/// `(define-values formals init)` — keep the formals, expand the initializer.
fn expandDefineValues(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const init = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), types.car(rest), init);
}

/// `(cond clause...)` — every clause is `(test body...)`, `(test => recv)` or
/// `(else body...)`; `else` and `=>` are symbols (expand to themselves) and
/// every other position is an expression, so mapping each clause is exact.
fn expandCond(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const clauses = try mapEach(vm, types.cdr(expr), depth);
    return vm.gc.allocPair(types.car(expr), clauses);
}

/// `(guard (var clause...) body...)` — keep `var`, expand the cond-style
/// clauses and the body.
fn expandGuard(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const spec = types.car(rest);
    var new_spec = spec;
    if (types.isPair(spec)) {
        const clauses = try mapEach(vm, types.cdr(spec), depth);
        new_spec = try vm.gc.allocPair(types.car(spec), clauses);
    }
    const body = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), new_spec, body);
}

/// `(case key clause...)` — expand `key`; each clause keeps its datum list (or
/// `else`) verbatim and expands only its body.
fn expandCase(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const new_key = try expandForm(vm, types.car(rest), depth);
    const new_clauses = try mapCaseClauses(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), new_key, new_clauses);
}

fn mapCaseClauses(vm: *VM, clauses: Value, depth: u16) error{OutOfMemory}!Value {
    if (!types.isPair(clauses)) return clauses;
    const clause = types.car(clauses);
    var new_clause = clause;
    if (types.isPair(clause)) {
        const body = try mapExpand(vm, types.cdr(clause), depth); // keep selector, expand body
        new_clause = try vm.gc.allocPair(types.car(clause), body);
    }
    const rest = try mapCaseClauses(vm, types.cdr(clauses), depth);
    return vm.gc.allocPair(new_clause, rest);
}

/// `(do ((var init step)...) (test result...) body...)` — keep each `var`,
/// expand its init/step, the test/result clause and the body.
fn expandDo(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const rest2 = types.cdr(rest);
    if (!types.isPair(rest2)) return expr;

    const var_specs = try expandBindings(vm, types.car(rest), depth);
    const test_clause = try mapExpand(vm, types.car(rest2), depth);
    const body = try mapExpand(vm, types.cdr(rest2), depth);
    const tail = try vm.gc.allocPair(test_clause, body);
    return cons3Tail(vm, types.car(expr), var_specs, tail);
}

/// `(case-lambda (formals body...)...)` — keep each `formals`, expand each body.
fn expandCaseLambda(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const clauses = try mapClausesKeepHead(vm, types.cdr(expr), depth);
    return vm.gc.allocPair(types.car(expr), clauses);
}

/// `(parameterize ((param val)...) body...)` — both `param` and `val` are
/// expressions, so map each binding wholesale; expand the body.
fn expandParameterize(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const bindings = try mapEach(vm, types.car(rest), depth);
    const body = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), bindings, body);
}

/// `(let-values ((formals init)...) body...)` — keep each `formals`, expand each
/// init and the body.
fn expandLetValues(vm: *VM, expr: Value, depth: u16) error{OutOfMemory}!Value {
    const rest = types.cdr(expr);
    if (!types.isPair(rest)) return expr;
    const bindings = try expandBindings(vm, types.car(rest), depth);
    const body = try mapExpand(vm, types.cdr(rest), depth);
    return cons3Tail(vm, types.car(expr), bindings, body);
}

/// Map over a `((name init...)...)` binding list, keeping each `name` and
/// expanding each init expression.
fn expandBindings(vm: *VM, bindings: Value, depth: u16) error{OutOfMemory}!Value {
    if (!types.isPair(bindings)) return bindings;
    const b = types.car(bindings);
    var new_b = b;
    if (types.isPair(b)) {
        const inits = try mapExpand(vm, types.cdr(b), depth);
        new_b = try vm.gc.allocPair(types.car(b), inits);
    }
    const rest = try expandBindings(vm, types.cdr(bindings), depth);
    return vm.gc.allocPair(new_b, rest);
}

/// Map `mapExpand` over each element of a list (each element is itself a form
/// whose every position is an expression — cond/parameterize clauses).
fn mapEach(vm: *VM, list: Value, depth: u16) error{OutOfMemory}!Value {
    if (!types.isPair(list)) return list;
    const new_head = try mapExpand(vm, types.car(list), depth);
    const rest = try mapEach(vm, types.cdr(list), depth);
    return vm.gc.allocPair(new_head, rest);
}

/// Map over clause list keeping each clause's head (formals) and expanding its
/// body — case-lambda clauses.
fn mapClausesKeepHead(vm: *VM, clauses: Value, depth: u16) error{OutOfMemory}!Value {
    if (!types.isPair(clauses)) return clauses;
    const clause = types.car(clauses);
    var new_clause = clause;
    if (types.isPair(clause)) {
        const body = try mapExpand(vm, types.cdr(clause), depth);
        new_clause = try vm.gc.allocPair(types.car(clause), body);
    }
    const rest = try mapClausesKeepHead(vm, types.cdr(clauses), depth);
    return vm.gc.allocPair(new_clause, rest);
}

/// Build `(a b . tail)`. Safe to leave the result unrooted between allocations:
/// every caller runs under `no_collect` (see expandTopLevel), so no allocation
/// here can trigger a collection that frees a partially built spine.
fn cons3Tail(vm: *VM, a: Value, b: Value, tail: Value) error{OutOfMemory}!Value {
    return vm.gc.allocPair(a, try vm.gc.allocPair(b, tail));
}

/// The macro transformer bound to `name`, if any. Uses the VM's global macro
/// table; local (`let-syntax`) macros are intentionally not consulted.
fn lookupMacro(vm: *VM, name: []const u8) ?Value {
    return vm.macros.get(name);
}

// ── ir ───────────────────────────────────────────────────────────────────────

/// `kaappi ir <file> [--no-opt]` — print each top-level form's IR tree. With
/// `no_opt` the tree is shown straight after lowering (analysis only); otherwise
/// the five optimization passes have run, so the two are a before/after diff.
pub fn runIr(vm: *VM, path: []const u8, no_opt: bool) u8 {
    const allocator = vm.gc.allocator;
    const source = readSource(allocator, path) orelse return 1;
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = dirOf(path);
    defer vm.current_lib_dir = saved_lib_dir;

    // The IR command's whole point is to observe with and without the passes;
    // drive `optimize_enabled` directly rather than through the global flag.
    const saved_opt = ir_mod.optimize_enabled;
    ir_mod.optimize_enabled = !no_opt;
    defer ir_mod.optimize_enabled = saved_opt;

    crash.noteFile(path);

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    var exit: u8 = 0;
    while (r.hasMore() catch |err| return reportRead(&r, path, err)) {
        crash.noteStage(.reading);
        var expr = r.readDatum() catch |err| return reportRead(&r, path, err);
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();
        crash.noteStage(.compiling); // lowering to IR
        irTopLevel(vm, expr, path, &exit);
    }
    return exit;
}

fn irTopLevel(vm: *VM, expr: Value, path: []const u8, exit: *u8) void {
    // Splice top-level begin so each spliced form is lowered on its own, and an
    // interior define-syntax registers before a later sibling's use.
    if (headIs(expr, "begin")) {
        var rest = types.cdr(expr);
        while (types.isPair(rest)) : (rest = types.cdr(rest)) {
            irTopLevel(vm, types.car(rest), path, exit);
        }
        return;
    }

    // Macro-importing forms have no expression IR and must be run so later
    // macro uses lower to a `passthrough` node instead of a spurious call — the
    // same forms `expand` runs. `define-record-type` is *not* here: it lowers to
    // a passthrough node on its own, so it needs no execution to appear.
    if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
        const name = types.symbolName(types.car(expr));
        if (std.mem.eql(u8, name, "import") or
            std.mem.eql(u8, name, "define-library") or
            std.mem.eql(u8, name, "include") or
            std.mem.eql(u8, name, "include-ci"))
        {
            if (vm.handleTopLevelForm(expr)) |result| {
                _ = result catch {};
                clearErr(vm);
            }
            printEnvNote(name);
            return;
        }
        // Register a define-syntax transformer so later macro uses lower to a
        // `passthrough` node rather than a spurious call to an unbound global.
        if (std.mem.eql(u8, name, "define-syntax")) {
            _ = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, 0, path, false) catch {};
        }
    }

    lowerAndPrint(vm, expr, exit);
}

fn lowerAndPrint(vm: *VM, expr: Value, exit: *u8) void {
    // Freeze collection: IR nodes live in the C heap but reference GC Values
    // (folded constants allocated by the passes among them), and nothing roots
    // those until they are printed just below.
    vm.gc.no_collect += 1;
    defer vm.gc.no_collect -= 1;

    var ir = ir_mod.IR.init(vm.gc.allocator);
    ir.globals = vm.globals;
    defer ir.deinit();

    const node = ir_mod.lowerAndOptimize(&ir, expr, &vm.macros, false) catch |err| {
        var buf: [128]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "; lower error: {s}\n", .{@errorName(err)}) catch "; lower error\n";
        writeStdout(s);
        exit.* = 1;
        return;
    };

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(vm.gc.allocator);
    printNode(&out, vm.gc.allocator, node, 0) catch {
        writeStdout("; (out of memory formatting IR)\n");
        return;
    };
    out.append(vm.gc.allocator, '\n') catch {};
    writeStdout(out.items);
}

/// Render an IR node as an indented S-expression. Fully-lowered forms show their
/// child node structure; forms the compiler delegates as raw S-expressions
/// (let, cond, define bodies, macro uses …) show that S-expression, matching the
/// two node categories in `docs/dev/ir.md`.
fn printNode(out: *std.ArrayList(u8), a: std.mem.Allocator, node: *const Node, indent: usize) error{OutOfMemory}!void {
    switch (node.tag) {
        .constant => {
            try out.appendSlice(a, "(constant ");
            try appendValue(out, a, node.data.constant);
            try out.append(a, ')');
        },
        .global_ref => {
            try out.appendSlice(a, "(global-ref ");
            try appendValue(out, a, node.data.global_ref);
            try out.append(a, ')');
        },
        .call => {
            try openTag(out, a, "call", node);
            try printChild(out, a, node.data.call.operator, indent);
            for (node.data.call.args) |arg| try printChild(out, a, arg, indent);
            try out.append(a, ')');
        },
        .@"if" => {
            try openTag(out, a, "if", node);
            try printChild(out, a, node.data.@"if".test_expr, indent);
            try printChild(out, a, node.data.@"if".consequent, indent);
            if (node.data.@"if".alternate) |alt| try printChild(out, a, alt, indent);
            try out.append(a, ')');
        },
        .begin => try printSeq(out, a, "begin", node, node.data.begin, indent),
        .and_form => try printSeq(out, a, "and", node, node.data.and_form, indent),
        .or_form => try printSeq(out, a, "or", node, node.data.or_form, indent),
        .when_form => {
            try openTag(out, a, "when", node);
            try printChild(out, a, node.data.when_form.test_expr, indent);
            for (node.data.when_form.body) |b| try printChild(out, a, b, indent);
            try out.append(a, ')');
        },
        .unless_form => {
            try openTag(out, a, "unless", node);
            try printChild(out, a, node.data.unless_form.test_expr, indent);
            for (node.data.unless_form.body) |b| try printChild(out, a, b, indent);
            try out.append(a, ')');
        },
        .define => {
            try out.appendSlice(a, "(define ");
            try appendValue(out, a, node.data.define.name);
            try out.append(a, ' ');
            try appendValue(out, a, node.data.define.value);
            try out.append(a, ')');
        },
        .set_form => {
            try out.appendSlice(a, "(set! ");
            try appendValue(out, a, node.data.set_form.name);
            try out.append(a, ' ');
            try appendValue(out, a, node.data.set_form.value);
            try out.append(a, ')');
        },
        .lambda => {
            try out.appendSlice(a, "(lambda ");
            try appendValue(out, a, node.data.lambda.args);
            if (node.data.lambda.name) |nm| {
                try out.appendSlice(a, "  ; name=");
                try out.appendSlice(a, nm);
            }
            try out.append(a, ')');
        },
        .let_form => try printLet(out, a, "let", node.data.let_form.args),
        .let_star => try printLet(out, a, "let*", node.data.let_star.args),
        .letrec => try printLet(out, a, "letrec", node.data.letrec.args),
        .letrec_star => try printLet(out, a, "letrec*", node.data.letrec_star.args),
        .sexpr_form => {
            try out.appendSlice(a, "(sexpr-form ");
            try out.appendSlice(a, node.data.sexpr_form.form.keyword());
            try out.append(a, ' ');
            try appendValue(out, a, node.data.sexpr_form.args);
            try out.append(a, ')');
        },
        .passthrough => {
            try out.appendSlice(a, "(passthrough ");
            try appendValue(out, a, node.data.passthrough);
            try out.append(a, ')');
        },
    }
}

fn printSeq(out: *std.ArrayList(u8), a: std.mem.Allocator, tag: []const u8, node: *const Node, children: []const *Node, indent: usize) error{OutOfMemory}!void {
    try openTag(out, a, tag, node);
    for (children) |c| try printChild(out, a, c, indent);
    try out.append(a, ')');
}

fn printLet(out: *std.ArrayList(u8), a: std.mem.Allocator, tag: []const u8, args: Value) error{OutOfMemory}!void {
    try out.append(a, '(');
    try out.appendSlice(a, tag);
    try out.append(a, ' ');
    try appendValue(out, a, args);
    try out.append(a, ')');
}

/// Write `(tag` plus a `; tail` marker when the node is in tail position.
fn openTag(out: *std.ArrayList(u8), a: std.mem.Allocator, tag: []const u8, node: *const Node) error{OutOfMemory}!void {
    try out.append(a, '(');
    try out.appendSlice(a, tag);
    if (node.ann.is_tail) try out.appendSlice(a, "  ; tail");
}

fn printChild(out: *std.ArrayList(u8), a: std.mem.Allocator, child: *const Node, indent: usize) error{OutOfMemory}!void {
    try out.append(a, '\n');
    try indentTo(out, a, indent + 1);
    try printNode(out, a, child, indent + 1);
}

fn indentTo(out: *std.ArrayList(u8), a: std.mem.Allocator, indent: usize) error{OutOfMemory}!void {
    var i: usize = 0;
    while (i < indent) : (i += 1) try out.appendSlice(a, "  ");
}

fn appendValue(out: *std.ArrayList(u8), a: std.mem.Allocator, val: Value) error{OutOfMemory}!void {
    const s = printer.valueToString(a, val, .write) catch return error.OutOfMemory;
    defer a.free(s);
    try out.appendSlice(a, s);
}

fn printEnvNote(head: []const u8) void {
    var buf: [128]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "; ({s} …) — processed for environment (no IR)\n", .{head}) catch "; processed for environment (no IR)\n";
    writeStdout(s);
}

// ── Shared helpers ────────────────────────────────────────────────────────────

fn readSource(allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
    return file_utils.readWholeFile(allocator, path, 4 * 1024 * 1024) catch {
        writeStderr("kaappi: cannot read '");
        writeStderr(path);
        writeStderr("'\n");
        return null;
    };
}

fn dirOf(path: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
}

fn printDatum(allocator: std.mem.Allocator, value: Value) void {
    const s = printer.valueToString(allocator, value, .write) catch {
        writeStdout("; (unprintable datum)\n");
        return;
    };
    defer allocator.free(s);
    writeStdout(s);
    writeStdout("\n");
}

fn reportRead(r: *reader.Reader, path: []const u8, err: anyerror) u8 {
    const lc = r.getLineCol();
    toplevel_driver.reportReadError(path, lc.line, lc.col, err);
    return 1;
}

/// A processed env-setup form may have raised (e.g. an unknown import) and
/// stashed error detail on the VM; clear it so it never bleeds into a later
/// report. The form's failure does not fail the dump — the point is to show the
/// program, not to run it.
fn clearErr(vm: *VM) void {
    vm.last_error_detail_len = 0;
    vm.last_error_code = .uncategorized;
}

fn headIs(expr: Value, name: []const u8) bool {
    return types.isPair(expr) and types.isSymbol(types.car(expr)) and
        std.mem.eql(u8, types.symbolName(types.car(expr)), name);
}

fn streq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

// ── Test hooks ────────────────────────────────────────────────────────────────

/// Fully expand one already-read form (any macros it uses must be registered in
/// `vm.macros`). Wraps the same collection freeze the CLI path uses.
pub fn expandFormForTest(vm: *VM, expr: Value) Value {
    vm.gc.no_collect += 1;
    defer vm.gc.no_collect -= 1;
    return expandForm(vm, expr, 0) catch expr;
}

/// Lower one form and return its printed IR tree (caller frees with `a`).
/// `no_opt` selects the pre-optimization tree.
pub fn lowerFormToStringForTest(vm: *VM, a: std.mem.Allocator, expr: Value, no_opt: bool) ![]u8 {
    const saved = ir_mod.optimize_enabled;
    ir_mod.optimize_enabled = !no_opt;
    defer ir_mod.optimize_enabled = saved;

    vm.gc.no_collect += 1;
    defer vm.gc.no_collect -= 1;

    var ir = ir_mod.IR.init(a);
    ir.globals = vm.globals;
    defer ir.deinit();
    const node = try ir_mod.lowerAndOptimize(&ir, expr, &vm.macros, false);

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    try printNode(&out, a, node, 0);
    return out.toOwnedSlice(a);
}
