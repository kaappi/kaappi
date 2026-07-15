//! Lint analysis for `kaappi check` (kaappi#1511, part of the machine-legibility
//! epic kaappi#1503).
//!
//! `kaappi check` reads + expands + compiles a program without running it and
//! reports the reserved `KP4xxx` lint findings. The analysis is a pass over the
//! IR the *real* compiler produces: `check` drives an ordinary compilation (so
//! macros expand, imports load, and lexical scope is resolved exactly as they
//! would be at run time) but discards the bytecode. A thread-local `Context`
//! (installed only while a user form is being compiled) collects the findings
//! `ir.lowerAndOptimize` hands to `maybeWalk`.
//!
//! Reusing the compiler's own lowering is what makes the analysis sound:
//!
//!  * `IR.isRedefined` already answers "is this the genuine, unshadowed
//!    built-in?" — it consults lexical scope, `set!` targets, and the globals
//!    table. We flag a call only when that check confirms the operator resolves
//!    to a matching `NativeFn`, so a rebound or lexically-shadowed name is never
//!    touched (the "never reject a valid program" invariant).
//!  * Quoted data lowers to `constant` nodes, so `'(car 1 2)` is never walked as
//!    a call. Lambda / let / cond / … bodies are compiled on demand through the
//!    same `lowerAndOptimize` choke point, so recursion is automatic and every
//!    nested body is analysed with its own correct scope.
//!  * Macro expansions are *suppressed*: `expandAndCompileMacroUse` brackets the
//!    compile of an expansion with `enterMacroExpansion`/`exitMacroExpansion`, so
//!    only calls the user wrote directly — never code a macro synthesised — are
//!    linted. This is what lets a program like `(test-error (apply +))` pass:
//!    the erroring sub-form lives inside a macro use and is not the user's direct
//!    call. "Direct call to a known built-in" is exactly a call that survives to
//!    the IR outside any macro expansion.

const std = @import("std");
const types = @import("types.zig");
const ir_mod = @import("ir.zig");
const diagnostics = @import("diagnostics.zig");

const Value = types.Value;
const Node = ir_mod.Node;
const IR = ir_mod.IR;
const Code = diagnostics.Code;

/// One lint finding, ready to render. `message` is owned by the arena the
/// `Context` was created with, so a finding stays valid until the check run ends.
pub const Finding = struct {
    code: Code,
    span: types.Span,
    message: []const u8,
};

/// Collector for one `kaappi check` run. Installed in `active` while a user form
/// compiles; `ir.lowerAndOptimize` finds it there and calls `maybeWalk`.
pub const Context = struct {
    /// Backs both the findings list and every `message` string — freed in one
    /// shot when the check run ends.
    arena: std.mem.Allocator,
    findings: std.ArrayList(Finding) = .empty,
    /// Names bound by a top-level `define` / `define-values` / `define-syntax`
    /// in the file. `check` does not execute those top-level `define`s, so the
    /// globals table still holds the original built-in for a redefined name;
    /// this set is what tells the linter "the user rebound this — leave it be",
    /// and it doubles as the "known name" set for the unbound-variable warning
    /// (a forward reference to a not-yet-defined name is legal, not a warning).
    user_defined: *const std.StringHashMap(void),
    /// >0 while inside a macro expansion or an import load: the walk is skipped
    /// so only the user's own direct forms are analysed.
    suppress_depth: u32 = 0,

    pub fn addFinding(self: *Context, code: Code, span: types.Span, message: []const u8) void {
        // Dedup on (code, line, col): a form can be lowered more than once (a
        // macro fixed point, a define RHS), and a doubled finding is noise.
        for (self.findings.items) |f| {
            if (f.code == code and f.span.line == span.line and f.span.col == span.col) return;
        }
        self.findings.append(self.arena, .{ .code = code, .span = span, .message = message }) catch {};
    }
};

/// The active collector, or null outside a check run (the common case: normal
/// compilation pays only a null-pointer test in the hot `lowerAndOptimize` path).
pub threadlocal var active: ?*Context = null;

/// Enter a region whose compilation must not be linted (a macro expansion, an
/// import load). Balanced by `exitMacroExpansion`. A no-op when no check is running.
pub fn enterMacroExpansion() void {
    if (active) |ctx| ctx.suppress_depth += 1;
}

pub fn exitMacroExpansion() void {
    if (active) |ctx| {
        if (ctx.suppress_depth > 0) ctx.suppress_depth -= 1;
    }
}

