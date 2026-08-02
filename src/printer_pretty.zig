//! REPL pretty-printer (split from printer.zig under the 1500-line policy).
//!
//! Human-facing layout only: `prettyPrint` first renders the value exactly
//! via `printer.valueToString` (cycle-labelled, never truncated) and returns
//! that when it fits the terminal width. Only the multi-line layout fallback
//! below uses the bounded diagnostic `printer.printValue`, whose
//! MAX_PRINT_DEPTH cap (and per-element spine tick) keeps layout probing
//! cheap and terminating even on cyclic sub-structure -- `exactFlatLen` on a
//! cdr-cyclic value looped forever before the printer rework (the tail of
//! kaappi#859, noted in tests/scheme/compliance/printer-gaps.scm).

const std = @import("std");
const types = @import("types.zig");
const printer = @import("printer.zig");
const Value = types.Value;
const MAX_PRINT_DEPTH = printer.MAX_PRINT_DEPTH;
const printValue = printer.printValue;

pub fn prettyPrint(allocator: std.mem.Allocator, value: Value, width: u16) ![]u8 {
    const flat = try printer.valueToString(allocator, value, .write);
    if (flat.len <= width) return flat;
    allocator.free(flat);
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try ppValue(&aw.writer, value, 0, width, 0);
    return aw.toOwnedSlice();
}

fn ppValue(writer: anytype, value: Value, indent: u16, width: u16, depth: u32) anyerror!void {
    if (depth >= MAX_PRINT_DEPTH) {
        try writer.writeAll("...");
        return;
    }

    // Atoms — always single-line
    if (!types.isPair(value) and !types.isVector(value) and !types.isBytevector(value)) {
        try printValue(writer, value, .write);
        return;
    }

    // Anything that fits on one line — print flat
    const flat_len = exactFlatLen(value);
    if (indent + flat_len <= width) {
        try printValue(writer, value, .write);
        return;
    }

    // Vectors — one element per line when too wide
    if (types.isVector(value)) {
        const vec = types.toObject(value).as(types.Vector);
        try writer.writeAll("#(");
        const new_indent = indent + 2;
        for (vec.data, 0..) |elem, i| {
            if (i > 0) {
                try writer.writeByte('\n');
                try writeIndent(writer, new_indent);
            }
            try ppValue(writer, elem, new_indent, width, depth + 1);
        }
        try writer.writeByte(')');
        return;
    }

    // Bytevectors — flow-wrap (multiple bytes per line)
    if (types.isBytevector(value)) {
        const bv = types.toObject(value).as(types.Bytevector);
        try writer.writeAll("#u8(");
        const new_indent = indent + 4;
        var col: u16 = indent + 4;
        for (bv.data, 0..) |byte, i| {
            var num_buf: [4]u8 = undefined;
            var nw: std.Io.Writer = .fixed(&num_buf);
            nw.print("{d}", .{byte}) catch {};
            const num_str = nw.buffered();
            const elem_w: u16 = @intCast(num_str.len + @as(usize, if (i > 0) 1 else 0));
            if (i > 0 and col + elem_w > width) {
                try writer.writeByte('\n');
                try writeIndent(writer, new_indent);
                col = new_indent;
            } else if (i > 0) {
                try writer.writeByte(' ');
                col += 1;
            }
            try writer.writeAll(num_str);
            col += @intCast(num_str.len);
        }
        try writer.writeByte(')');
        return;
    }

    // Lists — special-form-aware indentation
    const style = specialFormStyle(value);
    try writer.writeByte('(');
    const body_indent = indent + 2;

    switch (style) {
        .body => {
            // (head arg1\n  body...) — head + first arg on line 1
            try ppValue(writer, types.car(value), body_indent, width, depth + 1);
            var cur = types.cdr(value);
            if (cur != types.NIL and types.isPair(cur)) {
                try writer.writeByte(' ');
                try ppValue(writer, types.car(cur), body_indent, width, depth + 1);
                cur = types.cdr(cur);
            }
            try ppListTail(writer, cur, body_indent, width, depth);
        },
        .clause => {
            // (head\n  clause...) — head alone on line 1
            try ppValue(writer, types.car(value), body_indent, width, depth + 1);
            try ppListTail(writer, types.cdr(value), body_indent, width, depth);
        },
        .none => {
            // Default: each element on its own line
            try ppValue(writer, types.car(value), body_indent, width, depth + 1);
            try ppListTail(writer, types.cdr(value), body_indent, width, depth);
        },
    }
    try writer.writeByte(')');
}

fn ppListTail(writer: anytype, tail: Value, indent: u16, width: u16, depth: u32) anyerror!void {
    var cur = tail;
    var count: u32 = 0;
    while (cur != types.NIL) {
        if (count >= MAX_PRINT_DEPTH) {
            try writer.writeAll(" ...");
            break;
        }
        if (!types.isPair(cur)) {
            try writer.writeByte('\n');
            try writeIndent(writer, indent);
            try writer.writeAll(". ");
            try ppValue(writer, cur, indent, width, depth + 1);
            break;
        }
        try writer.writeByte('\n');
        try writeIndent(writer, indent);
        try ppValue(writer, types.car(cur), indent, width, depth + 1);
        cur = types.cdr(cur);
        count += 1;
    }
}

fn writeIndent(writer: anytype, n: u16) !void {
    var i: u16 = 0;
    while (i < n) : (i += 1) try writer.writeByte(' ');
}

const FormStyle = enum { body, clause, none };

