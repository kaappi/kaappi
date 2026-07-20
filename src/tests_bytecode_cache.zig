// Regression tests for the .sbc bytecode cache (src/bytecode_file.zig).
//
// A program that runs correctly on a fresh compile used to fail with
// error.InvalidBytecode when re-run from its cached .sbc — but only for
// programs that allocate enough to trigger a GC mid-run (deep-mark-864.scm,
// env-uaf.scm, gcd-gc-843.scm, lambda-leak-832.scm, deep-copy-list-801.scm).
//
// Cause: deserialization rooted the loaded functions only for the duration of
// the load and dropped them from the root set on return. A collection fired
// while executing one top-level form then reclaimed the *other*, not-yet-run
// top-level functions, so calling them read freed bytecode. A fresh compile
// never hits this because main.zig keeps every compiled top-level function in
// gc.extra_roots for the whole run (see main.zig comment near compiled_funcs).

const std = @import("std");
const platform = @import("platform.zig");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const bytecode_file = @import("bytecode_file.zig");
const compiler_mod = @import("compiler.zig");
const reader_mod = @import("reader.zig");

const GC = memory.GC;
const Function = types.Function;

// A trivial top-level function: load constant #0 into r0 and return it.
fn makeReturnConstFunc(gc: *GC, n: i64) !*Function {
    const a = gc.allocator;
    const func = try gc.allocFunction();
    try func.code.append(a, @intFromEnum(types.OpCode.load_const));
    try func.code.append(a, 0); // dst hi
    try func.code.append(a, 0); // dst lo (r0)
    try func.code.append(a, 0); // const idx hi
    try func.code.append(a, 0); // const idx lo (#0)
    try func.code.append(a, @intFromEnum(types.OpCode.@"return"));
    try func.code.append(a, 0); // src hi
    try func.code.append(a, 0); // src lo (r0)
    try func.constants.append(a, types.makeFixnum(n));
    func.arity = 0;
    func.locals_count = 1;
    return func;
}

// Walk the GC's live-object lists (young + old) and report whether `obj` is
// still present. Only compares pointer identity — never dereferences `obj` —
// so it is safe to call with a pointer to an object that may have been freed.
fn gcHoldsObject(gc: *GC, obj: *types.Object) bool {
    var it = gc.objects;
    while (it) |o| : (it = o.next) {
        if (o == obj) return true;
    }
    it = gc.old_objects;
    while (it) |o| : (it = o.next) {
        if (o == obj) return true;
    }
    return false;
}

test "bytecode cache: deserialized top-level functions survive a mid-run GC" {
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Three independent top-level thunks, each returning a distinct fixnum —
    // standing in for a program's sequence of top-level forms. Root each
    // across the next helper call: they stay valid today only because
    // allocFunction happens never to collect, and this must not silently
    // break if that changes (#1682).
    const f0 = try makeReturnConstFunc(&gc, 111);
    var f0_root = types.makePointer(&f0.header);
    gc.pushRoot(&f0_root);
    defer gc.popRoot();
    const f1 = try makeReturnConstFunc(&gc, 222);
    var f1_root = types.makePointer(&f1.header);
    gc.pushRoot(&f1_root);
    defer gc.popRoot();
    const f2 = try makeReturnConstFunc(&gc, 333);

    var funcs_arr = [_]*Function{ f0, f1, f2 };
    const hash: u64 = 0x5BC0;
    const path = "/tmp/kaappi_test_sbc_survive_gc.sbc";
    try bytecode_file.writeFileWithTopLevel(allocator, &funcs_arr, hash, "test.scm", path);
    defer _ = std.posix.system.unlink(@ptrCast(path));

    const loaded = (try bytecode_file.readFileWithTopLevel(&gc, hash, path)) orelse
        return error.TestUnexpectedResult;
    defer allocator.free(loaded.funcs);
    try std.testing.expectEqual(@as(u32, 3), loaded.top_level_count);

    const want = [_]i64{ 111, 222, 333 };

    // The round-tripped bytecode executes and returns each constant.
    for (loaded.funcs[0..loaded.top_level_count], want) |func, w| {
        var fv = types.makePointer(&func.header);
        gc.pushRoot(&fv);
        defer gc.popRoot();
        const r = try vm.execute(func);
        try std.testing.expect(types.isFixnum(r));
        try std.testing.expectEqual(w, types.toFixnum(r));
    }

    // A collection that fires while the runtime sits between top-level forms
    // (nothing externally rooted) must not reclaim the loaded functions.
    // Before the fix this freed f1/f2 and the assertions below caught it.
    gc.collect();
    for (loaded.funcs) |func| {
        try std.testing.expect(gcHoldsObject(&gc, &func.header));
    }

    // ...and they remain executable after the collection.
    for (loaded.funcs[0..loaded.top_level_count], want) |func, w| {
        var fv = types.makePointer(&func.header);
        gc.pushRoot(&fv);
        defer gc.popRoot();
        const r = try vm.execute(func);
        try std.testing.expect(types.isFixnum(r));
        try std.testing.expectEqual(w, types.toFixnum(r));
    }
}

