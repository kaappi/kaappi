const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const ir_mod = @import("ir.zig");
const llvm_emit = @import("llvm_emit.zig");
const reader_mod = @import("reader.zig");
const native_decls = @import("native_decls.zig");

// The LLVMEmitter stores lambda function defs via toOwnedSlice that aren't
// individually freed on deinit (by design — production uses an arena).
// Use page_allocator for the emitter to avoid false leak reports.
const emitter_alloc = std.heap.page_allocator;

const EmitResult = struct {
    gc: memory.GC,
    ir_instance: ir_mod.IR,
    emitter: llvm_emit.LLVMEmitter,

    fn toSlice(self: *EmitResult) []const u8 {
        return self.emitter.toSlice();
    }

    fn deinit(self: *EmitResult) void {
        self.emitter.deinit();
        self.ir_instance.deinit();
        self.gc.deinit();
    }
};

fn emitSourceResult(source: []const u8) !EmitResult {
    var gc = memory.GC.init(emitter_alloc);
    errdefer gc.deinit();

    // Mirror emitLlvmFile: the IR references sexpr Values that nothing
    // roots, so defer collection across the read → lower → emit batch or a
    // gc-stress build frees them mid-emission (#1401). Balanced before the
    // return (a defer would decrement only after `gc` is copied out).
    gc.no_collect += 1;

    var reader = reader_mod.Reader.init(&gc, source);
    defer reader.deinit();
    const expr = try reader.readDatum();

    var ir_instance = ir_mod.IR.init(emitter_alloc);
    errdefer ir_instance.deinit();

    var root = try ir_mod.lower(&ir_instance, expr);
    ir_mod.markTailPositions(root, false);
    root = ir_mod.foldConstants(&ir_instance, root);
    root = ir_mod.eliminateDeadBranches(&ir_instance, root);
    root = ir_mod.simplifyBooleans(&ir_instance, root);
    root = ir_mod.eliminateIdentity(&ir_instance, root);
    root = ir_mod.simplifyBegin(&ir_instance, root);

    var nodes = [_]*ir_mod.Node{root};
    var emitter = llvm_emit.LLVMEmitter.init(emitter_alloc);
    errdefer emitter.deinit();
    try emitter.emitProgram(&nodes);

    gc.no_collect -= 1;
    return .{ .gc = gc, .ir_instance = ir_instance, .emitter = emitter };
}

fn emitMultiResult(source: []const u8) !EmitResult {
    return emitMultiResultOpts(source, true);
}

/// With `optimize` false, the five IR optimization passes are skipped —
/// callers must also clear `ir_mod.optimize_enabled` so closure-body
/// lowering inside the emitter (which calls lowerAndOptimize) skips them
/// too. Used by the fuzz gate for exact eval accounting: dead-branch
/// elimination legitimately deletes eval-fallback forms from constant-test
/// branches, so exact counts only hold on unoptimized emission.
fn emitMultiResultOpts(source: []const u8, optimize: bool) !EmitResult {
    var gc = memory.GC.init(emitter_alloc);
    errdefer gc.deinit();

    // See emitSourceResult: collection is deferred until emission is done.
    gc.no_collect += 1;

    var reader = reader_mod.Reader.init(&gc, source);
    defer reader.deinit();

    var ir_instance = ir_mod.IR.init(emitter_alloc);
    errdefer ir_instance.deinit();

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(emitter_alloc);

    while (try reader.hasMore()) {
        const expr = try reader.readDatum();
        var root = try ir_mod.lower(&ir_instance, expr);
        ir_mod.markTailPositions(root, false);
        if (optimize) {
            root = ir_mod.foldConstants(&ir_instance, root);
            root = ir_mod.eliminateDeadBranches(&ir_instance, root);
            root = ir_mod.simplifyBooleans(&ir_instance, root);
            root = ir_mod.eliminateIdentity(&ir_instance, root);
            root = ir_mod.simplifyBegin(&ir_instance, root);
        }
        try ir_nodes.append(emitter_alloc, root);
    }

    var emitter = llvm_emit.LLVMEmitter.init(emitter_alloc);
    errdefer emitter.deinit();
    try emitter.emitProgram(ir_nodes.items);

    gc.no_collect -= 1;
    return .{ .gc = gc, .ir_instance = ir_instance, .emitter = emitter };
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\n--- Expected to find ---\n{s}\n--- in output (len={d}) ---\n", .{ needle, haystack.len });
        return error.TestExpectedEqual;
    }
}

