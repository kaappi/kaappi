// Phase 6: Libraries (import, define-library, export)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
const library_mod = @import("library.zig");
const primitives_mod = @import("primitives.zig");
const vm_mod = @import("vm.zig");
const vm_bootstrap = @import("vm_bootstrap.zig");
const bytecode_file = @import("bytecode_file.zig");

test "import scheme base" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // (import (scheme base)) should make + available
    _ = try vm.eval("(import (scheme base))");
    const result = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "import only" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define a custom library with procedures not registered globally
    _ = try vm.eval(
        \\(define-library (test only-lib)
        \\  (import (scheme base))
        \\  (export alpha beta gamma)
        \\  (begin
        \\    (define (alpha) 1)
        \\    (define (beta) 2)
        \\    (define (gamma) 3)))
    );

    // Import only alpha and beta — gamma should be unavailable
    _ = try vm.eval("(import (only (test only-lib) alpha beta))");
    const r1 = try vm.eval("(alpha)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));
    const r2 = try vm.eval("(beta)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r2));

    // gamma was not imported — calling it must raise an error
    const r3 = vm.eval("(gamma)");
    try std.testing.expectError(th.VMError.UndefinedVariable, r3);
}

test "import except" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define a custom library with procedures not registered globally
    _ = try vm.eval(
        \\(define-library (test except-lib)
        \\  (import (scheme base))
        \\  (export foo bar baz)
        \\  (begin
        \\    (define (foo) 10)
        \\    (define (bar) 20)
        \\    (define (baz) 30)))
    );

    // Import everything except foo
    _ = try vm.eval("(import (except (test except-lib) foo))");
    const r1 = try vm.eval("(bar)");
    try std.testing.expectEqual(@as(i64, 20), types.toFixnum(r1));
    const r2 = try vm.eval("(baz)");
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(r2));

    // foo was excluded — calling it must raise an error
    const r3 = vm.eval("(foo)");
    try std.testing.expectError(th.VMError.UndefinedVariable, r3);
}

test "import rename" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (rename (scheme base) (+ add) (- subtract)))");
    const r1 = try vm.eval("(add 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r1));
    const r2 = try vm.eval("(subtract 10 3)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

test "import rename with colliding names" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test rename-coll)
        \\  (import (scheme base))
        \\  (export a b)
        \\  (begin (define (a) 1) (define (b) 2)))
    );
    _ = try vm.eval("(import (rename (test rename-coll) (a b) (b c)))");
    const r1 = try vm.eval("(b)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));
    const r2 = try vm.eval("(c)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r2));
}

test "import prefix" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (prefix (scheme base) my:))");
    const result = try vm.eval("(my:+ 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "import only rejects unknown identifier" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test only-err)
        \\  (import (scheme base))
        \\  (export alpha)
        \\  (begin (define (alpha) 1)))
    );

    const r = vm.eval("(import (only (test only-err) alpha bogus))");
    try std.testing.expectError(th.VMError.CompileError, r);
}

test "import except rejects unknown identifier" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r = vm.eval("(import (except (scheme base) totally-bogus))");
    try std.testing.expectError(th.VMError.CompileError, r);
}

test "import rename rejects unknown identifier" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r = vm.eval("(import (rename (scheme base) (totally-bogus tb)))");
    try std.testing.expectError(th.VMError.CompileError, r);
}

test "import only accepts syntax keywords" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (only (scheme base) define if car))");
    const r = try vm.eval("(car (list 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r));
}

// Regression tests for #1726: importing two libraries that export the same
// identifier with two different bindings used to silently resolve to
// whichever import came last, with no diagnostic. R7RS 5.2 says this is
// an error.