fn specialFormStyle(value: Value) FormStyle {
    if (!types.isPair(value)) return .none;
    const head = types.car(value);
    if (!types.isSymbol(head)) return .none;
    const name = types.symbolName(head);
    for (body_forms) |f| {
        if (std.mem.eql(u8, name, f)) return .body;
    }
    for (clause_forms) |f| {
        if (std.mem.eql(u8, name, f)) return .clause;
    }
    return .none;
}

const body_forms = [_][]const u8{
    "define",               "define-syntax",        "define-record-type",
    "define-library",       "define-values",        "lambda",
    "let",                  "let*",                 "letrec",
    "letrec*",              "let-values",           "let*-values",
    "when",                 "unless",               "begin",
    "guard",                "parameterize",         "do",
    "syntax-rules",         "dynamic-wind",         "with-exception-handler",
    "call-with-port",       "call-with-input-file", "call-with-output-file",
    "with-input-from-file", "with-output-to-file",
};

const clause_forms = [_][]const u8{ "cond", "case", "case-lambda" };

fn exactFlatLen(value: Value) u16 {
    var discard_buf: [64]u8 = undefined;
    var dw: std.Io.Writer.Discarding = .init(&discard_buf);
    printValue(&dw.writer, value, .write) catch return std.math.maxInt(u16);
    const count = dw.fullCount();
    return if (count > std.math.maxInt(u16)) std.math.maxInt(u16) else @intCast(count);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "prettyPrint short list stays single-line" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    const list_val = try gc.makeList(&items);

    const s = try prettyPrint(std.testing.allocator, list_val, 80);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(1 2 3)", s);
}

test "prettyPrint long list wraps" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var items: [20]Value = undefined;
    for (&items, 0..) |*slot, i| slot.* = types.makeFixnum(@intCast(i + 1));
    const list_val = try gc.makeList(&items);

    const s = try prettyPrint(std.testing.allocator, list_val, 40);
    defer std.testing.allocator.free(s);
    // Should wrap — check it contains newlines and starts/ends correctly
    try std.testing.expect(std.mem.indexOf(u8, s, "\n") != null);
    try std.testing.expect(std.mem.startsWith(u8, s, "(1\n"));
    try std.testing.expect(std.mem.endsWith(u8, s, "20)"));
}

test "prettyPrint vector wraps when too wide" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    var data: [15]Value = undefined;
    for (&data, 0..) |*slot, i| slot.* = types.makeFixnum(@intCast(i + 1));
    const vec = try gc.allocVector(&data);

    const s = try prettyPrint(std.testing.allocator, vec, 30);
    defer std.testing.allocator.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "\n") != null);
    try std.testing.expect(std.mem.startsWith(u8, s, "#(1\n"));
    try std.testing.expect(std.mem.endsWith(u8, s, "15)"));
}

test "prettyPrint short vector stays single-line" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const data = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    const vec = try gc.allocVector(&data);

    const s = try prettyPrint(std.testing.allocator, vec, 80);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("#(1 2 3)", s);
}

test "prettyPrint body form indentation" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (define name (+ 1 2 3 4 5 6 7 8 9 10))
    var body_items: [10]Value = undefined;
    for (&body_items, 0..) |*slot, i| slot.* = types.makeFixnum(@intCast(i + 1));
    const plus_sym = try gc.allocSymbol("+");
    var plus_args: [11]Value = undefined;
    plus_args[0] = plus_sym;
    for (plus_args[1..], 0..) |*slot, i| slot.* = body_items[i];
    var body = try gc.makeList(&plus_args);
    // Root across the allocations below — unrooted locals are swept under
    // -Dgc-stress=true (#1682).
    gc.pushRoot(&body);
    defer gc.popRoot();

    const define_sym = try gc.allocSymbol("define");
    const name_sym = try gc.allocSymbol("name");
    const define_items = [_]Value{ define_sym, name_sym, body };
    const form = try gc.makeList(&define_items);

    const s = try prettyPrint(std.testing.allocator, form, 30);
    defer std.testing.allocator.free(s);
    // Should start with "(define name" on line 1
    try std.testing.expect(std.mem.startsWith(u8, s, "(define name\n"));
}

test "prettyPrint clause form indentation" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // (cond (#t 1) (#f 2))
    const cond_sym = try gc.allocSymbol("cond");
    const clause1_items = [_]Value{ types.TRUE, types.makeFixnum(1) };
    var clause1 = try gc.makeList(&clause1_items);
    // clause1 must stay rooted while the next makeList allocates: under
    // -Dgc-stress=true that collection sweeps unrooted locals (#1682).
    gc.pushRoot(&clause1);
    defer gc.popRoot();
    const clause2_items = [_]Value{ types.FALSE, types.makeFixnum(2) };
    const clause2 = try gc.makeList(&clause2_items);
    const cond_items = [_]Value{ cond_sym, clause1, clause2 };
    const form = try gc.makeList(&cond_items);

    const s = try prettyPrint(std.testing.allocator, form, 15);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(cond\n  (#t 1)\n  (#f 2))", s);
}

test "prettyPrint terminates on a cyclic value at narrow width" {
    // Pre-rework, `exactFlatLen` fed a cdr-cyclic value to a printer with no
    // spine bound and never returned (kaappi#859's surviving tail; the REPL
    // wedged at narrow COLUMNS). The bounded printer now ticks the cap per
    // spine element, so layout probing terminates.
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    var cyc = try gc.makeList(&items);
    gc.pushRoot(&cyc);
    defer gc.popRoot();
    // (1 2 3 . <self>)
    const third = types.cdr(types.cdr(cyc));
    types.setCdr(third, cyc);

    const s = try prettyPrint(std.testing.allocator, cyc, 5);
    defer std.testing.allocator.free(s);
    try std.testing.expect(s.len > 0);
}
