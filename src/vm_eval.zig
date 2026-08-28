const std = @import("std");
const types = @import("types.zig");
const compiler_mod = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const vm_library = @import("vm_library.zig");
const vm_records = @import("vm_records.zig");
const Value = types.Value;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

// Run a compiled top-level Function (an expression thunk), re-entrant-safely.
//
// At true top level (`frame_count == 0`) this is `vm.execute`, which resets the
// execution state and runs the form from frame 0. But since #1500 a natively
// compiled function is bound to a native closure *value*; when such a value is
// itself invoked from inside an outer `vm.execute` (e.g. `(define p (g0 5))`
// eval'd at top level runs the native `@g0` under the VM's CALL dispatch), and
// `@g0`'s body reaches an eval/quote fallback, that fallback lands back here
// with the outer form still suspended on frame 0. A nested `vm.execute` would
// `resetExecutionState` and overwrite frame 0's registers, corrupting the outer
// run. Detect the active execution and run the thunk through the same
// re-entrant path native callbacks use (`callWithArgs` pushes a frame above the
// current ones and returns when it unwinds), leaving the outer execution intact.
//
// `func` must already be GC-rooted by the caller (all call sites root it), so
// the `allocClosure` here — which may collect — cannot free it.
//
// This is the single re-entrant-safe way to run a compiled top-level thunk;
// every nested-entry caller (library loading, top-level begin/cond-expand
// splicing, define-values, define-record-type expansion, top-level include)
// must use it rather than a bare vm.execute — a bare one would
// resetExecutionState and abandon the enclosing form mid-flight (#2012).
pub fn runTopLevelFunction(vm: *VM, func: *types.Function) VMError!Value {
    if (vm.frame_count == 0) return vm.execute(func);
    const closure_val = try vm.gc.allocClosure(func);
    return vm.callWithArgs(closure_val, &.{});
}

pub fn eval(vm: *VM, source: []const u8) VMError!Value {
    vm_mod.setVMInstance(vm);
    // Outermost boundary for a source string (#1855): unwind the GC root
    // stack if the error escapes. The compile boundary
    // (compileExpression*) covers everything reached through the compiler;
    // this covers the rest — the reader and the top-level-only handlers
    // (import/define-library/define-record-type/...), which push roots of
    // their own. Registered before the per-form `defer popRoot()`s below, so
    // it fires last and has the final say on the depth even when an earlier
    // leak made those pops remove the wrong entries.
    const root_depth = vm.gc.root_count;
    errdefer vm.gc.truncateRoots(root_depth);
    const reader_mod = @import("reader.zig");
    var reader = reader_mod.Reader.init(vm.gc, source);
    defer reader.deinit();

    var last_result: Value = types.VOID;
    while (reader.hasMore() catch return VMError.CompileError) {
        var expr = reader.readDatum() catch return VMError.CompileError;
        // Root the form: evaluating it (e.g. an import that loads a library)
        // can trigger GC, which would otherwise reclaim the AST mid-walk.
        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();
        if (handleTopLevelForm(vm, expr)) |result| {
            last_result = result catch |err| return err;
            continue;
        }
        const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch return VMError.CompileError;
        {
            var func_val = types.makePointer(&func.header);
            vm.gc.pushRoot(&func_val);
            defer vm.gc.popRoot();
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            last_result = runTopLevelFunction(vm, func) catch |err| return err;
        }
    }
    return last_result;
}

