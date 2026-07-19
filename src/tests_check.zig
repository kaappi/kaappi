//! Unit tests for `kaappi check` lint analysis (kaappi#1511).
//!
//! Each test drives the real compiler over a source string with the lint active
//! (via `check.analyzeForTest`) and asserts which `KP4xxx` findings result. The
//! emphasis is the "never reject a valid program" invariant: the negative cases
//! (shadowing, redefinition, quoting, macro expansions, non-literal arguments)
//! matter as much as the positive ones.

const std = @import("std");
const types = @import("types.zig");
const th = @import("testing_helpers.zig");
const check = @import("check.zig");
const check_lint = @import("check_lint.zig");
const diagnostics = @import("diagnostics.zig");

const Code = diagnostics.Code;
const testing = std.testing;

/// One analysis run: a fresh VM, an arena for findings, and the collected
/// user-defined name set — all torn down together by `deinit`.
const Harness = struct {
    tc: th.TestContext = undefined,
    arena: std.heap.ArenaAllocator = undefined,
    udefs: std.StringHashMap(void) = undefined,
    ctx: check_lint.Context = undefined,

    fn run(self: *Harness, source: []const u8) !void {
        try self.tc.init();
        self.arena = std.heap.ArenaAllocator.init(testing.allocator);
        const a = self.arena.allocator();
        self.udefs = std.StringHashMap(void).init(a);
        check.collectTopLevelDefines(&self.udefs, a, &self.tc.gc, source);
        self.ctx = .{ .arena = a, .user_defined = &self.udefs };
        check.analyzeForTest(self.tc.vm, &self.ctx, source);
    }

    fn deinit(self: *Harness) void {
        self.tc.deinit();
        self.arena.deinit();
    }

    fn count(self: *Harness, code: Code) usize {
        var n: usize = 0;
        for (self.ctx.findings.items) |f| {
            if (f.code == code) n += 1;
        }
        return n;
    }

    fn total(self: *Harness) usize {
        return self.ctx.findings.items.len;
    }

    fn firstMessage(self: *Harness, code: Code) ?[]const u8 {
        for (self.ctx.findings.items) |f| {
            if (f.code == code) return f.message;
        }
        return null;
    }

    /// Print every collected finding. Wired into failures so an unexpected
    /// finding (a failed import, a stray compile error) identifies itself
    /// instead of surfacing as a bare lint miscount (#1627).
    fn dump(self: *Harness, source: []const u8) void {
        std.debug.print("collected findings for: {s}\n", .{source});
        if (self.ctx.findings.items.len == 0) {
            std.debug.print("  (none)\n", .{});
            return;
        }
        for (self.ctx.findings.items) |f| {
            var cbuf: [Code.render_width]u8 = undefined;
            std.debug.print("  {s} at {d}:{d}: {s}\n", .{ f.code.render(&cbuf), f.span.line, f.span.col, f.message });
        }
    }
};

fn expectCounts(source: []const u8, arity: usize, type_mismatch: usize, unbound: usize) !void {
    var h: Harness = .{};
    try h.run(source);
    defer h.deinit();
    errdefer h.dump(source);
    testing.expectEqual(arity, h.count(.primitive_arity_mismatch)) catch |e| {
        std.debug.print("arity mismatch count wrong for: {s}\n", .{source});
        return e;
    };
    testing.expectEqual(type_mismatch, h.count(.primitive_type_mismatch)) catch |e| {
        std.debug.print("type mismatch count wrong for: {s}\n", .{source});
        return e;
    };
    testing.expectEqual(unbound, h.count(.unknown_toplevel_variable)) catch |e| {
        std.debug.print("unbound count wrong for: {s}\n", .{source});
        return e;
    };
    // Nothing beyond the expected lint findings: an extra finding here is a
    // broken precondition (a failed import, a stray compile error), which must
    // fail as itself — not hide until it perturbs a lint count (#1627).
    testing.expectEqual(arity + type_mismatch + unbound, h.total()) catch |e| {
        std.debug.print("unexpected extra findings for: {s}\n", .{source});
        return e;
    };
}

// ── Arity (KP4002, error) ──────────────────────────────────────────────────

test "arity: too many args to a fixed-arity built-in" {
    try expectCounts("(car 1 2)", 1, 0, 0);
}

