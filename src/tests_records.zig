// Phase 8: Records (R7RS 5.5 define-record-type)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const hashtable = @import("primitives_hashtable.zig");

test "define-record-type basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    const p = try vm.eval("(make-point 1 2)");
    try std.testing.expect(types.isRecordInstance(p));
}

test "record predicate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try vm.eval("(define p (make-point 1 2))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(point? p)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? #t)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? '())"));
}

test "record accessors" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try vm.eval("(define p (make-point 1 2))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(point-x p)")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(point-y p)")));
}

test "record mutator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y point-y-set!))
    );
    _ = try vm.eval("(define p (make-point 1 2))");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(point-y p)")));
    _ = try vm.eval("(point-y-set! p 99)");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("(point-y p)")));
}

test "record type distinction" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try vm.eval(
        \\(define-record-type color
        \\  (make-color r g b)
        \\  color?
        \\  (r color-r)
        \\  (g color-g)
        \\  (b color-b))
    );

    _ = try vm.eval("(define p (make-point 1 2))");
    _ = try vm.eval("(define c (make-color 255 128 0))");

    // Type checking works correctly
    try std.testing.expectEqual(types.TRUE, try vm.eval("(point? p)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? c)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(color? p)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(color? c)"));

    // Accessors work on the correct types
    try std.testing.expectEqual(@as(i64, 255), types.toFixnum(try vm.eval("(color-r c)")));
    try std.testing.expectEqual(@as(i64, 128), types.toFixnum(try vm.eval("(color-g c)")));
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(try vm.eval("(color-b c)")));
}

// #1882: SRFI 237's R6RS clause grammar is ambient, so `define-record-type`
// tells the two syntaxes apart structurally. Reading only the head of the
// 2nd element captured any R7RS record whose *constructor* was named after
// a clause keyword; the 3rd element (R7RS's bare-symbol predicate, vs. an
// R6RS clause list or nothing) is what actually separates them.
test "R7RS record whose constructor is named after an R6RS clause keyword" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval(
        \\(define-record-type point
        \\  (fields x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try ctx.vm.eval(
        \\(define-record-type node
        \\  (parent l r)
        \\  node?
        \\  (l node-l)
        \\  (r node-r))
    );

    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try ctx.vm.eval("(point-x (fields 1 2))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try ctx.vm.eval("(point-y (fields 1 2))")));
    try std.testing.expectEqual(types.TRUE, try ctx.vm.eval("(point? (fields 1 2))"));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try ctx.vm.eval("(node-l (parent 3 4))")));
    try std.testing.expectEqual(types.FALSE, try ctx.vm.eval("(point? (parent 3 4))"));
}

// The other half of #1882's narrowing: every genuine R6RS form must keep
// its path, whether it has one clause (no 3rd element at all) or several
// (a clause list there).
test "R6RS clause syntax still detected after the #1882 narrowing" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    _ = try ctx.vm.eval("(define-record-type box (fields (mutable contents)))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try ctx.vm.eval("(box-contents (make-box 42))")));

    _ = try ctx.vm.eval("(define-record-type animal (fields (immutable id animal-id)))");
    _ = try ctx.vm.eval(
        \\(define-record-type (dog make-dog dog?)
        \\  (parent animal)
        \\  (fields (immutable breed dog-breed)))
    );
    _ = try ctx.vm.eval("(define rex (make-dog 7 9))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try ctx.vm.eval("(animal-id rex)")));
    try std.testing.expectEqual(@as(i64, 9), types.toFixnum(try ctx.vm.eval("(dog-breed rex)")));
    try std.testing.expectEqual(types.TRUE, try ctx.vm.eval("(animal? rex)"));
}

// The risk in narrowing a discriminator is that a form which used to be
// rejected by the parser it reached now reaches the *other* parser and
// slips through. These are the shapes near #1882's new boundary — a
// non-symbol atom, a list, and a well-formed-looking R7RS form — and each
// must still be an error whichever parser ends up seeing it.
test "malformed record forms still fail after the #1882 narrowing" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const malformed = [_][]const u8{
        // A non-symbol atom where a predicate or a clause would go: not a
        // predicate for R7RS, not a clause for R6RS.
        "(define-record-type point (fields x y) 42 (x point-x))",
        "(define-record-type point (fields x y) \"pred\" (x point-x))",
        // A list there, so still R6RS — and these are clauses it rejects
        // (unknown, and the documented `parent-rtd` gap).
        "(define-record-type point (fields x) (bogus 1))",
        "(define-record-type point (fields x) (parent-rtd r))",
        // Now reaches the R7RS parser, which must still catch a constructor
        // field with no matching field spec.
        "(define-record-type point (fields x) point?)",
        // Not a clause keyword at all, so untouched by this fix.
        "(define-record-type point (make-point x y))",
    };
    for (malformed) |src| {
        try std.testing.expectError(vm_mod.VMError.CompileError, ctx.vm.eval(src));
    }
}

test "record with mixed field types" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type person
        \\  (make-person name age)
        \\  person?
        \\  (name person-name)
        \\  (age person-age person-set-age!))
    );

    _ = try vm.eval("(define bob (make-person \"Bob\" 30))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(person? bob)"));

    // Check string field
    const name_val = try vm.eval("(person-name bob)");
    try std.testing.expect(types.isString(name_val));

    // Check fixnum field
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(try vm.eval("(person-age bob)")));

    // Mutate age
    _ = try vm.eval("(person-set-age! bob 31)");
    try std.testing.expectEqual(@as(i64, 31), types.toFixnum(try vm.eval("(person-age bob)")));
}