/// The eight top-level heads `handleTopLevelForm` claims: forms `eval()`
/// interprets directly instead of compiling to a reusable Function.
///
/// This enum is the single source of truth for that set. Four consumers read
/// it — the dispatch chain in `runTopLevelHead` (an exhaustive `switch`, so a
/// new head cannot reach the VM without a handler), the `.sbc` cache's decline
/// predicate `isSpecialTopLevelForm`, `--timings`' "not cached: ..." reason,
/// and `check.zig`'s env-setup allowlist. Until #2114 those were four
/// hand-kept lists, and `--timings` reported every one of them as `imports`.
pub const TopLevelHead = enum {
    import,
    define_library,
    define_record_type,
    define_values,
    include,
    include_ci,
    begin,
    cond_expand,

    pub fn keyword(self: TopLevelHead) []const u8 {
        return switch (self) {
            .import => "import",
            .define_library => "define-library",
            .define_record_type => "define-record-type",
            .define_values => "define-values",
            .include => "include",
            .include_ci => "include-ci",
            .begin => "begin",
            .cond_expand => "cond-expand",
        };
    }

    pub fn fromKeyword(name: []const u8) ?TopLevelHead {
        inline for (@typeInfo(TopLevelHead).@"enum".fields) |f| {
            const cand: TopLevelHead = @enumFromInt(f.value);
            if (std.mem.eql(u8, name, comptime cand.keyword())) return cand;
        }
        return null;
    }

    /// Static string naming this head in `--timings`' "not cached: ..." line.
    /// Every one of the eight disables the `.sbc` cache for the same reason:
    /// `handleTopLevelForm` consumes the form and appends no Function to the
    /// run's `compiled_funcs`, so a HIT — which compiles nothing — would skip
    /// the form's work entirely. See `docs/dev/cache.md`.
    pub fn cacheReason(self: TopLevelHead) []const u8 {
        return switch (self) {
            inline else => |h| "top-level " ++ comptime h.keyword(),
        };
    }

    /// Whether a *compile-only* driver has to evaluate this head for real.
    /// True for the declarations that establish the environment later forms
    /// are compiled against — `import`/`include`/`include-ci`/`define-library`
    /// bring in bindings, macros and library code, and `define-record-type`
    /// registers a type. False for the rest, whose bodies are ordinary program
    /// code a compile-only command must never run (#2156): `begin` and
    /// `cond-expand` splice (see `topLevelSpliceBody`), and `define-values`
    /// only needs its *names*, never its producer expression's effects.
    pub fn isEnvSetup(self: TopLevelHead) bool {
        return switch (self) {
            .import, .define_library, .include, .include_ci, .define_record_type => true,
            .define_values, .begin, .cond_expand => false,
        };
    }
};

/// The `TopLevelHead` claiming `expr`, or null if `eval` would compile it as an
/// ordinary expression. Callers that then dispatch should pass the result to
/// `runTopLevelHead` rather than re-deriving it: evaluating one form (an
/// `import` bringing a shadowing macro into scope) can change the answer for
/// the next, so the two must be read from the same moment.
pub fn topLevelHead(vm: *VM, expr: Value) ?TopLevelHead {
    if (!types.isPair(expr)) return null;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return null;
    const found = TopLevelHead.fromKeyword(types.symbolName(head)) orelse return null;

    // R7RS has no reserved words: an imported macro may shadow a special
    // form keyword (compiler.zig's compileForm already honors this for
    // every non-top-level use, e.g. SRFI-219 redefining `define` -- see
    // its own comment). SRFI 136/131/57 each define their own
    // define-record-type macro (extended record-type syntax reusing the
    // same name); when one is in scope, report no head at all so the form
    // reaches ordinary macro-aware compilation, exactly like every other
    // top-level form does.
    if (found == .define_record_type and isMacroShadowed(vm, "define-record-type")) return null;
    return found;
}

pub fn handleTopLevelForm(vm: *VM, expr: Value) ?VMError!Value {
    const head = topLevelHead(vm, expr) orelse return null;
    return runTopLevelHead(vm, head, expr);
}

/// Evaluate a form already classified by `topLevelHead`.
pub fn runTopLevelHead(vm: *VM, head: TopLevelHead, expr: Value) VMError!Value {
    // Root the form across the handlers: import/define-library load, compile,
    // and execute entire libraries (GC runs many times) while still walking
    // this datum, and most callers pass a freshly read, unrooted expr. Without
    // this, the import form itself can be swept mid-walk (issue #1010).
    var expr_root = expr;
    vm.gc.pushRoot(&expr_root);
    defer vm.gc.popRoot();

    const args = types.cdr(expr);
    return switch (head) {
        .import => vm_library.handleImport(vm, args),
        .define_library => vm_library.handleDefineLibrary(vm, args),
        .define_record_type => vm_records.handleDefineRecordType(vm, args),
        .define_values => handleDefineValues(vm, args),
        .include => vm_library.handleTopLevelInclude(vm, args, false),
        .include_ci => vm_library.handleTopLevelInclude(vm, args, true),
        // R7RS 5.1: top-level begin splices its body as top-level forms.
        .begin => handleTopLevelBegin(vm, args),
        // R7RS 4.2.1: a top-level cond-expand expands to the selected clause's
        // forms in a top-level context, so its body may contain declarations
        // (import, define-library, ...) that only work at top level (#1661).
        .cond_expand => handleTopLevelCondExpand(vm, args),
    };
}

