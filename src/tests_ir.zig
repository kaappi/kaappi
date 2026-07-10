const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const reader_mod = @import("reader.zig");
const ir_mod = @import("ir.zig");
const th = @import("testing_helpers.zig");

test "IR behavioral: integer literal" {
    try th.expectEval("42", 42);
}

test "IR behavioral: boolean true" {
    try th.expectEvalBool("#t", true);
}

test "IR behavioral: boolean false" {
    try th.expectEvalBool("#f", false);
}

test "IR behavioral: if with boolean test and constant branches" {
    try th.expectEval("(if #t 1 2)", 1);
}

test "IR behavioral: if false" {
    try th.expectEval("(if #f 10 20)", 20);
}

test "IR behavioral: if without else" {
    try th.expectEval("(if #t 42)", 42);
}

test "IR behavioral: constant-folded arithmetic" {
    try th.expectEval("(+ 3 4)", 7);
}

test "IR behavioral: constant-folded comparison" {
    try th.expectEvalTrue("(< 1 2)");
}

test "IR behavioral: nested if with constant folding" {
    try th.expectEval("(if (< 1 2) (+ 3 4) 5)", 7);
}

test "IR behavioral: quoted datum" {
    try th.expectEval("(quote 42)", 42);
}

test "IR behavioral: quoted list" {
    try th.expectEvalTrue("(equal? (quote (1 2 3)) '(1 2 3))");
}

test "IR behavioral: global variable reference" {
    try th.expectEval("(define x 99) x", 99);
}

test "IR behavioral: nested calls" {
    try th.expectEval("(+ (+ 1 2) (+ 3 4))", 10);
}

test "IR behavioral: call with global args" {
    try th.expectEval("(define x 5) (+ x 1)", 6);
}

test "IR behavioral: if with call in test position" {
    try th.expectEval("(define x 5) (if (< x 10) 1 2)", 1);
}

test "IR behavioral: if with calls in all positions" {
    try th.expectEval("(define x 5) (if (< x 10) (+ x 1) (- x 1))", 6);
}

test "IR behavioral: unary constant fold (not)" {
    try th.expectEvalBool("(not #f)", true);
}

test "IR behavioral: unary constant fold (zero?)" {
    try th.expectEvalTrue("(zero? 0)");
}

test "IR behavioral: constant fold multiplication" {
    try th.expectEval("(* 6 7)", 42);
}

test "IR behavioral: and with true" {
    try th.expectEval("(and 1 2 3)", 3);
}

test "IR behavioral: and short-circuit" {
    try th.expectEvalBool("(and 1 #f 3)", false);
}

test "IR behavioral: and empty" {
    try th.expectEvalBool("(and)", true);
}

test "IR behavioral: or with false" {
    try th.expectEval("(or #f #f 3)", 3);
}

test "IR behavioral: or short-circuit" {
    try th.expectEval("(or 1 2 3)", 1);
}

test "IR behavioral: or empty" {
    try th.expectEvalBool("(or)", false);
}

test "IR behavioral: when true" {
    try th.expectEval("(when #t 42)", 42);
}

test "IR behavioral: when false" {
    try th.expectEvalVoid("(when #f 42)");
}

test "IR behavioral: unless true" {
    try th.expectEvalVoid("(unless #t 42)");
}

test "IR behavioral: unless false" {
    try th.expectEval("(unless #f 42)", 42);
}

test "IR behavioral: begin with define" {
    try th.expectEval("(begin (define x 1) (define y 2) (+ x y))", 3);
}

test "IR behavioral: lambda and call" {
    try th.expectEval("((lambda (x) (+ x 1)) 41)", 42);
}

test "IR behavioral: let binding" {
    try th.expectEval("(let ((x 10) (y 20)) (+ x y))", 30);
}

test "IR behavioral: define and call" {
    try th.expectEval("(define (f x) (* x x)) (f 7)", 49);
}

test "IR behavioral: set!" {
    try th.expectEval("(define x 1) (set! x 42) x", 42);
}

test "IR behavioral: cond" {
    try th.expectEval("(cond (#f 1) (#t 2) (else 3))", 2);
}

test "IR behavioral: case" {
    try th.expectEval("(case (+ 1 1) ((1) 10) ((2) 20) (else 30))", 20);
}

test "IR behavioral: do loop" {
    try th.expectEval("(do ((i 0 (+ i 1))) ((= i 5) i))", 5);
}

