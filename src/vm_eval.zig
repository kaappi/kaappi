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
// `func` must already be GC-rooted by the caller (both call sites root it), so
// the `allocClosure` here — which may collect — cannot free it.
fn runTopLevelFunction(vm: *VM, func: *types.Function) VMError!Value {
    if (vm.frame_count == 0) return vm.execute(func);
    const closure_val = try vm.gc.allocClosure(func);
    return vm.callWithArgs(closure_val, &.{});
}

pub fn eval(vm: *VM, source: []const u8) VMError!Value {
    vm_mod.setVMInstance(vm);
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

pub fn handleTopLevelForm(vm: *VM, expr: Value) ?VMError!Value {
    if (!types.isPair(expr)) return null;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return null;
    const name = types.symbolName(head);

    // Root the form across the handlers: import/define-library load, compile,
    // and execute entire libraries (GC runs many times) while still walking
    // this datum, and most callers pass a freshly read, unrooted expr. Without
    // this, the import form itself can be swept mid-walk (issue #1010).
    var expr_root = expr;
    vm.gc.pushRoot(&expr_root);
    defer vm.gc.popRoot();

    if (std.mem.eql(u8, name, "import")) return vm_library.handleImport(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "define-library")) return vm_library.handleDefineLibrary(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "define-record-type")) return vm_records.handleDefineRecordType(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "define-values")) return handleDefineValues(vm, types.cdr(expr));
    if (std.mem.eql(u8, name, "include")) return vm_library.handleTopLevelInclude(vm, types.cdr(expr), false);
    if (std.mem.eql(u8, name, "include-ci")) return vm_library.handleTopLevelInclude(vm, types.cdr(expr), true);

    // R7RS 5.1: top-level begin splices its body as top-level forms
    if (std.mem.eql(u8, name, "begin")) return handleTopLevelBegin(vm, types.cdr(expr));

    // R7RS 4.2.1: a top-level cond-expand expands to the selected clause's forms
    // in a top-level context, so its body may contain declarations (import,
    // define-library, ...) that only work at top level (#1661).
    if (std.mem.eql(u8, name, "cond-expand")) return handleTopLevelCondExpand(vm, types.cdr(expr));

    return null;
}