/// The lint hook `ir.lowerAndOptimize` calls after lowering each form, before
/// the optimization passes (so folding never hides a call). Cheap and inert
/// unless a check is running and we are outside a suppressed region.
pub fn maybeWalk(ir: *IR, node: *Node) void {
    const ctx = active orelse return;
    if (ctx.suppress_depth > 0) return;
    walk(ctx, ir, node, node.ann.span);
}

/// Recurse through the forms that share this node's lexical scope — `if`,
/// `begin`, `and`/`or`, `when`/`unless`, and call operands. Binding forms
/// (`lambda`, `let`, `cond`, …) hold their bodies as raw data that the compiler
/// lowers separately through `lowerAndOptimize`, so we stop at them and let that
/// second lowering walk them with the right scope — this is what keeps every
/// call linted exactly once.
fn walk(ctx: *Context, ir: *IR, node: *Node, fallback: types.Span) void {
    // Carry the nearest known span down: a bare symbol reference (a `global_ref`)
    // has no span of its own, so the unbound-variable warning falls back to the
    // enclosing form's line rather than reporting an unknown position.
    const here = if (node.ann.span.known()) node.ann.span else fallback;
    switch (node.tag) {
        .call => {
            checkCall(ctx, ir, node);
            walk(ctx, ir, node.data.call.operator, here);
            for (node.data.call.args) |arg| walk(ctx, ir, arg, here);
        },
        .global_ref => checkGlobalRef(ctx, ir, node, here),
        .@"if" => {
            walk(ctx, ir, node.data.@"if".test_expr, here);
            walk(ctx, ir, node.data.@"if".consequent, here);
            if (node.data.@"if".alternate) |alt| walk(ctx, ir, alt, here);
        },
        .begin => for (node.data.begin) |c| walk(ctx, ir, c, here),
        .and_form => for (node.data.and_form) |c| walk(ctx, ir, c, here),
        .or_form => for (node.data.or_form) |c| walk(ctx, ir, c, here),
        .when_form => {
            walk(ctx, ir, node.data.when_form.test_expr, here);
            for (node.data.when_form.body) |c| walk(ctx, ir, c, here);
        },
        .unless_form => {
            walk(ctx, ir, node.data.unless_form.test_expr, here);
            for (node.data.unless_form.body) |c| walk(ctx, ir, c, here);
        },
        // constant, lambda, let*, letrec, define, set!, sexpr_form, passthrough:
        // either leaves or forms whose bodies are lowered (and walked) separately.
        else => {},
    }
}

// ── Unbound top-level variable (KP4001, warning) ───────────────────────────

/// A free reference to a global that is neither a built-in, an imported binding,
/// nor defined anywhere in the file. A warning, never an error: R7RS permits
/// top-level forward references.
fn checkGlobalRef(ctx: *Context, ir: *IR, node: *Node, fallback: types.Span) void {
    const sym = node.data.global_ref;
    if (!types.isSymbol(sym)) return;
    const name = types.symbolName(sym);

    // Macro-introduced identifiers are not the user's source text.
    if (!std.mem.eql(u8, name, types.stripHygienicPrefix(name))) return;

    // A lexical binding shadows the global — not a top-level reference at all.
    if (ir.compiler) |c| {
        if (c.isLexicallyBound(name)) return;
    }
    if (knownGlobal(ir, ctx, name)) return;

    const span = if (node.ann.span.known()) node.ann.span else fallback;
    const msg = std.fmt.allocPrint(ctx.arena, "unknown variable '{s}' at top level", .{name}) catch return;
    ctx.addFinding(.unknown_toplevel_variable, span, msg);
}

/// True when `name` names something the program has (or will have) in scope at
/// top level: a built-in / imported binding (present in globals), or a name a
/// top-level `define` introduces anywhere in the file (forward references
/// included).
fn knownGlobal(ir: *IR, ctx: *Context, name: []const u8) bool {
    if (ctx.user_defined.contains(name)) return true;
    const g = ir.globals orelse return true; // no table to judge against — stay quiet
    return g.contains(name);
}

// ── Direct built-in call checks (KP4002 arity, KP4003 type) ────────────────