/// The forms a top-level `begin` or `cond-expand` splices into the enclosing
/// top-level sequence, or null when `expr` is neither. The returned list is a
/// sublist of `expr`, so a single root over `expr` keeps it alive.
///
/// This is the *non-evaluating* half of what `runTopLevelHead` does for those
/// two heads, for drivers that must compile a body rather than run it: only a
/// `cond-expand`'s branch **selection** is a compile-time question, its body is
/// ordinary program code. `kaappi --compile` and `--disassemble` route every
/// claimed head through the evaluator, so `(begin (delete-file "x"))` deleted
/// the file while producing the `.sbc` — and again at run time from the
/// recorded preamble (#2156).
pub fn topLevelSpliceBody(vm: *VM, expr: Value) ?VMError!Value {
    const head = topLevelHead(vm, expr) orelse return null;
    switch (head) {
        .begin => return types.cdr(expr),
        .cond_expand => return selectCondExpandBody(vm, types.cdr(expr)),
        else => return null,
    }
}

// Whether `name` is shadowed by a macro in the currently-relevant scope: the
// active library's own env when compiling a library body, else the
// process-global macro table at true top level. Using vm.macros
// unconditionally here would let one program's own special-form-shadowing
// macro (imported into vm.globals, hence vm.macros) silently affect how a
// completely unrelated library's top-level forms are dispatched later in
// the same process (#1718) -- current_lib_env is what the library's own
// define-syntax/import bindings actually land in (see compileLibExpr's
// lib_macros), so it's the only scope that matters while compiling that
// library's body.
fn isMacroShadowed(vm: *VM, name: []const u8) bool {
    if (vm.current_lib_env) |env| {
        return if (env.get(name)) |v| types.isTransformer(v) else false;
    }
    return vm.macros.get(name) != null;
}

// True for the top-level-only forms that eval() interprets specially rather
// than compiling to a single reusable Function. compileCachedForm (#1494)
// consults this to decline caching such a form — the caller falls back to a
// plain eval(). Derived from TopLevelHead, so it can no longer drift from the
// dispatch chain the way the hand-kept mirror it replaced had (#2114).
fn isSpecialTopLevelForm(vm: *VM, expr: Value) bool {
    return topLevelHead(vm, expr) != null;
}

/// Compile a single expression for the native eval-fallback cache (#1494):
/// parse exactly one datum from `source`, compile it, and return the resulting
/// Function wrapped as a Value that is permanently GC-rooted. The native
/// call-site slot that holds the returned value is invisible to the collector,
/// so the Function must be kept alive independently for the program's lifetime.
///
/// Returns CompileError — signaling the caller to fall back to a plain,
/// uncached eval() — when `source` is not a single compilable expression: it is
/// empty, carries a trailing second datum, or is a special top-level form
/// (import, define-library, ...) that eval() must interpret rather than
/// compile. The emitter's code fallbacks never produce those in practice; the
/// checks keep the cache correct if one ever does.
pub fn compileCachedForm(vm: *VM, source: []const u8) VMError!Value {
    vm_mod.setVMInstance(vm);
    const reader_mod = @import("reader.zig");
    var reader = reader_mod.Reader.init(vm.gc, source);
    defer reader.deinit();

    if (!(reader.hasMore() catch return VMError.CompileError)) return VMError.CompileError;
    var expr = reader.readDatum() catch return VMError.CompileError;
    vm.gc.pushRoot(&expr);
    defer vm.gc.popRoot();

    if (isSpecialTopLevelForm(vm, expr)) return VMError.CompileError;
    if (reader.hasMore() catch return VMError.CompileError) return VMError.CompileError;

    const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch return VMError.CompileError;
    const func_val = types.makePointer(&func.header);
    // No GC-triggering allocation runs between the compile above and the
    // rootedSlot below (unrootFunction and rootedSlot only touch the
    // C-allocated extra_roots list), so `func` needs no interim shadow root.
    // eval() moves this Function to a transient shadow-stack root and drops the
    // compiler's extra_roots entry; the cache instead needs it alive for the
    // whole program, so drop the compiler's transient root and take an
    // explicit, permanent one of our own via extra_roots (which, unlike the
    // LIFO shadow stack, can hold a root indefinitely).
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    _ = vm.gc.rootedSlot(func_val) catch return VMError.OutOfMemory;
    return func_val;
}

