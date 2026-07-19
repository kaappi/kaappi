//! SRFI-260 (Generated Symbols) tests.
//!
//! `generate-symbol` is registered as a global primitive, so these evals reach
//! it without importing `(srfi 260)`. The interesting properties are that every
//! call yields a *fresh* symbol and that a generated symbol nonetheless keeps
//! write/read invariance (it round-trips through `write`/`read` to an `eq?`
//! symbol) — the distinction from an uninterned symbol.

const std = @import("std");
const types = @import("types.zig");
const th = @import("testing_helpers.zig");

test "generate-symbol returns a symbol" {
    try th.expectEvalTrue("(symbol? (generate-symbol))");
}

test "generate-symbol accepts a pretty-name string" {
    try th.expectEvalTrue("(symbol? (generate-symbol \"pretty\"))");
}

test "generate-symbol yields distinct symbols" {
    try th.expectEvalBool("(eq? (generate-symbol) (generate-symbol))", false);
}

test "generate-symbol: same pretty-name still distinct" {
    try th.expectEvalBool("(eq? (generate-symbol \"x\") (generate-symbol \"x\"))", false);
}

test "generate-symbol: a symbol is eq? to itself" {
    try th.expectEvalTrue("(let ((g (generate-symbol))) (eq? g g))");
}

test "generate-symbol: write/read invariance" {
    // Unlike an uninterned symbol, a generated symbol printed and read back
    // yields an eq? symbol.
    try th.expectEvalTrue(
        \\(let ((g (generate-symbol)) (out (open-output-string)))
        \\  (write g out)
        \\  (eq? g (read (open-input-string (get-output-string out)))))
    );
}

test "generate-symbol: pretty-name is used as the name prefix" {
    // The pretty-name is a display hint; our implementation prefixes the name
    // with it, so the string representation begins with "p".
    try th.expectEvalTrue(
        \\(string-prefix? "p" (symbol->string (generate-symbol "p")))
    );
}

test "generate-symbol: pretty-name does not force equality of the name" {
    // Same pretty prefix, but the names of two calls still differ.
    try th.expectEvalBool(
        \\(string=? (symbol->string (generate-symbol "p"))
        \\          (symbol->string (generate-symbol "p")))
    , false);
}

test "generate-symbol: too many arguments is an arity error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectError(th.VMError.ArityMismatch, ctx.vm.eval("(generate-symbol \"a\" \"b\")"));
}

test "generate-symbol: non-string pretty-name is a type error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try std.testing.expectError(th.VMError.TypeError, ctx.vm.eval("(generate-symbol 42)"));
}