test "record in define-library" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (shapes)
        \\  (import (scheme base))
        \\  (export make-rect rect? rect-width rect-height)
        \\  (begin
        \\    (define-record-type rect
        \\      (make-rect width height)
        \\      rect?
        \\      (width rect-width)
        \\      (height rect-height))))
    );

    _ = try vm.eval("(import (shapes))");
    _ = try vm.eval("(define r (make-rect 10 20))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(rect? r)"));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(try vm.eval("(rect-width r)")));
    try std.testing.expectEqual(@as(i64, 20), types.toFixnum(try vm.eval("(rect-height r)")));
}

test "record-set! field survives full GC" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type <point>
        \\  (make-point x y)
        \\  point?
        \\  (x point-x set-point-x!)
        \\  (y point-y set-point-y!))
    );

    // Under -Dgc-stress=true every allocation already collects (full every
    // 8th), so a small churn count exercises promotion + full collection
    // without the marathon.
    const result = try vm.eval(if (@import("build_options").gc_stress)
        \\(let ()
        \\  (define p (make-point 1 2))
        \\  ;; Promote p to old generation
        \\  (let loop ((i 0))
        \\    (when (< i 100) (make-list 10 i) (loop (+ i 1))))
        \\  ;; Mutate with young-gen value
        \\  (set-point-y! p (list 'a 'b 'c))
        \\  ;; Force enough GC cycles to trigger full collection
        \\  (let loop ((i 0))
        \\    (when (< i 100) (make-list 10 i) (loop (+ i 1))))
        \\  (point-y p))
    else
        \\(let ()
        \\  (define p (make-point 1 2))
        \\  ;; Promote p to old generation
        \\  (let loop ((i 0))
        \\    (when (< i 3000) (make-list 10 i) (loop (+ i 1))))
        \\  ;; Mutate with young-gen value
        \\  (set-point-y! p (list 'a 'b 'c))
        \\  ;; Force enough GC cycles to trigger full collection
        \\  (let loop ((i 0))
        \\    (when (< i 3000) (make-list 10 i) (loop (+ i 1))))
        \\  (point-y p))
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expect(types.isSymbol(types.car(result)));
}

// #1973: allocRecordInstance sized its allocation as
// `@sizeOf(RecordInstance) + num_fields * @sizeOf(Value)` in u8 arithmetic
// (num_fields is a u8), so instantiating any record with >= 27 fields
// (40 + 8*27 = 256) aborted the process with an uncatchable integer-overflow
// panic. The type itself was created without complaint; only the first
// instance died. A 256-field spec was worse: parseRecordSpec admitted it and
// handleDefineRecordType's @intCast into the u8 panicked at DEFINITION time.
test "wide records: 27 and 255 fields instantiate; 256 fields error cleanly" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const a = std.testing.allocator;

    // Builds "(define-record-type big<n> (mk<n> f0 ... f<n-1>) big<n>?
    //          (f0 g<n>-0) ... )" plus "(g<n>-<n-1> (mk<n> 0 1 ... <n-1>))".
    const Gen = struct {
        fn append(buf: *std.ArrayList(u8), al: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
            const s = try std.fmt.allocPrint(al, fmt, args);
            defer al.free(s);
            try buf.appendSlice(al, s);
        }
        fn defSource(al: std.mem.Allocator, n: usize) ![]u8 {
            var buf: std.ArrayList(u8) = .empty;
            errdefer buf.deinit(al);
            try append(&buf, al, "(define-record-type big{d} (mk{d}", .{ n, n });
            for (0..n) |i| try append(&buf, al, " f{d}", .{i});
            try append(&buf, al, ") big{d}?", .{n});
            for (0..n) |i| try append(&buf, al, " (f{d} g{d}-{d})", .{ i, n, i });
            try buf.appendSlice(al, ")");
            return buf.toOwnedSlice(al);
        }
        fn probeSource(al: std.mem.Allocator, n: usize) ![]u8 {
            var buf: std.ArrayList(u8) = .empty;
            errdefer buf.deinit(al);
            try append(&buf, al, "(g{d}-{d} (mk{d}", .{ n, n - 1, n });
            for (0..n) |i| try append(&buf, al, " {d}", .{i});
            try buf.appendSlice(al, "))");
            return buf.toOwnedSlice(al);
        }
    };

    // 27 fields: the first count past the old u8 cliff.
    {
        const def = try Gen.defSource(a, 27);
        defer a.free(def);
        _ = try vm.eval(def);
        const probe = try Gen.probeSource(a, 27);
        defer a.free(probe);
        const got = try vm.eval(probe);
        try std.testing.expectEqual(@as(i64, 26), types.toFixnum(got));
    }

    // 254 fields: the syntactic ceiling. The desugared constructor body is
    // (%make-record __rt f0 ... fN-1), a call with N+1 arguments, and the
    // call ISA encodes nargs as a u8 -- so 254 fields is the widest record
    // a syntactic define-record-type can build (255 needs a 256-argument
    // call). The record TYPE itself supports 255 (procedural layer).
    {
        const def = try Gen.defSource(a, 254);
        defer a.free(def);
        _ = try vm.eval(def);
        const probe = try Gen.probeSource(a, 254);
        defer a.free(probe);
        const got = try vm.eval(probe);
        try std.testing.expectEqual(@as(i64, 253), types.toFixnum(got));
    }

    // 255 fields: the desugared %make-record call exceeds the ISA's 255-arg
    // width -- a clean, pre-existing compile error (not part of #1973).
    {
        const def = try Gen.defSource(a, 255);
        defer a.free(def);
        try std.testing.expectError(vm_mod.VMError.CompileError, vm.eval(def));
    }

    // 256 fields: over RecordType.num_fields' u8 ceiling -- must be a clean
    // compile error from parseRecordSpec, not a definition-time @intCast
    // panic in handleDefineRecordType.
    {
        const def = try Gen.defSource(a, 256);
        defer a.free(def);
        try std.testing.expectError(vm_mod.VMError.CompileError, vm.eval(def));
    }
}

// equal? recurses into record fields (kaappi#2293): two distinct instances of
// the same record type with equal? fields are equal?, while eq?/eqv? stay
// identity-based.
test "equal? structural on records" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );

    // Distinct-but-equal instances compare equal? ...
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? (make-point 1 2) (make-point 1 2))"));
    // ... but eqv?/eq? remain identity-based (spec-required).
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eqv? (make-point 1 2) (make-point 1 2))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eq? (make-point 1 2) (make-point 1 2))"));
    // A record is still equal? to itself.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(let ((p (make-point 1 2))) (equal? p p))"));
    // Differing field values are not equal?.
    try std.testing.expectEqual(types.FALSE, try vm.eval("(equal? (make-point 1 2) (make-point 1 9))"));
    // Fields are compared recursively (nested equal? contents).
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? (make-point '(1 2) \"ab\") (make-point '(1 2) \"ab\"))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(equal? (make-point '(1 2) \"ab\") (make-point '(1 2) \"ac\"))"));
}

