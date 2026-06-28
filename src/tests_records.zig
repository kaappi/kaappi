// Phase 8: Records (R7RS 5.5 define-record-type)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");

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

    const result = try vm.eval(
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
