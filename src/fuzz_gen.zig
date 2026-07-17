//! Smith-driven grammar generator for valid R7RS programs (fuzzing Tier 2,
//! issue #1392).
//!
//! A Zest-style parametric generator: every structural decision is a
//! `std.testing.Smith` choice, so the fuzzer mutates the decision stream and
//! coverage feedback turns byte mutations into structural program mutations
//! (docs/dev/fuzzing-feasibility.md, "Zig's Smith is the Zest architecture").
//! Each design constraint comes from a documented research lesson or the
//! doc's operating guidance:
//!
//! - **Well-bound** (PolyGlot): a scope stack tracks every identifier with a
//!   type-ish `Kind`; references pick only from visible innermost bindings,
//!   calls match arities, and indices stay in range, so programs exercise the
//!   VM instead of dying at "unbound variable".
//! - **Bounded by construction**: expression depth, literal sizes, loop
//!   iteration counts, and total program bytes are capped. Loop-carried
//!   integer accumulators are modulo-clamped so no program degenerates into
//!   million-digit bignum arithmetic that a single primitive call could ride
//!   past the 100 ms VM deadline.
//! - **No ambient effects**: filesystem, process, FFI, network, and thread
//!   forms are never emitted (the sandboxed eval harness enforces the same
//!   at runtime as a second line of defense).
//! - **Form coverage** weighted toward the interesting compiler/VM/GC paths:
//!   closures, tail calls, named let / do loops, call/cc, dynamic-wind,
//!   guard/raise, quasiquote, syntax-rules definition + use, and
//!   vector/string/bytevector mutation (GC write-barrier paths).
//!
//! Ordinary Scheme runtime errors remain expected fuzz outcomes, but most
//! generated programs evaluate cleanly (asserted by a test in
//! tests_fuzz.zig); every program parses and compiles (asserted below).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Error = error{ WriteFailed, OutOfMemory };

// ---------------------------------------------------------------------------
// Bounds — everything the generator emits is capped by construction.
// ---------------------------------------------------------------------------

const max_depth: u32 = 5;
/// Once the program exceeds this many bytes, all further expressions are
/// forced to leaves. The remaining open forms can only add a bounded tail,
/// so `expected_max_bytes` holds with a wide margin (unit-tested).
const soft_budget: usize = 3072;
pub const expected_max_bytes: usize = 8192;
/// Prime clamp for loop-carried accumulators: `(modulo acc 999983)` keeps
/// repeated squaring inside loops from building huge bignums.
pub const acc_modulus: u32 = 999983;
const max_outer_iters: u32 = 16;
const max_inner_iters: u32 = 5;

// ---------------------------------------------------------------------------
// Static vocabulary. All names live in fixed pools so bindings can be
// compared and re-emitted without allocation. Reserved names that never
// appear in the general pool: lp (loops), k (continuations), ex (guard),
// p/q/r (syntax-rules pattern variables), g*/f*/m* (top-level definitions).
// ---------------------------------------------------------------------------

const local_names = [_][]const u8{ "a", "b", "c", "d", "e", "h", "u", "v" };
/// Public: the differential oracle (tests_fuzz.zig) prints these globals
/// after evaluation to widen its observable — a wrong fold inside
/// `(define g1 ...)` is invisible in the program's final value alone.
pub const global_names = [_][]const u8{ "g0", "g1", "g2" };
pub const fn_names = [_][]const u8{ "f0", "f1" };
const macro_names = [_][]const u8{ "m0", "m1" };
const pattern_names = [_][]const u8{ "p", "q", "r" };

pub const symbol_names = [_][]const u8{ "alpha", "beta", "boom", "zed" };

/// String literal pool entry: the source text (with quotes) plus its length
/// in codepoints — the unit every string index and length primitive uses.
pub const StrLit = struct { text: []const u8, len: u16 };

