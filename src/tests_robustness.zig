const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");

// ---------------------------------------------------------------------------
// Reader error tests
// ---------------------------------------------------------------------------

test "reader: unterminated string" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "\"hello");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnterminatedString, result);
}

test "reader: unterminated block comment" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "#| unclosed comment");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnexpectedEof, result);
}

test "reader: mismatched parenthesis" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, ")");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnexpectedRightParen, result);
}

test "reader: unterminated list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "(1 2 3");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.UnexpectedEof, result);
}

test "reader: dot outside list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, ". 42");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.DotNotInList, result);
}

test "reader: invalid character name" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "#\\nonexistent");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.InvalidCharacterName, result);
}

test "reader: nesting depth limit" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    // Build a string with 1100 nested open parens
    var buf: [2200]u8 = undefined;
    for (0..1100) |i| {
        buf[i] = '(';
    }
    for (1100..2200) |i| {
        buf[i] = ')';
    }
    var reader = reader_mod.Reader.init(&gc, &buf);
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.NestingTooDeep, result);
}

test "reader: valid nested block comment" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "#| outer #| inner |# still outer |# 42");
    defer reader.deinit();
    const result = try reader.readDatum();
    try std.testing.expect(types.isFixnum(result));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

// GC-stress smoke tests for readListTail. These verify structural integrity
// (spine length, car payloads, terminator) under gc.stress=true. They do NOT
// fail without the write barriers because markRoots traces transitively
// through old objects, so the rooted `result` keeps the entire spine alive
// regardless of remembered-set state. The barriers are verified correct by
// inspection against gc-safety.md; these tests guard against other reader
// regressions under heavy GC pressure.

test "reader: readListTail under GC stress (proper list)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.stress = true;

    var reader = reader_mod.Reader.init(&gc, "(a b c d e f g h)");
    defer reader.deinit();
    const result = try reader.readDatum();

    const expected = [_][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h" };
    var cur = result;
    var i: usize = 0;
    while (types.isPair(cur)) : (i += 1) {
        try std.testing.expectEqualStrings(expected[i], types.symbolName(types.car(cur)));
        cur = types.cdr(cur);
    }
    try std.testing.expectEqual(@as(usize, 8), i);
    try std.testing.expectEqual(types.NIL, cur);
}

test "reader: readListTail under GC stress (dotted list)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.stress = true;

    var reader = reader_mod.Reader.init(&gc, "(a b c . d)");
    defer reader.deinit();
    const result = try reader.readDatum();

    const expected = [_][]const u8{ "a", "b", "c" };
    var cur = result;
    var i: usize = 0;
    while (types.isPair(cur)) : (i += 1) {
        try std.testing.expectEqualStrings(expected[i], types.symbolName(types.car(cur)));
        cur = types.cdr(cur);
    }
    try std.testing.expectEqual(@as(usize, 3), i);
    try std.testing.expectEqualStrings("d", types.symbolName(cur));
}

test "reader: rational with zero denominator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var reader = reader_mod.Reader.init(&gc, "1/0");
    defer reader.deinit();
    const result = reader.readDatum();
    try std.testing.expectError(reader_mod.ReadError.InvalidNumber, result);
}

// ---------------------------------------------------------------------------
// Numeric overflow / bignum promotion
// ---------------------------------------------------------------------------

test "fixnum overflow promotes to bignum: addition" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 140737488355327 1)");
    try std.testing.expect(types.isBignum(result));
}

test "fixnum overflow promotes to bignum: multiplication" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(* 140737488355327 2)");
    try std.testing.expect(types.isBignum(result));
}

test "fixnum underflow promotes to bignum: subtraction" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(- -140737488355328 1)");
    try std.testing.expect(types.isBignum(result));
}

test "division by zero raises error" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (exn (#t 'caught)) (/ 1 0))");
    try std.testing.expect(types.isSymbol(result));
}

// ---------------------------------------------------------------------------
// Unicode string operations
// ---------------------------------------------------------------------------

test "string-length with multi-byte UTF-8" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(string-length \"hello\")");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(result));
}

