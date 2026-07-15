//! Tests for full source spans threaded reader -> IR -> bytecode (#1506).
//!
//! The reader records a `(line, col, end_line, end_col)` span for every datum
//! it can key on heap identity (pairs and vectors); the compiler copies the
//! start `(line, col)` into the bytecode line table so runtime errors can
//! report `file:line:col`. These tests pin the reader's span math and the
//! end-to-end flow into a compiled function's line table.

const std = @import("std");
const testing = std.testing;
const types = @import("types.zig");
const memory = @import("memory.zig");
const reader = @import("reader.zig");
const compiler = @import("compiler.zig");
const th = @import("testing_helpers.zig");

fn spanOf(gc: *memory.GC, source: []const u8) !types.Span {
    var r = reader.Reader.init(gc, source);
    defer r.deinit();
    const val = try r.readDatum();
    return gc.source_spans.get(val) orelse error.NoSpanRecorded;
}

test "reader records a full span for a top-level list" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // "(a b)" — open paren at col 1, close paren at col 5, end is half-open at
    // col 6 (one past the ')').
    const sp = try spanOf(&gc, "(a b)");
    try testing.expectEqual(@as(u32, 1), sp.line);
    try testing.expectEqual(@as(u32, 1), sp.col);
    try testing.expectEqual(@as(u32, 1), sp.end_line);
    try testing.expectEqual(@as(u32, 6), sp.end_col);
    try testing.expect(sp.known());
    try testing.expect(sp.hasEnd());
}

test "reader span start tracks leading indentation" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const sp = try spanOf(&gc, "   (if x)");
    try testing.expectEqual(@as(u32, 1), sp.line);
    try testing.expectEqual(@as(u32, 4), sp.col); // the '(' sits at column 4
}

test "reader records precise columns for a nested form" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // The inner "(if)" of "(define (f) (if))" begins at column 13.
    var r = reader.Reader.init(&gc, "(define (f) (if))");
    defer r.deinit();
    const outer = try r.readDatum();

    // Walk to the third element ((if)) of the outer list: cddr -> car.
    const rest2 = types.cdr(types.cdr(outer));
    const inner = types.car(rest2);
    try testing.expect(types.isPair(inner));

    const inner_sp = gc.source_spans.get(inner) orelse return error.NoSpanRecorded;
    try testing.expectEqual(@as(u32, 1), inner_sp.line);
    try testing.expectEqual(@as(u32, 13), inner_sp.col);
    try testing.expectEqual(@as(u32, 17), inner_sp.end_col); // one past the final ')'

    const outer_sp = gc.source_spans.get(outer) orelse return error.NoSpanRecorded;
    try testing.expectEqual(@as(u32, 1), outer_sp.col); // outer starts at column 1
}

test "reader span spans multiple lines" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    // A form whose open and close parens sit on different lines.
    const sp = try spanOf(&gc, "(a\n  b)");
    try testing.expectEqual(@as(u32, 1), sp.line);
    try testing.expectEqual(@as(u32, 1), sp.col);
    try testing.expectEqual(@as(u32, 2), sp.end_line);
    try testing.expectEqual(@as(u32, 5), sp.end_col); // ')' is at col 4 on line 2
}

test "reader records spans for vectors" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    const sp = try spanOf(&gc, "#(1 2 3)");
    try testing.expectEqual(@as(u32, 1), sp.col);
    try testing.expect(sp.hasEnd());
}

test "atoms get no span (only heap-keyable data)" {
    var gc = memory.GC.init(testing.allocator);
    defer gc.deinit();

    var r = reader.Reader.init(&gc, "foo");
    defer r.deinit();
    const val = try r.readDatum();
    try testing.expect(gc.source_spans.get(val) == null);
}

test "compiled function line table carries a column" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // Read an indented call so its span column is distinctive, then compile it
    // and confirm the recorded line-table entry carries that column. A free
    // global keeps the call from const-folding away.
    var r = reader.Reader.init(&ctx.gc, "  (car x)");
    defer r.deinit();
    const expr = try r.readDatum();

    const func = try compiler.compileExpressionWithMacros(&ctx.gc, expr, &ctx.vm.macros, ctx.vm.globals);
    try testing.expect(func.line_table.items.len > 0);

    var found = false;
    for (func.line_table.items) |entry| {
        if (entry.line == 1 and entry.col == 3) found = true;
    }
    try testing.expect(found);

    // locForOffset resolves the same position for an instruction offset.
    const loc = func.locForOffset(func.code.items.len - 1);
    try testing.expectEqual(@as(u32, 1), loc.line);
    try testing.expectEqual(@as(u32, 3), loc.col);
}