fn checkCall(ctx: *Context, ir: *IR, node: *Node) void {
    const call = node.data.call;
    const op = call.operator;
    if (op.tag != .global_ref) return; // not a direct named call
    const sym = op.data.global_ref;
    if (!types.isSymbol(sym)) return;
    const name = types.symbolName(sym);

    // Skip macro-introduced operators and any name the user rebinds: a lexical
    // shadow, a set! target, or a top-level (re)definition of the name.
    if (!std.mem.eql(u8, name, types.stripHygienicPrefix(name))) return;
    if (ir.isRedefined(name)) return;
    if (ctx.user_defined.contains(name)) return;

    const nfn = lookupNativeFn(ir, name) orelse return;
    // A wrong argument count makes per-position type checks speculative (the
    // arguments may not line up with the parameters the user intended), so
    // report the arity and stop — one clear finding beats two on a broken call.
    if (checkArity(ctx, node, name, nfn.arity)) return;
    checkTypes(ctx, node, name);
}

/// The `NativeFn` a name resolves to, or null when it is not a genuine built-in.
/// `isRedefined` already established this succeeds for a matching built-in; the
/// re-lookup is just to read the arity.
fn lookupNativeFn(ir: *IR, name: []const u8) ?*types.NativeFn {
    const g = ir.globals orelse return null;
    const val = g.get(name) orelse return null;
    if (!types.isPointer(val)) return null;
    const obj = types.toObject(val);
    if (obj.tag != .native_fn) return null;
    const nfn = obj.as(types.NativeFn);
    if (!std.mem.eql(u8, nfn.name, name)) return null;
    return nfn;
}

/// Returns true when an arity finding was recorded (the caller then skips the
/// literal-type checks for this call).
fn checkArity(ctx: *Context, node: *Node, name: []const u8, arity: types.NativeFn.Arity) bool {
    const nargs = node.data.call.args.len;
    const bad = switch (arity) {
        .exact => |e| nargs != e,
        .variadic => |min| nargs < min,
    };
    if (!bad) return false;

    const msg = switch (arity) {
        .exact => |e| std.fmt.allocPrint(
            ctx.arena,
            "'{s}' expects {d} argument{s}, but {d} {s} given",
            .{ name, e, plural(e), nargs, wasWere(nargs) },
        ),
        .variadic => |min| std.fmt.allocPrint(
            ctx.arena,
            "'{s}' expects at least {d} argument{s}, but {d} {s} given",
            .{ name, min, plural(min), nargs, wasWere(nargs) },
        ),
    } catch return true;
    ctx.addFinding(.primitive_arity_mismatch, node.ann.span, msg);
    return true;
}

fn checkTypes(ctx: *Context, node: *Node, name: []const u8) void {
    const args = node.data.call.args;
    for (args, 0..) |arg, i| {
        if (arg.tag != .constant) continue; // literals only — no inference
        const lit = arg.data.constant;
        const req = requiredType(name, i, args.len) orelse continue;
        if (!conflicts(req, lit)) continue;
        const span = if (arg.ann.span.known()) arg.ann.span else node.ann.span;
        const want = typeName(req);
        const got = litTypeName(lit);
        const msg = std.fmt.allocPrint(
            ctx.arena,
            "'{s}' expects {s} {s} as argument {d}, but {s} {s} literal was given",
            .{ name, article(want), want, i + 1, article(got), got },
        ) catch return;
        ctx.addFinding(.primitive_type_mismatch, span, msg);
    }
}

// ── The literal-type table ─────────────────────────────────────────────────
//
// Deliberately narrow. An entry belongs here only when R7RS unambiguously
// requires a specific type in that position, so a conflicting *literal* is
// always a run-time type error — never a value some conforming program relies
// on. Higher-order and polymorphic primitives (map, apply, append, cons, eq?,
// display, not, …) are intentionally absent.

const ArgType = enum { pair, number, string, char, vector, symbol, list };

const TypeSpec = struct {
    name: []const u8,
    /// Requirement for arg i (null = unconstrained). Beyond the slice, `rest`
    /// applies — used for the "every argument is a T" primitives (+, string-append).
    positions: []const ?ArgType = &.{},
    rest: ?ArgType = null,
};

const P: ?ArgType = .pair;
const N: ?ArgType = .number;
const S: ?ArgType = .string;
const C: ?ArgType = .char;
const V: ?ArgType = .vector;
const Y: ?ArgType = .symbol;
const L: ?ArgType = .list;

