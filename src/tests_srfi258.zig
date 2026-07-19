//! SRFI 258 — Uninterned Symbols.
//!
//! Behavioural coverage of the three procedures runs from Scheme in
//! tests/scheme/srfi/srfi-258.scm. These unit tests pin the parts that are only
//! visible below the language: that `allocUninternedSymbol` bypasses the intern
//! table and flags the symbol, and — the load-bearing property — that an
//! uninterned symbol is an ordinary collectable object (swept when unreachable,
//! kept when rooted), unlike an interned symbol which the intern-table root scan
//! keeps alive forever. std.testing.allocator also catches a leaked name if a
//! swept uninterned symbol ever failed to free it.

const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const GC = memory.GC;

// --- Allocation semantics --------------------------------------------------

test "allocUninternedSymbol yields distinct, unflagged symbols" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false; // deterministic; also gc-stress-safe (locals unrooted)

    const a = try gc.allocUninternedSymbol("x");
    const b = try gc.allocUninternedSymbol("x");
    const interned = try gc.allocSymbol("x");

    try std.testing.expect(types.isSymbol(a));
    try std.testing.expect(a != b); // distinct objects despite the same name
    try std.testing.expect(a != interned); // and distinct from the interned one
    try std.testing.expect(!types.symbolInterned(a));
    try std.testing.expect(!types.symbolInterned(b));
    try std.testing.expect(types.symbolInterned(interned));
    try std.testing.expectEqualStrings("x", types.symbolName(a));
}

test "allocSymbol still interns after adding the uninterned path" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    const a1 = try gc.allocSymbol("hello");
    const a2 = try gc.allocSymbol("hello");
    try std.testing.expectEqual(a1, a2); // same name → same object
    try std.testing.expect(types.symbolInterned(a1));
}

// --- Garbage collection ----------------------------------------------------

test "gc sweeps unreachable uninterned symbols" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    _ = try gc.allocUninternedSymbol("a");
    _ = try gc.allocUninternedSymbol("a"); // same name, still a second object
    _ = try gc.allocUninternedSymbol("b");
    try std.testing.expectEqual(@as(usize, 3), gc.object_count);

    gc.collect();
    // Unlike interned symbols (kept alive by the intern-table root scan),
    // uninterned symbols are ordinary collectable objects: all three, being
    // unrooted, are swept — and freeObject frees each name (no leak).
    try std.testing.expectEqual(@as(usize, 0), gc.object_count);
}

test "gc keeps interned but sweeps uninterned of the same name" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    const interned = try gc.allocSymbol("shared"); // enters the intern table
    const uninterned = try gc.allocUninternedSymbol("shared"); // does not
    try std.testing.expect(interned != uninterned);
    try std.testing.expectEqual(@as(usize, 2), gc.object_count);

    gc.collect();
    // The interned symbol survives via the intern table even though nothing
    // roots it here; the uninterned one is swept. (Kaappi's collector is
    // non-moving, so `interned` keeps its address.)
    try std.testing.expectEqual(@as(usize, 1), gc.object_count);
    try std.testing.expect(types.isSymbol(interned));
    try std.testing.expect(types.symbolInterned(interned));
    try std.testing.expectEqualStrings("shared", types.symbolName(interned));
}

test "gc preserves a rooted uninterned symbol" {
    var gc = GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.enabled = false;

    var sym = try gc.allocUninternedSymbol("kept");
    gc.pushRoot(&sym);
    _ = try gc.allocUninternedSymbol("dropped");
    try std.testing.expectEqual(@as(usize, 2), gc.object_count);

    gc.collect();
    try std.testing.expectEqual(@as(usize, 1), gc.object_count);
    try std.testing.expect(types.isSymbol(sym));
    try std.testing.expect(!types.symbolInterned(sym));
    try std.testing.expectEqualStrings("kept", types.symbolName(sym));

    gc.popRoot();
    gc.collect();
    try std.testing.expectEqual(@as(usize, 0), gc.object_count);
}

// --- Cross-thread deep copy (gc_deep_copy) ---------------------------------

test "deepCopy keeps uninterned symbols uninterned with shared identity" {
    // Models an SRFI-18 thread boundary: values are deep-copied between two
    // independent GC heaps. An uninterned symbol must stay uninterned (not be
    // re-interned by name), and repeated occurrences of the same one within a
    // single copy must stay mutually eq?.
    var gc1 = GC.init(std.testing.allocator);
    defer gc1.deinit();
    gc1.enabled = false;
    var gc2 = GC.init(std.testing.allocator);
    defer gc2.deinit();
    gc2.enabled = false;

    // A pair holding the SAME uninterned symbol in both slots.
    const u = try gc1.allocUninternedSymbol("crossing");
    const pair = try gc1.allocPair(u, u);

    const copied = try gc2.deepCopy(pair);
    const cp = types.toObject(copied).as(types.Pair);

    // Shared identity within one copy: both slots are the same new object...
    try std.testing.expectEqual(cp.car, cp.cdr);
    // ...a distinct object from the source (it lives in gc2 now)...
    try std.testing.expect(cp.car != u);
    // ...that stayed uninterned rather than being re-interned by name.
    try std.testing.expect(types.isSymbol(cp.car));
    try std.testing.expect(!types.symbolInterned(cp.car));
    try std.testing.expectEqualStrings("crossing", types.symbolName(cp.car));

    // An interned symbol still deep-copies to an interned symbol.
    const ic = try gc2.deepCopy(try gc1.allocSymbol("plain"));
    try std.testing.expect(types.symbolInterned(ic));
    try std.testing.expectEqualStrings("plain", types.symbolName(ic));
}

// --- End-to-end through the registered primitives --------------------------

test "string->uninterned-symbol is a symbol but uninterned" {
    try th.expectEvalBool("(symbol? (string->uninterned-symbol \"x\"))", true);
    try th.expectEvalBool("(symbol-interned? (string->uninterned-symbol \"x\"))", false);
}

test "symbol-interned? distinguishes ordinary symbols" {
    try th.expectEvalBool("(symbol-interned? 'x)", true);
    try th.expectEvalBool("(symbol-interned? (string->symbol \"y\"))", true);
}

test "uninterned symbols are never eqv?/equal? to like-named symbols" {
    try th.expectEvalBool("(eqv? (string->uninterned-symbol \"x\") (string->uninterned-symbol \"x\"))", false);
    try th.expectEvalBool("(equal? (string->uninterned-symbol \"x\") (string->uninterned-symbol \"x\"))", false);
    try th.expectEvalBool("(eqv? (string->uninterned-symbol \"x\") 'x)", false);
    // ...but eqv? to itself, and the name survives symbol->string.
    try th.expectEvalBool("(let ((s (string->uninterned-symbol \"x\"))) (eqv? s s))", true);
    try th.expectEvalBool("(string=? (symbol->string (string->uninterned-symbol \"abc\")) \"abc\")", true);
}

test "generate-uninterned-symbol yields fresh uninterned symbols" {
    try th.expectEvalBool("(symbol-interned? (generate-uninterned-symbol))", false);
    try th.expectEvalBool("(eqv? (generate-uninterned-symbol) (generate-uninterned-symbol))", false);
    // Prefix (string or symbol) is prepended to the generated name.
    try th.expectEvalBool("(string=? (substring (symbol->string (generate-uninterned-symbol \"pre-\")) 0 4) \"pre-\")", true);
    try th.expectEvalBool("(string=? (substring (symbol->string (generate-uninterned-symbol 'tag)) 0 3) \"tag\")", true);
}