test "equal? records of different types are not equal?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Two structurally identical but distinct record types.
    _ = try vm.eval("(define-record-type a (make-a x) a? (x a-x))");
    _ = try vm.eval("(define-record-type b (make-b x) b? (x b-x))");
    try std.testing.expectEqual(types.FALSE, try vm.eval("(equal? (make-a 1) (make-b 1))"));
    // Same type, same field: sanity check the positive case still holds.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? (make-a 1) (make-a 1))"));
}

test "equal? record with procedure field" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-record-type box (make-box p) box? (p box-p))");
    // Same closure object in both records: equal? at the leaf (identity).
    try std.testing.expectEqual(types.TRUE, try vm.eval("(let ((f (lambda (x) x))) (equal? (make-box f) (make-box f)))"));
    // Distinct closures are not equal?, so the records are not equal? either.
    try std.testing.expectEqual(types.FALSE, try vm.eval("(equal? (make-box (lambda (x) x)) (make-box (lambda (x) x)))"));
}

test "equal? cyclic records terminate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-record-type node (make-node v) node? (v node-v set-node-v!))");
    _ = try vm.eval("(define x (make-node 1))");
    _ = try vm.eval("(define y (make-node 1))");
    // Make each record point at itself -- two isomorphic cycles.
    _ = try vm.eval("(set-node-v! x x)");
    _ = try vm.eval("(set-node-v! y y)");
    // The VisitedMap must break the cycle and report the trees equal.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(equal? x y)"));
}