test "import raises on colliding export from two libraries" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test coll-lib-a)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'a)))
    );
    _ = try vm.eval(
        \\(define-library (test coll-lib-b)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'b)))
    );

    const r = vm.eval("(import (test coll-lib-a) (test coll-lib-b))");
    try std.testing.expectError(th.VMError.CompileError, r);
    const detail = vm.getErrorDetail();
    try std.testing.expect(std.mem.indexOf(u8, detail, "'frob'") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "(test coll-lib-a)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "(test coll-lib-b)") != null);
}

test "import collision is detected regardless of order" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test coll-lib-c)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'c)))
    );
    _ = try vm.eval(
        \\(define-library (test coll-lib-d)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'd)))
    );

    // Reversed order from the previous test -- still an error either way,
    // not "first wins" or "last wins" (kaappi#1726's repro flips which
    // binding silently won; now both orders must simply fail).
    const r = vm.eval("(import (test coll-lib-d) (test coll-lib-c))");
    try std.testing.expectError(th.VMError.CompileError, r);
    const detail = vm.getErrorDetail();
    try std.testing.expect(std.mem.indexOf(u8, detail, "(test coll-lib-d)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "(test coll-lib-c)") != null);
}

test "collision inside a library's own import declaration names that library" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test coll-inner-a)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'a)))
    );
    _ = try vm.eval(
        \\(define-library (test coll-inner-b)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'b)))
    );

    // The colliding import declaration is *inside* coll-inner, but the
    // error location cites the top-level form that triggered the load --
    // so the message itself must say which library the declaration lives
    // in (found the hard way via kaappi-mpl's sin.sld, kaappi-mpl#2).
    const r = vm.eval(
        \\(define-library (test coll-inner)
        \\  (import (test coll-inner-a) (test coll-inner-b))
        \\  (export frob)
        \\  (begin (define unused 1)))
    );
    try std.testing.expectError(th.VMError.CompileError, r);
    const detail = vm.getErrorDetail();
    try std.testing.expect(std.mem.indexOf(u8, detail, "'frob'") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "(test.coll-inner)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "own import declaration") != null);

    // The failed load must restore the context: the same collision at top
    // level stays attributed to the import form alone, not to any library.
    const r2 = vm.eval("(import (test coll-inner-a) (test coll-inner-b))");
    try std.testing.expectError(th.VMError.CompileError, r2);
    const detail2 = vm.getErrorDetail();
    try std.testing.expect(std.mem.indexOf(u8, detail2, "import declaration") == null);
    try std.testing.expect(std.mem.indexOf(u8, detail2, "'frob'") != null);
}

test "import does not raise when the same binding is reachable two ways" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A diamond re-import of the identical binding (same underlying (scheme
    // base) `car`, reached directly and through `only`) is not "two
    // different bindings" and must not be rejected.
    _ = try vm.eval("(import (scheme base) (only (scheme base) car))");
    const r = try vm.eval("(car (list 7 8))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r));

    // Importing the exact same library twice, directly, is likewise fine.
    _ = try vm.eval("(import (scheme base) (scheme base))");
}

test "import collision can be resolved with rename" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test coll-lib-e)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'e)))
    );
    _ = try vm.eval(
        \\(define-library (test coll-lib-f)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'f)))
    );

    _ = try vm.eval("(import (test coll-lib-e) (rename (test coll-lib-f) (frob frob-f)))");
    const r1 = try vm.eval("(frob)");
    try std.testing.expectEqualStrings("e", types.symbolName(r1));
    const r2 = try vm.eval("(frob-f)");
    try std.testing.expectEqualStrings("f", types.symbolName(r2));
}

test "import collision does not span separate top-level import forms" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (test coll-lib-g)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'g)))
    );
    _ = try vm.eval(
        \\(define-library (test coll-lib-h)
        \\  (import (scheme base))
        \\  (export frob)
        \\  (begin (define (frob) 'h)))
    );

    // Two SEPARATE (import ...) forms deliberately re-binding the same name
    // stay legal, exactly like ordinary top-level redefinition -- the
    // #1726 check is scoped to one import form, not the whole program.
    _ = try vm.eval("(import (test coll-lib-g))");
    _ = try vm.eval("(import (test coll-lib-h))");
    const r = try vm.eval("(frob)");
    try std.testing.expectEqualStrings("h", types.symbolName(r));
}

test "import scheme r5rs exports full R5RS identifier set" {
    // Regression for #813: the built-in (scheme r5rs) stub exported only 4
    // identifiers (null-environment, scheme-report-environment, eval,
    // interaction-environment). Per R7RS Appendix A it must provide the full
    // R5RS set. A prefix import exposes the real export table (plain imports
    // are masked because every primitive is also present in globals).
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (prefix (scheme r5rs) r5:))");

    // Procedures that were missing from the 4-name stub.
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(r5:car '(1 2))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(r5:sqrt 4)")));
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(try vm.eval("(r5:+ 1 2 3)")));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(r5:procedure? r5:map)"));
    // exact/inexact appear under their R5RS names.
    try std.testing.expectEqual(types.TRUE, try vm.eval("(r5:procedure? r5:exact->inexact)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(r5:procedure? r5:inexact->exact)"));
    // The four originally-exported identifiers still resolve.
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(r5:eval '(+ 1 2) (r5:interaction-environment))")));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(r5:procedure? r5:null-environment)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(r5:procedure? r5:scheme-report-environment)"));
}

test "import scheme write" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // After importing (scheme write), display/write/newline should be available
    // We test availability by checking they are procedures
    _ = try vm.eval("(import (scheme write))");
    const result = try vm.eval("(procedure? display)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "import scheme inexact" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (scheme inexact))");
    const result = try vm.eval("(sin 0)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), types.toFlonum(result), 1e-10);
}

test "import multiple libraries" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (scheme base) (scheme inexact))");
    const r1 = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));
    const r2 = try vm.eval("(cos 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), types.toFlonum(r2), 1e-10);
}

test "define-library and import" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Define a custom library
    _ = try vm.eval(
        \\(define-library (mylib)
        \\  (import (scheme base))
        \\  (export double)
        \\  (begin
        \\    (define (double x) (* x 2))))
    );

    // Import and use it
    _ = try vm.eval("(import (mylib))");
    const result = try vm.eval("(double 21)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "define-library with multiple exports" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (math-utils)
        \\  (import (scheme base))
        \\  (export square cube)
        \\  (begin
        \\    (define (square x) (* x x))
        \\    (define (cube x) (* x x x))))
    );

    _ = try vm.eval("(import (math-utils))");
    const r1 = try vm.eval("(square 5)");
    try std.testing.expectEqual(@as(i64, 25), types.toFixnum(r1));
    const r2 = try vm.eval("(cube 3)");
    try std.testing.expectEqual(@as(i64, 27), types.toFixnum(r2));
}

test "define-library with dotted name" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (my utils math)
        \\  (import (scheme base))
        \\  (export add5)
        \\  (begin
        \\    (define (add5 x) (+ x 5))))
    );

    _ = try vm.eval("(import (my utils math))");
    const result = try vm.eval("(add5 10)");
    try std.testing.expectEqual(@as(i64, 15), types.toFixnum(result));
}

// Regression tests for #868: cond-expand (library ...) must detect .sld
// libraries that are loadable but not yet imported, using the same search
// order as import itself (libraryFileExists in vm_library.zig).
test "cond-expand (library ...) detects an unloaded .sld on the lib path" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "condlib");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "condlib/feature.sld",
        .data = "(define-library (condlib feature) (export feature-value) (begin (define feature-value 7)))",
    });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(vm);
    vm.lib_paths = &[_][]const u8{dir_path};

    // Expression context: checked by the compiler's evalFeatureReq.
    const r1 = try vm.eval("(cond-expand ((library (condlib feature)) 1) (else 0))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));

    // Unknown libraries must stay undetected.
    const r2 = try vm.eval("(cond-expand ((library (condlib nonexistent)) 1) (else 0))");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r2));

    // Declaration context: checked by evalLibFeatureReq inside define-library.
    _ = try vm.eval(
        \\(define-library (test condlib-probe)
        \\  (import (scheme base))
        \\  (export probe)
        \\  (cond-expand
        \\    ((library (condlib feature)) (begin (define probe 1)))
        \\    (else (begin (define probe 0)))))
    );
    _ = try vm.eval("(import (test condlib-probe))");
    const r3 = try vm.eval("probe");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r3));

    // A library detected by cond-expand must actually import.
    _ = try vm.eval("(import (condlib feature))");
    const r4 = try vm.eval("feature-value");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r4));
}

