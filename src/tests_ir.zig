const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const reader_mod = @import("reader.zig");
const ir_mod = @import("ir.zig");
const th = @import("testing_helpers.zig");

fn compileViaDirectCompiler(gc: *memory.GC, source: []const u8) !*types.Function {
    var reader = reader_mod.Reader.init(gc, source);
    defer reader.deinit();
    const expr = try reader.readDatum();
    return compiler_mod.compileExpression(gc, expr);
}

fn compileViaIR(gc: *memory.GC, source: []const u8) !*types.Function {
    var reader = reader_mod.Reader.init(gc, source);
    defer reader.deinit();
    const expr = try reader.readDatum();

    var ir = ir_mod.IR.init(gc.allocator);
    defer ir.deinit();
    const root = try ir_mod.lower(&ir, expr);

    var emitter = try ir_mod.Emitter.init(gc);
    try emitter.compile(root);
    return emitter.func;
}

fn expectBehavioralParity(source: []const u8) !void {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    const result = try vm.eval(source);
    _ = result;
}

fn expectBytecodeParity(source: []const u8) !void {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    const direct = try compileViaDirectCompiler(&gc1, source);

    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();
    const ir_func = try compileViaIR(&gc2, source);

    try std.testing.expectEqual(direct.code.items.len, ir_func.code.items.len);
    try std.testing.expectEqualSlices(u8, direct.code.items, ir_func.code.items);
    try std.testing.expectEqual(direct.constants.items.len, ir_func.constants.items.len);
}

test "IR parity: integer literal" {
    try expectBytecodeParity("42");
}

test "IR parity: boolean true" {
    try expectBytecodeParity("#t");
}

test "IR parity: boolean false" {
    try expectBytecodeParity("#f");
}

test "IR behavioral: if with boolean test and constant branches" {
    try expectBehavioralParity("(if #t 1 2)");
}

test "IR behavioral: if false" {
    try expectBehavioralParity("(if #f 10 20)");
}

test "IR behavioral: if without else" {
    try expectBehavioralParity("(if #t 42)");
}

test "IR parity: constant-folded arithmetic" {
    try expectBytecodeParity("(+ 3 4)");
}

test "IR parity: constant-folded comparison" {
    try expectBytecodeParity("(< 1 2)");
}

test "IR behavioral: nested if with constant folding" {
    try expectBehavioralParity("(if (< 1 2) (+ 3 4) 5)");
}

test "IR parity: quoted datum" {
    try expectBytecodeParity("(quote 42)");
}

test "IR parity: quoted list" {
    try expectBytecodeParity("(quote (1 2 3))");
}

test "IR parity: global variable reference" {
    try expectBytecodeParity("x");
}

test "IR behavioral: nested calls" {
    try expectBehavioralParity("(+ (+ 1 2) (+ 3 4))");
}

test "IR behavioral: call with global args" {
    try expectBehavioralParity("(define x 5) (+ x 1)");
}

test "IR behavioral: if with call in test position" {
    try expectBehavioralParity("(define x 5) (if (< x 10) 1 2)");
}

test "IR behavioral: if with calls in all positions" {
    try expectBehavioralParity("(define x 5) (if (< x 10) (+ x 1) (- x 1))");
}

test "IR parity: unary constant fold (not)" {
    try expectBytecodeParity("(not #f)");
}

test "IR parity: unary constant fold (zero?)" {
    try expectBytecodeParity("(zero? 0)");
}

test "IR parity: constant fold multiplication" {
    try expectBytecodeParity("(* 6 7)");
}

test "IR behavioral: and with true" {
    try expectBehavioralParity("(and 1 2 3)");
}

test "IR behavioral: and short-circuit" {
    try expectBehavioralParity("(and 1 #f 3)");
}

test "IR behavioral: and empty" {
    try expectBehavioralParity("(and)");
}

test "IR behavioral: or with false" {
    try expectBehavioralParity("(or #f #f 3)");
}

test "IR behavioral: or short-circuit" {
    try expectBehavioralParity("(or 1 2 3)");
}

test "IR behavioral: or empty" {
    try expectBehavioralParity("(or)");
}

test "IR behavioral: when true" {
    try expectBehavioralParity("(when #t 42)");
}

test "IR behavioral: when false" {
    try expectBehavioralParity("(when #f 42)");
}

test "IR behavioral: unless true" {
    try expectBehavioralParity("(unless #t 42)");
}

