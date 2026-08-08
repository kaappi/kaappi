//! Unit tests for the `kaappi ast` / `expand` / `ir` pipeline dumps (#1512).
//!
//! The `expand` tests drive the real macro engine over a registered
//! `syntax-rules` macro and assert the fully expanded S-expression — with
//! emphasis on soundness: `quote`d data, `case` datum lists and `syntax-rules`
//! specs must never be touched, and multi-step / hygienic macros must expand
//! completely. The `ir` tests assert the structured tree and the before/after
//! optimization difference `--no-opt` exposes.

const std = @import("std");
const types = @import("types.zig");
const th = @import("testing_helpers.zig");
const reader = @import("reader.zig");
const printer = @import("printer.zig");
const pipeline = @import("pipeline.zig");
const memory = @import("memory.zig");

const testing = std.testing;
const Value = types.Value;

const Harness = struct {
    tc: th.TestContext = undefined,

    fn init(self: *Harness) !void {
        try self.tc.init();
    }
    fn deinit(self: *Harness) void {
        self.tc.deinit();
    }

    /// Register a macro (or run any setup) through the real compile path.
    fn setup(self: *Harness, src: []const u8) !void {
        _ = try self.tc.vm.eval(src);
    }

    /// Expand a single form and return the printed expansion (caller frees).
    fn expand(self: *Harness, src: []const u8) ![]u8 {
        var r = reader.Reader.init(&self.tc.gc, src);
        defer r.deinit();
        var expr = try r.readDatum();
        self.tc.gc.pushRoot(&expr);
        defer self.tc.gc.popRoot();
        var expanded = pipeline.expandFormForTest(self.tc.vm, expr);
        self.tc.gc.pushRoot(&expanded);
        defer self.tc.gc.popRoot();
        return printer.valueToString(testing.allocator, expanded, .write);
    }

    /// Lower a single form and return the printed IR tree (caller frees).
    fn ir(self: *Harness, src: []const u8, no_opt: bool) ![]u8 {
        var r = reader.Reader.init(&self.tc.gc, src);
        defer r.deinit();
        var expr = try r.readDatum();
        self.tc.gc.pushRoot(&expr);
        defer self.tc.gc.popRoot();
        return pipeline.lowerFormToStringForTest(self.tc.vm, testing.allocator, expr, no_opt);
    }
};

fn expectExpands(setup: ?[]const u8, src: []const u8, expected: []const u8) !void {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    if (setup) |s| try h.setup(s);
    const got = try h.expand(src);
    defer testing.allocator.free(got);
    testing.expectEqualStrings(expected, got) catch |e| {
        std.debug.print("expand mismatch for: {s}\n  got: {s}\n", .{ src, got });
        return e;
    };
}

/// Like expectExpands, but collapses `__hyg_<id>_` to `__hyg_N_` in the
/// actual output before comparing — for templates whose free references to a
/// global procedure are hygiene-renamed (issue #2003). The gensym id comes
/// from a process-global counter, so pinning the exact spelling in a snapshot
/// would be brittle across test additions; the rename itself (the `__hyg_`
/// prefix on the referenced name) is the behaviour these tests document.
fn expectExpandsNorm(setup: ?[]const u8, src: []const u8, expected: []const u8) !void {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    if (setup) |s| try h.setup(s);
    const raw = try h.expand(src);
    defer testing.allocator.free(raw);
    const got = testing.allocator.alloc(u8, raw.len) catch return error.OutOfMemory;
    defer testing.allocator.free(got);
    var out_len: usize = 0;
    var i: usize = 0;
    while (i < raw.len) {
        if (std.mem.startsWith(u8, raw[i..], "__hyg_")) {
            var j = i + "__hyg_".len;
            while (j < raw.len and raw[j] >= '0' and raw[j] <= '9') j += 1;
            if (j < raw.len and raw[j] == '_') {
                const piece = "__hyg_N_";
                @memcpy(got[out_len..][0..piece.len], piece);
                out_len += piece.len;
                i = j + 1;
                continue;
            }
        }
        got[out_len] = raw[i];
        out_len += 1;
        i += 1;
    }
    testing.expectEqualStrings(expected, got[0..out_len]) catch |e| {
        std.debug.print("expand mismatch for: {s}\n  got: {s}\n", .{ src, got[0..out_len] });
        return e;
    };
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, haystack, needle) != null;
}

// ── expand: basic macro use ─────────────────────────────────────────────────

test "expand: simple alias macro" {
    // Template keyword `begin` is hygiene-renamed like every other operator
    // keyword since kaappi#2074 (so a use-site local named `begin` cannot
    // capture it), so the expansion is compared through the gensym-id
    // normalizer. (`if`/`let` are renamed too, which the recursive-macro
    // test below exercises with substring checks.)
    try expectExpandsNorm(
        "(define-syntax seq (syntax-rules () ((_ a b) (begin a b))))",
        "(seq x y)",
        "(__hyg_N_begin x y)",
    );
}

test "expand: no macros — form unchanged" {
    try expectExpands(null, "(if a (f b) c)", "(if a (f b) c)");
}

test "expand: macro use nested in a call argument" {
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(f (dbl n) 3)",
        "(f (__hyg_N_* 2 n) 3)",
    );
}

// ── expand: recursion into binding/body positions ───────────────────────────