// Regression test: a .sld library must load with all its exports even when a
// hash-matching .sbc sits next to it. The old cache-read path in
// tryLoadLibraryFromFile accepted such a file and reconstructed exports by
// re-parsing the .sld top level only — silently dropping exports declared via
// include-library-declarations or nested in cond-expand, so the import
// succeeded with no bindings. .sbc files are now ignored for .sld libraries.
test "stale .sbc next to .sld must not drop include-library-declarations exports" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "cachedlib");

    const sld_source =
        \\(define-library (cachedlib mylib)
        \\  (import (scheme base))
        \\  (include-library-declarations "decls.scm")
        \\  (cond-expand
        \\    (kaappi (export extra) (begin (define extra 99))))
        \\  (begin (define answer 42)))
    ;
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "cachedlib/mylib.sld",
        .data = sld_source,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "cachedlib/decls.scm",
        .data = "(export answer)",
    });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    // Hand-build a valid .sbc with a matching source hash — exactly what the
    // removed cache-read path treated as a cache hit. Its single top-level
    // function just returns void, so on a bogus cache hit the library body
    // never runs and no exports get defined.
    const sbc_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/cachedlib/mylib.sbc", .{dir_path});
    defer std.testing.allocator.free(sbc_path);
    {
        var sbc_gc = memory.GC.init(std.testing.allocator);
        defer sbc_gc.deinit();
        const func = try sbc_gc.allocFunction();
        try func.code.append(std.testing.allocator, @intFromEnum(types.OpCode.load_void));
        try func.code.append(std.testing.allocator, 0); // dst high
        try func.code.append(std.testing.allocator, 0); // dst low
        try func.code.append(std.testing.allocator, @intFromEnum(types.OpCode.@"return"));
        try func.code.append(std.testing.allocator, 0); // src high
        try func.code.append(std.testing.allocator, 0); // src low
        func.locals_count = 1;
        var funcs_arr = [_]*types.Function{func};
        try bytecode_file.writeFileWithTopLevel(std.testing.allocator, &funcs_arr, bytecode_file.sourceHash(sld_source), "cachedlib/mylib.sld", sbc_path);
    }

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(vm);
    vm.lib_paths = &[_][]const u8{dir_path};

    _ = try vm.eval("(import (cachedlib mylib))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("answer")));
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("extra")));

    // Importing again must serve the registered library, exports intact.
    _ = try vm.eval("(import (cachedlib mylib))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("answer")));
}

test "imported macro chain resolves library-internal bindings" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // SRFI 64 pattern: an exported macro expands into an internal helper
    // macro whose template references a non-exported procedure
    // (test-assert -> %test-comp1body -> %test-on-test-begin). The internal
    // procedure must be reachable from the use-site expansion even though
    // only the outer macro was imported.
    _ = try vm.eval(
        \\(define-library (chainlib)
        \\  (import (scheme base))
        \\  (export outer)
        \\  (begin
        \\    (define (%internal x) (+ x 1))
        \\    (define-syntax %helper
        \\      (syntax-rules ()
        \\        ((_ e) (%internal e))))
        \\    (define-syntax outer
        \\      (syntax-rules ()
        \\        ((_ e) (%helper e))))))
    );
    _ = try vm.eval("(import (chainlib))");
    const result = try vm.eval("(outer 41)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "re-registering a library keeps old closures' lib_env alive (#820)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // f closes over the library env to look up the non-exported `secret`.
    _ = try vm.eval(
        \\(define-library (foo bar)
        \\  (import (scheme base))
        \\  (export f)
        \\  (begin
        \\    (define secret 42)
        \\    (define (f) secret)))
    );
    _ = try vm.eval("(import (foo bar))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("(f)")));

    // Re-register the same library name; the old lib_env must be retired,
    // not freed, because f still references it via Function.env.
    _ = try vm.eval(
        \\(define-library (foo bar)
        \\  (import (scheme base))
        \\  (export g)
        \\  (begin (define (g) 99)))
    );

    // Calling the stale closure must still resolve `secret` in the old env.
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("(f)")));

    // And the replacement library works normally.
    _ = try vm.eval("(import (foo bar))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("(g)")));
}