test "arity: too few args to a fixed-arity built-in" {
    try expectCounts("(cons 1)", 1, 0, 0);
}

test "arity: below the minimum of a variadic built-in" {
    // `-` is variadic with a minimum of 1, so a zero-arg call is an arity error.
    try expectCounts("(-)", 1, 0, 0);
}

test "arity: correct counts produce nothing" {
    try expectCounts("(cons 1 2)", 0, 0, 0);
    try expectCounts("(+ 1 2 3 4 5)", 0, 0, 0); // variadic, any count ok
    try expectCounts("(- 5)", 0, 0, 0); // unary negation is fine
}

test "arity: message names the procedure and both counts" {
    var h: Harness = .{};
    try h.run("(car 1 2)");
    defer h.deinit();
    const msg = h.firstMessage(.primitive_arity_mismatch).?;
    try testing.expect(std.mem.indexOf(u8, msg, "car") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "1") != null);
    try testing.expect(std.mem.indexOf(u8, msg, "2") != null);
}

// ── Type of literal argument (KP4003, error) ───────────────────────────────

test "type: number where a pair is required" {
    try expectCounts("(car 5)", 0, 1, 0);
}

test "type: the empty list is not a pair" {
    try expectCounts("(car '())", 0, 1, 0);
}

test "type: string where a vector is required" {
    try expectCounts("(vector-ref \"s\" 0)", 0, 1, 0);
}

test "type: non-number literal to arithmetic" {
    try expectCounts("(+ 1 \"a\")", 0, 1, 0);
}

test "type: string where a symbol is required" {
    try expectCounts("(symbol->string \"x\")", 0, 1, 0);
}

test "type: correct literals produce nothing" {
    try expectCounts("(car '(1 2))", 0, 0, 0);
    try expectCounts("(vector-ref (vector 1 2) 0)", 0, 0, 0); // vector not a literal
    try expectCounts("(string-length \"hi\")", 0, 0, 0);
    try expectCounts("(char->integer #\\a)", 0, 0, 0);
    try expectCounts("(symbol->string 'foo)", 0, 0, 0);
}

test "type: a non-literal argument is never inferred" {
    // The value of `x` is unknown to the linter, so no type finding — only the
    // unbound-variable warning for the free reference.
    try expectCounts("(car x)", 0, 0, 1);
}

// ── The invariant: valid programs are never rejected ───────────────────────

test "invariant: a lexically-bound name shadows the built-in" {
    try expectCounts("(define (f car) (car 1 2))", 0, 0, 0);
}

test "invariant: a let binding shadows the built-in" {
    try expectCounts("(let ((car (lambda (a b) a))) (car 1 2))", 0, 0, 0);
}

test "invariant: a top-level redefinition is left alone" {
    // The user's own `car` may take any number of args; we do not know its
    // arity, so we must not flag the call.
    try expectCounts("(define (car x) x)\n(car 1 2 3)", 0, 0, 0);
}

test "invariant: quoted data is never a call" {
    try expectCounts("'(car 1 2)", 0, 0, 0);
    try expectCounts("(list 'car 1 2)", 0, 0, 0);
}

test "invariant: calls synthesized by a macro are not linted" {
    // `m` expands to `(car x x)` — a 2-arg car — but that call is the macro's,
    // not the user's direct source, so it is suppressed.
    try expectCounts(
        \\(define-syntax m (syntax-rules () ((_ x) (car x x))))
        \\(m 5)
    , 0, 0, 0);
}

