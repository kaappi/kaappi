// Values a primitive holds where the collector cannot see them (#2160, #2161).
//
// Two shapes, one failure mode. A primitive parks a heap `Value` outside the
// GC's view — in an `ArrayList(Value)`'s caller-owned storage, or as a
// borrowed key slice in a `StringHashMap` — and then keeps allocating. The
// next collection sees no reference and reclaims it, so the primitive later
// reads freed memory: a use-after-free abort under a stressed build, and
// silent wrong data (recycled bytes) under a plain one.
//
// `gc.stress` is a *runtime* field, not only what `-Dgc-stress=true` sets at
// comptime, so flipping it here forces a collection at every allocation on
// every build — which is what makes the #2160 cases deterministic at n = 3
// instead of needing the n = 2000 allocation storm the issue used to trip a
// default build's threshold.
//
// What the flag cannot supply is *detection*: freed-object poisoning and the
// marking-freed-object panic are both comptime (`memory.uaf_detection`, Debug
// or gc-stress). On a plain ReleaseSafe build a freed pair at these sizes is
// usually read back intact, so the #2160 cases are a live gate on the Debug
// and `-Dgc-stress=true` unit legs and only a smoke test on the plain one.
// Measured pre-fix, not assumed: the three abort with "GC: marking freed
// object" under both `-Doptimize=Debug` and `-Dgc-stress=true` — at the exact
// frame, `markRoots` marking `allocPair`'s own `arg_roots` entry, which is
// `items[i]` — and pass under plain ReleaseSafe.
//
// Bootstrapping runs unstressed: registering ~700 primitives with a
// collection per allocation costs seconds and proves nothing.

const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");

/// Evaluate `source` with a collection forced at every allocation, and expect
/// `#t`.
fn expectStressedTrue(source: []const u8) !void {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    ctx.gc.stress = true;
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(types.TRUE, result);
}

// --------------------------------------------------------------------------
// #2160 — primitives_srfi1 accumulators
//
// `buildList` conses an `ArrayList(Value)` into a list. Elements taken from
// the *input* list are fine: `args` still reaches them. Elements the
// primitive or a callback freshly allocated are reachable from nothing, and
// the next allocation — the callback's own, or buildList's first allocPair —
// frees them. Only `appendRooted` makes the buffer's contents visible.
//
// `list-tabulate` was the one #1027 missed; `zip` and `alist-copy` allocate
// their elements directly and were never covered by it at all.
// --------------------------------------------------------------------------

test "#2160: list-tabulate keeps an allocating callback's results" {
    try expectStressedTrue(
        \\(import (scheme base) (srfi 1))
        \\(equal? (list-tabulate 3 (lambda (i) (list i i)))
        \\        '((0 0) (1 1) (2 2)))
    );
}

test "#2160: list-tabulate with a non-allocating callback (control)" {
    // The discriminating control: fixnums are immediates, never heap values,
    // so this half was correct even pre-fix. If it ever fails, the bug is in
    // list-tabulate itself and not in what the accumulator can see.
    try expectStressedTrue(
        \\(import (scheme base) (srfi 1))
        \\(equal? (list-tabulate 3 values) '(0 1 2))
    );
}

test "#2160: zip keeps the rows it just allocated" {
    try expectStressedTrue(
        \\(import (scheme base) (srfi 1))
        \\(equal? (zip '(1 2 3) '(4 5 6)) '((1 4) (2 5) (3 6)))
    );
}

test "#2160: alist-copy keeps the entries it just allocated" {
    try expectStressedTrue(
        \\(import (scheme base) (srfi 1))
        \\(equal? (alist-copy '((1 . 2) (3 . 4) (5 . 6)))
        \\        '((1 . 2) (3 . 4) (5 . 6)))
    );
}

test "#2160: the accumulators #1027 already fixed stay fixed" {
    try expectStressedTrue(
        \\(import (scheme base) (srfi 1))
        \\(and (equal? (filter-map (lambda (x) (cons x x)) '(1 2 3))
        \\             '((1 . 1) (2 . 2) (3 . 3)))
        \\     (equal? (append-map (lambda (x) (list (cons x x))) '(1 2 3))
        \\             '((1 . 1) (2 . 2) (3 . 3)))
        \\     (equal? (map-in-order (lambda (x) (cons x x)) '(1 2 3))
        \\             '((1 . 1) (2 . 2) (3 . 3)))
        \\     (equal? (unfold (lambda (i) (= i 3)) (lambda (i) (cons i i))
        \\                     (lambda (i) (+ i 1)) 0)
        \\             '((0 . 0) (1 . 1) (2 . 2))))
    );
}

// --------------------------------------------------------------------------
// #2161 — the nongenerative-uid registry
//
// `%make-record-type-descriptor` keyed `record_uid_registry` by the uid
// argument's own `SchemeString` bytes. The registry outlives that transient
// string, so once it is collected the key dangles and the uid stops
// resolving: a later definition with the same uid allocates a fresh,
// non-interoperable rtd instead of reusing the registered one — silently,
// which is exactly the R6RS guarantee `nongenerative` exists to provide.
//
// Asserted here as *pointer identity*, not as an observed miss. Reproducing
// the miss needs the source string to actually be collected AND its bytes
// reused, which in-process is not something a unit test controls: a string
// literal is pinned by the compiled form's constant pool, and freed string
// data is deliberately not poisoned (`freeSliceNoFill`), so a freed key
// usually still compares equal. The `-Dgc-stress=true` run of
// tests/scheme/srfi/srfi237.scm is what observes the behaviour end to end.
// What *is* deterministic, and is the whole fix, is where the key points:
// the rtd's own owned `uid` copy, whose lifetime is the entry's, rather than
// a borrowed slice into a Value the registry does not keep alive. Same
// reasoning gc_deep_copy.zig documents at its own insert into this map.
// --------------------------------------------------------------------------

test "#2161: the registry key is the rtd's own uid, not the argument's bytes" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const rtd_val = try ctx.vm.eval(
        \\(import (scheme base) (srfi 237 primitives))
        \\(%make-record-type-descriptor
        \\  "thing" #f (string-copy "my-uid") #f #f (list (cons "v" #f)))
    );
    const owned = types.toObject(rtd_val).as(types.RecordType).uid.?;
    try std.testing.expectEqualStrings("my-uid", owned);

    const key = ctx.vm.record_uid_registry.getKey("my-uid") orelse
        return error.UidNotRegistered;
    // Pre-fix this is the argument SchemeString's `data` slice: same bytes,
    // different memory, and freed the moment that string is collected.
    try std.testing.expectEqual(owned.ptr, key.ptr);
    try std.testing.expectEqual(owned.len, key.len);
}

test "#2161: the same uid reuses the same rtd" {
    try expectStressedTrue(
        \\(import (scheme base) (srfi 237 primitives))
        \\(define (rtd uid)
        \\  (%make-record-type-descriptor
        \\    "thing" #f (and uid (string-copy uid)) #f #f (list (cons "v" #f))))
        \\(and (eq? (rtd "my-uid") (rtd "my-uid"))
        \\     (eq? (rtd "my-uid") (%record-uid->rtd (string-copy "my-uid")))
        \\     ;; controls: a different uid is a different type, and a
        \\     ;; generative type is registered under nothing at all.
        \\     (not (eq? (rtd "my-uid") (rtd "other-uid")))
        \\     (not (eq? (rtd #f) (rtd #f))))
    );
}