test "retired lib_env values survive GC (#820)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (gc lib)
        \\  (import (scheme base))
        \\  (export get)
        \\  (begin
        \\    (define stash (list 1 2 3))
        \\    (define (get) stash)))
    );
    _ = try vm.eval("(import (gc lib))");
    _ = try vm.eval(
        \\(define-library (gc lib)
        \\  (import (scheme base))
        \\  (export other)
        \\  (begin (define (other) 0)))
    );

    // Allocation churn to force collections; `stash` is only reachable
    // through the retired env, which markVMRoots must trace. Under
    // -Dgc-stress=true every cons already collects and the growing list
    // makes marking O(n²), so a small count churns just as decisively.
    _ = try vm.eval(if (@import("build_options").gc_stress)
        \\(let churn ((n 500) (acc '()))
        \\  (if (= n 0) acc (churn (- n 1) (cons n acc))))
    else
        \\(let churn ((n 50000) (acc '()))
        \\  (if (= n 0) acc (churn (- n 1) (cons n acc))))
    );
    const result = try vm.eval("(length (get))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "every spec name resolves in globals (drift guard)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    for (&primitives_mod.all_specs) |spec| {
        // A `.wasm = false` spec is deliberately not registered on wasm32-wasi
        // — registerAll gates it with `if (!is_wasm or spec.wasm)`, so on this
        // target its absence is the rule, not drift (kaappi#2018).
        if (comptime platform.is_wasm) {
            if (!spec.wasm) continue;
        }
        // The helpers vm_bootstrap.install() removes from globals after the
        // bootstrapped closures capture them (#1375) must NOT resolve —
        // calling %push-wind or a %promise-* mutator out of sequence
        // corrupts VM state. Every other spec must, `.internal` included:
        // being unexported is not being unreachable (#1856).
        const purged = for (&vm_bootstrap.internal_helpers) |name| {
            if (std.mem.eql(u8, name, spec.name)) break true;
        } else false;
        if (purged) {
            if (vm.globals.get(spec.name) != null) {
                std.debug.print("DRIFT: purged spec \"{s}\" is still in globals\n", .{spec.name});
                return error.TestUnexpectedResult;
            }
            continue;
        }
        if (vm.globals.get(spec.name) == null) {
            std.debug.print("DRIFT: spec \"{s}\" is not in globals\n", .{spec.name});
            return error.TestUnexpectedResult;
        }
    }
}

test "purged %unwind-to-escape still resolves for guard's desugaring (#2037)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Purged from globals like its %push-wind sibling — user code cannot pop
    // the wind stack out of sequence. But unlike the sibling it has a
    // compile-time consumer: compileGuard emits a base-binding reference that
    // resolves through libraries.internal_bindings, and the registrar's
    // snapshot of globals runs only AFTER the purge, so vm_bootstrap.install
    // seeds the entry itself. Dropping either half breaks every guard.
    try std.testing.expect(vm.globals.get("%unwind-to-escape") == null);
    try std.testing.expect(vm.libraries.internal_bindings.get("%unwind-to-escape") != null);
    const r = try vm.eval("(guard (e (#t 42)) (raise 'boom))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r));
    // And the wind discipline survives the seeded path: the clauses must see
    // the after-thunks of extents entered in the body already run (#1988).
    const order = try vm.eval(
        \\(let ((log '()))
        \\  (guard (e (#t (set! log (cons 'clause log)) 'done))
        \\    (dynamic-wind (lambda () (set! log (cons 'B log)))
        \\                  (lambda () (raise 'x))
        \\                  (lambda () (set! log (cons 'A log)))))
        \\  (reverse log))
    );
    try std.testing.expect(types.isPair(order));
    var it = order;
    const expected = [_][]const u8{ "B", "A", "clause" };
    for (expected) |name| {
        try std.testing.expect(types.isSymbol(types.car(it)));
        try std.testing.expectEqualStrings(name, types.symbolName(types.car(it)));
        it = types.cdr(it);
    }
    try std.testing.expectEqual(types.NIL, it);
}

test "no standard library exports a %-prefixed internal (#1856)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The comptime guard in primitives.zig covers the spec tables; this
    // covers the assembled export sets, which also draw on
    // library.extra_exports and would not be caught there.
    var it = vm.libraries.libraries.iterator();
    while (it.next()) |entry| {
        const lib_name = entry.key_ptr.*;
        if (!std.mem.startsWith(u8, lib_name, "scheme.")) continue;
        var exports = entry.value_ptr.exports.iterator();
        while (exports.next()) |e| {
            if (e.key_ptr.*[0] == '%') {
                std.debug.print("DRIFT: {s} exports \"{s}\"\n", .{ lib_name, e.key_ptr.* });
                return error.TestUnexpectedResult;
            }
        }
    }
}

test "(kaappi primitives) exports what the portable .slds import (#1856)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // lib/srfi/{27,74,271/*,57,131,136,150,237}.sld name these in Scheme
    // source and import (kaappi primitives) for them. A .sld cannot spell the
    // base_binding_prefix compiler-synthesized references use, so this export
    // is the only declared route — losing it breaks those libraries at load.
    const lib = vm.libraries.get("kaappi.primitives") orelse {
        std.debug.print("(kaappi primitives) is not registered\n", .{});
        return error.TestUnexpectedResult;
    };
    for ([_][]const u8{
        "%make-record",                 "%make-record-type",            "%record?",
        "%record-ref",                  "%record-set!",                 "%host-big-endian?",
        "%rs-next-int",                 "%rs-next-real",                "%default-random-source",
        "%random-port?",                "%random-port-state",           "%random-port-make-from-seed",
        "%random-port-make-from-state", "%random-port-make-randomized",
    }) |name| {
        if (lib.exports.get(name) == null) {
            std.debug.print("(kaappi primitives) is missing \"{s}\"\n", .{name});
            return error.TestUnexpectedResult;
        }
        // Same spec is `.internal` too, which is what puts it in the pristine
        // snapshot the compiler resolves against — the two halves are
        // independent and both load-bearing.
        if (vm.libraries.internal_bindings.get(name) == null) {
            std.debug.print("\"{s}\" is missing from internal_bindings\n", .{name});
            return error.TestUnexpectedResult;
        }
    }
}

// A user library may define its own %-prefixed name and still import
// (scheme base): #1856's exact failure was the R7RS 5.2 collision check
// (#1726) firing between (scheme base)'s %length and the user's own.
test "user library may define %length alongside (scheme base) (#1856)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (mylib ffi)
        \\  (import (scheme base))
        \\  (export %length)
        \\  (begin (define (%length s) (string-length s))))
    );
    _ = try vm.eval(
        \\(define-library (mylib)
        \\  (import (scheme base) (mylib ffi))
        \\  (export byte-length)
        \\  (begin (define (byte-length s) (%length s))))
    );
    _ = try vm.eval("(import (mylib))");
    const result = try vm.eval("(byte-length \"hi\")");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));

    // ... and case-lambda's arity dispatch still counts arguments with the
    // real list-length inside that same library, rather than picking up the
    // user's one-argument string-length (#1714 via #1715's pristine
    // (scheme base) reference — the former %length alias, being an ordinary
    // global, would have lost to the import here).
    _ = try vm.eval(
        \\(define-library (mylib cl)
        \\  (import (scheme base) (mylib ffi))
        \\  (export pick)
        \\  (begin
        \\    (define pick (case-lambda ((a) 'one) ((a b) 'two)))))
    );
    _ = try vm.eval("(import (mylib cl))");
    const two = try vm.eval("(pick 1 2)");
    try std.testing.expect(types.isSymbol(two));
    try std.testing.expectEqualStrings("two", types.toObject(two).as(types.Symbol).name);
}

// ── SRFI 261 (#1645): portable SRFI library references ──────────────────────
// (srfi srfi-<n>) and (srfi <mnemonic>-<n>) resolve to (srfi <n>) as a
// fallback; literal names win. Disk-backed forms are covered by
// tests/scheme/srfi/srfi261.scm — these tests stay registry-only.

const vm_library = @import("vm_library.zig");
const reader_mod = @import("reader.zig");

test "srfi 261: suffix parser accepts trailing -<digits> only" {
    const s = vm_library.srfi261Suffix;
    try std.testing.expectEqual(@as(?i64, 1), s("srfi-1"));
    try std.testing.expectEqual(@as(?i64, 1), s("lists-1"));
    try std.testing.expectEqual(@as(?i64, 69), s("basic-hash-tables-69"));
    try std.testing.expectEqual(@as(?i64, 133), s("vectors-133"));
    try std.testing.expectEqual(@as(?i64, 1), s("a-01")); // leading zeros parse
    try std.testing.expectEqual(@as(?i64, null), s("srfi"));
    try std.testing.expectEqual(@as(?i64, null), s("srfi-"));
    try std.testing.expectEqual(@as(?i64, null), s("-1")); // no prefix before the dash
    try std.testing.expectEqual(@as(?i64, null), s("lists-nope"));
    try std.testing.expectEqual(@as(?i64, null), s("lists-1x"));
    try std.testing.expectEqual(@as(?i64, null), s("a-+5")); // a sign is not a digit
    try std.testing.expectEqual(@as(?i64, null), s("a-99999999999999999999")); // overflow
}

test "srfi 261: buildSrfi261RelPath splices the number over the second segment" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    gc.no_collect += 1;

    const cases = [_]struct { src: []const u8, want: ?[]const u8 }{
        .{ .src = "(srfi srfi-2)", .want = "srfi/2.sld" },
        .{ .src = "(srfi vectors-133)", .want = "srfi/133.sld" },
        .{ .src = "(srfi lists-146 hash)", .want = "srfi/146/hash.sld" },
        .{ .src = "(srfi 2)", .want = null }, // already numeric
        .{ .src = "(scheme base)", .want = null }, // not srfi
        .{ .src = "(srfi srfi-)", .want = null }, // no digits
    };
    for (cases) |c| {
        var rdr = reader_mod.Reader.init(&gc, c.src);
        defer rdr.deinit();
        const name = try rdr.readDatum();
        var buf: [512]u8 = undefined;
        const got = vm_library.buildSrfi261RelPath(name, &buf);
        if (c.want) |w| {
            try std.testing.expectEqualStrings(w, got.?);
        } else {
            try std.testing.expect(got == null);
        }
    }
}

test "srfi 261: (srfi srfi-1) and (srfi lists-1) resolve to built-in (srfi 1)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (srfi srfi-1))");
    const r1 = try vm.eval("(fold + 0 (list 1 2 3))");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(r1));

    // Mnemonic form composes with import modifiers.
    _ = try vm.eval("(import (only (srfi lists-1) last))");
    const r2 = try vm.eval("(last (list 1 2 3))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r2));
}

test "srfi 261: sub-library components pass through" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (srfi srfi-254 ephemerons))");
    const r = try vm.eval("(procedure? make-ephemeron)");
    try std.testing.expect(r == types.TRUE);
}

test "srfi 261: a literal registry name shadows the rewrite" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // srfi/4.sld exists on disk, but a library registered under the literal
    // hyphenated name must win over normalizing to (srfi 4).
    _ = try vm.eval(
        \\(define-library (srfi srfi-4)
        \\  (import (scheme base))
        \\  (export srfi261-shadow-marker)
        \\  (begin (define srfi261-shadow-marker 42)))
    );
    _ = try vm.eval("(import (srfi srfi-4))");
    const r = try vm.eval("srfi261-shadow-marker");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r));
}

test "srfi 261: malformed and missing names fail as library-not-found" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // No trailing digits: not a 261 form, plain not-found under the literal name.
    try std.testing.expectError(th.VMError.CompileError, vm.eval("(import (srfi srfi-))"));
    var detail = vm.last_error_detail[0..vm.last_error_detail_len];
    try std.testing.expect(std.mem.startsWith(u8, detail, "library not found: (srfi.srfi-)"));

    try std.testing.expectError(th.VMError.CompileError, vm.eval("(import (srfi lists-nope))"));

    // Well-formed 261 name whose target doesn't exist: the message names the
    // original spelling and the resolved number.
    try std.testing.expectError(th.VMError.CompileError, vm.eval("(import (srfi srfi-99999))"));
    detail = vm.last_error_detail[0..vm.last_error_detail_len];
    try std.testing.expect(std.mem.indexOf(u8, detail, "(srfi.srfi-99999)") != null);
    try std.testing.expect(std.mem.indexOf(u8, detail, "srfi 261 form of (srfi 99999)") != null);
}

test "srfi 261: cond-expand (library ...) sees 261 forms" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(cond-expand ((library (srfi srfi-1)) 1) (else 0))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));
    const r2 = try vm.eval("(cond-expand ((library (srfi srfi-99999)) 1) (else 0))");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r2));
}