test "invariant: an imported macro use is not linted as a call" {
    // `swallow`'s argument is a deliberate error the macro discards; the
    // program is valid, so `check` must not reject it. The macro arrives
    // through `import` — registered by importBinding at import time, a
    // different path from the in-file `define-syntax` test above. The library
    // is defined in-source so the import resolves from the registry and the
    // test never touches the filesystem (#1627); the on-disk `.sld` variant
    // follows below.
    try expectCounts(
        \\(define-library (t macros)
        \\  (export swallow)
        \\  (begin (define-syntax swallow (syntax-rules () ((_ e) 'ok)))))
        \\(import (t macros))
        \\(swallow (car 1 2))
    , 0, 0, 0);
}

test "invariant: a macro imported from an .sld file is not linted as a call" {
    // The on-disk variant of the test above: `(chibi test)` goes through the
    // real .sld search + load path, and `test-error`'s argument is a
    // deliberate error the guard catches. CWD-DEPENDENT: unit-test VMs have
    // no lib_paths, so resolution probes "" and "lib/" relative to the
    // process cwd — this test needs the repo root (lib/chibi/test.sld) as
    // cwd. The macro probe turns any resolution/load hiccup into a loud
    // import failure instead of a baffling lint miscount (#1627).
    const source =
        \\(import (chibi test))
        \\(test-error (apply +))
    ;
    var h: Harness = .{};
    try h.run(source);
    defer h.deinit();
    errdefer h.dump(source);
    if (!h.tc.vm.macros.contains("test-error")) {
        std.debug.print(
            "import failed: (chibi test) did not provide the test-error macro — " ++
                ".sld resolution is cwd-relative and needs lib/chibi/test.sld under the cwd (#1627)\n",
            .{},
        );
        return error.ImportFailed;
    }
    try testing.expectEqual(@as(usize, 0), h.total());
}

// ── Recursion into bodies (calls inside standard forms still checked) ───────

test "recursion: arity error inside a lambda body" {
    try expectCounts("(define (f) (car 1 2))", 1, 0, 0);
}

test "recursion: type error inside a let body" {
    try expectCounts("(let ((x 1)) (car 5))", 0, 1, 0);
}

test "recursion: error inside a cond branch" {
    try expectCounts("(cond (#t (car 5)))", 0, 1, 0);
}

test "recursion: error inside an if branch" {
    try expectCounts("(if #t (car 1 2) 0)", 1, 0, 0);
}

// ── Unbound top-level variable (KP4001, warning) ───────────────────────────

test "unbound: a free reference to an unknown global warns" {
    try expectCounts("(display nonexistent-name)", 0, 0, 1);
}

test "unbound: a forward reference to a later define is legal" {
    try expectCounts("(define (f) (g))\n(define (g) 1)", 0, 0, 0);
}

test "unbound: a local variable is never flagged" {
    try expectCounts("(lambda (x) x)", 0, 0, 0);
    try expectCounts("(let ((y 1)) y)", 0, 0, 0);
}

test "unbound: built-ins and defined names are known" {
    try expectCounts("(define x 1)\n(+ x 1)", 0, 0, 0);
}

// ── Compile / read errors still surface (with their KP codes) ──────────────

test "read and compile errors are reported as findings" {
    var h: Harness = .{};
    try h.run("(if)"); // invalid syntax — too few subforms
    defer h.deinit();
    try testing.expect(h.total() >= 1);
    var saw_compile = false;
    for (h.ctx.findings.items) |f| {
        if (f.code.stage() == .compile) saw_compile = true;
    }
    try testing.expect(saw_compile);
}

// ── Top-level cond-expand splices its selected clause (#1661) ───────────────
// check must analyse a matched top-level cond-expand clause as spliced
// top-level forms, exactly as it already does for begin. Otherwise the clause
// compiled as an expression: a nested import turned `(srfi 1)` into a call to
// an unknown `srfi`, and a nested define was never gathered as a top-level name
// so a forward reference to it warned. Both were spurious KP4001 warnings.

test "cond-expand: import nested in a matched clause is not flagged (#1661)" {
    // else clause — the import runs for effect, `srfi` is not a call target.
    try expectCounts("(cond-expand (else (import (srfi 1))))", 0, 0, 0);
    // srfi-N guard (the #1649 idiom) selects the same clause.
    try expectCounts("(cond-expand (srfi-1 (import (srfi 1))) (else 0))", 0, 0, 0);
}

test "cond-expand: a define in a matched clause is a known top-level name (#1661)" {
    // The define nested in the clause must be gathered as a top-level name so
    // the earlier forward reference resolves — like a top-level begin.
    try expectCounts("(define (f) (helper))\n(cond-expand (else (define (helper) 1)))", 0, 0, 0);
}

test "cond-expand: an unsatisfied top-level clause is not an error (#1661)" {
    // No clause matches and there is no else: folds to void, no finding.
    try expectCounts("(cond-expand (no-such-feature (import (srfi 1))))", 0, 0, 0);
}