/// Build a pool entry with the length derived from the text at comptime. A
/// hand-maintained count is a generator leak waiting to happen: "x y!" was
/// recorded as len 5 (actually 4), so every index the generators derived
/// from it — `(string-ref s 4)`, `(modulo i 5)` — could land out of range,
/// making erroneous programs the oracle can't flag because both sides raise
/// identically (#1620).
pub fn strLit(comptime text: []const u8) StrLit {
    comptime {
        std.debug.assert(text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"');
        const inner = text[1 .. text.len - 1];
        // Escape sequences would need their own length rules; the pools are
        // escape-free, so reject rather than miscount.
        std.debug.assert(std.mem.indexOfScalar(u8, inner, '\\') == null);
        const n = std.unicode.utf8CountCodepoints(inner) catch unreachable;
        return .{ .text = text, .len = n };
    }
}

// Public: also referenced by the expression generators in fuzz_gen_expr.zig.
pub const arith_ops = [_][]const u8{ "+", "-", "*", "min", "max" };
pub const div_ops = [_][]const u8{ "quotient", "remainder", "modulo" };
pub const cmp_ops = [_][]const u8{ "<", "<=", "=", ">", ">=" };
pub const rec_ops = [_][]const u8{ "+", "*", "max" };
pub const fold_ops = [_][]const u8{ "+", "*", "max", "min" };
pub const real_round_ops = [_][]const u8{ "round", "floor", "truncate", "ceiling" };
pub const guard_preds = [_][]const u8{ "number?", "symbol?", "string?", "pair?" };
pub const any_preds = [_][]const u8{ "number?", "string?", "boolean?", "procedure?", "symbol?", "char?", "vector?", "list?" };

// ---------------------------------------------------------------------------
// Decision source: Smith under the fuzzer, a seeded PRNG in unit tests.
// Smith replays out-of-range decisions as the range minimum, so a PRNG is
// what gives the fixed-seed tests real variety.
// ---------------------------------------------------------------------------

/// Coarse per-decision-point identifiers; they become stable Smith UIDs so
/// the fuzzer can attribute coverage to individual grammar decisions.
const Tag = enum(u32) {
    count,
    top_kind,
    depth_pick,
    bind_kind,
    arity,
    shape,
    op_pick,
    name_pick,
    var_pick,
    lit_pick,
    iters,
    nargs,
    idx_kind,
    idx_pick,
    coin,
    len_pick,
};

const Chooser = union(enum) {
    smith: *std.testing.Smith,
    random: std.Random,

    pub fn range(c: *Chooser, comptime tag: Tag, lo: u32, hi: u32) u32 {
        std.debug.assert(lo <= hi);
        if (lo == hi) return lo;
        return switch (c.*) {
            .smith => |s| s.valueRangeAtMostWithHash(u32, lo, hi, @intFromEnum(tag) *% 0x9e3779b9),
            .random => |r| r.intRangeAtMost(u32, lo, hi),
        };
    }

    pub fn index(c: *Chooser, comptime tag: Tag, len: usize) usize {
        return c.range(tag, 0, @intCast(len - 1));
    }

    /// True with probability num/den.
    pub fn chance(c: *Chooser, comptime tag: Tag, num: u32, den: u32) bool {
        return c.range(tag, 1, den) <= num;
    }
};

// ---------------------------------------------------------------------------
// Kind model: enough type/shape information to keep generated programs
// well-typed, well-arity'd, and in-bounds.
// ---------------------------------------------------------------------------

pub const Len = union(enum) {
    exact: u16,
    at_least_one,
    unknown,

    pub fn nonEmpty(l: Len) bool {
        return switch (l) {
            .exact => |n| n > 0,
            .at_least_one => true,
            .unknown => false,
        };
    }

    pub fn exactLen(l: Len) ?u16 {
        return switch (l) {
            .exact => |n| n,
            else => null,
        };
    }

    pub fn plusOne(l: Len) Len {
        return switch (l) {
            .exact => |n| .{ .exact = n + 1 },
            else => .at_least_one,
        };
    }

    pub fn sum(a: Len, b: Len) Len {
        if (a.exactLen()) |x| if (b.exactLen()) |y| return .{ .exact = x + y };
        if (a.nonEmpty() or b.nonEmpty()) return .at_least_one;
        return .unknown;
    }
};

pub const StrInfo = struct { len: ?u16, mutable: bool };
/// Cell mutability of a list value: `head` means only the first cell is
/// known-fresh (e.g. a cons onto a possibly-literal tail), `all` means every
/// cell is newly allocated. set-car! through a binding needs `head` or
/// better; cdr walks onto the spine, so it needs `all` to stay writable.
pub const Mut = enum { none, head, all };
/// `ints`: every element is an exact integer (safe to feed to arithmetic).
pub const ListInfo = struct { len: Len, mut: Mut, ints: bool };
/// `boxed`: elements are non-empty int lists (heap values — write-barrier
/// paths) rather than fixnums.
pub const VecInfo = struct { len: u16, boxed: bool };
/// `bounded_first`: recursive skeleton whose first argument is the recursion
/// counter — call it only with a small literal, never via map/apply/fold.
const ProcInfo = struct { arity: u8, variadic: bool = false, bounded_first: bool = false };

pub const Kind = union(enum) {
    int,
    boolean,
    char,
    string: StrInfo,
    list: ListInfo,
    vector: VecInfo,
    bytevector: u16,
    proc: ProcInfo,
    /// Structural binder emitted by a skeleton (e.g. a letrec-bound
    /// procedure name that must not be called freely): hides outer
    /// same-named bindings from the picker without being pickable itself.
    /// Without this, a generated reference to an outer variable of the same
    /// name would resolve to the shadowing binder and change type.
    reserved,
};

pub const Binding = struct {
    name: []const u8,
    kind: Kind,
    /// Pattern variables of syntax-rules templates expand to arbitrary
    /// expressions, so they must never be `set!` targets.
    settable: bool = true,
};

const Macro = struct { name: []const u8, arity: u8, variadic: bool };

pub const ListNeed = struct { ints: bool = false, non_empty: bool = false };

// Binding predicates (comptime, for pickVar/hasVar).
pub fn bindIsInt(b: Binding) bool {
    return b.kind == .int;
}
pub fn bindIsSettableAtom(b: Binding) bool {
    return b.settable and (b.kind == .int or b.kind == .boolean or b.kind == .char);
}
pub fn bindIsSettableInt(b: Binding) bool {
    return b.settable and b.kind == .int;
}
pub fn bindIsBool(b: Binding) bool {
    return b.kind == .boolean;
}
pub fn bindIsChar(b: Binding) bool {
    return b.kind == .char;
}
pub fn bindIsProc(b: Binding) bool {
    return b.kind == .proc;
}
pub fn bindIsPlainProc(b: Binding) bool {
    return switch (b.kind) {
        .proc => |p| !p.bounded_first,
        else => false,
    };
}
pub fn bindIsPlainProc2(b: Binding) bool {
    return switch (b.kind) {
        .proc => |p| !p.bounded_first and !p.variadic and p.arity == 2,
        else => false,
    };
}
pub fn bindIsVec(b: Binding) bool {
    return switch (b.kind) {
        .vector => |v| v.len > 0,
        else => false,
    };
}
pub fn bindIsIntVec(b: Binding) bool {
    return switch (b.kind) {
        .vector => |v| v.len > 0 and !v.boxed,
        else => false,
    };
}
pub fn bindIsBv(b: Binding) bool {
    return switch (b.kind) {
        .bytevector => |n| n > 0,
        else => false,
    };
}
pub fn bindIsString(b: Binding) bool {
    return b.kind == .string;
}
pub fn bindIsStringIndexable(b: Binding) bool {
    return switch (b.kind) {
        .string => |s| s.len != null and s.len.? > 0,
        else => false,
    };
}
pub fn bindIsStringSettable(b: Binding) bool {
    return switch (b.kind) {
        .string => |s| s.mutable and s.len != null and s.len.? > 0,
        else => false,
    };
}
pub fn bindIsStringExact(b: Binding) bool {
    return switch (b.kind) {
        .string => |s| s.len != null,
        else => false,
    };
}
pub fn bindIsListMutNonEmpty(b: Binding) bool {
    return switch (b.kind) {
        .list => |l| l.mut != .none and l.len.nonEmpty(),
        else => false,
    };
}
pub fn bindIsListIntsExactNonEmpty(b: Binding) bool {
    return switch (b.kind) {
        .list => |l| l.ints and l.len.exactLen() != null and l.len.exactLen().? > 0,
        else => false,
    };
}

/// Weighted candidate list; candidates are gated on availability (in-scope
/// bindings, depth, guard context) before being added.
pub fn Cands(comptime E: type) type {
    return struct {
        ops: [40]E = undefined,
        weights: [40]u32 = undefined,
        n: usize = 0,
        total: u32 = 0,

        pub fn add(self: *@This(), op: E, weight: u32) void {
            std.debug.assert(self.n < self.ops.len);
            self.ops[self.n] = op;
            self.weights[self.n] = weight;
            self.n += 1;
            self.total += weight;
        }

        pub fn pick(self: *@This(), ch: *Chooser) E {
            std.debug.assert(self.total > 0);
            var r = ch.range(.op_pick, 0, self.total - 1);
            for (self.ops[0..self.n], self.weights[0..self.n]) |op, wt| {
                if (r < wt) return op;
                r -= wt;
            }
            unreachable;
        }
    };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Emit one small valid R7RS program driven by Smith decisions.
/// Caller owns the returned slice.
pub fn generateProgram(smith: *std.testing.Smith, gpa: Allocator) Error![]u8 {
    var ch: Chooser = .{ .smith = smith };
    return generateWith(&ch, gpa);
}

/// Deterministic PRNG-driven generation for unit tests and measurements.
pub fn generateSeeded(seed: u64, gpa: Allocator) Error![]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    var ch: Chooser = .{ .random = prng.random() };
    return generateWith(&ch, gpa);
}

/// Native-compilable subset (fuzz_gen_native.zig): programs restricted to
/// forms the LLVM native backend compiles without interpreter fallback, for
/// the offline VM-vs-native differential harness (tests/fuzz/native-diff.sh,
/// issue #1395).
pub fn generateNativeSeeded(seed: u64, gpa: Allocator) Error![]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    var ch: Chooser = .{ .random = prng.random() };
    return generateNativeWith(&ch, gpa);
}