// ── SRFI 0 srfi-<n> cond-expand feature identifiers (#1649) ─────────────────
// A supported SRFI is probeable as the feature id `srfi-<n>`, routed through
// the same availability check as (library (srfi <n>)) so built-in, portable,
// sandbox and WASM answers all match what (import (srfi <n>)) would do.

test "srfi-N feature: number parser requires the srfi- prefix (#1649)" {
    const f = vm_library.srfiFeatureNumber;
    try std.testing.expectEqual(@as(?i64, 1), f("srfi-1"));
    try std.testing.expectEqual(@as(?i64, 0), f("srfi-0"));
    try std.testing.expectEqual(@as(?i64, 261), f("srfi-261"));
    try std.testing.expectEqual(@as(?i64, 170), f("srfi-170"));
    // Unlike srfi261Suffix, a bare mnemonic form is not a feature id.
    try std.testing.expectEqual(@as(?i64, null), f("lists-1"));
    try std.testing.expectEqual(@as(?i64, null), f("vectors-133"));
    // Non-srfi platform features never look like one.
    try std.testing.expectEqual(@as(?i64, null), f("kaappi-threads"));
    try std.testing.expectEqual(@as(?i64, null), f("kaappi-shared-channels"));
    try std.testing.expectEqual(@as(?i64, null), f("r7rs"));
    // Malformed / noncanonical srfi- forms.
    try std.testing.expectEqual(@as(?i64, null), f("srfi-")); // no digits
    try std.testing.expectEqual(@as(?i64, null), f("srfi")); // no dash
    try std.testing.expectEqual(@as(?i64, null), f("srfi-1x")); // trailing non-digit
    try std.testing.expectEqual(@as(?i64, null), f("srfi-1-2")); // extra dash
    try std.testing.expectEqual(@as(?i64, null), f("srfi-99999999999999999999")); // overflow
    // Leading zeros normalize (as in srfi261Suffix), e.g. srfi-01 → 1.
    try std.testing.expectEqual(@as(?i64, 1), f("srfi-01"));
}

test "srfi-N feature: cond-expand resolves built-in, portable, 261, and unknown (#1649)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Built-in SRFI (registered in vm.libraries).
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand (srfi-1 1) (else 0))")));
    // SRFI 261 is a naming convention with no .sld, but still supported (#1645).
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand (srfi-261 1) (else 0))")));
    // A number no SRFI uses is false.
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(try vm.eval("(cond-expand (srfi-99999 1) (else 0))")));
    // Composes with and/or/not and matches the (library ...) spelling.
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand ((and srfi-1 srfi-261) 1) (else 0))")));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand ((not srfi-99999) 1) (else 0))")));

    // Portable SRFI resolves via the on-disk .sld probe (skip if tree absent).
    if (platform.pathExists("lib/srfi/2.sld")) {
        try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand (srfi-2 1) (else 0))")));
    }
}

