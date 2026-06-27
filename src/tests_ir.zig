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

test "IR parity: if with boolean test and constant branches" {
    try expectBytecodeParity("(if #t 1 2)");
}

test "IR parity: if false" {
    try expectBytecodeParity("(if #f 10 20)");
}

test "IR parity: if without else" {
    try expectBytecodeParity("(if #t 42)");
}

test "IR parity: constant-folded arithmetic" {
    try expectBytecodeParity("(+ 3 4)");
}

test "IR parity: constant-folded comparison" {
    try expectBytecodeParity("(< 1 2)");
}

test "IR parity: nested if with constant folding" {
    try expectBytecodeParity("(if (< 1 2) (+ 3 4) 5)");
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

fn readExpr(gc: *memory.GC, source: []const u8) !types.Value {
    var reader = reader_mod.Reader.init(gc, source);
    defer reader.deinit();
    return reader.readDatum();
}