test "IR behavioral: guard" {
    try th.expectEval("(guard (e (#t 42)) (error \"test\"))", 42);
}

test "IR behavioral: quasiquote" {
    try th.expectEvalBool("(equal? (let ((x 5)) `(a ,x b)) '(a 5 b))", true);
}

test "IR behavioral: macros" {
    try th.expectEval("(define-syntax my-add (syntax-rules () ((my-add a b) (+ a b)))) (my-add 3 4)", 7);
}

test "IR behavioral: macro in bare-lambda body (#1025)" {
    try th.expectEval(
        \\(define-syntax my-add
        \\  (syntax-rules ()
        \\    ((_ a b) (+ a b))))
        \\(define f (lambda () (my-add 1 2)))
        \\(f)
    , 3);
}

test "IR behavioral: macro in immediately-applied lambda (#1025)" {
    try th.expectEval(
        \\(define-syntax my-add
        \\  (syntax-rules ()
        \\    ((_ a b) (+ a b))))
        \\((lambda () (my-add 1 2)))
    , 3);
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

test "IR optimization: set! target suppresses constant folding" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var ir = ir_mod.IR.init(std.testing.allocator);
    defer ir.deinit();

    var set_targets = std.StringHashMap(void).init(std.testing.allocator);
    defer set_targets.deinit();
    try set_targets.put("+", {});
    ir.set_targets = &set_targets;

    const plus_sym = try gc.allocSymbol("+");
    const op = try ir.makeGlobalRef(plus_sym);
    const a = try ir.makeConst(types.makeFixnum(3));
    const b = try ir.makeConst(types.makeFixnum(4));
    const call = try ir.makeCall(op, &.{ a, b });

    const folded = ir_mod.foldConstants(&ir, call);
    try std.testing.expect(folded.tag == .call); // must stay a call, not fold to 7
}

test "IR fold: set! of + in lambda body is not folded (stale global rebind)" {
    // (+ 5 2) must not fold to 7: + is set! to - before the call runs.
    try th.expectEval("(define f (lambda () (set! + -) (+ 5 2))) (f)", 3);
}

test "IR fold: set! of + inside let body is not folded (legacy passthrough path)" {
    try th.expectEval("(define g (lambda () (let ((x 1)) (set! + -) (+ 5 2)))) (g)", 3);
}

test "IR fold: set! in outer body suppresses fold in nested lambda" {
    try th.expectEval("(define k (lambda () (set! + -) (lambda () (+ 5 2)))) ((k))", 3);
}

test "IR fold: every + call in a set!-body is suppressed" {
    try th.expectEval("(define h (lambda () (+ 100 1) (set! + -) (+ 5 2))) (h)", 3);
}

test "IR fold: set! of * in lambda body is not folded" {
    try th.expectEval("(define f (lambda () (set! * -) (* 10 3))) (f)", 7);
}

test "IR fold: primitive still folds when no set! targets it" {
    try th.expectEval("((lambda () (+ 5 2)))", 7);
}

test "IR fold: set! inside quoted data does not suppress folding" {
    // (quote (set! + -)) is data, not a rebind; (+ 5 2) still folds to 7.
    try th.expectEval("(define p (lambda () (quote (set! + -)) (+ 5 2))) (p)", 7);
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
    try th.expectEval("(define (f x) (if (< x 10) (+ x 1) (- x 1))) (f 5)", 6);
}

test "bare lambda with single internal define" {
    try th.expectEval("(define b (lambda () (define q 7) (- q))) (b)", -7);
}

test "bare lambda with internal define and complex expression" {
    try th.expectEval("(define h (lambda () (define z 5) (+ (* z z) z))) (h)", 30);
}

test "bare lambda with multiple internal defines" {
    try th.expectEval("(define m (lambda () (define a 3) (define b 4) (+ a b))) (m)", 7);
}

test "bare lambda internal define with lambda application" {
    try th.expectEval("(define g (lambda () (define x 10) ((lambda (a) a) x))) (g)", 10);
}

// Issue #790: IR constant folding / simplifyBooleans must not fold a call to a
// primitive name that is shadowed by a lambda parameter (or an enclosing
// local). The lambda body is lowered through the IR by compileLambdaWithIR;
// the IR now consults the enclosing compiler's lexical scope in isRedefined.
// These forms are evaluated bare (not wrapped in a macro), so the operator
// lambda is compiled via the IR path, not the legacy passthrough compiler.

test "issue #790: lambda param shadows + (binary fold suppressed)" {
    try th.expectEval("((lambda (+) (+ 1 2)) -)", -1);
}