// -- Preamble and structure --

test "LLVM emit: preamble has target triple and runtime calls" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "target triple");
    try expectContains(ll, "define i32 @main()");
    try expectContains(ll, "@kaappi_runtime_init");
    try expectContains(ll, "@kaappi_runtime_deinit");
    try expectContains(ll, "ret i32 0");
}

test "LLVM emit: preamble declares runtime functions" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "declare ptr @kaappi_runtime_init()");
    try expectContains(ll, "declare i64 @kaappi_global_lookup(ptr, ptr, i64)");
    try expectContains(ll, "declare i64 @kaappi_call_scheme(ptr, i64, ptr, i64)");
    try expectContains(ll, "declare i64 @kaappi_fixnum_add(i64, i64)");
    try expectContains(ll, "declare i64 @kaappi_cons(i64, i64)");
    try expectContains(ll, "declare i64 @kaappi_car(i64)");
    try expectContains(ll, "declare i64 @kaappi_cdr(i64)");
}

// -- Constants --

test "LLVM emit: fixnum constant" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    try expectContains(res.toSlice(), "add i64 0,");
}

test "LLVM emit: string constant" {
    var res = try emitSourceResult(
        \\"hello"
    );
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "@kaappi_make_string");
    try expectContains(ll, "hello");
}

test "LLVM emit: boolean constants" {
    var res_t = try emitSourceResult("#t");
    defer res_t.deinit();
    try expectContains(res_t.toSlice(), "add i64 0,");

    var res_f = try emitSourceResult("#f");
    defer res_f.deinit();
    try expectContains(res_f.toSlice(), "add i64 0,");
}

// -- Global references --

test "LLVM emit: global reference" {
    var res = try emitSourceResult("display");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "@kaappi_global_lookup");
    try expectContains(ll, "display");
}

// -- Calls --

test "LLVM emit: general call emits kaappi_call_scheme" {
    var res = try emitSourceResult("(f 1 2)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_call_scheme");
}

test "LLVM emit: inline add" {
    var res = try emitSourceResult("(+ a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_add");
}

test "LLVM emit: inline sub" {
    var res = try emitSourceResult("(- a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_sub");
}

test "LLVM emit: inline mul" {
    var res = try emitSourceResult("(* a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_mul");
}

test "LLVM emit: inline car" {
    var res = try emitSourceResult("(car x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_car");
}

test "LLVM emit: inline cdr" {
    var res = try emitSourceResult("(cdr x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_cdr");
}

test "LLVM emit: inline cons" {
    var res = try emitSourceResult("(cons a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_cons");
}

test "LLVM emit: inline null?" {
    var res = try emitSourceResult("(null? x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_is_null");
}

// -- Control flow --