/// Execute a Function previously produced by compileCachedForm. This is the
/// cache fast path: it runs the already-compiled form directly, skipping the
/// reader and compiler that plain eval() re-runs on every call.
pub fn runCachedForm(vm: *VM, func_val: Value) VMError!Value {
    return runTopLevelFunction(vm, types.toObject(func_val).as(types.Function));
}

fn handleTopLevelBegin(vm: *VM, body: Value) VMError!Value {
    var last: Value = types.VOID;
    // #2405 (CodeRabbit re-review): a cyclic top-level begin compiled and
    // executed its rotation forever — same guard as selectCondExpandBody,
    // reported through the VM's detail channel.
    var rest = compiler_mod.SpineWalk.init(body);
    while (types.isPair(rest.cur)) : (rest.next()) {
        if (rest.cyclic()) {
            vm.setErrorDetail("circular form in code position: the form contains itself (datum-label cycle)", .{});
            return VMError.CompileError;
        }
        const form = types.car(rest.cur);
        if (handleTopLevelForm(vm, form)) |result| {
            last = result catch |err| return err;
        } else {
            const func = compiler_mod.compileExpressionWithMacros(vm.gc, form, &vm.macros, vm.globals) catch return VMError.CompileError;
            var func_val = types.makePointer(&func.header);
            vm.gc.pushRoot(&func_val);
            defer vm.gc.popRoot();
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            // runTopLevelFunction, not vm.execute: a spliced top-level body can
            // be reached while an outer execution is suspended (eval re-entered
            // from a native callback, frame_count != 0). A bare vm.execute would
            // resetExecutionState and corrupt frame 0; runTopLevelFunction runs
            // the thunk re-entrantly in that case and is identical to vm.execute
            // at true top level. func is rooted above, as it requires.
            last = runTopLevelFunction(vm, func) catch |err| return err;
        }
    }
    return last;
}

// R7RS 4.2.1: evaluate a top-level cond-expand by selecting the first clause
// whose feature requirement holds (or the else clause) and splicing that
// clause's body as top-level forms — the same splicing handleTopLevelBegin
// does. This lets top-level-only declarations nested in a matched clause
// (import, define-library, define-record-type, ...) work, instead of the whole
// form being compiled as an expression where those aren't recognized (#1661).
//
// Clause selection reuses vm_library.evalLibFeatureReq (the live-registry
// evaluator define-library uses), so guards resolve identically in both
// contexts: else, (library (srfi N)), and the srfi-N feature ids (#1649).
//
// The caller (handleTopLevelForm) has the whole cond-expand form rooted, so the
// clause list and the selected body stay reachable across the compile/execute
// that handleTopLevelBegin performs.
//
// Malformed-form handling tracks the expression-position compiler
// (compiler_conditionals.compileCondExpand) so the same form errors the same way
// regardless of position: a non-pair where a clause is expected is a syntax
// error; a proper but unsatisfied list (no matching clause, no else) yields
// void; and — like the compiler — a matched clause returns immediately without
// inspecting later clauses, so trailing clauses after a match are not validated.
// Two structural cases need an explicit check because handleTopLevelBegin (shared
// with top-level begin) silently ignores improper tails while the compiler
// rejects them: an improper clause-list tail reached without a match (e.g.
// `(cond-expand (x 1) . junk)`), and an improper selected clause body (e.g.
// `(cond-expand (else 1 . junk))`). Both are validated here so cond-expand's own
// structure matches the compiler; begin's own leniency is left untouched.
fn handleTopLevelCondExpand(vm: *VM, clauses_val: Value) VMError!Value {
    // An unmatched cond-expand selects no body; splicing the empty list yields
    // void, exactly as returning void directly did.
    return handleTopLevelBegin(vm, try selectCondExpandBody(vm, clauses_val));
}

