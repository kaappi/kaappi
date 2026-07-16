const std = @import("std");
const ir_mod = @import("ir.zig");

// The LLVM-emit test infrastructure (EmitResult + the emit/count/assert
// helpers) lives with the per-form emit tests in tests_native.zig; this gate
// is a specialized consumer of the same infra.
const native_tests = @import("tests_native.zig");
const emitMultiResult = native_tests.emitMultiResult;
const emitMultiResultOpts = native_tests.emitMultiResultOpts;
const countEvalFallbacks = native_tests.countEvalFallbacks;
const expectNativeDef = native_tests.expectNativeDef;

// -- Native-subset generator stays on the native path (#1395) --

// The VM-vs-native differential oracle (tests/fuzz/native-diff.sh) is only
// as strong as the generated programs' nativeness: every form that falls
// back to the interpreter shrinks the diff to VM-vs-VM. This gate emits
// fixed-seed native-subset programs through the LLVM emitter and counts
// eval-fallback call sites in the IR (countEvalFallbacks spans both the plain
// and the compile-once-cached spelling — #1494). Two shapes legitimately eval:
//
//   - a define emits ONE eval for its global binding when it is VARIADIC (a
//     native closure value dispatches by exact arity, so a variadic entry can't
//     be one) OR when its body reaches a code eval fallback (an inline variadic
//     lambda, whose bindParamsAsGlobals would alias across activations if the
//     value ran natively — the #1500 gate keeps the interpreter closure). A
//     fixed-arity define with a fallback-free body emits ZERO: since #1500 its
//     global binding is a native closure over the compiled entry (call sites
//     already used the direct native path either way);
//   - an inline VARIADIC lambda emits exactly ONE eval (#1420): no
//     closure tier accepts a rest parameter, so it goes through
//     emitLambdaViaEval, which first republishes the enclosing frame as
//     globals — the #1410 codegen this shape exists to exercise. (This is the
//     same code fallback that gates the enclosing define's value above, so a
//     define with an inline variadic body contributes both evals.)
//
// The exact count is checked on UNOPTIMIZED emission: dead-branch
// elimination legitimately deletes variadic lambdas from constant-test
// branches (the generator emits constant tests as dead-branch fodder), so
// under the production pass pipeline the count is only bounded — the
// optimized emission is checked against that range instead, and anything
// above it means a generated form silently fell back.
test "native-subset generator emits no unexpected kaappi_eval fallbacks" {
    const fuzz_gen = @import("fuzz_gen.zig");
    const gpa = std.testing.allocator;

    var seed: u64 = 0;
    while (seed < 200) : (seed += 1) {
        const src = try fuzz_gen.generateNativeSeeded(seed, gpa);
        defer gpa.free(src);
        errdefer std.debug.print("seed {d} program:\n{s}\n", .{ seed, src });

        // The generator emits one top-level form per line, so define position
        // is line-syntactic, and every parameter list is flat — a " . " in one
        // (before its closing ')') marks a rest parameter.
        //
        // Per line we count two things:
        //   value_evals: a define whose global binding evals — variadic, or a
        //     fixed-arity define whose body reaches a code eval fallback. For a
        //     generator body the only such fallback is an inline variadic
        //     lambda, so "line has an inline variadic lambda" ⟺ the define's
        //     body has a code fallback ⟺ #1500 keeps the interpreter value.
        //   nvariadic: every inline variadic lambda (each one its own eval).
        var value_evals: usize = 0;
        var nvariadic: usize = 0;
        var names: [8][]const u8 = undefined;
        var name_count: usize = 0;
        var lines = std.mem.splitScalar(u8, src, '\n');
        while (lines.next()) |line| {
            // Inline variadic lambdas: every "(lambda (" occurrence except the
            // define-position one on a `(define name (lambda ...)` line. The
            // parameter list is flat, so it ends at the first ')'; a " . "
            // inside it marks a rest parameter.
            var line_inline_variadic: usize = 0;
            var from: usize = 0;
            if (std.mem.startsWith(u8, line, "(define ") and !std.mem.startsWith(u8, line, "(define (")) {
                if (std.mem.indexOf(u8, line, "(lambda (")) |pos| from = pos + "(lambda (".len;
            }
            while (std.mem.indexOfPos(u8, line, from, "(lambda (")) |pos| {
                from = pos + "(lambda (".len;
                const plist_end = std.mem.indexOfScalarPos(u8, line, from, ')') orelse line.len;
                if (std.mem.indexOf(u8, line[from..plist_end], " . ") != null) line_inline_variadic += 1;
            }
            nvariadic += line_inline_variadic;

            var name: ?[]const u8 = null;
            var define_plist: ?[]const u8 = null; // the define's formal list
            if (std.mem.startsWith(u8, line, "(define (")) {
                const rest = line["(define (".len..];
                const end = std.mem.indexOfAny(u8, rest, " )") orelse rest.len;
                name = rest[0..end];
                // Sugared `(define (f a . rest) ...)`: formals close at the
                // first ')'.
                const plist_end = std.mem.indexOfScalar(u8, rest, ')') orelse rest.len;
                define_plist = rest[0..plist_end];
            } else if (std.mem.startsWith(u8, line, "(define ") and
                std.mem.indexOf(u8, line, "(lambda ") != null)
            {
                const rest = line["(define ".len..];
                const end = std.mem.indexOfScalar(u8, rest, ' ') orelse rest.len;
                name = rest[0..end];
                // `(define f (lambda (a . rest) ...))`: the define-position
                // lambda's formals close at the first ')' after "(lambda (".
                if (std.mem.indexOf(u8, line, "(lambda (")) |pos| {
                    const pos_from = pos + "(lambda (".len;
                    const plist_end = std.mem.indexOfScalarPos(u8, line, pos_from, ')') orelse line.len;
                    define_plist = line[pos_from..plist_end];
                }
            }
            if (name) |n| {
                names[name_count] = n;
                name_count += 1;
                // The define's value evals when it is variadic, or when its body
                // has a code eval fallback (#1500 gate) — an inline variadic
                // lambda on this line.
                const define_variadic = if (define_plist) |pl|
                    std.mem.indexOf(u8, pl, " . ") != null
                else
                    false;
                if (define_variadic or line_inline_variadic > 0) value_evals += 1;
            }
        }
        const expected = value_evals + nvariadic;

        // Exact accounting on unoptimized emission: every source shape
        // reaches the emitter, so any count mismatch is a shape that
        // unexpectedly fell back (or unexpectedly stayed native).
        var res_noopt = blk: {
            ir_mod.optimize_enabled = false;
            defer ir_mod.optimize_enabled = true;
            break :blk try emitMultiResultOpts(src, false);
        };
        defer res_noopt.deinit();
        // Count both eval spellings: define-time and inline-variadic-lambda
        // fallbacks now route through @kaappi_eval_cached (#1494).
        const actual_noopt = countEvalFallbacks(res_noopt.toSlice());
        if (actual_noopt != expected) {
            std.debug.print("seed {d}: expected {d} kaappi_eval calls unoptimized ({d} define-value evals + {d} inline variadic lambdas), found {d}\n", .{ seed, expected, value_evals, nvariadic, actual_noopt });
            return error.NativeSubsetFellBackToEval;
        }

        // Production pass pipeline: elimination can only remove eval sites,
        // never add them. A define's value eval is top-level (never in a dead
        // branch), so it is the unremovable floor; inline variadic lambdas in
        // constant-test branches may be eliminated above it.
        var res = try emitMultiResult(src);
        defer res.deinit();
        const ll = res.toSlice();
        const actual = countEvalFallbacks(ll);
        if (actual < value_evals or actual > expected) {
            std.debug.print("seed {d}: expected {d}..{d} kaappi_eval calls optimized, found {d}\n", .{ seed, value_evals, expected, actual });
            return error.NativeSubsetFellBackToEval;
        }

        // The eval count alone cannot see a function whose native
        // compilation was REJECTED (the define-time eval is emitted either
        // way and call sites just degrade to global lookups), so also
        // require the named native function definition that the emitter
        // tags with a `; <name>` header comment.
        for (names[0..name_count]) |n| {
            // A named define is emitted as a tailcc fast entry (#1499) or, when
            // not fast-eligible, a uniform definition — expectNativeDef accepts
            // either. (A false return would mean the whole define fell back.)
            expectNativeDef(ll, n) catch {
                std.debug.print("seed {d}: no native definition for {s}\n", .{ seed, n });
                return error.NativeSubsetFellBackToEval;
            };
        }
    }
}