test "equal? records hash alike; different record types hash apart" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-record-type a (make-a x) a? (x a-x))");
    _ = try vm.eval("(define-record-type b (make-b x) b? (x b-x))");
    const a1 = try vm.eval("(make-a 1)");
    const a2 = try vm.eval("(make-a 1)");
    const b1 = try vm.eval("(make-b 1)");
    // The hash/equality contract: deepEqual is structural on records, so
    // valueHash must fold the same type identity + fields, not the address
    // (kaappi#2293). Two equal? records hash alike; a different record type
    // hashes apart even with identical field values.
    try std.testing.expectEqual(hashtable.valueHash(a1), hashtable.valueHash(a2));
    try std.testing.expect(hashtable.valueHash(a1) != hashtable.valueHash(b1));
}

// #2088: the R7RS positional define-record-type path populated no field
// metadata, so record-type-field-names (SRFI 237/240 inspection) returned #()
// and record-accessor/record-mutator/record-field-mutable? were unusable on
// such rtds. The desugarer now records each field's name and mutability
// (mutable iff the field's clause names a mutator, R7RS 5.5.1) on the rtd --
// for the top-level handler AND the body-context desugarer below.
test "R7RS define-record-type records field names and mutability on the rtd" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type <pt> (mk-pt x y) pt?
        \\  (x pt-x) (y pt-y set-pt-y!))
    );

    const rt_val = vm.globals.get(" __record_type_<pt>") orelse
        return error.TestUnexpectedResult;
    const rt = types.toObject(rt_val).as(types.RecordType);
    try std.testing.expectEqual(@as(usize, 2), rt.own_field_names.len);
    try std.testing.expectEqualStrings("x", rt.own_field_names[0]);
    try std.testing.expectEqualStrings("y", rt.own_field_names[1]);
    try std.testing.expectEqual(@as(usize, 2), rt.own_field_mutable.len);
    try std.testing.expect(!rt.own_field_mutable[0]);
    try std.testing.expect(rt.own_field_mutable[1]);
}

test "body-local R7RS define-record-type records field names too" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The lambda body's leading define-record-type goes through the
    // body-scanning desugarer (expandRecordTypeDefines), whose generated
    // %make-record-type call must carry the field specs as well. The
    // accessors it defines are locals of the body, so the rtd is reached
    // through an instance (the same route the SRFI 237 inspection layer
    // takes).
    _ = try vm.eval(
        \\(define (make-lp a b)
        \\  (define-record-type <lp> (mk-lp u v) lp? (u lp-u) (v lp-v))
        \\  (mk-lp a b))
    );
    const result = try vm.eval(
        \\(let ((rtd (%record-rtd (make-lp 1 2))))
        \\  (list (%record-type-field-names rtd)
        \\        (%record-field-mutable? rtd 0)
        \\        (%record-field-mutable? rtd 1)))
    );
    try std.testing.expect(types.isPair(result));
    const names = types.car(result);
    try std.testing.expect(types.isSymbol(types.car(names)));
    try std.testing.expectEqualStrings("u", types.symbolName(types.car(names)));
    try std.testing.expect(types.isSymbol(types.car(types.cdr(names))));
    try std.testing.expectEqualStrings("v", types.symbolName(types.car(types.cdr(names))));
    try std.testing.expect(types.isNil(types.cdr(types.cdr(names))));
    try std.testing.expectEqual(types.FALSE, types.car(types.cdr(result)));
    try std.testing.expectEqual(types.FALSE, types.car(types.cdr(types.cdr(result))));
}