test "string-ref with ASCII" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(char->integer (string-ref \"abc\" 1))");
    try std.testing.expectEqual(@as(i64, 98), types.toFixnum(result));
}

test "substring basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(substring \"hello world\" 6 11)");
    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("world", str.data[0..str.len]);
}

// ---------------------------------------------------------------------------
// GC stress — allocate many objects to trigger collection cycles
// ---------------------------------------------------------------------------

test "GC stress: build long list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // These three tests exist to force collection cycles. A -Dgc-stress=true
    // build already collects on every allocation, so large iteration counts
    // add no coverage there — only wall time and allocator churn (the 5000-
    // iteration string loop peaked ~19.7 GB RSS under the testing allocator
    // and got the suite OOM-killed). Scale the counts down on stress builds,
    // like tests_records.
    const result = try vm.eval(if (@import("build_options").gc_stress)
        \\(let loop ((i 0) (acc '()))
        \\  (if (= i 500)
        \\      (length acc)
        \\      (loop (+ i 1) (cons i acc))))
    else
        \\(let loop ((i 0) (acc '()))
        \\  (if (= i 10000)
        \\      (length acc)
        \\      (loop (+ i 1) (cons i acc))))
    );
    const expected_len: i64 = if (@import("build_options").gc_stress) 500 else 10000;
    try std.testing.expectEqual(expected_len, types.toFixnum(result));
}

test "GC stress: many string allocations" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // See "GC stress: build long list" for the stress-build scaling.
    const result = try vm.eval(if (@import("build_options").gc_stress)
        \\(let loop ((i 0))
        \\  (if (= i 300)
        \\      i
        \\      (begin
        \\        (string-append "hello" "world" (number->string i))
        \\        (loop (+ i 1)))))
    else
        \\(let loop ((i 0))
        \\  (if (= i 5000)
        \\      i
        \\      (begin
        \\        (string-append "hello" "world" (number->string i))
        \\        (loop (+ i 1)))))
    );
    const expected: i64 = if (@import("build_options").gc_stress) 300 else 5000;
    try std.testing.expectEqual(expected, types.toFixnum(result));
}

test "GC stress: many vector allocations" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // See "GC stress: build long list" for the stress-build scaling.
    const result = try vm.eval(if (@import("build_options").gc_stress)
        \\(let loop ((i 0))
        \\  (if (= i 300)
        \\      i
        \\      (begin
        \\        (make-vector 10 i)
        \\        (loop (+ i 1)))))
    else
        \\(let loop ((i 0))
        \\  (if (= i 5000)
        \\      i
        \\      (begin
        \\        (make-vector 10 i)
        \\        (loop (+ i 1)))))
    );
    const expected: i64 = if (@import("build_options").gc_stress) 300 else 5000;
    try std.testing.expectEqual(expected, types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Continuation edge cases
// ---------------------------------------------------------------------------

test "call/cc: normal return without invoking continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-current-continuation (lambda (k) 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/ec: escape continuation basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-escape-continuation (lambda (k) (k 99) 0))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Exception handling
// ---------------------------------------------------------------------------

test "guard catches division by zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (exn (#t (error-object-message exn)))
        \\  (/ 1 0))
    );
    try std.testing.expect(types.isString(result));
}

test "guard with re-raise" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (exn
        \\    ((string? (error-object-message exn)) "string-error"))
        \\  (error "test error" 1 2 3))
    );
    try std.testing.expect(types.isString(result));
}

// ---------------------------------------------------------------------------
// Special float values
// ---------------------------------------------------------------------------

test "special float: +inf.0" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("+inf.0");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isPositiveInf(types.toFlonum(result)));
}

test "special float: -inf.0" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("-inf.0");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNegativeInf(types.toFlonum(result)));
}

test "special float: +nan.0" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("+nan.0");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNan(types.toFlonum(result)));
}