test "srfi-N feature: works inside define-library (evalLibFeatureReq) (#1649)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The cond-expand here is a library declaration, evaluated by
    // evalLibFeatureReq (not the compiler's evalFeatureReq).
    _ = try vm.eval(
        \\(define-library (test feat-lib)
        \\  (export marker)
        \\  (cond-expand
        \\    (srfi-1 (begin (define marker 'has-1)))
        \\    (else   (begin (define marker 'no-1)))))
    );
    _ = try vm.eval("(import (test feat-lib))");
    try std.testing.expectEqualStrings("has-1", types.symbolName(try vm.eval("marker")));
}

// Regression companion to "cond-expand library check honors sandbox mode":
// a portable SRFI's srfi-<n> feature id must track availability under
// --sandbox exactly as (library (srfi <n>)) does — both go through
// libraryIsAvailable, so a disk-only SRFI is false when sandboxed.
test "srfi-N feature: portable srfi id honors sandbox mode (#1649)" {
    if (!platform.pathExists("lib/srfi/2.sld")) return error.SkipZigTest;

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand (srfi-2 1) (else 0))")));

    vm.sandbox_mode = true;
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(try vm.eval("(cond-expand (srfi-2 1) (else 0))")));
    // A built-in, sandbox-allowed SRFI stays true under sandbox.
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond-expand (srfi-1 1) (else 0))")));
}

// ── Top-level cond-expand splices its body as top-level forms (#1661) ────────
// R7RS 4.2.1: a top-level cond-expand expands to the selected clause's forms in
// a top-level context, so declarations that only work at top level (import,
// define, define-library, ...) nested in the matched clause must work. Before
// the fix the whole form compiled as an expression, where `import` was not a
// recognized form and `(srfi 1)` read as a call to an undefined `srfi` — the
// program printed KP3001 and exited 1 even though the import still ran.

test "top-level cond-expand splices a nested import via else (#1661)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Old behavior raised UndefinedVariable here; now it splices and imports.
    _ = try vm.eval("(cond-expand (else (import (srfi 1))))");
    // The import's side effect is visible: fold comes from (srfi 1).
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(try vm.eval("(fold + 0 '(1 2 3))")));
}

test "top-level cond-expand: matched srfi-N guard imports cleanly (#1661)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The idiomatic #1649 probe: the srfi-1 clause is selected by
    // evalLibFeatureReq and its nested import runs as a top-level form.
    _ = try vm.eval("(cond-expand (srfi-1 (import (srfi 1))) (else (error \"no srfi-1\")))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(try vm.eval("(fold + 0 '(1 2 3 4))")));
}

test "top-level cond-expand still yields a value as an expression (#1661)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A matched clause whose body is an expression: the spliced begin returns
    // its last form's value, so a bare top-level cond-expand is still a value.
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("(cond-expand (else 42))")));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(cond-expand (srfi-1 3) (else 0))")));

    // cond-expand in expression position (not the top-level datum) still goes
    // through the compiler and composes inside a larger expression.
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try vm.eval("(+ 1 (cond-expand (else 6)))")));

    // No clause matches and there is no else: void, not an error (matching the
    // expression-position compiler in compiler_conditionals.compileCondExpand).
    try std.testing.expectEqual(types.VOID, try vm.eval("(cond-expand (no-such-feature 1))"));
}

test "top-level cond-expand malformed-form parity with the compiler (#1661)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // A matched clause returns immediately and never inspects later clauses —
    // so a bare symbol after a matched else is ignored, not a syntax error,
    // exactly as the expression-position compiler treats it.
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try vm.eval("(cond-expand (else 42) trailing-junk)")));

    // A non-pair where a clause is expected is a syntax error, like the compiler.
    try std.testing.expectError(error.CompileError, vm.eval("(cond-expand not-a-clause)"));

    // An improper clause-list tail reached without a match is the syntax error
    // the compiler reports for the same form in expression position.
    try std.testing.expectError(error.CompileError, vm.eval("(cond-expand (no-such-feature 1) . junk)"));

    // An improper selected clause body is likewise rejected, rather than
    // silently splicing the proper prefix and dropping the tail.
    try std.testing.expectError(error.CompileError, vm.eval("(cond-expand (else 1 . junk))"));
}

// Regression for #1831: a library body referencing a global that is registered
// in vm.globals but absent from its own lib_env resolved in tail position only.
// The compiler picks a global-reference opcode purely by syntactic position —
// get_global plus a plain tail_call for a tail call's operator, the call_global
// superinstruction everywhere else — and only get_global carried the vm.globals
// fallback library code needs (455f5cc2). So `(cadar x)` worked as a body's last
// form and raised "undefined variable 'cadar'" one position over, which surfaced
// as a bare `invalid syntax` when the caller ran at macro-expansion time.
test "library resolves a non-imported global in every syntactic position (#1831)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // `cadar` belongs to (scheme cxr); this library imports only (scheme base),
    // so the name lives in vm.globals and not in the library's own env.
    _ = try vm.eval(
        \\(define-library (test cxr-position)
        \\  (import (scheme base))
        \\  (export in-tail in-operand in-test in-nested)
        \\  (begin
        \\    (define (in-tail x) (cadar x))
        \\    (define (in-operand x) (car (cadar x)))
        \\    (define (in-test x) (if (cadar x) 1 0))
        \\    (define (in-nested x) (begin (cadar x) 5))))
    );
    _ = try vm.eval("(import (test cxr-position))");

    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try vm.eval("(car (in-tail '((1 (7)))))")));
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try vm.eval("(in-operand '((1 (7))))")));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(in-test '((1 (7))))")));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(try vm.eval("(in-nested '((1 (7))))")));
}

// Companion to the above: the vm.globals fallback call_global gained must stay
// gated by restricted_globals, so a restricted (environment ...) is no leakier
// for a non-tail call than the tail call #1253 already covers.
test "restricted environment does not leak globals to a non-tail call (#1831)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // `car` is excluded from the environment; the call sits in operand position
    // (inside `list`), so it compiles to call_global rather than a tail call.
    const result = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (eval '(list (car '(1))) (environment '(only (scheme base) list))))
    );
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("caught", types.symbolName(result));
}