// -- .sbc serialize → deserialize → execute equivalence tests --
//
// Compile source to Functions via the bytecode compiler, serialize to a temp
// .sbc file, deserialize, execute each top-level form, and compare the result
// from the last form against the same source evaluated directly.

fn expectSbcEquivalence(source: []const u8) !void {
    const allocator = std.testing.allocator;

    // Phase 1: evaluate directly to get the expected result
    var gc1 = GC.init(allocator);
    defer gc1.deinit();
    var vm1 = try th.makeTestVM(&gc1);
    defer vm1.deinit();
    const expected = try vm1.eval(source);

    // Phase 2: compile each top-level form to a Function
    var gc2 = GC.init(allocator);
    defer gc2.deinit();
    var vm2 = try th.makeTestVM(&gc2);
    defer vm2.deinit();

    var funcs: std.ArrayList(*Function) = .empty;
    defer funcs.deinit(allocator);

    var reader = reader_mod.Reader.init(&gc2, source);
    defer reader.deinit();
    while (try reader.hasMore()) {
        const expr = try reader.readDatum();
        const func = try compiler_mod.compileExpression(&gc2, expr);
        try funcs.append(allocator, func);
    }

    // Phase 3: serialize → deserialize
    const hash: u64 = 0xE001;
    const path = "/tmp/kaappi_test_sbc_equiv.sbc";
    try bytecode_file.writeFileWithTopLevel(allocator, funcs.items, hash, "test.scm", path);
    defer _ = std.posix.system.unlink(@ptrCast(path));

    const loaded = (try bytecode_file.readFileWithTopLevel(&gc2, hash, path)) orelse
        return error.TestUnexpectedResult;
    defer allocator.free(loaded.funcs);

    // Phase 4: execute deserialized functions and compare final result
    var result: types.Value = types.VOID;
    for (loaded.funcs[0..loaded.top_level_count]) |func| {
        var fv = types.makePointer(&func.header);
        gc2.pushRoot(&fv);
        defer gc2.popRoot();
        result = try vm2.execute(func);
    }

    if (types.isFixnum(expected)) {
        try std.testing.expect(types.isFixnum(result));
        try std.testing.expectEqual(types.toFixnum(expected), types.toFixnum(result));
    } else {
        try std.testing.expectEqual(expected, result);
    }
}

test "sbc equiv: fixnum arithmetic" {
    try expectSbcEquivalence("(+ (* 3 4) 5)");
}

test "sbc equiv: conditional" {
    try expectSbcEquivalence("(if (< 1 2) 10 20)");
}

test "sbc equiv: let binding" {
    try expectSbcEquivalence("(let ((x 5) (y 3)) (+ x y))");
}

test "sbc equiv: boolean logic" {
    try expectSbcEquivalence("(and (or #f #t) (not #f))");
}

test "sbc equiv: list operations" {
    try expectSbcEquivalence("(car (cons 42 '()))");
}

test "sbc equiv: tail-recursive loop" {
    try expectSbcEquivalence(
        \\(define (loop n acc) (if (= n 0) acc (loop (- n 1) (+ acc 1))))
        \\(loop 1000 0)
    );
}