/// The selected clause's body, or nil when no clause matched. Split out of
/// `handleTopLevelCondExpand` so a compile-only driver can make the same
/// branch selection without running the body (#2156) — selection is the only
/// part of a `cond-expand` that is a compile-time question.
fn selectCondExpandBody(vm: *VM, clauses_val: Value) VMError!Value {
    // #2405: a datum-label cycle through the clause list with no matching
    // clause spun this walk forever — the compiler-side twin
    // (compiler_conditionals.compileCondExpand) is guarded; this top-level
    // selector needs the same tortoise-and-hare. The named diagnosis is
    // recorded through the compiler's detail channel so the reporter shows
    // the cause rather than a bare compile error.
    var clauses = compiler_mod.SpineWalk.init(clauses_val);
    while (types.isPair(clauses.cur)) : (clauses.next()) {
        if (clauses.cyclic()) {
            // Through the VM's own detail channel: this path reports via the
            // runtime reporter, which prefers the VM detail over the code's
            // registry template.
            vm.setErrorDetail("circular form in code position: the form contains itself (datum-label cycle)", .{});
            return VMError.CompileError;
        }
        const clause = types.car(clauses.cur);
        if (!types.isPair(clause)) return VMError.CompileError;
        const feature_req = types.car(clause);
        const is_else = types.isSymbol(feature_req) and std.mem.eql(u8, types.symbolName(feature_req), "else");
        if (is_else or vm_library.evalLibFeatureReq(vm, feature_req)) {
            const body = types.cdr(clause);
            if (!isProperList(body)) return VMError.CompileError;
            return body;
        }
    }
    if (clauses.cur != types.NIL) return VMError.CompileError;
    return types.NIL;
}

// A proper (nil-terminated) list? Used to reject improper clause bodies before
// splicing them, matching the compiler's rejection of the same malformed form.
// #2405: a cyclic body is not a proper list — spineCyclic bounds the walk.
fn isProperList(list: Value) bool {
    if (compiler_mod.spineCyclic(list)) return false;
    var rest = list;
    while (types.isPair(rest)) rest = types.cdr(rest);
    return rest == types.NIL;
}