/// Portable subset (fuzz_gen_portable.zig): fully-specified, deterministic
/// R7RS-small programs for the Kaappi-vs-external-reference differential
/// harness (tests/fuzz/oracle-diff.sh, issue #1396).
pub fn generatePortableSeeded(seed: u64, gpa: Allocator) Error![]u8 {
    var prng = std.Random.DefaultPrng.init(seed);
    var ch: Chooser = .{ .random = prng.random() };
    var g: Gen = .{
        .ch = &ch,
        .aw = .init(gpa),
        .gpa = gpa,
    };
    defer {
        g.scope.deinit(gpa);
        g.macros.deinit(gpa);
        g.aw.deinit();
    }
    try @import("fuzz_gen_portable.zig").genProgram(&g);
    return g.aw.toOwnedSlice() catch return error.OutOfMemory;
}

fn generateWith(ch: *Chooser, gpa: Allocator) Error![]u8 {
    var g: Gen = .{
        .ch = ch,
        .aw = .init(gpa),
        .gpa = gpa,
    };
    defer {
        g.scope.deinit(gpa);
        g.macros.deinit(gpa);
        g.aw.deinit();
    }
    try g.genProgram();
    return g.aw.toOwnedSlice() catch return error.OutOfMemory;
}

fn generateNativeWith(ch: *Chooser, gpa: Allocator) Error![]u8 {
    var g: Gen = .{
        .ch = ch,
        .aw = .init(gpa),
        .gpa = gpa,
    };
    defer {
        g.scope.deinit(gpa);
        g.macros.deinit(gpa);
        g.aw.deinit();
    }
    try @import("fuzz_gen_native.zig").genProgram(&g);
    return g.aw.toOwnedSlice() catch return error.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Generator
// ---------------------------------------------------------------------------

pub const Gen = struct {
    ch: *Chooser,
    aw: std.Io.Writer.Allocating,
    gpa: Allocator,
    scope: std.ArrayList(Binding) = .empty,
    macros: std.ArrayList(Macro) = .empty,
    global_count: u8 = 0,
    fn_count: u8 = 0,
    macro_count: u8 = 0,
    /// Static loop-nesting depth; >0 shrinks iteration bounds and clamps
    /// integer writes so loop-carried values stay small.
    loop_nest: u8 = 0,
    /// `raise`/`error` are only emitted inside a guard body.
    guard_depth: u8 = 0,

    // -- data-kind generators (split into fuzz_gen_data.zig for the file
    // size policy); re-exported so call sites keep method syntax --

    const data = @import("fuzz_gen_data.zig");
    pub const genChar = data.genChar;
    pub const genString = data.genString;
    pub const genList = data.genList;
    pub const genVector = data.genVector;
    pub const genBytevector = data.genBytevector;
    pub const genReal = data.genReal;
    pub const pickListVar = data.pickListVar;
    pub const listVarAvail = data.listVarAvail;
    pub const pickCdrVar = data.pickCdrVar;
    pub const cdrVarAvail = data.cdrVarAvail;
    pub const genStmt = data.genStmt;

    // -- integer/boolean/test expression generators (split into
    // fuzz_gen_expr.zig for the file size policy); re-exported so call
    // sites keep method syntax --

    const expr = @import("fuzz_gen_expr.zig");
    pub const genInt = expr.genInt;
    pub const genIndex = expr.genIndex;
    pub const genLambdaInt = expr.genLambdaInt;
    pub const genBool = expr.genBool;
    pub const genTest = expr.genTest;
    pub const genClampedInt = expr.genClampedInt;

    // -- emission helpers --

    pub fn emit(g: *Gen, s: []const u8) Error!void {
        try g.aw.writer.writeAll(s);
    }

    pub fn emitf(g: *Gen, comptime fmt: []const u8, args: anytype) Error!void {
        try g.aw.writer.print(fmt, args);
    }

    /// Depth cap: past the byte budget, everything becomes a leaf.
    pub fn cap(g: *Gen, depth: u32) u32 {
        return if (g.aw.written().len > soft_budget) 0 else depth;
    }

    // -- scope helpers --

    pub fn pushBinding(g: *Gen, name: []const u8, kind: Kind) Error!void {
        try g.scope.append(g.gpa, .{ .name = name, .kind = kind });
    }

    pub fn pushNonSettable(g: *Gen, name: []const u8, kind: Kind) Error!void {
        try g.scope.append(g.gpa, .{ .name = name, .kind = kind, .settable = false });
    }

    fn pushPatternVar(g: *Gen, name: []const u8) Error!void {
        try g.scope.append(g.gpa, .{ .name = name, .kind = .int, .settable = false });
    }

    /// Count bindings visible under shadowing (innermost occurrence of each
    /// name wins) that satisfy `match`.
    fn countVisible(g: *Gen, comptime match: fn (Binding) bool) u32 {
        var seen: [24][]const u8 = undefined;
        var nseen: usize = 0;
        var count: u32 = 0;
        var i = g.scope.items.len;
        scan: while (i > 0) {
            i -= 1;
            const b = g.scope.items[i];
            for (seen[0..nseen]) |nm| {
                if (std.mem.eql(u8, nm, b.name)) continue :scan;
            }
            if (nseen == seen.len) break;
            seen[nseen] = b.name;
            nseen += 1;
            if (match(b)) count += 1;
        }
        return count;
    }

    pub fn hasVar(g: *Gen, comptime match: fn (Binding) bool) bool {
        return g.countVisible(match) > 0;
    }

    pub fn pickVar(g: *Gen, comptime match: fn (Binding) bool) ?Binding {
        const total = g.countVisible(match);
        if (total == 0) return null;
        var want = g.ch.range(.var_pick, 0, total - 1);
        var seen: [24][]const u8 = undefined;
        var nseen: usize = 0;
        var i = g.scope.items.len;
        scan: while (i > 0) {
            i -= 1;
            const b = g.scope.items[i];
            for (seen[0..nseen]) |nm| {
                if (std.mem.eql(u8, nm, b.name)) continue :scan;
            }
            if (nseen == seen.len) break;
            seen[nseen] = b.name;
            nseen += 1;
            if (match(b)) {
                if (want == 0) return b;
                want -= 1;
            }
        }
        unreachable;
    }

    /// Pick `n` distinct names from the local pool (binders in one form must
    /// not collide; shadowing outer scopes is fine and intended).
    pub fn pickNames(g: *Gen, n: usize, buf: *[4][]const u8) []const []const u8 {
        const start = g.ch.range(.name_pick, 0, local_names.len - 1);
        for (0..n) |j| buf[j] = local_names[(start + j) % local_names.len];
        return buf[0..n];
    }

    pub fn loopIters(g: *Gen) u32 {
        const hi = if (g.loop_nest == 0) max_outer_iters else max_inner_iters;
        return g.ch.range(.iters, 0, hi);
    }

    // -- program structure --

    fn genProgram(g: *Gen) Error!void {
        const nglobals = g.ch.range(.count, 0, global_names.len);
        for (0..nglobals) |_| try g.genGlobalDefine();
        const nfns = g.ch.range(.count, 0, fn_names.len);
        for (0..nfns) |_| try g.genFnDefine();
        const nmacros = g.ch.range(.count, 0, macro_names.len);
        for (0..nmacros) |_| try g.genMacroDefine();
        const nexprs = g.ch.range(.count, 1, 3);
        for (0..nexprs) |_| {
            try g.genTopExpr();
            try g.emit("\n");
        }
    }

    fn genTopExpr(g: *Gen) Error!void {
        const depth = g.ch.range(.depth_pick, 2, max_depth);
        const TopKind = enum { int, stmt, boolean, list, vector, string };
        var c: Cands(TopKind) = .{};
        c.add(.int, 6);
        c.add(.stmt, 3);
        c.add(.boolean, 1);
        c.add(.list, 1);
        c.add(.vector, 1);
        c.add(.string, 1);
        switch (c.pick(g.ch)) {
            .int => try g.genInt(depth),
            .stmt => try g.genStmt(depth),
            .boolean => try g.genBool(depth),
            .list => _ = try g.genList(depth, .{}),
            .vector => _ = try g.genVector(depth, false),
            .string => _ = try g.genString(depth),
        }
    }

    pub const BindKind = enum { int, boolean, char, string, list, vector, bytevector, proc };

    pub fn pickBindKind(g: *Gen) BindKind {
        var c: Cands(BindKind) = .{};
        c.add(.int, 6);
        c.add(.proc, 3);
        c.add(.vector, 3);
        c.add(.list, 3);
        c.add(.string, 2);
        c.add(.bytevector, 1);
        c.add(.boolean, 1);
        c.add(.char, 1);
        return c.pick(g.ch);
    }

    /// Emit an expression of the chosen kind and return the Kind (with shape
    /// info) for the binding that will hold it.
    pub fn genValueOfKind(g: *Gen, bk: BindKind, depth: u32) Error!Kind {
        switch (bk) {
            .int => {
                try g.genInt(depth);
                return .int;
            },
            .boolean => {
                try g.genBool(depth);
                return .boolean;
            },
            .char => {
                try g.genChar(depth);
                return .char;
            },
            .string => return .{ .string = try g.genString(depth) },
            .list => return .{ .list = try g.genList(depth, .{}) },
            .vector => return .{ .vector = try g.genVector(depth, false) },
            .bytevector => return .{ .bytevector = try g.genBytevector(depth) },
            .proc => {
                const variadic = g.ch.chance(.coin, 1, 5);
                const arity: u8 = @intCast(g.ch.range(.arity, if (variadic) 0 else 1, 3));
                try g.genLambdaInt(arity, variadic, depth);
                return .{ .proc = .{ .arity = arity, .variadic = variadic } };
            },
        }
    }

    fn genGlobalDefine(g: *Gen) Error!void {
        const name = global_names[g.global_count];
        g.global_count += 1;
        try g.emitf("(define {s} ", .{name});
        const kind = try g.genValueOfKind(g.pickBindKind(), 2);
        try g.emit(")\n");
        // Registered after the value expression so it cannot reference itself.
        try g.pushBinding(name, kind);
    }

    fn genFnDefine(g: *Gen) Error!void {
        const name = fn_names[g.fn_count];
        g.fn_count += 1;
        var nb: [4][]const u8 = undefined;
        switch (g.ch.range(.shape, 0, 2)) {
            0 => { // plain function
                const arity: u8 = @intCast(g.ch.range(.arity, 0, 3));
                const params = g.pickNames(arity, &nb);
                try g.emitf("(define ({s}", .{name});
                const mark = g.scope.items.len;
                for (params) |p| {
                    try g.emitf(" {s}", .{p});
                    try g.pushBinding(p, .int);
                }
                try g.emit(") ");
                if (g.ch.chance(.coin, 1, 3)) {
                    try g.genStmt(2);
                    try g.emit(" ");
                }
                try g.genInt(3);
                try g.emit(")\n");
                g.scope.shrinkRetainingCapacity(mark);
                try g.pushBinding(name, .{ .proc = .{ .arity = arity } });
            },
            1 => { // tail-recursive skeleton: bounded countdown, clamped accumulator
                const params = g.pickNames(2, &nb);
                try g.emitf("(define ({s} {s} {s}) (if (<= {s} 0) {s} ({s} (- {s} 1) (modulo ", .{
                    name, params[0], params[1], params[0], params[1], name, params[0],
                });
                const mark = g.scope.items.len;
                try g.pushBinding(params[0], .int);
                try g.pushBinding(params[1], .int);
                try g.genInt(3);
                g.scope.shrinkRetainingCapacity(mark);
                try g.emitf(" {d}))))\n", .{acc_modulus});
                // Registered after the body so the accumulator expression
                // cannot call the function itself (unbounded recursion).
                try g.pushBinding(name, .{ .proc = .{ .arity = 2, .bounded_first = true } });
            },
            else => { // non-tail recursive skeleton (stack-frame paths)
                const params = g.pickNames(1, &nb);
                const op = rec_ops[g.ch.index(.op_pick, rec_ops.len)];
                try g.emitf("(define ({s} {s}) (if (<= {s} 0) ", .{ name, params[0], params[0] });
                const mark = g.scope.items.len;
                try g.pushBinding(params[0], .int);
                try g.genInt(2);
                try g.emitf(" ({s} ", .{op});
                try g.genInt(2);
                try g.emitf(" ({s} (- {s} 1)))))\n", .{ name, params[0] });
                g.scope.shrinkRetainingCapacity(mark);
                try g.pushBinding(name, .{ .proc = .{ .arity = 1, .bounded_first = true } });
            },
        }
    }

    fn genMacroDefine(g: *Gen) Error!void {
        const name = macro_names[g.macro_count];
        g.macro_count += 1;
        try g.emitf("(define-syntax {s} (syntax-rules ()", .{name});
        const shape = g.ch.range(.shape, 0, 2);
        var arity: u8 = 0;
        var variadic = false;
        if (shape == 0 or shape == 2) {
            arity = @intCast(g.ch.range(.arity, 1, 3));
            try g.emit(" ((_");
            const mark = g.scope.items.len;
            for (pattern_names[0..arity]) |pn| {
                try g.emitf(" {s}", .{pn});
                try g.pushPatternVar(pn);
            }
            try g.emit(") ");
            try g.genInt(2);
            try g.emit(")");
            g.scope.shrinkRetainingCapacity(mark);
        }
        if (shape == 1 or shape == 2) {
            variadic = true;
            const vop = if (g.ch.chance(.coin, 1, 2)) "+" else "*";
            try g.emitf(" ((_ p ...) ({s} 1 p ...))", .{vop});
        }
        try g.emit("))\n");
        // Registered after the template so a template cannot expand itself.
        try g.macros.append(g.gpa, .{ .name = name, .arity = arity, .variadic = variadic });
    }
};

// ---------------------------------------------------------------------------
// Tests: every fixed-seed program must parse and compile (runtime errors are
// allowed — asserted separately in tests_fuzz.zig, which owns the VM
// harness). This mirrors the read → compile half of vm_eval.eval, keeping a
// persistent macro table so syntax-rules definitions apply to later forms.
// ---------------------------------------------------------------------------

test "fixed-seed generated programs parse, compile, and stay bounded" {
    const memory = @import("memory.zig");
    const reader_mod = @import("reader.zig");
    const compiler_mod = @import("compiler.zig");
    const types = @import("types.zig");
    const gpa = std.testing.allocator;

    var seed: u64 = 0;
    while (seed < 2000) : (seed += 1) {
        const src = try generateSeeded(seed, gpa);
        defer gpa.free(src);
        errdefer std.debug.print("seed {d} program:\n{s}\n", .{ seed, src });
        try std.testing.expect(src.len < expected_max_bytes);

        var gc = memory.GC.init(gpa);
        defer gc.deinit();
        // No VM here, so nothing marks the macro table's transformers as
        // roots; suppress collection (bounded allocation per seed) so a
        // -Dgc-stress build cannot sweep them between top-level forms.
        gc.no_collect += 1;
        var macros = std.StringHashMap(types.Value).init(gpa);
        defer macros.deinit();
        var globals = std.StringHashMap(types.Value).init(gpa);
        defer globals.deinit();
        var r = reader_mod.Reader.init(&gc, src);
        defer r.deinit();
        while (try r.hasMore()) {
            var expr = try r.readDatum();
            gc.pushRoot(&expr);
            defer gc.popRoot();
            _ = try compiler_mod.compileExpressionWithMacros(&gc, expr, &macros, &globals);
        }
    }
}

test "generation is deterministic per seed" {
    const gpa = std.testing.allocator;
    const a = try generateSeeded(42, gpa);
    defer gpa.free(a);
    const b = try generateSeeded(42, gpa);
    defer gpa.free(b);
    try std.testing.expectEqualStrings(a, b);
}

test {
    _ = @import("fuzz_gen_native.zig");
    _ = @import("fuzz_gen_portable.zig");
}