test "nan arithmetic: nan + 1" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ +nan.0 1)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNan(types.toFlonum(result)));
}

test "inf arithmetic: inf - inf is nan" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(- +inf.0 +inf.0)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expect(std.math.isNan(types.toFlonum(result)));
}

test "root stack symmetry after compile errors" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const roots_before = gc.root_count;
    for (0..25) |_| {
        const result = vm.eval("(if 1)");
        try std.testing.expectError(th.VMError.CompileError, result);
        try std.testing.expectEqual(roots_before, gc.root_count);
    }
}

test "root stack symmetry after raised exceptions" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const roots_before = gc.root_count;
    for (0..25) |_| {
        const result = vm.eval("(raise 42)");
        try std.testing.expectError(th.VMError.ExceptionRaised, result);
        try std.testing.expectEqual(roots_before, gc.root_count);
    }
}

// ---------------------------------------------------------------------------
// GC memory_limit must respect no_collect guard (issue #7)
// ---------------------------------------------------------------------------

test "memory_limit defers collection inside no_collect section" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Root a across b's allocation: under -Dgc-stress=true it collects and
    // would sweep the unrooted pair, which the assertions below dereference.
    var a = try gc.allocPair(types.NIL, types.NIL);
    gc.pushRoot(&a);
    defer gc.popRoot();
    const b = try gc.allocPair(types.NIL, types.NIL);

    gc.no_collect += 1;

    // Set limit below current bytes so the memory_limit branch fires
    gc.memory_limit = gc.bytes_allocated - 1;

    const collections_before = gc.stats.collections;

    const c = try gc.allocPair(a, b);

    try std.testing.expectEqual(collections_before, gc.stats.collections);
    try std.testing.expect(gc.stats.no_collect_deferred > 0);
    try std.testing.expect(types.isPair(c));
    const pair = types.toObject(c).as(types.Pair);
    try std.testing.expect(types.isPair(pair.car));
    try std.testing.expect(types.isPair(pair.cdr));

    gc.no_collect -= 1;
    gc.memory_limit = null;
}

test "memory_limit collects when no_collect is zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    _ = try gc.allocPair(types.NIL, types.NIL);
    _ = try gc.allocPair(types.NIL, types.NIL);
    _ = try gc.allocPair(types.NIL, types.NIL);

    gc.memory_limit = gc.bytes_allocated - 1;

    const collections_before = gc.stats.collections;

    _ = try gc.allocPair(types.NIL, types.NIL);

    try std.testing.expect(gc.stats.collections > collections_before);
    gc.memory_limit = null;
}

test "memory_limit respects enabled flag" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    _ = try gc.allocPair(types.NIL, types.NIL);

    gc.memory_limit = gc.bytes_allocated - 1;
    gc.enabled = false;

    const collections_before = gc.stats.collections;

    _ = try gc.allocPair(types.NIL, types.NIL);

    try std.testing.expectEqual(collections_before, gc.stats.collections);

    gc.enabled = true;
    gc.memory_limit = null;
}

test "memory_limit with record-type no_collect" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    gc.memory_limit = gc.bytes_allocated * 8;

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    const result = try vm.eval("(point-x (make-point 3 4))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
    gc.memory_limit = null;
}