test "IR behavioral: unless false" {
    try expectBehavioralParity("(unless #f 42)");
}

test "IR behavioral: begin with define" {
    try expectBehavioralParity("(begin (define x 1) (define y 2) (+ x y))");
}

test "IR behavioral: lambda and call" {
    try expectBehavioralParity("((lambda (x) (+ x 1)) 41)");
}

test "IR behavioral: let binding" {
    try expectBehavioralParity("(let ((x 10) (y 20)) (+ x y))");
}

test "IR behavioral: define and call" {
    try expectBehavioralParity("(define (f x) (* x x)) (f 7)");
}

test "IR behavioral: set!" {
    try expectBehavioralParity("(define x 1) (set! x 42) x");
}

test "IR behavioral: cond" {
    try expectBehavioralParity("(cond (#f 1) (#t 2) (else 3))");
}

test "IR behavioral: case" {
    try expectBehavioralParity("(case (+ 1 1) ((1) 10) ((2) 20) (else 30))");
}

test "IR behavioral: do loop" {
    try expectBehavioralParity("(do ((i 0 (+ i 1))) ((= i 5) i))");
}

test "IR behavioral: guard" {
    try expectBehavioralParity("(guard (e (#t 42)) (error \"test\"))");
}

test "IR behavioral: quasiquote" {
    try expectBehavioralParity("(let ((x 5)) `(a ,x b))");
}

test "IR behavioral: macros" {
    try expectBehavioralParity("(define-syntax my-add (syntax-rules () ((my-add a b) (+ a b)))) (my-add 3 4)");
}

// --- Semantic analysis tests ---

test "IR analysis: tail position in if" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const root = try ir_mod.lower(&ir, try readExpr(&gc, "(if #t 1 2)"));
    ir_mod.markTailPositions(root, false);
    try std.testing.expect(!root.ann.is_tail);
    try std.testing.expect(root.tag == .@"if");
    try std.testing.expect(!root.data.@"if".test_expr.ann.is_tail);
    try std.testing.expect(!root.data.@"if".consequent.ann.is_tail);
    try std.testing.expect(!root.data.@"if".alternate.?.ann.is_tail);
}

test "IR analysis: tail position propagates through if" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const root = try ir_mod.lower(&ir, try readExpr(&gc, "(if #t 1 2)"));
    ir_mod.markTailPositions(root, true);
    try std.testing.expect(root.ann.is_tail);
    try std.testing.expect(!root.data.@"if".test_expr.ann.is_tail);
    try std.testing.expect(root.data.@"if".consequent.ann.is_tail);
    try std.testing.expect(root.data.@"if".alternate.?.ann.is_tail);
}

test "IR analysis: tail position in begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const root = try ir_mod.lower(&ir, try readExpr(&gc, "(begin 1 2 3)"));
    ir_mod.markTailPositions(root, true);
    try std.testing.expect(root.ann.is_tail);
    try std.testing.expect(!root.data.begin[0].ann.is_tail);
    try std.testing.expect(!root.data.begin[1].ann.is_tail);
    try std.testing.expect(root.data.begin[2].ann.is_tail);
}

test "IR analysis: tail position in and/or" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const root = try ir_mod.lower(&ir, try readExpr(&gc, "(and 1 2 3)"));
    ir_mod.markTailPositions(root, true);
    try std.testing.expect(!root.data.and_form[0].ann.is_tail);
    try std.testing.expect(!root.data.and_form[1].ann.is_tail);
    try std.testing.expect(root.data.and_form[2].ann.is_tail);
}

test "IR analysis: primitive identification on Call node" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const plus_sym = try gc.allocSymbol("+");
    const op = try ir.makeGlobalRef(plus_sym);
    const arg1 = try ir.makeConst(types.makeFixnum(1));
    const arg2 = try ir.makeConst(types.makeFixnum(2));
    const call = try ir.makeCall(op, &.{ arg1, arg2 });

    ir_mod.identifyPrimitives(call);
    try std.testing.expect(call.ann.is_primitive_call);
    try std.testing.expect(std.mem.eql(u8, call.ann.primitive_name.?, "+"));
}

test "IR analysis: non-primitive not marked" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const my_fn = try gc.allocSymbol("my-function");
    const op = try ir.makeGlobalRef(my_fn);
    const arg = try ir.makeConst(types.makeFixnum(1));
    const call = try ir.makeCall(op, &.{arg});

    ir_mod.identifyPrimitives(call);
    try std.testing.expect(!call.ann.is_primitive_call);
    try std.testing.expect(call.ann.primitive_name == null);
}