// Regression for #1860, #1831's residual: the vm.globals fallback above was
// gated on a flag every library-body form's *outer* function carried and no
// closure inside it did, because compileExpressionInEnv derived it from the
// compile-time restricted_env. So the fallback was off exactly at a library
// body's own top level: the same reference resolved from inside a lambda and
// raised "undefined variable" as a top-level define's initializer — the
// position-dependence #1831 set out to remove, one level up.
test "library resolves a non-imported global at its own top level (#1860)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Same premise as the #1831 test: `cadar` is (scheme cxr), so it lives in
    // vm.globals and not in this library's lib_env. Every form here is
    // evaluated as the library body loads, not inside a procedure.
    _ = try vm.eval(
        \\(define-library (test cxr-toplevel)
        \\  (import (scheme base))
        \\  (export from-define from-begin from-nested-let in-lambda)
        \\  (begin
        \\    (define from-define (cadar '((1 2) 3)))
        \\    (define from-begin 0)
        \\    (set! from-begin (car (cadar '((1 (9)) 3))))
        \\    (define from-nested-let (let ((v '((4 5) 6))) (cadar v)))
        \\    (define (in-lambda) (cadar '((7 8) 9)))))
    );
    _ = try vm.eval("(import (test cxr-toplevel))");

    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("from-define")));
    try std.testing.expectEqual(@as(i64, 9), types.toFixnum(try vm.eval("from-begin")));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(try vm.eval("from-nested-let")));
    // The case that already worked, kept alongside: both must agree.
    try std.testing.expectEqual(@as(i64, 8), types.toFixnum(try vm.eval("(in-lambda)")));
}

// The mirror of the above, and why #1860 could not be fixed by flipping the
// flag: the same per-function derivation left restricted_globals *off* for
// closures compiled inside a restricted environment, so `(environment ...)`
// withheld a name from its top level and handed it over through one lambda.
// Both directions now follow the environment rather than the nesting depth.
test "restricted environment does not leak globals into a closure (#1860)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // `car` is not in the environment; the reference sits in the body of a
    // lambda the eval'd expression immediately applies.
    const from_closure = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (eval '((lambda () (car '(1)))) (environment '(only (scheme base) list))))
    );
    try std.testing.expect(types.isSymbol(from_closure));
    try std.testing.expectEqualStrings("caught", types.symbolName(from_closure));

    // Two levels deep, and via a named local procedure, to pin that the
    // restriction is inherited down the whole chain rather than one level.
    const from_nested = try vm.eval(
        \\(guard (e (#t 'caught))
        \\  (eval '(let ((f (lambda () (lambda () (car '(1))))))
        \\           ((f)))
        \\        (environment '(only (scheme base) list))))
    );
    try std.testing.expect(types.isSymbol(from_nested));
    try std.testing.expectEqualStrings("caught", types.symbolName(from_nested));

    // The environment's own imports still resolve from inside a closure —
    // the restriction withholds vm.globals, it does not break the env.
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval(
        \\(car (eval '((lambda () (list 3))) (environment '(only (scheme base) list))))
    )));
}

// Regression test for #2510: a .sld whose define-library form is well-formed
// but is followed by a read error (stray trailing paren) fails its FIRST
// import — and used to succeed on the SECOND, because the loader dispatched
// (and registered) the library before the reader hit the stray datum, so the
// retry's registry short-circuit served the half-load as a good cache hit.
// The load must now roll its registration back, so both imports fail
// identically; a clean library next to it keeps importing fine, twice.
test "failed .sld load rolls back its registration so both imports fail (#2510)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "rollback2510");
    // Well-formed library + one stray trailing paren: the form dispatches and
    // registers, then the reader fails on the extra ")".
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "rollback2510/broken.sld",
        .data =
        \\(define-library (rollback2510 broken)
        \\  (import (scheme base))
        \\  (export answer)
        \\  (begin (define (answer) 42)))
        \\)
        ,
    });
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "rollback2510/good.sld",
        .data =
        \\(define-library (rollback2510 good)
        \\  (import (scheme base))
        \\  (export answer)
        \\  (begin (define (answer) 42)))
        ,
    });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    ctx.vm.lib_paths = &[_][]const u8{dir_path};

    // First import fails...
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(import (rollback2510 broken))"));
    // ...the library is no longer registered (the rollback took it out)...
    try std.testing.expect(ctx.vm.libraries.get("rollback2510.broken") == null);
    // ...so the second import fails the SAME way instead of succeeding
    // against the half-registered entry.
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(import (rollback2510 broken))"));
    try std.testing.expect(ctx.vm.libraries.get("rollback2510.broken") == null);
    // The failed loads left no rollback frame or record behind (#2518 review):
    // a leaked frame would make every later top-level define-library
    // rollback-able by an unrelated future failure, and a leaked record would
    // unregister a live library on that failure.
    try std.testing.expectEqual(@as(usize, 0), ctx.vm.lib_rollback_frames.items.len);
    try std.testing.expectEqual(@as(usize, 0), ctx.vm.lib_rollback_regs.items.len);

    // The contrast case: a clean library imports fine, twice — the rollback
    // must fire only on failed loads, never on successful ones. The frame
    // now wraps the whole tryLoadLibraryFromFile (#2518 review), so a
    // success path that forgot to commit (load_ok left false) would roll
    // the library back out and the final registry get would turn up null.
    _ = try ctx.vm.eval("(import (rollback2510 good))");
    _ = try ctx.vm.eval("(import (rollback2510 good))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(try ctx.vm.eval("(answer)")));
    try std.testing.expect(ctx.vm.libraries.get("rollback2510.good") != null);
    try std.testing.expectEqual(@as(usize, 0), ctx.vm.lib_rollback_frames.items.len);
    try std.testing.expectEqual(@as(usize, 0), ctx.vm.lib_rollback_regs.items.len);
}