test "LLVM emit: if with else" {
    var res = try emitSourceResult("(if x 1 2)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "br i1");
    try expectContains(ll, "then");
    try expectContains(ll, "else");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: if without else" {
    var res = try emitSourceResult("(if x 1)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "br i1");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: and short-circuit" {
    var res = try emitSourceResult("(and x y)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "and_merge");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: or short-circuit" {
    var res = try emitSourceResult("(or x y)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "or_merge");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: when form" {
    var res = try emitSourceResult("(when x 42)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "when_body");
    try expectContains(ll, "when_merge");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: unless form" {
    var res = try emitSourceResult("(unless x 42)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "unless_body");
    try expectContains(ll, "unless_merge");
    try expectContains(ll, "phi i64");
}

// -- Definitions --

test "LLVM emit: define global" {
    var res = try emitSourceResult("(define x 42)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_define_global");
}

test "LLVM emit: set! global" {
    var res = try emitMultiResult("(define y 0) (set! y 1)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_set_global");
}

// -- Lambda --

test "LLVM emit: lambda as native closure" {
    var res = try emitSourceResult("(lambda (x) x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_create_native_closure");
}

// -- Let --

test "LLVM emit: let binding" {
    var res = try emitSourceResult("(let ((x 1)) x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "alloca i64");
}

test "LLVM emit: let* sequential" {
    var res = try emitSourceResult("(let* ((x 1) (y x)) y)");
    defer res.deinit();
    try expectContains(res.toSlice(), "alloca i64");
}

// -- Free variables hidden inside let/let* (#1407) --
// The closure tiers' free-variable analysis must descend into raw let/let*
// forms. Before the fix, a lambda capturing an enclosing param only through
// a let compiled as a *closed* native closure and the reference degraded to
// kaappi_global_lookup: "undefined variable" at runtime, or a silently wrong
// value when a same-named global existed.

test "LLVM emit: lambda capturing enclosing param through a let gets an upvalue (#1407)" {
    var res = try emitSourceResult("(define g0 (lambda (u) ((lambda (a) (let ((b u)) b)) 1)))");
    defer res.deinit();
    const ll = res.toSlice();
    // Tier 1 must capture `u`: closure created with one upvalue (arity 1)...
    try expectContains(ll, "@kaappi_create_native_closure");
    try expectContains(ll, ", i64 1, i64 1, ptr");
    // ...and the closure body must read it from the upvalue array.
    try expectContains(ll, "ptr %upvalues, i64 0");
    // The lambda-local name must never be interned for a global lookup.
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"u\"") == null);
}

test "LLVM emit: lambda capturing enclosing param through a let* gets an upvalue (#1407)" {
    var res = try emitSourceResult("(define g0 (lambda (u) ((lambda (a) (let* ((b u) (c b)) c)) 1)))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "@kaappi_create_native_closure");
    try expectContains(ll, ", i64 1, i64 1, ptr");
    try expectContains(ll, "ptr %upvalues, i64 0");
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"u\"") == null);
}

test "LLVM emit: top-level lambda with let-hidden free name falls back to eval (#1407)" {
    // With no enclosing scope to capture from, both closure tiers must
    // reject; emitLambdaViaEval resolves `u` in the global environment at
    // call time, which is correct at top level.
    var res = try emitSourceResult("(lambda (a) (let ((b u)) b))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "call i64 @kaappi_eval");
    try std.testing.expect(std.mem.indexOf(u8, ll, "call i64 @kaappi_create_native_closure") == null);
}

test "LLVM emit: let over own params still compiles as a closed native closure" {
    // Guard against over-conservatism: a let that only references the
    // lambda's own params has no free variables and must stay native.
    var res = try emitSourceResult("(lambda (a) (let ((b a)) b))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "call i64 @kaappi_create_native_closure");
    try std.testing.expect(std.mem.indexOf(u8, ll, "call i64 @kaappi_eval") == null);
}

// -- Enclosing bindings that shadow primitives (#1407 review) --
// The shadow check must outrank isKnownGlobal: a param named `car` is a
// capture, not the primitive. Before the fix these compiled as closed
// closures whose reference degraded to a global lookup, silently returning
// the builtin instead of the captured value.

test "LLVM emit: param shadowing a primitive is captured as an upvalue" {
    var res = try emitSourceResult("(define g0 (lambda (car) ((lambda () car))))");
    defer res.deinit();
    const ll = res.toSlice();
    // Tier 1 must capture `car`: one upvalue, arity 0...
    try expectContains(ll, "call i64 @kaappi_create_native_closure");
    try expectContains(ll, ", i64 1, i64 0, ptr");
    // ...read from the upvalue array, never interned for a global lookup.
    try expectContains(ll, "ptr %upvalues, i64 0");
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"car\"") == null);
}

test "LLVM emit: param shadowing a primitive is captured through a let" {
    var res = try emitSourceResult("(define g0 (lambda (car) ((lambda () (let ((x car)) x)))))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "call i64 @kaappi_create_native_closure");
    try expectContains(ll, ", i64 1, i64 0, ptr");
    try expectContains(ll, "ptr %upvalues, i64 0");
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"car\"") == null);
}

// -- Free variables hidden inside nested lambdas (#1410) --
// The closure tiers' free-variable analysis must also descend into nested
// .lambda IR nodes, and tier 1 must be able to chain a capture from the
// enclosing closure's %upvalues (not just its %args). Before the fix, a
// lambda whose only reference to an enclosing binding lived inside an inner
// lambda compiled as a *closed* closure and the inner lambda's eval fallback
// resolved the name globally: "undefined variable" at runtime.

test "LLVM emit: capture through a nested lambda chains upvalues natively (#1410)" {
    var res = try emitSourceResult("(define g0 (lambda (u) ((lambda (a) (lambda (c) u)) 1)))");
    defer res.deinit();
    const ll = res.toSlice();
    // Both the middle and the inner lambda become capturing native closures
    // (one upvalue, arity 1 each): the middle copies u from g0's %args, the
    // inner chains it out of the middle closure's %upvalues.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, ll, "call i64 @kaappi_create_native_closure(ptr %vm, ptr @closure_"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, ll, ", i64 1, i64 1, ptr"));
    try expectContains(ll, "getelementptr i64, ptr %upvalues, i64 0");
    // u must never degrade to a global lookup / interned symbol...
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"u\"") == null);
    // ...and nothing may fall back to eval beyond the define-time binding.
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, ll, "call i64 @kaappi_eval("));
}

test "LLVM emit: depth-3 nested capture chains through every closure level (#1410)" {
    var res = try emitSourceResult("(define g0 (lambda (u) (lambda (a) (lambda (b) (lambda (c) u)))))");
    defer res.deinit();
    const ll = res.toSlice();
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, ll, "call i64 @kaappi_create_native_closure(ptr %vm, ptr @closure_"));
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"u\"") == null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, ll, "call i64 @kaappi_eval("));
}