const type_table = [_]TypeSpec{
    // Pair accessors / mutators — arg 0 must be a pair.
    .{ .name = "car", .positions = &.{P} },
    .{ .name = "cdr", .positions = &.{P} },
    .{ .name = "caar", .positions = &.{P} },
    .{ .name = "cadr", .positions = &.{P} },
    .{ .name = "cdar", .positions = &.{P} },
    .{ .name = "cddr", .positions = &.{P} },
    .{ .name = "caaar", .positions = &.{P} },
    .{ .name = "caadr", .positions = &.{P} },
    .{ .name = "cadar", .positions = &.{P} },
    .{ .name = "caddr", .positions = &.{P} },
    .{ .name = "cdaar", .positions = &.{P} },
    .{ .name = "cdadr", .positions = &.{P} },
    .{ .name = "cddar", .positions = &.{P} },
    .{ .name = "cdddr", .positions = &.{P} },
    .{ .name = "set-car!", .positions = &.{P} },
    .{ .name = "set-cdr!", .positions = &.{P} },

    // List operations — arg 0 must be a proper list (the empty list is fine).
    .{ .name = "length", .positions = &.{L} },
    .{ .name = "reverse", .positions = &.{L} },
    .{ .name = "list->vector", .positions = &.{L} },
    .{ .name = "list->string", .positions = &.{L} },

    // Every argument numeric.
    .{ .name = "+", .rest = N },
    .{ .name = "-", .rest = N },
    .{ .name = "*", .rest = N },
    .{ .name = "/", .rest = N },
    .{ .name = "=", .rest = N },
    .{ .name = "<", .rest = N },
    .{ .name = ">", .rest = N },
    .{ .name = "<=", .rest = N },
    .{ .name = ">=", .rest = N },
    .{ .name = "max", .rest = N },
    .{ .name = "min", .rest = N },
    .{ .name = "gcd", .rest = N },
    .{ .name = "lcm", .rest = N },

    // Fixed-arity numeric.
    .{ .name = "abs", .positions = &.{N} },
    .{ .name = "zero?", .positions = &.{N} },
    .{ .name = "positive?", .positions = &.{N} },
    .{ .name = "negative?", .positions = &.{N} },
    .{ .name = "even?", .positions = &.{N} },
    .{ .name = "odd?", .positions = &.{N} },
    .{ .name = "quotient", .positions = &.{ N, N } },
    .{ .name = "remainder", .positions = &.{ N, N } },
    .{ .name = "modulo", .positions = &.{ N, N } },
    .{ .name = "expt", .positions = &.{ N, N } },
    .{ .name = "number->string", .positions = &.{ N, N } },

    // Strings.
    .{ .name = "string-length", .positions = &.{S} },
    .{ .name = "string-ref", .positions = &.{ S, N } },
    .{ .name = "substring", .positions = &.{ S, N, N } },
    .{ .name = "string->symbol", .positions = &.{S} },
    .{ .name = "string->number", .positions = &.{S} },
    .{ .name = "string->list", .positions = &.{S} },
    .{ .name = "string-append", .rest = S },

    // Vectors.
    .{ .name = "vector-length", .positions = &.{V} },
    .{ .name = "vector-ref", .positions = &.{ V, N } },
    .{ .name = "vector-set!", .positions = &.{ V, N } },
    .{ .name = "vector->list", .positions = &.{V} },

    // Characters.
    .{ .name = "char->integer", .positions = &.{C} },
    .{ .name = "char-upcase", .positions = &.{C} },
    .{ .name = "char-downcase", .positions = &.{C} },

    // Symbols.
    .{ .name = "symbol->string", .positions = &.{Y} },
};

fn requiredType(name: []const u8, index: usize, argc: usize) ?ArgType {
    _ = argc;
    for (type_table) |spec| {
        if (!std.mem.eql(u8, spec.name, name)) continue;
        if (index < spec.positions.len) return spec.positions[index];
        return spec.rest;
    }
    return null;
}

/// True when literal `v` cannot satisfy requirement `req` — i.e. it is
/// definitely the wrong type, so the call is a guaranteed run-time type error.
fn conflicts(req: ArgType, v: Value) bool {
    return switch (req) {
        .pair => !types.isPair(v),
        .number => !isNumberLit(v),
        .string => !types.isString(v),
        .char => !types.isChar(v),
        .vector => !types.isVector(v),
        .symbol => !types.isSymbol(v),
        .list => !(types.isPair(v) or v == types.NIL),
    };
}

fn isNumberLit(v: Value) bool {
    return types.isFixnum(v) or types.isFlonum(v) or types.isBignum(v) or
        types.isRationalObj(v) or types.isComplex(v);
}