test "memory_limit with quasiquote no_collect" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    gc.memory_limit = gc.bytes_allocated * 8;

    const result = try vm.eval(
        \\(let ((x 1) (y 2))
        \\  (length `(,x ,y ,@(list 3 4 5))))
    );
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(result));
    gc.memory_limit = null;
}

test "macro expansion limit returns compile error deterministically" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const roots_before = gc.root_count;
    const result = vm.eval(
        \\(define-syntax loop
        \\  (syntax-rules ()
        \\    ((_ ) (loop))))
        \\(loop)
    );
    try std.testing.expectError(th.VMError.CompileError, result);
    try std.testing.expectEqual(roots_before, gc.root_count);
}

// ---------------------------------------------------------------------------
// Instruction-count execution bound (#1447)
//
// A speed-independent alternative to the wall-clock timeout_deadline_ns: the
// fuzz eval harness uses it under gc-stress, where a full collection on every
// allocation makes wall-clock time meaningless while the program still runs
// the same number of bytecode instructions.
// ---------------------------------------------------------------------------

test "vm: instruction_limit aborts a long-running loop" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A bounded loop far longer than the limit: hits the budget early, yet
    // still terminates on its own if the budget check ever regresses (so this
    // fails as a wrong value rather than hanging).
    vm.instruction_limit = 50_000;
    const result = vm.eval(
        \\(define (loop n) (if (= n 0) 'done (loop (- n 1))))
        \\(loop 100000000)
    );
    try std.testing.expectError(th.VMError.ExecutionTimeout, result);
}

test "vm: instruction_limit does not trip a short program" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A generous budget must let an ordinary program run to completion.
    vm.instruction_limit = 50_000;
    const result = try vm.eval("(let loop ((n 0) (acc 0)) (if (= n 100) acc (loop (+ n 1) (+ acc n))))");
    try std.testing.expectEqual(@as(i64, 4950), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Profile reporting vs. generational GC
// ---------------------------------------------------------------------------
// Functions that survive two minor collections are promoted from gc.objects
// to gc.old_objects (sweepYoung). The profile walkers must traverse both
// lists, or every long-lived (i.e. hottest) function silently vanishes from
// the report — a long-running program printed no profile at all.

const reporting = @import("reporting.zig");
const file_utils = @import("file_utils.zig");

fn findFunctionOnList(head: ?*types.Object, name: []const u8) ?*types.Function {
    var obj = head;
    while (obj) |o| {
        if (o.tag == .function) {
            const func = o.as(types.Function);
            if (func.name) |n| {
                if (std.mem.eql(u8, n, name)) return func;
            }
        }
        obj = o.next;
    }
    return null;
}

/// Promote long-lived objects: full collections (every 8th cycle) don't
/// promote, so 4 collects guarantee at least 3 minor ones — two survivals
/// is the promotion threshold.
fn forcePromotion(gc: *memory.GC) void {
    var i: usize = 0;
    while (i < 4) : (i += 1) gc.collect();
}

test "profile: resetProfileCounters reaches functions promoted to the old generation" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    ctx.vm.profile_mode = true;
    _ = try ctx.vm.eval("(define (profile-oldgen-fn x) (+ x 1))");
    _ = try ctx.vm.eval("(profile-oldgen-fn 41)");

    forcePromotion(&ctx.gc);

    // Setup validity: the function must really be on the old list with live
    // counters, or this test cannot distinguish a young-list-only walk.
    const func = findFunctionOnList(ctx.gc.old_objects, "profile-oldgen-fn") orelse
        return error.TestSetupFunctionNotPromoted;
    try std.testing.expect(func.profile_calls > 0);

    reporting.resetProfileCounters(&ctx.gc);
    try std.testing.expectEqual(@as(u64, 0), func.profile_calls);
}

test "profile: JSON report includes functions promoted to the old generation" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    ctx.vm.profile_mode = true;
    _ = try ctx.vm.eval("(define (profile-oldgen-json-fn x) (* x 2))");
    _ = try ctx.vm.eval("(profile-oldgen-json-fn 21)");

    forcePromotion(&ctx.gc);

    if (findFunctionOnList(ctx.gc.old_objects, "profile-oldgen-json-fn") == null)
        return error.TestSetupFunctionNotPromoted;

    const path = "/tmp/kaappi-test-profile-oldgen.json";
    reporting.writeProfileJson(&ctx.gc, path);
    defer _ = std.posix.system.unlink(path);

    const contents = try file_utils.readWholeFile(std.testing.allocator, path, 1 << 20);
    defer std.testing.allocator.free(contents);
    try std.testing.expect(std.mem.indexOf(u8, contents, "profile-oldgen-json-fn") != null);
}