// #2518 review of #2510: a failed load that REPLACED an existing
// registration must restore the prior, not unregister the name outright.
// loadLibrarySource dispatches every datum in the requested .sld, and a file
// may define a library under ANY name — including one already registered.
// The sharpest shape redefines (scheme base): it has no .sld to reload from
// (built-in only), so before the restore, one failed import of an unrelated
// file left the name unregistered and every later (scheme base) import died
// with "library not found". The commit side is exercised too: a load that
// redefines a user library and SUCCEEDS keeps the replacement and releases
// the prior (#820: env retired, exports gone).
test "failed load that redefines a registered library restores the prior (#2510 review)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "rollback2518");
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "rollback2518/v.sld",
        .data =
        \\(define-library (rollback2518 v)
        \\  (export old-x)
        \\  (begin (define old-x 1)))
        ,
    });
    // Redefines (rollback2518 v) — registered by the import above — then
    // defines itself; the load succeeds, so the replacement commits.
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "rollback2518/wrapper.sld",
        .data =
        \\(define-library (rollback2518 v)
        \\  (export new-y)
        \\  (begin (define new-y 2)))
        \\(define-library (rollback2518 wrapper)
        \\  (import (scheme base) (rollback2518 v))
        \\  (export w)
        \\  (begin (define (w) (+ new-y 10))))
        ,
    });
    // Redefines the built-in (scheme base), then fails to read. The rollback
    // must put the built-in entry back, replacement exports and all.
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "rollback2518/evil.sld",
        .data =
        \\(define-library (rollback2518 evil)
        \\  (import (scheme base))
        \\  (export evil-answer)
        \\  (begin (define (evil-answer) 'evil)))
        \\(define-library (scheme base)
        \\  (export evil-replacement)
        \\  (begin (define evil-replacement 'redefined)))
        \\)
        ,
    });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    ctx.vm.lib_paths = &[_][]const u8{dir_path};

    // The victim of the committed redefine: load v, then a successful load
    // that replaces it. The wrapper body saw the replacement live (same
    // file walk), and afterwards the replacement is what stays.
    _ = try ctx.vm.eval("(import (rollback2518 v))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try ctx.vm.eval("old-x")));
    _ = try ctx.vm.eval("(import (rollback2518 wrapper))");
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(try ctx.vm.eval("(w)")));
    const committed = ctx.vm.libraries.get("rollback2518.v").?;
    try std.testing.expect(committed.exports.get("new-y") != null);
    try std.testing.expect(committed.exports.get("old-x") == null);

    // The regression: the broken file replaces (scheme base) mid-load, then
    // the reader fails. Both imports must fail identically AND the built-in
    // registration must survive with its own exports — not be unregistered
    // with the replacement.
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(import (rollback2518 evil))"));
    try std.testing.expectError(error.CompileError, ctx.vm.eval("(import (rollback2518 evil))"));
    try std.testing.expect(ctx.vm.libraries.get("rollback2518.evil") == null);
    const base = ctx.vm.libraries.get("scheme.base").?;
    try std.testing.expect(base.exports.get("car") != null);
    try std.testing.expect(base.exports.get("evil-replacement") == null);
    // Restored means importable, not just present in the map.
    _ = try ctx.vm.eval("(import (scheme base))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(try ctx.vm.eval("(car '(7 8))")));
    // Nothing leaked: both stacks balanced after the failed loads.
    try std.testing.expectEqual(@as(usize, 0), ctx.vm.lib_rollback_frames.items.len);
    try std.testing.expectEqual(@as(usize, 0), ctx.vm.lib_rollback_regs.items.len);
}

// #2518 review of #2510: the rollback journaling in registerAndJournal must
// be atomic with the registration — under allocation failure the load fails
// (and rolls back) instead of leaving a registration no rollback can see,
// which would resurrect the first-import-fails-second-succeeds bug. The
// journal allocates from the raw allocator (name dupe + list growth), which
// gc.oom_countdown cannot reach (#2435), so this sweeps memory.OomAllocator
// across the import's raw allocation sequence: every countdown position
// either fails the import — and must leave the registry exactly as it was,
// the displaced (scheme base) entry restored — or exhausts the sweep.
//
// The backing allocator is page_allocator, not std.testing.allocator: the
// load's OOM error paths deliberately absorb some failures (e.g.
// retired_envs appends, per #820), so a sweep would trip the leak checker on
// pre-existing behavior this test does not claim to fix. Ownership of the
// registry moves is covered leak-checked by the library.zig registry test.
test "rollback journaling is atomic under allocation failure (#2510 review)" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "rollback2518");
    // Minimal shape that still journals a displaced prior: the only
    // define-library replaces (scheme base), then the read fails.
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "rollback2518/oom-evil.sld",
        .data =
        \\(define-library (scheme base)
        \\  (export evil-replacement)
        \\  (begin (define evil-replacement 'redefined)))
        \\)
        ,
    });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    var oom = memory.OomAllocator.init(std.heap.page_allocator);
    var gc = memory.GC.init(oom.allocator());
    const vm = try th.makeTestVM(&gc);
    defer {
        vm.deinit();
        gc.deinit();
    }
    vm.lib_paths = &[_][]const u8{dir_path};

    // Sweep scaled down under gc-stress (each failed load pays a collection
    // per GC allocation); the journaling allocations sit well inside the
    // first slice of the sequence either way.
    const gc_stress = @import("build_options").gc_stress;
    const cap: usize = if (gc_stress) 40 else 400;
    var n: usize = 0;
    while (n < cap) : (n += 1) {
        oom.countdown = n;
        _ = vm.eval("(import (rollback2518 oom-evil))") catch {};
        oom.countdown = null;
        // Whatever allocation failed, the invariant holds: the displaced
        // built-in is registered with its own exports, the broken library
        // is not, and no rollback frame or record survived the failure.
        const base = vm.libraries.get("scheme.base") orelse return error.TestUnexpectedResult;
        try std.testing.expect(base.exports.get("car") != null);
        try std.testing.expect(base.exports.get("evil-replacement") == null);
        try std.testing.expect(vm.libraries.get("rollback2518.oom-evil") == null);
        try std.testing.expectEqual(@as(usize, 0), vm.lib_rollback_frames.items.len);
        try std.testing.expectEqual(@as(usize, 0), vm.lib_rollback_regs.items.len);
    }

    // Clean run after the sweep: still the same failure, still consistent —
    // the sweep itself must not have desynchronized the loader.
    try std.testing.expectError(error.CompileError, vm.eval("(import (rollback2518 oom-evil))"));
    try std.testing.expect(vm.libraries.get("scheme.base") != null);
    try std.testing.expect(vm.libraries.get("rollback2518.oom-evil") == null);
}
