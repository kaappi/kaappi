//! Tests for the diagnostic registry (KEP-0005, #1504).
//!
//! Registry integrity (uniqueness, completeness, non-empty fields) is also
//! enforced at compile time by the `comptime` block in diagnostics.zig; these
//! runtime tests exercise the public API (render, lookup, the internal
//! error->code mappings) and the end-to-end stamping of codes onto error
//! objects.

const std = @import("std");
const diagnostics = @import("diagnostics.zig");
const types = @import("types.zig");
const th = @import("testing_helpers.zig");
const Code = diagnostics.Code;

test "code renders as KPnnnn" {
    var buf: [Code.render_width]u8 = undefined;
    try std.testing.expectEqualStrings("KP1002", Code.unexpected_char.render(&buf));
    try std.testing.expectEqualStrings("KP2002", Code.syntax_error.render(&buf));
    try std.testing.expectEqualStrings("KP3000", Code.uncaught_exception.render(&buf));
    try std.testing.expectEqualStrings("KP3001", Code.undefined_variable.render(&buf));
    try std.testing.expectEqualStrings("KP3004", Code.division_by_zero.render(&buf));
    try std.testing.expectEqualStrings("KP9000", Code.uncategorized.render(&buf));
}

test "every code resolves to a complete registry entry" {
    for (std.enums.values(Code)) |c| {
        const d = diagnostics.lookup(c);
        try std.testing.expectEqual(c, d.code);
        try std.testing.expect(d.name.len > 0);
        try std.testing.expect(d.template.len > 0);
        try std.testing.expect(d.explanation.len > 0);
    }
}

test "no two registry entries share a code" {
    for (diagnostics.table, 0..) |a, i| {
        for (diagnostics.table[i + 1 ..]) |b| {
            try std.testing.expect(a.code != b.code);
        }
    }
}

test "reader errors map to read-stage codes with no leak fallback" {
    try std.testing.expectEqual(Code.unexpected_eof, diagnostics.readErrorCode(error.UnexpectedEof));
    try std.testing.expectEqual(Code.unexpected_char, diagnostics.readErrorCode(error.UnexpectedChar));
    try std.testing.expectEqual(Code.unexpected_right_paren, diagnostics.readErrorCode(error.UnexpectedRightParen));
    try std.testing.expectEqual(Code.unterminated_string, diagnostics.readErrorCode(error.UnterminatedString));
    try std.testing.expectEqual(Code.dot_outside_list, diagnostics.readErrorCode(error.DotNotInList));
    // An unrecognized reader error still resolves to a real read-stage code
    // rather than leaking the Zig error name.
    try std.testing.expectEqual(Code.unexpected_char, diagnostics.readErrorCode(error.SomeFutureReaderError));
}

test "compile errors map to compile-stage codes" {
    try std.testing.expectEqual(Code.invalid_syntax, diagnostics.compileErrorCode(error.InvalidSyntax));
    try std.testing.expectEqual(Code.macro_expansion_limit, diagnostics.compileErrorCode(error.MacroExpansionLimit));
    try std.testing.expectEqual(Code.syntax_error, diagnostics.compileErrorCode(error.NoMatchingPattern));
    try std.testing.expectEqual(Code.internal_error, diagnostics.compileErrorCode(error.TooManyConstants));
    try std.testing.expectEqual(Code.invalid_syntax, diagnostics.compileErrorCode(error.SomeFutureCompileError));
}

test "runtime errors map to runtime-stage codes" {
    try std.testing.expectEqual(Code.undefined_variable, diagnostics.runtimeErrorCode(error.UndefinedVariable));
    try std.testing.expectEqual(Code.type_error, diagnostics.runtimeErrorCode(error.TypeError));
    try std.testing.expectEqual(Code.arity_mismatch, diagnostics.runtimeErrorCode(error.ArityMismatch));
    try std.testing.expectEqual(Code.not_a_procedure, diagnostics.runtimeErrorCode(error.NotAProcedure));
    try std.testing.expectEqual(Code.index_out_of_bounds, diagnostics.runtimeErrorCode(error.IndexOutOfBounds));
    try std.testing.expectEqual(Code.uncaught_exception, diagnostics.runtimeErrorCode(error.ExceptionRaised));
    // Control-flow signals are not diagnostics — they must never surface a
    // stage-specific code.
    try std.testing.expectEqual(Code.uncategorized, diagnostics.runtimeErrorCode(error.Yielded));
    try std.testing.expectEqual(Code.uncategorized, diagnostics.runtimeErrorCode(error.ContinuationInvoked));
}

test "division-by-zero error object carries the division_by_zero code" {
    // Division raises through the exception system, so the specific code has to
    // ride on the object to survive to the reporting layer (KEP-0005 §4).
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval("(guard (e (#t e)) (/ 1 0))");
    try std.testing.expect(types.isErrorObject(result));
    const eo = types.toObject(result).as(types.ErrorObject);
    try std.testing.expectEqual(Code.division_by_zero, eo.code);
}

test "user (error ...) objects are uncoded" {
    // The KP namespace is reserved to the implementation; a user error carries
    // no code (surfaces as the generic KP3000 uncaught-exception at top level).
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval("(guard (e (#t e)) (error \"boom\" 1 2))");
    try std.testing.expect(types.isErrorObject(result));
    const eo = types.toObject(result).as(types.ErrorObject);
    try std.testing.expectEqual(Code.uncategorized, eo.code);
}