test "expand: macro use inside a let body" {
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(let ((n 1)) (dbl n))",
        "(let ((n 1)) (__hyg_N_* 2 n))",
    );
}

test "expand: macro use inside a let init expression" {
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(let ((y (dbl 5))) y)",
        "(let ((y (__hyg_N_* 2 5))) y)",
    );
}

test "expand: macro use inside a lambda body" {
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(lambda (x) (dbl x))",
        "(lambda (x) (__hyg_N_* 2 x))",
    );
}

test "expand: macro use inside a cond clause body" {
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(cond (a (dbl b)) (else (dbl c)))",
        "(cond (a (__hyg_N_* 2 b)) (else (__hyg_N_* 2 c)))",
    );
}

test "expand: macro use inside a case clause body, datum list untouched" {
    // The `(dbl)` in datum position is *data* and must stay; the body expands.
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(case k ((dbl) (dbl 1)) (else (dbl 2)))",
        "(case k ((dbl) (__hyg_N_* 2 1)) (else (__hyg_N_* 2 2)))",
    );
}

test "expand: macro use inside a do body and step" {
    try expectExpandsNorm(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(do ((i 0 (dbl i))) ((= i 8) i) (dbl i))",
        "(do ((i 0 (__hyg_N_* 2 i))) ((= i 8) i) (__hyg_N_* 2 i))",
    );
}

// ── expand: soundness — quoted data is never expanded ───────────────────────

test "expand: quoted data is not expanded" {
    // The macro-named list inside `quote` stays literal.
    try expectExpands(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(quote (dbl 1 2))",
        "(quote (dbl 1 2))",
    );
}

test "expand: quasiquote left in place" {
    try expectExpands(
        "(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))",
        "(quasiquote (a (dbl b)))",
        "(quasiquote (a (dbl b)))",
    );
}

// ── expand: multi-step / hygienic expansion ─────────────────────────────────

test "expand: recursive macro expands fully" {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    try h.setup(
        "(define-syntax my-or (syntax-rules () " ++
            "((_) #f) ((_ e) e) ((_ e1 e2 ...) (let ((t e1)) (if t t (my-or e2 ...))))))",
    );
    const got = try h.expand("(my-or a b c)");
    defer testing.allocator.free(got);
    // The key property: no residual macro keyword — it expanded fully. The
    // template's `let`/`if` keywords are hygiene-renamed (`__hyg_N_let`), so
    // match the bare keyword substring rather than a leading paren.
    try testing.expect(!contains(got, "my-or"));
    try testing.expect(contains(got, "let"));
    try testing.expect(contains(got, "if"));
}

test "expand: two separate expansions of a quoted template symbol get distinct hygienic renames (#1801)" {
    // #1801: a template-introduced identifier written directly inside
    // `(quote ...)` (e.g. `'g`) used to come back bare, unrenamed, from
    // EVERY expansion -- so two separate uses of `(gen)` were structurally
    // indistinguishable even before compilation, breaking any macro-level
    // identity check built out of further syntax-rules expansion (SRFI
    // 148's em-gensym/bound-identifier=?). Fixed by hygiene-renaming inside
    // quote exactly like anywhere else during expansion; the compiler
    // strips that rename back off once it turns the quoted datum into a
    // literal runtime Value (see tests_macros.zig's "quoted template symbol
    // is eq?" test for that complementary, post-compile behavior).
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    try h.setup("(define-syntax gen (syntax-rules () ((gen) 'g)))");

    const first = try h.expand("(gen)");
    defer testing.allocator.free(first);
    const second = try h.expand("(gen)");
    defer testing.allocator.free(second);

    try testing.expect(contains(first, "__hyg_"));
    try testing.expect(contains(second, "__hyg_"));
    try testing.expect(!std.mem.eql(u8, first, second));
}

// ── ir: structure ────────────────────────────────────────────────────────────

test "ir: if over a primitive comparison" {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    const got = try h.ir("(if (< n 2) 1 2)", false);
    defer testing.allocator.free(got);
    try testing.expect(contains(got, "(if"));
    try testing.expect(contains(got, "(call"));
    try testing.expect(contains(got, "(global-ref n)"));
    try testing.expect(contains(got, "(constant 1)"));
    try testing.expect(contains(got, "(constant 2)"));
}

test "ir: constant folding differs before and after optimization" {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();

    const pre = try h.ir("(+ 1 2)", true); // --no-opt: no early fold
    defer testing.allocator.free(pre);
    try testing.expect(contains(pre, "(call"));
    try testing.expect(contains(pre, "(constant 1)"));

    const post = try h.ir("(+ 1 2)", false); // optimized: folded to 3
    defer testing.allocator.free(post);
    try testing.expectEqualStrings("(constant 3)", post);
}

test "ir: macro use lowers to a passthrough node" {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    try h.setup("(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))");
    const got = try h.ir("(dbl 5)", false);
    defer testing.allocator.free(got);
    try testing.expect(contains(got, "(passthrough"));
}

test "ir: define shows name and raw value" {
    var h: Harness = .{};
    try h.init();
    defer h.deinit();
    const got = try h.ir("(define x (+ 1 2))", true);
    defer testing.allocator.free(got);
    try testing.expect(contains(got, "(define x"));
}