test "IR optimization: constant folding on Call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const plus_sym = try gc.allocSymbol("+");
    const op = try ir.makeGlobalRef(plus_sym);
    const a = try ir.makeConst(types.makeFixnum(3));
    const b = try ir.makeConst(types.makeFixnum(4));
    const call = try ir.makeCall(op, &.{ a, b });

    const folded = ir_mod.foldConstants(&ir, call);
    try std.testing.expect(folded.tag == .constant);
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(folded.data.constant));
}

test "IR optimization: constant folding not applied to non-constant args" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const plus_sym = try gc.allocSymbol("+");
    const x_sym = try gc.allocSymbol("x");
    const op = try ir.makeGlobalRef(plus_sym);
    const a = try ir.makeGlobalRef(x_sym);
    const b = try ir.makeConst(types.makeFixnum(1));
    const call = try ir.makeCall(op, &.{ a, b });

    const folded = ir_mod.foldConstants(&ir, call);
    try std.testing.expect(folded.tag == .call);
}

test "IR optimization: constant folding through if" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const plus_sym = try gc.allocSymbol("+");
    const op = try ir.makeGlobalRef(plus_sym);
    const a = try ir.makeConst(types.makeFixnum(1));
    const b = try ir.makeConst(types.makeFixnum(2));
    const call = try ir.makeCall(op, &.{ a, b });

    const test_node = try ir.makeConst(types.TRUE);
    const alt = try ir.makeConst(types.makeFixnum(0));
    const if_node = try ir.makeIf(test_node, call, alt);

    const folded = ir_mod.foldConstants(&ir, if_node);
    try std.testing.expect(folded.tag == .@"if");
    try std.testing.expect(folded.data.@"if".consequent.tag == .constant);
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(folded.data.@"if".consequent.data.constant));
}

test "IR optimization: dead branch elimination — true test" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const test_node = try ir.makeConst(types.TRUE);
    const cons = try ir.makeConst(types.makeFixnum(42));
    const alt = try ir.makeConst(types.makeFixnum(0));
    const if_node = try ir.makeIf(test_node, cons, alt);

    const result = ir_mod.eliminateDeadBranches(&ir, if_node);
    try std.testing.expect(result.tag == .constant);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result.data.constant));
}

test "IR optimization: dead branch elimination — false test" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const test_node = try ir.makeConst(types.FALSE);
    const cons = try ir.makeConst(types.makeFixnum(42));
    const alt = try ir.makeConst(types.makeFixnum(0));
    const if_node = try ir.makeIf(test_node, cons, alt);

    const result = ir_mod.eliminateDeadBranches(&ir, if_node);
    try std.testing.expect(result.tag == .constant);
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result.data.constant));
}

test "IR optimization: dead branch elimination — non-constant test unchanged" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const x_sym = try gc.allocSymbol("x");
    const test_node = try ir.makeGlobalRef(x_sym);
    const cons = try ir.makeConst(types.makeFixnum(42));
    const alt = try ir.makeConst(types.makeFixnum(0));
    const if_node = try ir.makeIf(test_node, cons, alt);

    const result = ir_mod.eliminateDeadBranches(&ir, if_node);
    try std.testing.expect(result.tag == .@"if");
}

test "IR analysis: constant detection — literal is constant" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const node = try ir.makeConst(types.makeFixnum(42));
    ir_mod.markConstants(node);
    try std.testing.expect(node.ann.is_constant);
}

test "IR analysis: constant detection — primitive call with const args" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const plus_sym = try gc.allocSymbol("+");
    const op = try ir.makeGlobalRef(plus_sym);
    const a = try ir.makeConst(types.makeFixnum(1));
    const b = try ir.makeConst(types.makeFixnum(2));
    const call = try ir.makeCall(op, &.{ a, b });
    ir_mod.identifyPrimitives(call);
    ir_mod.markConstants(call);
    try std.testing.expect(call.ann.is_constant);
}

test "IR analysis: constant detection — variable ref is not constant" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();
    const x_sym = try gc.allocSymbol("x");
    const node = try ir.makeGlobalRef(x_sym);
    ir_mod.markConstants(node);
    try std.testing.expect(!node.ann.is_constant);
}

