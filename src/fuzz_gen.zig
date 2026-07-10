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
const global_names = [_][]const u8{ "g0", "g1", "g2" };
const fn_names = [_][]const u8{ "f0", "f1" };
const macro_names = [_][]const u8{ "m0", "m1" };
const pattern_names = [_][]const u8{ "p", "q", "r" };

pub const symbol_names = [_][]const u8{ "alpha", "beta", "boom", "zed" };

const arith_ops = [_][]const u8{ "+", "-", "*", "min", "max" };
const div_ops = [_][]const u8{ "quotient", "remainder", "modulo" };
const cmp_ops = [_][]const u8{ "<", "<=", "=", ">", ">=" };
const rec_ops = [_][]const u8{ "+", "*", "max" };
const fold_ops = [_][]const u8{ "+", "*", "max", "min" };
pub const real_round_ops = [_][]const u8{ "round", "floor", "truncate", "ceiling" };
const guard_preds = [_][]const u8{ "number?", "symbol?", "string?", "pair?" };
const any_preds = [_][]const u8{ "number?", "string?", "boolean?", "procedure?", "symbol?", "char?", "vector?", "list?" };

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

const Kind = union(enum) {
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

    fn loopIters(g: *Gen) u32 {
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

    const BindKind = enum { int, boolean, char, string, list, vector, bytevector, proc };

    fn pickBindKind(g: *Gen) BindKind {
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
    fn genValueOfKind(g: *Gen, bk: BindKind, depth: u32) Error!Kind {
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

    // -- integer expressions --

    const IntOp = enum {
        lit,
        ref,
        arith,
        abs_op,
        divmod,
        if_form,
        cond_form,
        case_form,
        and_or,
        let_form,
        letrec_lambdas,
        inline_call,
        call_proc,
        call_macro,
        named_let,
        do_loop,
        letrec_rec,
        callcc,
        dynwind,
        guard_form,
        raise_form,
        begin_form,
        vec_ref,
        bv_ref,
        char_int,
        str_len,
        list_len,
        car_op,
        list_ref_op,
        force_delay,
        cwv,
        let_values,
        num_roundtrip,
        from_real,
        apply_op,
        fold_op,
    };

    pub fn genInt(g: *Gen, depth_in: u32) Error!void {
        const depth = g.cap(depth_in);
        var c: Cands(IntOp) = .{};
        c.add(.lit, 5);
        if (g.hasVar(bindIsInt)) c.add(.ref, 6);
        if (depth > 0) {
            c.add(.arith, 8);
            c.add(.abs_op, 1);
            c.add(.divmod, 3);
            c.add(.if_form, 5);
            c.add(.cond_form, 3);
            c.add(.case_form, 2);
            c.add(.and_or, 2);
            c.add(.let_form, 6);
            c.add(.letrec_lambdas, 2);
            c.add(.inline_call, 2);
            if (g.hasVar(bindIsProc)) c.add(.call_proc, 6);
            if (g.macros.items.len > 0) c.add(.call_macro, 4);
            c.add(.named_let, 4);
            c.add(.do_loop, 3);
            c.add(.letrec_rec, 3);
            c.add(.callcc, 3);
            c.add(.dynwind, 2);
            c.add(.guard_form, 3);
            if (g.guard_depth > 0) c.add(.raise_form, 2);
            c.add(.begin_form, 3);
            if (g.hasVar(bindIsVec)) c.add(.vec_ref, 3);
            if (g.hasVar(bindIsBv)) c.add(.bv_ref, 2);
            c.add(.char_int, 1);
            c.add(.str_len, 1);
            c.add(.list_len, 2);
            c.add(.car_op, 2);
            if (g.hasVar(bindIsListIntsExactNonEmpty)) c.add(.list_ref_op, 2);
            c.add(.force_delay, 1);
            c.add(.cwv, 1);
            c.add(.let_values, 1);
            c.add(.num_roundtrip, 1);
            c.add(.from_real, 1);
            if (g.hasVar(bindIsPlainProc)) c.add(.apply_op, 2);
            c.add(.fold_op, 2);
        }
        const d = depth -| 1;
        switch (c.pick(g.ch)) {
            .lit => try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 200)) - 100}),
            .ref => try g.emit(g.pickVar(bindIsInt).?.name),
            .arith => {
                const op = arith_ops[g.ch.index(.op_pick, arith_ops.len)];
                const nargs = g.ch.range(.nargs, 2, 3);
                try g.emitf("({s}", .{op});
                for (0..nargs) |_| {
                    try g.emit(" ");
                    try g.genInt(d);
                }
                try g.emit(")");
            },
            .abs_op => {
                try g.emit("(abs ");
                try g.genInt(d);
                try g.emit(")");
            },
            .divmod => {
                const op = div_ops[g.ch.index(.op_pick, div_ops.len)];
                var divisor: i32 = @intCast(g.ch.range(.lit_pick, 1, 12));
                if (g.ch.chance(.coin, 1, 4)) divisor = -divisor;
                try g.emitf("({s} ", .{op});
                try g.genInt(d);
                try g.emitf(" {d})", .{divisor});
            },
            .if_form => {
                try g.emit("(if ");
                try g.genTest(d);
                try g.emit(" ");
                try g.genInt(d);
                try g.emit(" ");
                try g.genInt(d);
                try g.emit(")");
            },
            .cond_form => {
                try g.emit("(cond ");
                if (g.ch.chance(.coin, 1, 4)) {
                    // (cond (EXPR => (lambda (x) ...)) ...): ints are truthy,
                    // so the arrow receives the test value.
                    var nb: [4][]const u8 = undefined;
                    const names = g.pickNames(1, &nb);
                    try g.emit("(");
                    try g.genInt(d);
                    try g.emitf(" => (lambda ({s}) ", .{names[0]});
                    const mark = g.scope.items.len;
                    try g.pushBinding(names[0], .int);
                    try g.genInt(d);
                    g.scope.shrinkRetainingCapacity(mark);
                    try g.emit(")) ");
                } else {
                    const nclauses = g.ch.range(.count, 1, 2);
                    for (0..nclauses) |_| {
                        try g.emit("(");
                        try g.genTest(d);
                        try g.emit(" ");
                        try g.genInt(d);
                        try g.emit(") ");
                    }
                }
                try g.emit("(else ");
                try g.genInt(d);
                try g.emit("))");
            },
            .case_form => {
                try g.emit("(case ");
                try g.genInt(d);
                const nclauses = g.ch.range(.count, 1, 2);
                for (0..nclauses) |_| {
                    try g.emit(" ((");
                    const ndata = g.ch.range(.count, 1, 3);
                    for (0..ndata) |j| {
                        if (j > 0) try g.emit(" ");
                        try g.emitf("{d}", .{@as(i64, g.ch.range(.lit_pick, 0, 40)) - 20});
                    }
                    try g.emit(") ");
                    try g.genInt(d);
                    try g.emit(")");
                }
                try g.emit(" (else ");
                try g.genInt(d);
                try g.emit("))");
            },
            .and_or => {
                // With all-integer arguments (never #f), both forms yield an
                // integer while still exercising boolean simplification.
                try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and" else "(or");
                const nargs = g.ch.range(.nargs, 2, 3);
                for (0..nargs) |_| {
                    try g.emit(" ");
                    try g.genInt(d);
                }
                try g.emit(")");
            },
            .let_form => try g.genLetInt(d),
            .letrec_lambdas => try g.genLetrecLambdas(d),
            .inline_call => {
                const arity = g.ch.range(.arity, 0, 2);
                var nb: [4][]const u8 = undefined;
                const params = g.pickNames(arity, &nb);
                try g.emit("((lambda (");
                const mark = g.scope.items.len;
                for (params, 0..) |p, i| {
                    if (i > 0) try g.emit(" ");
                    try g.emit(p);
                    try g.pushBinding(p, .int);
                }
                try g.emit(") ");
                try g.genInt(d);
                try g.emit(")");
                g.scope.shrinkRetainingCapacity(mark);
                for (0..arity) |_| {
                    try g.emit(" ");
                    try g.genInt(d);
                }
                try g.emit(")");
            },
            .call_proc => {
                const b = g.pickVar(bindIsProc).?;
                const info = b.kind.proc;
                var nargs: u32 = info.arity;
                if (info.variadic) nargs += g.ch.range(.nargs, 0, 2);
                try g.emitf("({s}", .{b.name});
                for (0..nargs) |i| {
                    try g.emit(" ");
                    if (i == 0 and info.bounded_first)
                        try g.emitf("{d}", .{g.ch.range(.iters, 0, 12)})
                    else
                        try g.genInt(d);
                }
                try g.emit(")");
            },
            .call_macro => {
                const m = g.macros.items[g.ch.index(.op_pick, g.macros.items.len)];
                const nargs: u32 = if (m.variadic) g.ch.range(.nargs, 0, 3) else m.arity;
                try g.emitf("({s}", .{m.name});
                for (0..nargs) |_| {
                    try g.emit(" ");
                    try g.genInt(d);
                }
                try g.emit(")");
            },
            .named_let => {
                const iters = g.loopIters();
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(2, &nb);
                try g.emitf("(let lp (({s} {d}) ({s} ", .{ names[0], iters, names[1] });
                try g.genInt(d); // accumulator init: outer scope
                const mark = g.scope.items.len;
                try g.pushBinding(names[0], .int);
                try g.pushBinding(names[1], .int);
                g.loop_nest += 1;
                try g.emitf(")) (if (<= {s} 0) {s} (lp (- {s} 1) (modulo ", .{ names[0], names[1], names[0] });
                try g.genInt(d);
                try g.emitf(" {d}))))", .{acc_modulus});
                g.loop_nest -= 1;
                g.scope.shrinkRetainingCapacity(mark);
            },
            .do_loop => {
                const iters = g.loopIters();
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(2, &nb);
                try g.emitf("(do (({s} 0 (+ {s} 1)) ({s} ", .{ names[0], names[0], names[1] });
                try g.genInt(d); // accumulator init: outer scope
                const mark = g.scope.items.len;
                try g.pushBinding(names[0], .int);
                try g.pushBinding(names[1], .int);
                g.loop_nest += 1;
                try g.emit(" (modulo ");
                try g.genInt(d);
                try g.emitf(" {d}))) ((>= {s} {d}) {s})", .{ acc_modulus, names[0], iters, names[1] });
                if (g.ch.chance(.coin, 1, 2)) {
                    try g.emit(" ");
                    try g.genStmt(d);
                }
                try g.emit(")");
                g.loop_nest -= 1;
                g.scope.shrinkRetainingCapacity(mark);
            },
            .letrec_rec => {
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(2, &nb); // recursive proc, counter
                const op = rec_ops[g.ch.index(.op_pick, rec_ops.len)];
                try g.emitf("(letrec (({s} (lambda ({s}) (if (<= {s} 0) ", .{ names[0], names[1], names[1] });
                const mark = g.scope.items.len;
                // The proc name shadows any outer binding throughout the
                // letrec; reserve it so the body can't pick the outer one.
                try g.pushBinding(names[0], .reserved);
                try g.pushBinding(names[1], .int);
                try g.genInt(d);
                try g.emitf(" ({s} ", .{op});
                try g.genInt(d);
                try g.emitf(" ({s} (- {s} 1))))))) ({s} {d}))", .{ names[0], names[1], names[0], g.ch.range(.iters, 0, 12) });
                g.scope.shrinkRetainingCapacity(mark);
            },
            .callcc => {
                const nm = if (g.ch.chance(.coin, 1, 6)) "call-with-current-continuation" else "call/cc";
                try g.emitf("({s} (lambda (k) ", .{nm});
                const mark = g.scope.items.len;
                try g.pushBinding("k", .{ .proc = .{ .arity = 1 } });
                if (g.ch.chance(.coin, 1, 2)) {
                    // guaranteed conditional escape
                    try g.emit("(if ");
                    try g.genTest(d);
                    try g.emit(" (k ");
                    try g.genInt(d);
                    try g.emit(") ");
                    try g.genInt(d);
                    try g.emit(")");
                } else {
                    try g.genInt(d);
                }
                try g.emit("))");
                g.scope.shrinkRetainingCapacity(mark);
            },
            .dynwind => {
                try g.emit("(dynamic-wind (lambda () ");
                try g.genThunkBody(d);
                try g.emit(") (lambda () ");
                try g.genInt(d);
                try g.emit(") (lambda () ");
                try g.genThunkBody(d);
                try g.emit("))");
            },
            .guard_form => {
                try g.emit("(guard (ex");
                const nclauses = g.ch.range(.count, 0, 2);
                for (0..nclauses) |_| {
                    const pred = guard_preds[g.ch.index(.op_pick, guard_preds.len)];
                    try g.emitf(" (({s} ex) ", .{pred});
                    try g.genInt(d);
                    try g.emit(")");
                }
                if (nclauses == 0 or g.ch.chance(.coin, 7, 8)) {
                    try g.emit(" (else ");
                    try g.genInt(d);
                    try g.emit(")");
                }
                try g.emit(") ");
                g.guard_depth += 1;
                if (g.ch.chance(.coin, 1, 3)) {
                    // guaranteed conditional raise
                    try g.emit("(if ");
                    try g.genTest(d);
                    try g.emit(" ");
                    try g.genRaise(d);
                    try g.emit(" ");
                    try g.genInt(d);
                    try g.emit(")");
                } else {
                    try g.genInt(d);
                }
                g.guard_depth -= 1;
                try g.emit(")");
            },
            .raise_form => try g.genRaise(d),
            .begin_form => {
                try g.emit("(begin ");
                const n = g.ch.range(.count, 1, 2);
                for (0..n) |_| {
                    try g.genStmt(d);
                    try g.emit(" ");
                }
                try g.genInt(d);
                try g.emit(")");
            },
            .vec_ref => {
                const b = g.pickVar(bindIsVec).?;
                const v = b.kind.vector;
                // Boxed slots hold non-empty int lists, so car is safe.
                try g.emit(if (v.boxed) "(car (vector-ref " else "(vector-ref ");
                try g.emit(b.name);
                try g.emit(" ");
                try g.genIndex(d, v.len);
                try g.emit(if (v.boxed) "))" else ")");
            },
            .bv_ref => {
                const b = g.pickVar(bindIsBv).?;
                try g.emitf("(bytevector-u8-ref {s} ", .{b.name});
                try g.genIndex(d, b.kind.bytevector);
                try g.emit(")");
            },
            .char_int => {
                try g.emit("(char->integer ");
                try g.genChar(d);
                try g.emit(")");
            },
            .str_len => {
                try g.emit("(string-length ");
                _ = try g.genString(d);
                try g.emit(")");
            },
            .list_len => {
                try g.emit("(length ");
                _ = try g.genList(d, .{});
                try g.emit(")");
            },
            .car_op => {
                try g.emit("(car ");
                _ = try g.genList(d, .{ .ints = true, .non_empty = true });
                try g.emit(")");
            },
            .list_ref_op => {
                const b = g.pickVar(bindIsListIntsExactNonEmpty).?;
                const len = b.kind.list.len.exactLen().?;
                try g.emitf("(list-ref {s} {d})", .{ b.name, g.ch.range(.idx_pick, 0, len - 1) });
            },
            .force_delay => {
                try g.emit("(force (delay ");
                try g.genInt(d);
                try g.emit("))");
            },
            .cwv => {
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(2, &nb);
                try g.emit("(call-with-values (lambda () (values ");
                try g.genInt(d);
                try g.emit(" ");
                try g.genInt(d);
                try g.emitf(")) (lambda ({s} {s}) ", .{ names[0], names[1] });
                const mark = g.scope.items.len;
                try g.pushBinding(names[0], .int);
                try g.pushBinding(names[1], .int);
                try g.genInt(d);
                try g.emit("))");
                g.scope.shrinkRetainingCapacity(mark);
            },
            .let_values => {
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(2, &nb);
                try g.emitf("(let-values ((({s} {s}) (values ", .{ names[0], names[1] });
                try g.genInt(d);
                try g.emit(" ");
                try g.genInt(d);
                try g.emit("))) ");
                const mark = g.scope.items.len;
                try g.pushBinding(names[0], .int);
                try g.pushBinding(names[1], .int);
                try g.genInt(d);
                try g.emit(")");
                g.scope.shrinkRetainingCapacity(mark);
            },
            .num_roundtrip => {
                try g.emit("(string->number (number->string ");
                try g.genInt(d);
                try g.emit("))");
            },
            .from_real => {
                const op = real_round_ops[g.ch.index(.op_pick, real_round_ops.len)];
                try g.emitf("(exact ({s} ", .{op});
                try g.genReal(2);
                try g.emit("))");
            },
            .apply_op => {
                const b = g.pickVar(bindIsPlainProc).?;
                try g.emitf("(apply {s} (list", .{b.name});
                for (0..b.kind.proc.arity) |_| {
                    try g.emit(" ");
                    try g.genInt(d);
                }
                try g.emit("))");
            },
            .fold_op => {
                try g.emit("(fold ");
                if (g.hasVar(bindIsPlainProc2) and g.ch.chance(.coin, 1, 2)) {
                    try g.emit(g.pickVar(bindIsPlainProc2).?.name);
                } else if (g.ch.chance(.coin, 1, 3)) {
                    try g.genLambdaInt(2, false, d);
                } else {
                    try g.emit(fold_ops[g.ch.index(.op_pick, fold_ops.len)]);
                }
                try g.emit(" ");
                try g.genInt(d);
                try g.emit(" ");
                _ = try g.genList(d, .{ .ints = true });
                try g.emit(")");
            },
        }
    }

    /// Vector/bytevector index that is in range by construction: either a
    /// literal below `len` or `(modulo <int> len)`.
    pub fn genIndex(g: *Gen, d: u32, len: u16) Error!void {
        if (g.ch.chance(.idx_kind, 2, 3)) {
            try g.emitf("{d}", .{g.ch.range(.idx_pick, 0, len - 1)});
        } else {
            try g.emit("(modulo ");
            try g.genInt(@min(d, 1));
            try g.emitf(" {d})", .{len});
        }
    }

    fn genRaise(g: *Gen, d: u32) Error!void {
        switch (g.ch.range(.shape, 0, 2)) {
            0 => try g.emitf("(raise {d})", .{@as(i64, g.ch.range(.lit_pick, 0, 200)) - 100}),
            1 => try g.emitf("(raise '{s})", .{symbol_names[g.ch.index(.lit_pick, symbol_names.len)]}),
            else => {
                try g.emit("(error \"fuzz\" ");
                try g.genInt(@min(d, 1));
                try g.emit(")");
            },
        }
    }

    fn genThunkBody(g: *Gen, d: u32) Error!void {
        if (g.ch.chance(.coin, 1, 2)) try g.genStmt(d) else try g.emit("0");
    }

    fn genLetInt(g: *Gen, d: u32) Error!void {
        const star = g.ch.chance(.coin, 1, 2);
        const n = g.ch.range(.count, 1, 3);
        var nb: [4][]const u8 = undefined;
        const names = g.pickNames(n, &nb);
        try g.emit(if (star) "(let* (" else "(let (");
        const mark = g.scope.items.len;
        var stash: [3]Kind = undefined;
        for (0..n) |i| {
            try g.emitf("({s} ", .{names[i]});
            const kind = try g.genValueOfKind(g.pickBindKind(), d);
            try g.emit(") ");
            // let: inits are evaluated in the outer scope, so bindings only
            // become visible after all of them; let*: immediately.
            if (star) try g.pushBinding(names[i], kind) else stash[i] = kind;
        }
        if (!star) for (0..n) |i| try g.pushBinding(names[i], stash[i]);
        try g.emit(") ");
        if (g.ch.chance(.coin, 1, 3)) {
            try g.genStmt(d);
            try g.emit(" ");
        }
        try g.genInt(d);
        try g.emit(")");
        g.scope.shrinkRetainingCapacity(mark);
    }

    fn genLetrecLambdas(g: *Gen, d: u32) Error!void {
        // General letrec with lambda initializers. Bodies see only the outer
        // scope: sibling references would enable unbounded mutual recursion;
        // bounded recursion is exercised by the letrec_rec skeleton instead.
        const n = g.ch.range(.count, 1, 2);
        var nb: [4][]const u8 = undefined;
        const names = g.pickNames(n, &nb);
        try g.emit("(letrec (");
        const mark = g.scope.items.len;
        // letrec scope covers the initializers too: reserve the binder
        // names so lambda bodies can neither pick shadowed outer bindings
        // nor call a sibling (unbounded mutual recursion).
        for (0..n) |i| try g.pushBinding(names[i], .reserved);
        var stash: [2]Kind = undefined;
        for (0..n) |i| {
            const arity: u8 = @intCast(g.ch.range(.arity, 0, 2));
            try g.emitf("({s} ", .{names[i]});
            try g.genLambdaInt(arity, false, d);
            try g.emit(") ");
            stash[i] = .{ .proc = .{ .arity = arity } };
        }
        for (0..n) |i| g.scope.items[mark + i].kind = stash[i];
        try g.emit(") ");
        try g.genInt(d);
        try g.emit(")");
        g.scope.shrinkRetainingCapacity(mark);
    }

    /// (lambda (p...) <int body>), optionally variadic: (lambda (p... . rest) ...)
    /// or (lambda rest ...) when arity is 0.
    fn genLambdaInt(g: *Gen, arity: u8, variadic: bool, d: u32) Error!void {
        var nb: [4][]const u8 = undefined;
        const params = g.pickNames(arity, &nb);
        const mark = g.scope.items.len;
        if (variadic and arity == 0) {
            try g.emit("(lambda rest ");
            try g.pushBinding("rest", .{ .list = .{ .len = .unknown, .mut = .all, .ints = true } });
        } else {
            try g.emit("(lambda (");
            for (params, 0..) |p, i| {
                if (i > 0) try g.emit(" ");
                try g.emit(p);
                try g.pushBinding(p, .int);
            }
            if (variadic) {
                try g.emit(" . rest");
                try g.pushBinding("rest", .{ .list = .{ .len = .unknown, .mut = .all, .ints = true } });
            }
            try g.emit(") ");
        }
        if (g.ch.chance(.coin, 1, 4)) {
            try g.genStmt(d);
            try g.emit(" ");
        }
        try g.genInt(d);
        try g.emit(")");
        g.scope.shrinkRetainingCapacity(mark);
    }

    // -- booleans and tests --

    const BoolOp = enum {
        lit,
        ref,
        not_op,
        andor,
        cmp,
        zero_p,
        evenodd,
        null_p,
        pair_p,
        eq_sym,
        eqv_int,
        equal_list,
        string_eq,
        char_cmp,
        pred_any,
    };

    pub fn genBool(g: *Gen, depth_in: u32) Error!void {
        const depth = g.cap(depth_in);
        var c: Cands(BoolOp) = .{};
        c.add(.lit, 3);
        if (g.hasVar(bindIsBool)) c.add(.ref, 4);
        if (depth > 0) {
            c.add(.not_op, 2);
            c.add(.andor, 3);
            c.add(.cmp, 6);
            c.add(.zero_p, 2);
            c.add(.evenodd, 2);
            c.add(.null_p, 2);
            c.add(.pair_p, 1);
            c.add(.eq_sym, 1);
            c.add(.eqv_int, 2);
            c.add(.equal_list, 2);
            c.add(.string_eq, 1);
            c.add(.char_cmp, 1);
            c.add(.pred_any, 2);
        }
        const d = depth -| 1;
        switch (c.pick(g.ch)) {
            .lit => try g.emit(if (g.ch.chance(.coin, 1, 2)) "#t" else "#f"),
            .ref => try g.emit(g.pickVar(bindIsBool).?.name),
            .not_op => {
                try g.emit("(not ");
                try g.genTest(d);
                try g.emit(")");
            },
            .andor => {
                try g.emit(if (g.ch.chance(.coin, 1, 2)) "(and " else "(or ");
                try g.genBool(d);
                try g.emit(" ");
                try g.genBool(d);
                try g.emit(")");
            },
            .cmp => {
                const op = cmp_ops[g.ch.index(.op_pick, cmp_ops.len)];
                const real = g.ch.chance(.coin, 1, 4);
                try g.emitf("({s} ", .{op});
                if (real) try g.genReal(d) else try g.genInt(d);
                try g.emit(" ");
                if (real) try g.genReal(d) else try g.genInt(d);
                try g.emit(")");
            },
            .zero_p => {
                try g.emit("(zero? ");
                try g.genInt(d);
                try g.emit(")");
            },
            .evenodd => {
                try g.emit(if (g.ch.chance(.coin, 1, 2)) "(even? " else "(odd? ");
                try g.genInt(d);
                try g.emit(")");
            },
            .null_p => {
                try g.emit("(null? ");
                _ = try g.genList(d, .{});
                try g.emit(")");
            },
            .pair_p => {
                try g.emit("(pair? ");
                _ = try g.genList(d, .{});
                try g.emit(")");
            },
            .eq_sym => {
                try g.emitf("(eq? '{s} '{s})", .{
                    symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
                    symbol_names[g.ch.index(.lit_pick, symbol_names.len)],
                });
            },
            .eqv_int => {
                try g.emit("(eqv? ");
                try g.genInt(d);
                try g.emit(" ");
                try g.genInt(d);
                try g.emit(")");
            },
            .equal_list => {
                try g.emit("(equal? ");
                _ = try g.genList(d, .{});
                try g.emit(" ");
                _ = try g.genList(d, .{});
                try g.emit(")");
            },
            .string_eq => {
                try g.emit(if (g.ch.chance(.coin, 1, 2)) "(string=? " else "(string<? ");
                _ = try g.genString(d);
                try g.emit(" ");
                _ = try g.genString(d);
                try g.emit(")");
            },
            .char_cmp => {
                try g.emit(if (g.ch.chance(.coin, 1, 2)) "(char=? " else "(char<? ");
                try g.genChar(d);
                try g.emit(" ");
                try g.genChar(d);
                try g.emit(")");
            },
            .pred_any => {
                try g.emitf("({s} ", .{any_preds[g.ch.index(.op_pick, any_preds.len)]});
                try g.genAny(d);
                try g.emit(")");
            },
        }
    }

    /// Test position: anything goes — only #f is false, so always-truthy
    /// tests are deliberate dead-branch fodder for the optimizer.
    pub fn genTest(g: *Gen, d: u32) Error!void {
        if (g.ch.chance(.coin, 3, 5)) return g.genBool(d);
        try g.genAny(d);
    }

    fn genAny(g: *Gen, d: u32) Error!void {
        const AnyKind = enum { int, boolean, char, sym, string, list, vector, id_lambda };
        var c: Cands(AnyKind) = .{};
        c.add(.int, 4);
        c.add(.boolean, 2);
        c.add(.char, 1);
        c.add(.sym, 1);
        if (d > 0) {
            c.add(.string, 1);
            c.add(.list, 1);
            c.add(.vector, 1);
            c.add(.id_lambda, 1);
        }
        switch (c.pick(g.ch)) {
            .int => try g.genInt(d),
            .boolean => try g.genBool(d),
            .char => try g.genChar(d),
            .sym => try g.emitf("'{s}", .{symbol_names[g.ch.index(.lit_pick, symbol_names.len)]}),
            .string => _ = try g.genString(d),
            .list => _ = try g.genList(d, .{}),
            .vector => _ = try g.genVector(d, false),
            .id_lambda => {
                var nb: [4][]const u8 = undefined;
                const names = g.pickNames(1, &nb);
                try g.emitf("(lambda ({s}) {s})", .{ names[0], names[0] });
            },
        }
    }

    /// Integer write target: inside loops, clamp so repeated self-referencing
    /// writes (e.g. squaring an accumulator every iteration) stay bounded.
    pub fn genClampedInt(g: *Gen, d: u32) Error!void {
        if (g.loop_nest > 0) {
            try g.emit("(modulo ");
            try g.genInt(d);
            try g.emitf(" {d})", .{acc_modulus});
        } else {
            try g.genInt(d);
        }
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
