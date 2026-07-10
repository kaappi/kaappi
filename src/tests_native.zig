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

    return .{ .gc = gc, .ir_instance = ir_instance, .emitter = emitter };
}

fn emitMultiResult(source: []const u8) !EmitResult {
    var gc = memory.GC.init(emitter_alloc);
    errdefer gc.deinit();

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
        root = ir_mod.foldConstants(&ir_instance, root);
        root = ir_mod.eliminateDeadBranches(&ir_instance, root);
        root = ir_mod.simplifyBooleans(&ir_instance, root);
        root = ir_mod.eliminateIdentity(&ir_instance, root);
        root = ir_mod.simplifyBegin(&ir_instance, root);
        try ir_nodes.append(emitter_alloc, root);
    }

    var emitter = llvm_emit.LLVMEmitter.init(emitter_alloc);
    errdefer emitter.deinit();
    try emitter.emitProgram(ir_nodes.items);

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
