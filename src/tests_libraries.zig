// Phase 6: Libraries (import, define-library, export)
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");
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
        // .internal-only helpers are deliberately removed from globals by
        // vm_bootstrap.install() after being captured by the bootstrapped
        // closures (#1375) — they must NOT resolve.
        const internal_only = spec.libs.eql(primitives_mod.LibSet.initOne(.internal));
        if (internal_only) {
            if (vm.globals.get(spec.name) != null) {
                std.debug.print("DRIFT: internal spec \"{s}\" is still in globals\n", .{spec.name});
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