test "LLVM emit: capture through a let-wrapped nested lambda chains natively (#1410)" {
    var res = try emitSourceResult("(define g0 (lambda (u) ((lambda (a) (let ((b 1)) (lambda (c) u))) 1)))");
    defer res.deinit();
    const ll = res.toSlice();
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, ll, "call i64 @kaappi_create_native_closure(ptr %vm, ptr @closure_"));
    try std.testing.expect(std.mem.indexOf(u8, ll, "c\"u\"") == null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, ll, "call i64 @kaappi_eval("));
}

test "LLVM emit: eval fallback inside a native closure republishes upvalues (#1410)" {
    // The variadic inner lambda can never be a native closure (no tier
    // accepts a rest parameter), so it falls back to eval inside the middle
    // closure — and the fallback must first bind the captured u as a global.
    var res = try emitSourceResult("(define g0 (lambda (u) ((lambda (a) (lambda (c . r) u)) 1)))");
    defer res.deinit();
    const ll = res.toSlice();
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, ll, "call i64 @kaappi_create_native_closure(ptr %vm, ptr @closure_"));
    try expectContains(ll, "c\"u\"");
    try expectContains(ll, "@kaappi_define_global");
    try expectContains(ll, "getelementptr i64, ptr %upvalues, i64 0");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, ll, "call i64 @kaappi_eval("));
}

test "LLVM emit: eval fallback republishes the enclosing rest parameter (#1410)" {
    // The inner lambda captures the rest list, which no closure tier can
    // express; its eval fallback must bind xs (loaded from the rest-list
    // alloca) as a global, not just the fixed params.
    var res = try emitSourceResult("(define f (lambda (u . xs) (lambda (c) xs)))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "c\"xs\"");
    try expectContains(ll, "@kaappi_define_global");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, ll, "call i64 @kaappi_eval("));
}

