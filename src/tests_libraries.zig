// Phase 6: Libraries (import, define-library, export)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const library_mod = @import("library.zig");
const primitives_mod = @import("primitives.zig");
const vm_mod = @import("vm.zig");
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

test "import prefix" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (prefix (scheme base) my:))");
    const result = try vm.eval("(my:+ 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
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
    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);
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
    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
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
        try bytecode_file.writeFileWithTopLevel(std.testing.allocator, &funcs_arr, bytecode_file.sourceHash(sld_source), sbc_path);
    }

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();
    vm_mod.setVMInstance(&vm);
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