fn typeName(t: ArgType) []const u8 {
    return switch (t) {
        .pair => "pair",
        .number => "number",
        .string => "string",
        .char => "character",
        .vector => "vector",
        .symbol => "symbol",
        .list => "list",
    };
}

fn litTypeName(v: Value) []const u8 {
    if (types.isFixnum(v) or types.isBignum(v)) return "integer";
    if (types.isFlonum(v)) return "real";
    if (types.isRationalObj(v)) return "rational";
    if (types.isComplex(v)) return "complex number";
    if (types.isString(v)) return "string";
    if (types.isChar(v)) return "character";
    if (v == types.TRUE or v == types.FALSE) return "boolean";
    if (types.isSymbol(v)) return "symbol";
    if (types.isVector(v)) return "vector";
    if (types.isBytevector(v)) return "bytevector";
    if (v == types.NIL) return "empty list";
    if (v == types.EOF) return "eof-object";
    return "value";
}

/// "a" or "an" for `noun`, from its first letter. Good enough for the fixed set
/// of type names used here (no "hour"/"honest" exceptions among them).
fn article(noun: []const u8) []const u8 {
    if (noun.len == 0) return "a";
    return switch (std.ascii.toLower(noun[0])) {
        'a', 'e', 'i', 'o', 'u' => "an",
        else => "a",
    };
}

fn plural(n: u8) []const u8 {
    return if (n == 1) "" else "s";
}

fn wasWere(n: usize) []const u8 {
    return if (n == 1) "was" else "were";
}

// ── Tests ──────────────────────────────────────────────────────────────────

const testing = std.testing;

test "requiredType: fixed positions, rest, and unlisted primitives" {
    try testing.expectEqual(ArgType.pair, requiredType("car", 0, 1).?);
    try testing.expectEqual(ArgType.vector, requiredType("vector-ref", 0, 2).?);
    try testing.expectEqual(ArgType.number, requiredType("vector-ref", 1, 2).?);
    // Beyond the listed positions, unconstrained (vector-set! value is any type).
    try testing.expect(requiredType("vector-set!", 2, 3) == null);
    // `rest` covers every argument of a variadic-typed primitive.
    try testing.expectEqual(ArgType.number, requiredType("+", 0, 3).?);
    try testing.expectEqual(ArgType.number, requiredType("+", 7, 8).?);
    try testing.expectEqual(ArgType.string, requiredType("string-append", 4, 5).?);
    // Not in the table.
    try testing.expect(requiredType("cons", 0, 2) == null);
    try testing.expect(requiredType("map", 0, 2) == null);
}

test "conflicts: pair requirement rejects non-pairs including the empty list" {
    try testing.expect(conflicts(.pair, types.makeFixnum(5)));
    try testing.expect(conflicts(.pair, types.NIL)); // the empty list is not a pair
    try testing.expect(conflicts(.pair, types.makeChar('a')));
}

test "conflicts: number requirement" {
    try testing.expect(!conflicts(.number, types.makeFixnum(1)));
    try testing.expect(conflicts(.number, types.TRUE));
}

test "conflicts: list accepts empty list and pairs, rejects atoms" {
    try testing.expect(!conflicts(.list, types.NIL));
    try testing.expect(conflicts(.list, types.makeFixnum(3)));
    try testing.expect(conflicts(.list, types.TRUE));
}

test "litTypeName: representative values" {
    try testing.expectEqualStrings("integer", litTypeName(types.makeFixnum(1)));
    try testing.expectEqualStrings("boolean", litTypeName(types.TRUE));
    try testing.expectEqualStrings("empty list", litTypeName(types.NIL));
}

test "enter/exit macro suppression is balanced and never underflows" {
    var udefs = std.StringHashMap(void).init(testing.allocator);
    defer udefs.deinit();
    var ctx: Context = .{ .arena = testing.allocator, .user_defined = &udefs };
    defer ctx.findings.deinit(testing.allocator);
    active = &ctx;
    defer active = null;

    exitMacroExpansion(); // underflow guard: stays at 0
    try testing.expectEqual(@as(u32, 0), ctx.suppress_depth);
    enterMacroExpansion();
    try testing.expectEqual(@as(u32, 1), ctx.suppress_depth);
    exitMacroExpansion();
    try testing.expectEqual(@as(u32, 0), ctx.suppress_depth);
}