// Predicate mirror of the dispatch chain in handleTopLevelForm: true for the
// top-level-only forms that eval() interprets specially rather than compiling
// to a single reusable Function. compileCachedForm (#1494) consults this to
// decline caching such a form — the caller falls back to a plain eval(). Keep
// this list in sync with handleTopLevelForm above.
fn isSpecialTopLevelForm(expr: Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (!types.isSymbol(head)) return false;
    const name = types.symbolName(head);
    return std.mem.eql(u8, name, "import") or
        std.mem.eql(u8, name, "define-library") or
        std.mem.eql(u8, name, "define-record-type") or
        std.mem.eql(u8, name, "define-values") or
        std.mem.eql(u8, name, "include") or
        std.mem.eql(u8, name, "include-ci") or
        std.mem.eql(u8, name, "begin") or
        std.mem.eql(u8, name, "cond-expand");
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

    if (isSpecialTopLevelForm(expr)) return VMError.CompileError;
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
    var rest = body;
    while (types.isPair(rest)) {
        const form = types.car(rest);
        if (handleTopLevelForm(vm, form)) |result| {
            last = result catch |err| return err;
        } else {
            const func = compiler_mod.compileExpressionWithMacros(vm.gc, form, &vm.macros, vm.globals) catch return VMError.CompileError;
            var func_val = types.makePointer(&func.header);
            vm.gc.pushRoot(&func_val);
            defer vm.gc.popRoot();
            compiler_mod.Compiler.unrootFunction(vm.gc, func);
            last = vm.execute(func) catch |err| return err;
        }
        rest = types.cdr(rest);
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
// that handleTopLevelBegin performs. No clause matching yields void, matching
// the expression-position compiler (compiler_conditionals.compileCondExpand).
fn handleTopLevelCondExpand(vm: *VM, clauses_val: Value) VMError!Value {
    var clauses = clauses_val;
    while (types.isPair(clauses)) {
        const clause = types.car(clauses);
        clauses = types.cdr(clauses);
        if (!types.isPair(clause)) return VMError.CompileError;
        const feature_req = types.car(clause);
        const is_else = types.isSymbol(feature_req) and std.mem.eql(u8, types.symbolName(feature_req), "else");
        if (is_else or vm_library.evalLibFeatureReq(vm, feature_req)) {
            return handleTopLevelBegin(vm, types.cdr(clause));
        }
    }
    return types.VOID;
}

fn handleDefineValues(vm: *VM, args: Value) VMError!Value {
    if (!types.isPair(args)) return VMError.CompileError;
    var formals = types.car(args);
    vm.gc.pushRoot(&formals);
    defer vm.gc.popRoot();
    const rest = types.cdr(args);
    if (!types.isPair(rest)) return VMError.CompileError;
    const expr = types.car(rest);

    const func = compiler_mod.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch return VMError.CompileError;
    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);
    defer vm.gc.popRoot();
    compiler_mod.Compiler.unrootFunction(vm.gc, func);
    const result = vm.execute(func) catch |err| return err;

    if (types.isMultipleValues(result)) {
        const mv = types.toObject(result).as(types.MultipleValues);
        if (types.isSymbol(formals)) {
            // (define-values x (values 1 2 3)) → x = (1 2 3)
            var result_root = result;
            vm.gc.pushRoot(&result_root);
            defer vm.gc.popRoot();
            var list: Value = types.NIL;
            vm.gc.pushRoot(&list);
            defer vm.gc.popRoot();
            const mv2 = types.toObject(result_root).as(types.MultipleValues);
            var j: usize = mv2.values.len;
            while (j > 0) {
                j -= 1;
                list = vm.gc.allocPair(mv2.values[j], list) catch return VMError.OutOfMemory;
            }
            vm.defineGlobal(types.symbolName(formals), list) catch return VMError.OutOfMemory;
        } else {
            var formal = formals;
            var i: usize = 0;
            var has_rest = false;
            while (formal != types.NIL and i < mv.values.len) {
                if (types.isSymbol(formal)) {
                    // Rest parameter: (define-values (a b . rest) ...)
                    has_rest = true;
                    var result_root = result;
                    vm.gc.pushRoot(&result_root);
                    defer vm.gc.popRoot();
                    var rest_list: Value = types.NIL;
                    vm.gc.pushRoot(&rest_list);
                    defer vm.gc.popRoot();
                    const mv2 = types.toObject(result_root).as(types.MultipleValues);
                    var j: usize = mv2.values.len;
                    while (j > i) {
                        j -= 1;
                        rest_list = vm.gc.allocPair(mv2.values[j], rest_list) catch return VMError.OutOfMemory;
                    }
                    vm.defineGlobal(types.symbolName(formal), rest_list) catch return VMError.OutOfMemory;
                    formal = types.NIL;
                    i = mv.values.len;
                    break;
                }
                if (!types.isPair(formal)) return VMError.CompileError;
                const var_sym = types.car(formal);
                if (!types.isSymbol(var_sym)) return VMError.CompileError;
                vm.defineGlobal(types.symbolName(var_sym), mv.values[i]) catch return VMError.OutOfMemory;
                formal = types.cdr(formal);
                i += 1;
            }
            if (!has_rest) {
                if (types.isPair(formal)) return VMError.CompileError;
                if (i < mv.values.len and formal == types.NIL) return VMError.CompileError;
            }
        }
    } else {
        if (types.isSymbol(formals)) {
            // (define-values x expr) → x = (result)
            var result_root = result;
            vm.gc.pushRoot(&result_root);
            defer vm.gc.popRoot();
            const list = vm.gc.allocPair(result_root, types.NIL) catch return VMError.OutOfMemory;
            vm.defineGlobal(types.symbolName(formals), list) catch return VMError.OutOfMemory;
        } else if (types.isPair(formals)) {
            const var_sym = types.car(formals);
            if (types.isSymbol(var_sym)) {
                vm.defineGlobal(types.symbolName(var_sym), result) catch return VMError.OutOfMemory;
                const next = types.cdr(formals);
                if (types.isSymbol(next)) {
                    vm.defineGlobal(types.symbolName(next), types.NIL) catch return VMError.OutOfMemory;
                }
            }
        }
    }
    return types.VOID;
}