test "issue #790: lambda param shadows < (comparison fold suppressed)" {
    try th.expectEval("((lambda (<) (< 1 2)) +)", 3);
}

test "issue #790: lambda param shadows zero? (unary fold suppressed)" {
    try th.expectEval("((lambda (zero?) (if (zero? 0) 10 20)) (lambda (x) #f))", 20);
}

test "issue #790: lambda param shadows not (simplifyBooleans suppressed)" {
    try th.expectEval("((lambda (not) (if (not 5) 100 200)) odd?)", 100);
}

test "issue #790: shadowed operator with pre-folded args (foldConstants pass)" {
    try th.expectEval("((lambda (+) (+ (- 5 4) 2)) *)", 2);
}

test "issue #790: enclosing lambda param shadows via upvalue chain" {
    try th.expectEval("((lambda (+) ((lambda (y) (+ 3 4)) 10)) -)", -1);
}

test "issue #790: unshadowed operator still folds in a lambda body" {
    try th.expectEval("((lambda (y) (+ 1 2)) 99)", 3);
}

test "IR lowering: begin with >256 sub-expressions" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    var src: [300 * 4 + 20]u8 = undefined;
    var pos: usize = 0;
    @memcpy(src[pos..][0..7], "(begin ");
    pos += 7;
    for (0..300) |i| {
        const written = std.fmt.bufPrint(src[pos..], "{d} ", .{i}) catch unreachable;
        pos += written.len;
    }
    src[pos - 1] = ')';
    const result = try ctx.vm.eval(src[0..pos]);
    try std.testing.expectEqual(@as(i64, 299), types.toFixnum(result));
}

test "IR lowering: and with >256 sub-expressions" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    var src: [300 * 3 + 20]u8 = undefined;
    var pos: usize = 0;
    @memcpy(src[pos..][0..5], "(and ");
    pos += 5;
    for (0..299) |_| {
        @memcpy(src[pos..][0..3], "#t ");
        pos += 3;
    }
    @memcpy(src[pos..][0..3], "42)");
    pos += 3;
    const result = try ctx.vm.eval(src[0..pos]);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "IR lowering: or with >256 sub-expressions" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    var src: [300 * 3 + 20]u8 = undefined;
    var pos: usize = 0;
    @memcpy(src[pos..][0..4], "(or ");
    pos += 4;
    for (0..299) |_| {
        @memcpy(src[pos..][0..3], "#f ");
        pos += 3;
    }
    @memcpy(src[pos..][0..3], "42)");
    pos += 3;
    const result = try ctx.vm.eval(src[0..pos]);
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

fn readExpr(gc: *memory.GC, source: []const u8) !types.Value {
    var reader = reader_mod.Reader.init(gc, source);
    defer reader.deinit();
    return reader.readDatum();
}

// -- Issue #1026: bare-lambda internal defines need letrec* desugaring --