test "LLVM emit: let eval fallback republishes enclosing params (#1410)" {
    // bodyHasCapturingLambda (#827) sends this let to the interpreter; the
    // fallback must bind u first or the binding init comes up undefined.
    var res = try emitSourceResult("(define (f u) (let ((b u)) (lambda (c) b)))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "c\"u\"");
    try expectContains(ll, "@kaappi_define_global");
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, ll, "call i64 @kaappi_eval("));
}

test "LLVM emit: lambda in a let binding init falls back instead of aborting (#1410)" {
    // Before the fix the init's emission error propagated out of emitLet and
    // aborted the whole native compilation (emitSourceResult here failed).
    var res = try emitSourceResult("(let ((b (lambda (c) glob))) (b 0))");
    defer res.deinit();
    try expectContains(res.toSlice(), "call i64 @kaappi_eval");
}

test "LLVM emit: abandoned native let pops the binding roots it pushed (#1410)" {
    // 17 params exceed the closure tiers' 16-param cap, so the let body's
    // lambda fails emission after the binding for b was emitted and rooted;
    // the fallback path must pop that root or every execution of the
    // enclosing function leaks a GC root slot.
    var res = try emitSourceResult("(define (f u) (let ((b 1)) (lambda (p1 p2 p3 p4 p5 p6 p7 p8 p9 p10 p11 p12 p13 p14 p15 p16 p17) p1)))");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "call void @kaappi_gc_push_root(");
    try expectContains(ll, "call void @kaappi_gc_pop_roots(i64 1)");
}

// -- Begin --

test "LLVM emit: begin sequence" {
    var res = try emitSourceResult("(begin a b c)");
    defer res.deinit();
    const ll = res.toSlice();
    const count = std.mem.count(u8, ll, "@kaappi_global_lookup");
    try std.testing.expect(count >= 3);
}

// -- Comparisons --

test "LLVM emit: inline less-than" {
    var res = try emitSourceResult("(< a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_lt");
}

test "LLVM emit: inline equal" {
    var res = try emitSourceResult("(= a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_eq");
}

// -- Declare table drift test --
// The comptime block in native_decls.zig validates that the table matches
// the actual Zig signatures in runtime_exports.zig. This test verifies
// the emitted preamble contains every declare from the table.

test "native declare table covers all runtime exports in preamble" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    const ll = res.toSlice();
    for (native_decls.decls) |d| {
        if (std.mem.indexOf(u8, ll, d.export_name) == null) {
            std.debug.print("\nmissing declare for {s}\n", .{d.export_name});
            return error.TestExpectedEqual;
        }
    }
    try std.testing.expectEqual(@as(usize, 21), native_decls.decls.len);
}

// -- NativeClosure dispatch tests (#1376) --
// Since #1374 map/for-each/dynamic-wind/force are bytecode closures
// (vm_bootstrap.zig), so bytecode must be able to invoke natively-compiled
// callbacks (NativeClosure) from every call path in the dispatch loop.
// These build a NativeClosure by hand (as kaappi_create_native_closure
// would) and drive it through each opcode/helper.

const th = @import("testing_helpers.zig");
const Value = types.Value;

fn ncDouble(_: ?*th.VM, args: [*]const Value, nargs: u64, _: [*]const Value) callconv(.c) u64 {
    std.debug.assert(nargs == 1);
    return types.makeFixnum(types.toFixnum(args[0]) * 2);
}

fn ncAddUpvalue(_: ?*th.VM, args: [*]const Value, nargs: u64, upvalues: [*]const Value) callconv(.c) u64 {
    std.debug.assert(nargs == 1);
    return types.makeFixnum(types.toFixnum(args[0]) + types.toFixnum(upvalues[0]));
}

fn ncFortyTwo(_: ?*th.VM, _: [*]const Value, _: u64, _: [*]const Value) callconv(.c) u64 {
    return types.makeFixnum(42);
}