fn handleDefineValues(vm: *VM, args: Value) VMError!Value {
    if (!types.isPair(args)) return VMError.CompileError;
    var formals = types.car(args);
    vm.gc.pushRoot(&formals);
    defer vm.gc.popRoot();
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return VMError.CompileError;
    const expr = types.car(rest);

    // Compile against a macro table scoped to the current library, not the
    // process-global vm.macros: unlike define-record-type's desugaring,
    // this initializer is user-authored code that legitimately needs to see
    // whatever macros are in scope here -- but ONLY here, not an unrelated
    // program's own special-form-shadowing macro sitting in vm.macros
    // (#1718). Mirrors compileLibExpr's own lib_macros pattern (#877).
    var scope_macros = if (vm.current_lib_env) |env| blk: {
        var m = std.StringHashMap(Value).init(vm.gc.allocator);
        var it = env.iterator();
        while (it.next()) |entry| {
            if (types.isTransformer(entry.value_ptr.*)) {
                m.put(entry.key_ptr.*, entry.value_ptr.*) catch return VMError.OutOfMemory;
            }
        }
        break :blk m;
    } else vm.macros;
    defer if (vm.current_lib_env != null) scope_macros.deinit();

    const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &scope_macros, vm.globals) catch return VMError.CompileError;
    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);
    defer vm.gc.popRoot();
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    const result = runTopLevelFunction(vm, func) catch |err| return err;

    // Root the producer's result across the pair allocations below.
    var result_root = result;
    vm.gc.pushRoot(&result_root);
    defer vm.gc.popRoot();

    // Normalize the produced values into a count. A non-`MultipleValues`
    // result is exactly one value (R7RS: an ordinary expression returns a
    // single value); `mvValueAt` re-derives the values array from the rooted
    // result each call so a collection during binding cannot leave it dangling.
    const is_mv = types.isMultipleValues(result_root);
    const value_count: usize = if (is_mv)
        types.toObject(result_root).as(types.MultipleValues).values.len
    else
        1;

    // A bare-identifier formals spec collects every produced value as a list,
    // with no arity constraint: (define-values x (values 1 2 3)) → x = (1 2 3).
    if (types.isSymbol(formals)) {
        var list: Value = types.NIL;
        vm.gc.pushRoot(&list);
        defer vm.gc.popRoot();
        var j: usize = value_count;
        while (j > 0) {
            j -= 1;
            list = vm.gc.allocPair(mvValueAt(result_root, is_mv, j), list) catch return VMError.OutOfMemory;
        }
        vm.defineGlobal(types.symbolName(formals), list) catch return VMError.OutOfMemory;
        return types.VOID;
    }

    // Fixed/dotted formals. Parse into a fixed count plus an optional dotted
    // rest, validating each position is a symbol (matching the compiler's
    // parseDefineValuesFormals). R7RS 5.3.3 / SRFI 244: the values are matched
    // to the formals exactly as a lambda matches call arguments — a fixed list
    // requires an exact count, a dotted list a minimum. Until #550 this
    // top-level handler bound a prefix and continued on a single-value
    // mismatch, unlike the compiler desugaring one scope in; check arity
    // *before* defining any global so a mismatch leaves no partial bindings and
    // raises the same KP3003 the internal call-with-values consumer lambda does.
    var fixed_count: usize = 0;
    var has_rest = false;
    {
        var formal = formals;
        while (formal != types.NIL) {
            if (types.isSymbol(formal)) {
                has_rest = true;
                break;
            }
            if (!types.isPair(formal)) return VMError.CompileError;
            if (!types.isSymbol(types.car(formal))) return VMError.CompileError;
            fixed_count += 1;
            formal = types.cdr(formal);
        }
    }

    if (has_rest) {
        if (value_count < fixed_count) {
            vm.setErrorDetail("expected at least {d} arguments, got {d}", .{ fixed_count, value_count });
            return VMError.ArityMismatch;
        }
    } else if (value_count != fixed_count) {
        vm.setErrorDetail("expected {d} arguments, got {d}", .{ fixed_count, value_count });
        return VMError.ArityMismatch;
    }

    // Bind the fixed formals, then the dotted rest (if any) as a list of the
    // leftover values.
    var formal = formals;
    var i: usize = 0;
    while (i < fixed_count) : (i += 1) {
        vm.defineGlobal(types.symbolName(types.car(formal)), mvValueAt(result_root, is_mv, i)) catch return VMError.OutOfMemory;
        formal = types.cdr(formal);
    }
    if (has_rest) {
        // `formal` now points at the dotted rest symbol.
        var rest_list: Value = types.NIL;
        vm.gc.pushRoot(&rest_list);
        defer vm.gc.popRoot();
        var j: usize = value_count;
        while (j > fixed_count) {
            j -= 1;
            rest_list = vm.gc.allocPair(mvValueAt(result_root, is_mv, j), rest_list) catch return VMError.OutOfMemory;
        }
        vm.defineGlobal(types.symbolName(formal), rest_list) catch return VMError.OutOfMemory;
    }
    return types.VOID;
}

/// The i-th produced value of a `define-values` result. Re-derives the
/// `MultipleValues` array from `result` on every call so the read stays valid
/// even if an intervening allocation collected — `result` must be GC-rooted by
/// the caller. A non-`MultipleValues` result is the single value itself.
inline fn mvValueAt(result: Value, is_mv: bool, i: usize) Value {
    if (is_mv) return types.toObject(result).as(types.MultipleValues).values[i];
    return result;
}