test "IR: bare lambda mutual recursion with fresh names (#1026)" {
    try th.expectEvalTrue(
        \\((lambda ()
        \\   (define (e? n) (if (= n 0) #t (o? (- n 1))))
        \\   (define (o? n) (if (= n 0) #f (e? (- n 1))))
        \\   (e? 10)))
    );
}

test "IR: bare lambda internal defines shadow builtins (#1026)" {
    try th.expectEvalTrue(
        \\((lambda ()
        \\   (define (even? n) (if (= n 0) #t (odd? (- n 1))))
        \\   (define (odd? n) (if (= n 0) #f (even? (- n 1))))
        \\   (even? 10)))
    );
}

test "IR: define shorthand parity with bare lambda (#1026)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const r1 = try ctx.vm.eval(
        \\((lambda ()
        \\   (define (e? n) (if (= n 0) #t (o? (- n 1))))
        \\   (define (o? n) (if (= n 0) #f (e? (- n 1))))
        \\   (e? 4)))
    );
    try std.testing.expect(r1 == types.TRUE);
    const r2 = try ctx.vm.eval(
        \\(let ()
        \\   (define (e? n) (if (= n 0) #t (o? (- n 1))))
        \\   (define (o? n) (if (= n 0) #f (e? (- n 1))))
        \\   (e? 4))
    );
    try std.testing.expect(r2 == types.TRUE);
}

test "IR: bare lambda define-value form (#1026)" {
    try th.expectEval(
        \\((lambda ()
        \\   (define x 10)
        \\   (define y (+ x 5))
        \\   y))
    , 15);
}

// -- Issue #1035: self-tail-call + line-table for IR path --

test "IR: bare-lambda define emits self_tail_call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const source = "(define f (lambda (n) (if (= n 0) 0 (f (- n 1)))))";
    var reader = reader_mod.Reader.init(&gc, source);
    defer reader.deinit();
    const expr = try reader.readDatum();
    const func = try compiler_mod.compileExpression(&gc, expr);

    var found_self_tail_call = false;
    var found_generic_tail_call = false;
    for (func.constants.items) |c| {
        if (!types.isFunction(c)) continue;
        const child = types.toObject(c).as(types.Function);
        var ip: usize = 0;
        while (ip < child.code.items.len) {
            const raw = child.code.items[ip];
            if (raw == @intFromEnum(types.OpCode.self_tail_call)) {
                found_self_tail_call = true;
            }
            if (raw == @intFromEnum(types.OpCode.tail_call)) {
                found_generic_tail_call = true;
            }
            ip += 1;
        }
    }
    try std.testing.expect(found_self_tail_call);
    try std.testing.expect(!found_generic_tail_call);
}

test "IR: bare-lambda self-tail-call does not overflow stack" {
    try th.expectEval(
        \\(define f (lambda (n acc) (if (= n 0) acc (f (- n 1) (+ acc 1)))))
        \\(f 100000 0)
    , 100000);
}

test "IR: line-table entries recorded for IR-compiled code" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const source =
        \\(define f
        \\  (lambda (x)
        \\    (if (= x 0)
        \\        0
        \\        (+ x 1))))
    ;
    var reader = reader_mod.Reader.init(&gc, source);
    defer reader.deinit();
    const expr = try reader.readDatum();
    const func = try compiler_mod.compileExpression(&gc, expr);

    var child_has_lines = false;
    for (func.constants.items) |c| {
        if (!types.isFunction(c)) continue;
        const child = types.toObject(c).as(types.Function);
        if (child.line_table.items.len > 0) {
            child_has_lines = true;
        }
    }
    try std.testing.expect(child_has_lines);
}

// --- Issue #1393: optimization on/off switch ---

test "IR opt switch: folded patterns evaluate identically without optimization" {
    // One case per folding/simplification pattern: AST fold (+,-,*,cmp),
    // unary folds (not, zero?, negate), dead-branch elimination, boolean
    // simplification, identity elimination, begin simplification.
    const cases = [_]struct { src: []const u8, want: i64 }{
        .{ .src = "(+ 1 2)", .want = 3 },
        .{ .src = "(* 6 7)", .want = 42 },
        .{ .src = "(- 5)", .want = -5 },
        .{ .src = "(if (< 1 2) 10 20)", .want = 10 },
        .{ .src = "(if (not #f) 10 20)", .want = 10 },
        .{ .src = "(if (zero? 0) 1 2)", .want = 1 },
        .{ .src = "(if #t 1 2)", .want = 1 },
        .{ .src = "(if #f 1 2)", .want = 2 },
        .{ .src = "(if (< 1 2) (+ 3 4) 99)", .want = 7 },
        .{ .src = "(begin 1 2 3)", .want = 3 },
        .{ .src = "(begin (+ 40 2))", .want = 42 },
        .{ .src = "(and 1 2 3)", .want = 3 },
        .{ .src = "(or #f 7)", .want = 7 },
        .{ .src = "(let ((x (* 2 3))) (+ x (if #t 1 0)))", .want = 7 },
    };
    for (cases) |case| try th.expectEval(case.src, case.want);

    ir_mod.optimize_enabled = false;
    defer ir_mod.optimize_enabled = true;
    for (cases) |case| try th.expectEval(case.src, case.want);
}

test "IR opt switch: disabling optimization changes emitted bytecode" {
    // (if #t 1 2) collapses to a single constant load when dead-branch
    // elimination runs; without it the test, branch, and both arms are all
    // emitted. Different code proves the switch is live.
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const opt_func = try compiler_mod.compileExpression(&gc, try readExpr(&gc, "(if #t 1 2)"));
    const opt_len = opt_func.code.items.len;

    ir_mod.optimize_enabled = false;
    defer ir_mod.optimize_enabled = true;
    const noopt_func = try compiler_mod.compileExpression(&gc, try readExpr(&gc, "(if #t 1 2)"));
    try std.testing.expect(opt_len < noopt_func.code.items.len);
}