fn ncIgnoreArg(_: ?*th.VM, _: [*]const Value, nargs: u64, _: [*]const Value) callconv(.c) u64 {
    std.debug.assert(nargs == 1);
    return types.makeFixnum(7);
}

fn setupNativeClosures(ctx: *th.TestContext) !void {
    try ctx.vm.defineGlobal("nc-double", try ctx.gc.allocNativeClosure(&ncDouble, &.{}, 1, "nc-double"));
    try ctx.vm.defineGlobal("nc-42", try ctx.gc.allocNativeClosure(&ncFortyTwo, &.{}, 0, "nc-42"));
    try ctx.vm.defineGlobal("nc-ignore", try ctx.gc.allocNativeClosure(&ncIgnoreArg, &.{}, 1, "nc-ignore"));
}

test "bootstrapped map calls a NativeClosure callback (call opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("(equal? (map nc-double (list 1 2 3)) (list 2 4 6))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "bootstrapped dynamic-wind calls NativeClosure thunks" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("(dynamic-wind nc-42 nc-42 nc-42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "NativeClosure upvalues survive the dispatch-loop call path" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const upvals = [_]Value{types.makeFixnum(100)};
    try ctx.vm.defineGlobal("nc-add100", try ctx.gc.allocNativeClosure(&ncAddUpvalue, &upvals, 1, "nc-add100"));
    const result = try ctx.vm.eval("(equal? (map nc-add100 (list 1 2)) (list 101 102))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "bytecode tail-calls a NativeClosure (tail_call opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("((lambda (f) (f 21)) nc-double)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "bytecode tail-applies a NativeClosure (tail_apply opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("((lambda (f) (apply f (list 21))) nc-double)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "bytecode tail-calls a NativeClosure global (tail_call_global opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("((lambda () (nc-double 21)))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/cc with a NativeClosure receiver (callHandler / tail_call_cc)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const non_tail = try ctx.vm.eval("(+ 0 (call-with-current-continuation nc-ignore))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(non_tail));
    const tail = try ctx.vm.eval("((lambda () (call-with-current-continuation nc-ignore)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(tail));
}

test "with-exception-handler NativeClosure thunk and handler (callThunk/callHandler)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const thunk_res = try ctx.vm.eval("(with-exception-handler (lambda (e) 0) nc-42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(thunk_res));
    const handler_res = try ctx.vm.eval("(with-exception-handler nc-ignore (lambda () (raise-continuable 1)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(handler_res));
}

test "NativeClosure arity mismatch raises a catchable error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("(guard (e (#t 99)) (nc-double 1 2))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

// -- Native-subset generator stays on the native path (#1395) --

// The VM-vs-native differential oracle (tests/fuzz/native-diff.sh) is only
// as strong as the generated programs' nativeness: every form that falls
// back to the interpreter shrinks the diff to VM-vs-VM. This gate emits
// fixed-seed native-subset programs through the LLVM emitter and counts
// `kaappi_eval` calls in the IR. Two shapes legitimately eval:
//
//   - defining a function/lambda emits exactly ONE eval
//     (emitDefine/emitPassthrough create the global binding via the
//     interpreter; call sites still use the direct native path);
//   - an inline VARIADIC lambda emits exactly ONE eval (#1420): no
//     closure tier accepts a rest parameter, so it goes through
//     emitLambdaViaEval, which first republishes the enclosing frame as
//     globals — the #1410 codegen this shape exists to exercise.
//
// The exact count is checked on UNOPTIMIZED emission: dead-branch
// elimination legitimately deletes variadic lambdas from constant-test
// branches (the generator emits constant tests as dead-branch fodder), so
// under the production pass pipeline the count is only bounded — the
// optimized emission is checked against that range instead, and anything
// above it means a generated form silently fell back.
test "native-subset generator emits no unexpected kaappi_eval fallbacks" {
    const fuzz_gen = @import("fuzz_gen.zig");
    const gpa = std.testing.allocator;

    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        const src = try fuzz_gen.generateNativeSeeded(seed, gpa);
        defer gpa.free(src);
        errdefer std.debug.print("seed {d} program:\n{s}\n", .{ seed, src });

        // One eval per function define and per lambda-valued global define,
        // plus one per inline variadic lambda. The generator emits one
        // top-level form per line, so define position is line-syntactic.
        var ndefines: usize = 0;
        var nvariadic: usize = 0;
        var names: [8][]const u8 = undefined;
        var name_count: usize = 0;
        var lines = std.mem.splitScalar(u8, src, '\n');
        while (lines.next()) |line| {
            var name: ?[]const u8 = null;
            if (std.mem.startsWith(u8, line, "(define (")) {
                const rest = line["(define (".len..];
                const end = std.mem.indexOfAny(u8, rest, " )") orelse rest.len;
                name = rest[0..end];
            } else if (std.mem.startsWith(u8, line, "(define ") and
                std.mem.indexOf(u8, line, "(lambda ") != null)
            {
                const rest = line["(define ".len..];
                const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
                name = rest[0..end];
            }
            if (name) |n| {
                ndefines += 1;
                names[name_count] = n;
                name_count += 1;
            }
            // Inline variadic lambdas: every "(lambda (" occurrence except
            // the define-position one on a `(define name (lambda ...)` line.
            // The parameter list is flat, so it ends at the first ')'; a
            // " . " inside it marks a rest parameter.
            var from: usize = 0;
            if (std.mem.startsWith(u8, line, "(define ") and !std.mem.startsWith(u8, line, "(define (")) {
                if (std.mem.indexOf(u8, line, "(lambda (")) |pos| from = pos + "(lambda (".len;
            }
            while (std.mem.indexOfPos(u8, line, from, "(lambda (")) |pos| {
                from = pos + "(lambda (".len;
                const plist_end = std.mem.indexOfScalarPos(u8, line, from, ')') orelse line.len;
                if (std.mem.indexOf(u8, line[from..plist_end], " . ") != null) nvariadic += 1;
            }
        }
        const expected = ndefines + nvariadic;

        // Exact accounting on unoptimized emission: every source shape
        // reaches the emitter, so any count mismatch is a shape that
        // unexpectedly fell back (or unexpectedly stayed native).
        var res_noopt = blk: {
            ir_mod.optimize_enabled = false;
            defer ir_mod.optimize_enabled = true;
            break :blk try emitMultiResultOpts(src, false);
        };
        defer res_noopt.deinit();
        const actual_noopt = std.mem.count(u8, res_noopt.toSlice(), "call i64 @kaappi_eval(");
        if (actual_noopt != expected) {
            std.debug.print("seed {d}: expected {d} kaappi_eval calls unoptimized ({d} defines + {d} inline variadic lambdas), found {d}\n", .{ seed, expected, ndefines, nvariadic, actual_noopt });
            return error.NativeSubsetFellBackToEval;
        }

        // Production pass pipeline: elimination can only remove eval sites,
        // never add them.
        var res = try emitMultiResult(src);
        defer res.deinit();
        const ll = res.toSlice();
        const actual = std.mem.count(u8, ll, "call i64 @kaappi_eval(");
        if (actual < ndefines or actual > expected) {
            std.debug.print("seed {d}: expected {d}..{d} kaappi_eval calls optimized, found {d}\n", .{ seed, ndefines, expected, actual });
            return error.NativeSubsetFellBackToEval;
        }

        // The eval count alone cannot see a function whose native
        // compilation was REJECTED (the define-time eval is emitted either
        // way and call sites just degrade to global lookups), so also
        // require the named native function definition that the emitter
        // tags with a `; <name>` header comment.
        for (names[0..name_count]) |n| {
            var needle_buf: [64]u8 = undefined;
            const needle = try std.fmt.bufPrint(&needle_buf, "; {s}\ndefine i64 @lambda_", .{n});
            if (std.mem.indexOf(u8, ll, needle) == null) {
                std.debug.print("seed {d}: no native definition for {s}\n", .{ seed, n });
                return error.NativeSubsetFellBackToEval;
            }
        }
    }
}