test "IR optimization: boolean simplification — not not preserved for correctness" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const not_sym = try gc.allocSymbol("not");
    const x_sym = try gc.allocSymbol("x");
    const x = try ir.makeGlobalRef(x_sym);
    const not_op = try ir.makeGlobalRef(not_sym);
    const inner = try ir.makeCall(not_op, &.{x});
    const not_op2 = try ir.makeGlobalRef(not_sym);
    const outer = try ir.makeCall(not_op2, &.{inner});

    const result = ir_mod.simplifyBooleans(&ir, outer);
    // (not (not X)) must NOT fold to X — X may not be boolean
    try std.testing.expect(result.tag == .call);
}

test "IR optimization: boolean simplification — if not test swaps branches" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const not_sym = try gc.allocSymbol("not");
    const x_sym = try gc.allocSymbol("x");
    const x = try ir.makeGlobalRef(x_sym);
    const not_op = try ir.makeGlobalRef(not_sym);
    const test_node = try ir.makeCall(not_op, &.{x});
    const cons = try ir.makeConst(types.makeFixnum(1));
    const alt = try ir.makeConst(types.makeFixnum(2));
    const if_node = try ir.makeIf(test_node, cons, alt);

    const result = ir_mod.simplifyBooleans(&ir, if_node);
    try std.testing.expect(result.tag == .@"if");
    try std.testing.expect(result.data.@"if".test_expr.tag == .global_ref);
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result.data.@"if".consequent.data.constant));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result.data.@"if".alternate.?.data.constant));
}

test "IR optimization: identity elimination — add zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const plus_sym = try gc.allocSymbol("+");
    const op = try ir.makeGlobalRef(plus_sym);
    const five = try ir.makeConst(types.makeFixnum(5));
    const zero = try ir.makeConst(types.makeFixnum(0));
    const call = try ir.makeCall(op, &.{ five, zero });

    const result = ir_mod.eliminateIdentity(&ir, call);
    try std.testing.expect(result.tag == .constant);
    try std.testing.expect(types.toFixnum(result.data.constant) == 5);
}

test "IR optimization: identity elimination — add zero skipped for non-constant" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const plus_sym = try gc.allocSymbol("+");
    const x_sym = try gc.allocSymbol("x");
    const op = try ir.makeGlobalRef(plus_sym);
    const x = try ir.makeGlobalRef(x_sym);
    const zero = try ir.makeConst(types.makeFixnum(0));
    const call = try ir.makeCall(op, &.{ x, zero });

    const result = ir_mod.eliminateIdentity(&ir, call);
    try std.testing.expect(result.tag == .call);
}

test "IR optimization: identity elimination — multiply by zero (pure)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const mul_sym = try gc.allocSymbol("*");
    const op = try ir.makeGlobalRef(mul_sym);
    const five = try ir.makeConst(types.makeFixnum(5));
    const zero = try ir.makeConst(types.makeFixnum(0));
    const call = try ir.makeCall(op, &.{ five, zero });

    const result = ir_mod.eliminateIdentity(&ir, call);
    try std.testing.expect(result.tag == .constant);
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result.data.constant));
}

test "IR optimization: identity elimination — multiply by zero (impure preserved)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const mul_sym = try gc.allocSymbol("*");
    const x_sym = try gc.allocSymbol("x");
    const op = try ir.makeGlobalRef(mul_sym);
    const x = try ir.makeGlobalRef(x_sym);
    const zero = try ir.makeConst(types.makeFixnum(0));
    const call = try ir.makeCall(op, &.{ x, zero });

    const result = ir_mod.eliminateIdentity(&ir, call);
    // Non-constant operand must NOT be optimized away (may have side effects)
    try std.testing.expect(result.tag == .call);
}

test "IR optimization: begin simplification — single expr" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    const val = try ir.makeConst(types.makeFixnum(42));
    const begin = try ir.makeBegin(&.{val});
    const result = ir_mod.simplifyBegin(&ir, begin);
    try std.testing.expect(result.tag == .constant);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result.data.constant));
}

test "IR analysis: emission uses tail annotation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    const result = try vm.eval("(define (f x) (if (< x 10) (+ x 1) (- x 1))) (f 5)");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(result));
}

fn readExpr(gc: *memory.GC, source: []const u8) !types.Value {
    var reader = reader_mod.Reader.init(gc, source);
    defer reader.deinit();
    return reader.readDatum();
}
