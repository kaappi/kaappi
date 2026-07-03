// Phase 1: Basic eval (integers, booleans, arithmetic, if, define, lambda, quote, set!, begin, nested)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

test "eval integer literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("42");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval boolean" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("#t"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("#f"));
}

test "eval arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval if true" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(if #t 1 2)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result));
}

test "eval if false" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(if #f 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "eval define and reference" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define x 42)");
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval lambda and call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("((lambda (x) (+ x 1)) 41)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval define function and call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define add1 (lambda (x) (+ x 1)))");
    const result = try vm.eval("(add1 10)");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "eval quote" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("'(1 2 3)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    const tail1 = types.cdr(result);
    try std.testing.expect(types.isPair(tail1));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(tail1)));
    const tail2 = types.cdr(tail1);
    try std.testing.expect(types.isPair(tail2));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(tail2)));
    try std.testing.expectEqual(types.NIL, types.cdr(tail2));
}

test "eval set!" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define x 1)");
    _ = try vm.eval("(set! x 99)");
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "eval begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define a 0)");
    _ = try vm.eval("(define b 0)");
    const result = try vm.eval("(begin (set! a 1) (set! b 2) (+ a b))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval nested arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ (* 2 3) (- 10 4))");
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(result));
}

test "breakpoint strings freed on deinit" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);

    // Simulate ,break: allocate duped name strings and store as breakpoints
    const name1 = try std.testing.allocator.dupe(u8, "foo");
    const name2 = try std.testing.allocator.dupe(u8, "bar");
    const cond = try std.testing.allocator.dupe(u8, "(> x 0)");
    vm.breakpoints[0] = .{ .name = name1, .condition = cond };
    vm.breakpoints[1] = .{ .name = name2 };
    vm.breakpoint_count = 2;

    // deinit must free the duped strings — std.testing.allocator will
    // report a leak (test failure) if any are missed
    vm.deinit();
}

test "default-random-source is per-VM" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var vm1 = try th.makeTestVM(&gc1);
    defer vm1.deinit();

    const rs1 = try vm1.eval("(default-random-source)");
    try std.testing.expect(types.isRandomSource(rs1));

    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();
    var vm2 = try th.makeTestVM(&gc2);
    defer vm2.deinit();

    const rs2 = try vm2.eval("(default-random-source)");
    try std.testing.expect(types.isRandomSource(rs2));

    // Each VM must have its own default random source
    try std.testing.expect(rs1 != rs2);

    // VM1's source must still be its own after VM2 was created
    const rs1_again = try vm1.eval("(default-random-source)");
    try std.testing.expectEqual(rs1, rs1_again);
}

test "vm deinit clears threadlocal vm_instance" {
    const vm_mod = @import("vm.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);

    // execute() registers the VM in the threadlocal
    _ = try vm.eval("(+ 1 2)");
    try std.testing.expect(vm_mod.vm_instance == &vm);

    // deinit must unregister it: a stale pointer here is read by the macro
    // expander (renameForHygiene) during the next VM's first compile, before
    // that VM's own execute() re-registers the threadlocal — a use-after-free
    // that crashed the Linux unit-test runs.
    vm.deinit();
    try std.testing.expect(vm_mod.vm_instance == null);
}

// Regression tests for issue #812: set_global/define_global must clear the
// whole global cache when they bump global_version, not just refresh their own
// slot and re-stamp cache_version. Otherwise an entry cached before an
// unrelated rebinding (which already bumped global_version) gets re-blessed and
// served stale. Each scenario lives inside one procedure body so the caching,
// the rebinding, and the re-stamping all share a single Function's cache.

test "set! of unrelated global does not re-bless stale cache (issue 812)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (g) 1)");
    _ = try vm.eval("(define counter 0)");
    _ = try vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    // f call-caches g, rebinds g (bumps global_version), then set!s an
    // unrelated global. Pre-fix that set! re-stamped f's whole cache, so the
    // tail call to g served the stale old closure and returned 1.
    _ = try vm.eval(
        \\(define (f)
        \\  (g)
        \\  (redefine!)
        \\  (set! counter 1)
        \\  (g))
    );
    const result = try vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "reference to rebound global not served stale after set! (issue 812)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (g) 1)");
    _ = try vm.eval("(define counter 0)");
    _ = try vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    // Same staleness observed via plain get_global (reference position).
    _ = try vm.eval(
        \\(define (f)
        \\  (let ((h1 g)) (h1))
        \\  (redefine!)
        \\  (set! counter 1)
        \\  (let ((h2 g)) (h2)))
    );
    const result = try vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "define_global (named let) does not re-bless stale cache (issue 812)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (g) 1)");
    _ = try vm.eval("(define (redefine!) (set! g (lambda () 2)))");
    // A named let emits define_global for its loop procedure inside f's body,
    // bumping global_version. Pre-fix that re-stamped f's cache, serving g stale.
    _ = try vm.eval(
        \\(define (f)
        \\  (g)
        \\  (redefine!)
        \\  (let loop ((n 0)) (if (> n 0) (loop (- n 1))))
        \\  (g))
    );
    const result = try vm.eval("(f)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}
