const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const timings = @import("timings.zig");
const Value = types.Value;
const GC = memory.GC;

// Expansion is reachable from child-thread compile paths (SRFI 18 threads
// compile with their own VM); per-expansion context must be threadlocal so
// concurrent compilers cannot clobber each other's state.
threadlocal var active_custom_ellipsis: ?[]const u8 = null;
threadlocal var active_literals: []const Value = &.{};

fn isEllipsis(name: []const u8) bool {
    // If the name is listed as a literal, it's not the ellipsis
    for (active_literals) |lit| {
        if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) return false;
    }
    if (active_custom_ellipsis) |ce| {
        return std.mem.eql(u8, name, ce);
    }
    return std.mem.eql(u8, name, "...");
}

// ---------------------------------------------------------------------------
// Hygienic renaming support (sets-of-scopes, simplified)
// ---------------------------------------------------------------------------
//
// Template-introduced identifiers that are NOT pattern variables, NOT
// literals, and NOT well-known special forms / built-in procedures get
// consistently renamed to gensyms within a single macro invocation.
// This prevents the classic hygiene bugs where a macro's internal
// binding (e.g. `temp` in `or`) captures a user variable of the same name.

/// Identifiers that must NEVER be renamed. Special forms that CAN be
/// rebound as variables (if, let, begin, etc.) are NOT in this list --
/// they get hygiene-renamed, and the compiler recognizes them via the
/// `if` and `let` are omitted — the R7RS test rebinds them as
/// variables. The compiler recognizes hygienic renames via
/// effective_name stripping.
const well_known_forms = [_][]const u8{
    "begin",         "define",        "set!",             "lambda",
    "let*",          "letrec",        "letrec*",          "quote",
    "quasiquote",    "unquote",       "unquote-splicing", "define-syntax",
    "let-syntax",    "letrec-syntax", "syntax-rules",     "define-record-type",
    "define-values", "let-values",    "let*-values",      "case-lambda",
    "cond-expand",   "cond",          "case",             "and",
    "or",            "when",          "unless",           "do",
    "guard",         "delay",         "delay-force",      "parameterize",
    "syntax-error",  "include",       "include-ci",       "define-library",
    "import",        "export",        "else",             "=>",
    "...",           "_",
};

pub fn isWellKnown(name: []const u8) bool {
    for (&well_known_forms) |wk| {
        if (std.mem.eql(u8, wk, name)) return true;
    }
    return false;
}

/// Monotonically increasing counter for generating unique hygienic names.
/// Shared across threads (renames must be process-unique), so bumped
/// atomically; see freshGensymId.
var gensym_counter: u32 = 0;

/// Scope identifier for macro invocations (each invocation gets a fresh one).
/// Atomic for the same reason as gensym_counter.
var next_scope_id: u32 = 0;

fn freshScope() u32 {
    return @atomicRmw(u32, &next_scope_id, .Add, 1, .monotonic) + 1;
}

fn freshGensymId() u32 {
    return @atomicRmw(u32, &gensym_counter, .Add, 1, .monotonic) + 1;
}

/// Tracks renamings within a single macro invocation so that the same
/// template identifier maps to the same gensym consistently.
const ScopeEntry = struct {
    original_name: []const u8,
    scope: u32,
    renamed_to: []const u8,
};

const MAX_SCOPE_ENTRIES = 256;
// The scope table is a per-expansion dedup cache, saved/restored around each
// expansion — cross-thread sharing of it could interleave restorations and
// split a binding's rename from its references, so it is threadlocal (like
// the active_* expansion context above).
threadlocal var scope_table: [MAX_SCOPE_ENTRIES]ScopeEntry = undefined;
threadlocal var scope_table_count: usize = 0;

// ---------------------------------------------------------------------------
// Pattern variable binding
// ---------------------------------------------------------------------------

const MAX_BINDINGS = 128;
const MAX_ELLIPSIS_VALUES = 1024;

fn vectorToList(gc: *GC, data: []const Value) !Value {
    var result: Value = types.NIL;
    var i = data.len;
    while (i > 0) {
        i -= 1;
        result = try gc.allocPair(data[i], result);
    }
    return result;
}

fn listToVector(gc: *GC, list: Value) !Value {
    var len: usize = 0;
    var cur = list;
    while (cur != types.NIL and types.isPair(cur)) {
        len += 1;
        cur = types.cdr(cur);
    }
    const data = try gc.allocator.alloc(Value, len);
    defer gc.allocator.free(data);
    cur = list;
    for (0..len) |idx| {
        data[idx] = types.car(cur);
        cur = types.cdr(cur);
    }
    return gc.allocVector(data);
}

const Binding = struct {
    name: []const u8,
    value: Value,
    ellipsis_values: [MAX_ELLIPSIS_VALUES]Value = undefined,
    ellipsis_count: usize = 0,
    depth: u8,
    is_list: bool,
};

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

pub const LITERAL_UNBOUND: u32 = 0xFFFFFFFF;
pub const LITERAL_BOUND_PENDING: u32 = 0xFFFFFFFE;

pub const UseSiteBindingCheck = struct {
    ctx: ?*const anyopaque = null,
    resolve_fn: ?*const fn (?*const anyopaque, []const u8) u32 = null,
    frame_resolve_fn: ?*const fn (?*const anyopaque, []const u8) bool = null,

    pub fn resolve(self: UseSiteBindingCheck, name: []const u8) u32 {
        if (self.resolve_fn) |f| return f(self.ctx, name);
        return LITERAL_UNBOUND;
    }

    pub fn resolvesInFrame(self: UseSiteBindingCheck, name: []const u8) bool {
        if (self.frame_resolve_fn) |f| return f(self.ctx, name);
        return false;
    }
};

// Per-expansion context for renameForHygiene (set/restored by expandMacro,
// mirroring active_literals): the transformer's definition-site local
// references and the compiler callback that says whether a name is a local
// of the current function frame.
threadlocal var active_def_local_refs: []const []const u8 = &.{};
threadlocal var active_use_check: UseSiteBindingCheck = .{};

// Per-expansion context for renameForHygiene (#1812): the transformer's own
// definition environment (a library's lib_env) and its canonical name, so a
// free reference bound there can be marked to resolve through that specific
// library's environment at runtime instead of the use site's mutable
// globals table. Both null for a top-level/REPL-defined transformer.
threadlocal var active_def_env: ?*std.StringHashMap(Value) = null;
threadlocal var active_def_lib_name: ?[]const u8 = null;

pub fn expandMacro(gc: *GC, expr: Value, transformer_val: Value, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value), use_check: UseSiteBindingCheck) !Value {
    // The rule-matching bindings buffer is ~1MB and only entries below
    // bind_count are ever read, so it must not be filled per call: Zig 0.16
    // ReleaseSafe 0xAA-fills every plain `= undefined` local, and this fill
    // (here and in matchEllipsis/instantiateEllipsis) was ~96% of an
    // 80-second SRFI 148 library compile (kaappi#1802). The only shape that
    // suppresses the fill is declaring the buffer under a safety-off
    // *function* scope; the entire body then runs in the safety-on block
    // below, so index/overflow checks are unaffected. (The previous
    // `b: { @setRuntimeSafety(false); break :b undefined; }` initializer
    // does NOT work: it materializes a runtime undefined value whose store
    // into the local gets the fill anyway.)
    @setRuntimeSafety(false);
    var bindings: [MAX_BINDINGS]Binding = undefined;
    {
        @setRuntimeSafety(true);
        // `--timings` (kaappi#1515): the sole macro-expansion chokepoint, so timing
        // it here covers every caller (compiler, pipeline dump, REPL). Expansion runs
        // during emission; the self-time stack keeps it disjoint from the emit stage.
        timings.begin(.expand);
        defer timings.end();
        const transformer = types.toObject(transformer_val).as(types.Transformer);
        // SRFI 211: procedural transformers bypass the pattern/template
        // engine entirely — the Scheme procedure computes the expansion.
        if (transformer.kind != .syntax_rules) {
            return expandProceduralMacro(gc, expr, transformer, globals, macros, use_check);
        }
        const saved_ellipsis = active_custom_ellipsis;
        active_custom_ellipsis = transformer.custom_ellipsis;
        defer active_custom_ellipsis = saved_ellipsis;
        const saved_literals = active_literals;
        active_literals = transformer.literals;
        defer active_literals = saved_literals;
        const saved_def_local_refs = active_def_local_refs;
        active_def_local_refs = transformer.def_site_local_refs;
        defer active_def_local_refs = saved_def_local_refs;
        const saved_def_env = active_def_env;
        active_def_env = transformer.def_env;
        defer active_def_env = saved_def_env;
        const saved_def_lib_name = active_def_lib_name;
        active_def_lib_name = transformer.def_lib_name;
        defer active_def_lib_name = saved_def_lib_name;
        const saved_use_check = active_use_check;
        active_use_check = use_check;
        defer active_use_check = saved_use_check;
        const input = types.cdr(expr); // skip the keyword

        // Extract the macro keyword name from the first pattern (car of the
        // full pattern list). This identifier must not be renamed during
        // hygiene: recursive macro calls in the template need to resolve
        // back to the same macro.
        var macro_keyword: ?[]const u8 = null;
        if (transformer.num_rules > 0) {
            // Unwrap first: a generating macro that splices a WHOLE rule pattern
            // from user text hands this transformer a marker-wrapped pattern,
            // whose car is the marker symbol rather than the keyword.
            const first_pat = unwrapUsertext(transformer.patterns[0]);
            if (types.isPair(first_pat)) {
                const kw = types.car(first_pat);
                if (types.isSymbol(kw)) {
                    macro_keyword = types.symbolName(kw);
                }
            }
        }

        // Create a fresh scope for this macro invocation. All template-
        // introduced identifiers within this expansion share this scope,
        // so they get consistent renaming (the same name maps to the same
        // gensym) while differing from user identifiers.
        const intro_scope = freshScope();

        // The scope table is only a dedup cache for renames *within* this
        // expansion: each expansion has a globally-unique scope id, so entries
        // from prior expansions are never matched again. Release them on return
        // so the fixed-size table doesn't fill up over many expansions. (Once it
        // was full, new renames went unrecorded, so repeated references to the
        // same template identifier got *different* gensyms — splitting a binding
        // from its uses, e.g. `__hyg_N_res` undefined.) Save/restore rather than
        // zeroing keeps this correct even if expansion ever becomes re-entrant.
        const saved_scope_count = scope_table_count;
        defer scope_table_count = saved_scope_count;

        const literal_bound = transformer.literal_bound;

        // Try each rule in order. The bindings buffer is hoisted to the top of
        // the function and left uninitialized (entries below bind_count are
        // always written before being read).
        for (0..transformer.num_rules) |i| {
            var bind_count: usize = 0;

            // Skip the keyword in the pattern (first element of pattern).
            // Same whole-pattern unwrap as the keyword extraction above: without
            // it this cdr strips the MARKER instead of the keyword, so every
            // pattern position lines up one slot late against the input and the
            // user's own `_` keyword placeholder swallows the first argument.
            const pattern_body = types.cdr(unwrapUsertext(transformer.patterns[i]));

            if (matchPattern(pattern_body, input, transformer.literals[0..], &bindings, &bind_count, gc, literal_bound, use_check)) {
                return instantiateTemplate(gc, transformer.templates[i], bindings[0..bind_count], intro_scope, transformer.literals, macro_keyword, globals, macros);
            }
        }

        return error.NoMatchingPattern;
    }
}

pub const ExpandError = error{
    NoMatchingPattern,
    ScopeTableFull,
    PatternTooComplex,
    EllipsisCountMismatch,
    EllipsisDepthMismatch,
    /// R7RS 4.3.2 (kaappi#1791): a template subform followed by `...` whose
    /// element contains no pattern variable bound under an ellipsis in the
    /// pattern — e.g. a typo'd bare `...` where `(... ...)` (the ellipsis
    /// escape) was meant. See instantiateEllipsis's raise site for the proof
    /// that this can never fire for the legitimate nested-syntax-rules
    /// "belongs to the inner macro" case.
    EllipsisNoPatternVariable,
    /// SRFI 211: a procedural transformer raised, returned a non-datum, or
    /// could not run (no VM registered). The VM's error state carries any
    /// Scheme-level condition the transformer raised.
    TransformerFailed,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// SRFI 211: procedural macro transformers (explicit-renaming and Lisp-style)
// ---------------------------------------------------------------------------
//
// A procedural transformer is a Scheme procedure stored on the Transformer
// (kind != .syntax_rules) and invoked at expansion time through the
// globals.zig call_proc_for_macro hook (the expander cannot import vm.zig).
// The ER `rename`/`compare` arguments are freshly allocated NativeFn values
// whose implementations read the threadlocal context below — the same
// save/restore discipline as the active_* syntax-rules context, so nested
// expansions (a transformer that itself calls `eval` on a macro use)
// restore the outer invocation's context on return.
//
// `rename` reuses renameForHygiene with a fresh per-invocation scope: the
// same name renames to the same gensym within one expansion (the ER
// bound-identifier=? guarantee), definition-environment resolution comes
// from the same globals/known-macro checks syntax-rules templates get, and
// the compiler already resolves the resulting __hyg_N_x aliases. This gives
// ER macros exactly the hygiene strength of this engine's own syntax-rules
// — no more, no less; the .sld headers document the shared limitations.

threadlocal var er_scope: u32 = 0;
threadlocal var er_globals: ?*std.StringHashMap(Value) = null;
threadlocal var er_macros: ?*const std.StringHashMap(Value) = null;

fn expandProceduralMacro(gc: *GC, expr: Value, transformer: *types.Transformer, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value), use_check: UseSiteBindingCheck) !Value {
    const gmod = @import("globals.zig");
    const call = gmod.call_proc_for_macro orelse return ExpandError.TransformerFailed;

    // SRFI 211 hands the transformer "the fully unwrapped input form":
    // strip provenance markers a generating syntax-rules macro may have
    // left, so the procedure sees plain data. In-place, matching the
    // compile boundary's own stripUsertextMarkers use.
    var input = expr;
    if (isUsertextPair(input)) input = unwrapUsertext(input);
    if (types.isPair(input) or types.isVector(input)) stripUsertextMarkers(gc, input);

    // Fresh invocation scope + context, saved/restored for re-entrancy.
    const saved_scope = er_scope;
    const saved_globals = er_globals;
    const saved_macros = er_macros;
    const saved_check = active_use_check;
    const saved_refs = active_def_local_refs;
    const saved_def_env = active_def_env;
    const saved_def_lib_name = active_def_lib_name;
    er_scope = freshScope();
    er_globals = globals;
    er_macros = macros;
    active_use_check = use_check;
    active_def_local_refs = &.{};
    active_def_env = transformer.def_env;
    active_def_lib_name = transformer.def_lib_name;
    defer {
        er_scope = saved_scope;
        er_globals = saved_globals;
        er_macros = saved_macros;
        active_use_check = saved_check;
        active_def_local_refs = saved_refs;
        active_def_env = saved_def_env;
        active_def_lib_name = saved_def_lib_name;
    }
    // The rename dedup cache entries belong to this invocation only (the
    // scope id is globally fresh); release them on return like expandMacro.
    const saved_scope_count = scope_table_count;
    defer scope_table_count = saved_scope_count;

    // Roots: pushes are strictly nested (nothing here leaves the stack
    // unbalanced before the deferred pops fire — the transformer call
    // itself balances whatever it pushes).
    var pushed: usize = 0;
    defer for (0..pushed) |_| gc.popRoot();
    var input_root = input;
    gc.pushRoot(&input_root);
    pushed += 1;

    var result: Value = undefined;
    if (transformer.kind == .er_macro) {
        var rename_root = gc.allocNativeFn("rename", &erRenameFn, .{ .exact = 1 }) catch return ExpandError.OutOfMemory;
        gc.pushRoot(&rename_root);
        pushed += 1;
        var compare_root = gc.allocNativeFn("compare", &erCompareFn, .{ .exact = 2 }) catch return ExpandError.OutOfMemory;
        gc.pushRoot(&compare_root);
        pushed += 1;
        result = call(transformer.proc, &.{ input_root, rename_root, compare_root }) catch |err| return mapProcCallError(err);
    } else {
        result = call(transformer.proc, &.{input_root}) catch |err| return mapProcCallError(err);
    }

    // SRFI 213: a transformer returning a procedure asks to be re-entered
    // with the property-lookup procedure (capture-lookup is the identity in
    // this implementation, as its spec explicitly permits). Loop bounded:
    // each hop's result may itself request another lookup capture.
    var hops: u8 = 0;
    while (types.isProcedure(result) and hops < 8) : (hops += 1) {
        var res_root = result;
        gc.pushRoot(&res_root);
        var lookup_root = gc.allocNativeFn("lookup", &propertyLookupFn, .{ .exact = 2 }) catch {
            gc.popRoot();
            return ExpandError.OutOfMemory;
        };
        gc.pushRoot(&lookup_root);
        result = call(res_root, &.{lookup_root}) catch |err| {
            gc.popRoot();
            gc.popRoot();
            return mapProcCallError(err);
        };
        gc.popRoot();
        gc.popRoot();
    }
    if (types.isProcedure(result)) return ExpandError.TransformerFailed;
    return result;
}

fn mapProcCallError(err: anyerror) ExpandError {
    return switch (err) {
        error.OutOfMemory => ExpandError.OutOfMemory,
        else => ExpandError.TransformerFailed,
    };
}

/// The `rename` procedure handed to explicit-renaming transformers.
/// Accepts any datum per SRFI 211 ("replacing the symbols at the leaves by
/// their renamings"): symbols rename, pairs/vectors rebuild with renamed
/// leaves, everything else passes through.
fn erRenameFn(args: []const Value) anyerror!Value {
    const gc = memory.gc_instance orelse return error.TypeError;
    return erRenameDatum(gc, args[0]);
}

fn erRenameDatum(gc: *GC, v: Value) anyerror!Value {
    if (types.isSymbol(v)) return erRenameSymbol(gc, types.symbolName(v));
    if (types.isPair(v)) {
        var car_new = try erRenameDatum(gc, types.car(v));
        gc.pushRoot(&car_new);
        const cdr_new = erRenameDatum(gc, types.cdr(v)) catch |err| {
            gc.popRoot();
            return err;
        };
        var cdr_root = cdr_new;
        gc.pushRoot(&cdr_root);
        const pair = gc.allocPair(car_new, cdr_root);
        gc.popRoot();
        gc.popRoot();
        return pair;
    }
    if (types.isVector(v)) {
        const vec = types.toObject(v).as(types.Vector);
        var as_list = try vectorToList(gc, vec.data);
        gc.pushRoot(&as_list);
        const renamed = erRenameDatum(gc, as_list) catch |err| {
            gc.popRoot();
            return err;
        };
        var renamed_root = renamed;
        gc.pushRoot(&renamed_root);
        const out = listToVector(gc, renamed_root);
        gc.popRoot();
        gc.popRoot();
        return out;
    }
    return v;
}

/// Mirror of instantiateTemplate's template-introduced-symbol path (minus
/// pattern variables and literals, which procedural macros don't have):
/// well-known forms and in-scope macro keywords keep their names,
/// everything else goes through renameForHygiene under this invocation's
/// scope — globals-bound names stay unrenamed (definition-environment
/// resolution), fresh names gensym consistently.
fn erRenameSymbol(gc: *GC, name: []const u8) anyerror!Value {
    if (isWellKnown(name)) return gc.allocSymbol(name);
    if (er_macros) |m| {
        if (m.contains(name)) return gc.allocSymbol(name);
    }
    return renameForHygiene(gc, name, er_scope, er_globals);
}

/// The `compare` procedure handed to explicit-renaming transformers:
/// free-identifier=? to the strength this symbol-based expander can answer
/// — equal effective (hygiene-stripped) names. Non-symbols compare #f.
fn erCompareFn(args: []const Value) anyerror!Value {
    if (!types.isSymbol(args[0]) or !types.isSymbol(args[1])) return types.FALSE;
    const a = types.stripHygienicPrefix(types.symbolName(args[0]));
    const b = types.stripHygienicPrefix(types.symbolName(args[1]));
    return if (std.mem.eql(u8, a, b)) types.TRUE else types.FALSE;
}

/// SRFI 213: the `lookup` procedure a capture-lookup re-entry receives.
/// Resolves both identifiers to their effective names and consults the
/// VM-owned property table; #f when absent, per the spec.
fn propertyLookupFn(args: []const Value) anyerror!Value {
    const gmod = @import("globals.zig");
    if (!types.isSymbol(args[0]) or !types.isSymbol(args[1])) return types.FALSE;
    const get = gmod.syntax_property_get orelse return types.FALSE;
    const id = types.stripHygienicPrefix(types.symbolName(args[0]));
    const key = types.stripHygienicPrefix(types.symbolName(args[1]));
    return get(id, key) orelse types.FALSE;
}

// ---------------------------------------------------------------------------
// Pattern matching
// ---------------------------------------------------------------------------

fn matchPattern(pattern_in: Value, input_in: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize, gc: ?*GC, literal_bound: []const u32, use_check: UseSiteBindingCheck) bool {
    // See USERTEXT_MARKER: a user identifier spliced into this macro's
    // PATTERN by a generating macro participates as the bare datum, and a
    // marked chunk arriving as INPUT (via an argument another generated
    // macro passed along) matches as the datum it wraps.
    const pattern = unwrapUsertext(pattern_in);
    const input = unwrapUsertext(input_in);
    // Symbol patterns
    if (types.isSymbol(pattern)) {
        const name = types.symbolName(pattern);

        // Check if it's a literal (including _ when in literals list)
        for (literals, 0..) |lit, lit_idx| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) {
                if (!types.isSymbol(input)) return false;
                const input_name = types.symbolName(input);
                if (!std.mem.eql(u8, input_name, name)) {
                    // A hygiene-renamed identifier on EITHER side still
                    // free-identifier=?s an UNBOUND literal of the same base
                    // name: a rename is minted precisely because the
                    // identifier had no binding. Strip both sides before
                    // giving up, so either direction matches: (a) the INPUT
                    // is renamed but the literal is bare (SRFI 257's
                    // cm-match emits template tokens `<...>`/`<_>` that its
                    // helper matchers declare as syntax-rules literals), or
                    // (b) the LITERAL itself is renamed but the input is
                    // bare -- a literal declared by a macro-generated nested
                    // syntax-rules (e.g. `let` in a generated dispatch
                    // macro) is template-introduced from its generating
                    // macro's own point of view and gets hygiene-renamed
                    // like any other such identifier, but must still match a
                    // real, unrenamed token typed at the generated macro's
                    // own, later use site (#1720). Bound literals keep
                    // strict binding comparison below.
                    const stripped_input = types.stripHygienicPrefix(input_name);
                    const stripped_name = types.stripHygienicPrefix(name);
                    if (!std.mem.eql(u8, stripped_input, stripped_name)) return false;
                    const def_slot_s = if (lit_idx < literal_bound.len) literal_bound[lit_idx] else LITERAL_UNBOUND;
                    if (def_slot_s != LITERAL_UNBOUND) return false;
                    if (use_check.resolve(input_name) != LITERAL_UNBOUND) return false;
                    return true;
                }
                // R7RS 4.3.2: match only if both refer to the same binding
                // or both are unbound.  Compare binding slots, not just
                // bound-vs-unbound, so two different bindings with the same
                // name are correctly distinguished.
                const def_slot = if (lit_idx < literal_bound.len) literal_bound[lit_idx] else LITERAL_UNBOUND;
                const use_slot = use_check.resolve(input_name);
                if (def_slot == LITERAL_UNBOUND and use_slot == LITERAL_UNBOUND) return true;
                if (def_slot == LITERAL_UNBOUND or use_slot == LITERAL_UNBOUND) return false;
                // BOUND_PENDING: body define not yet allocated — accept any bound use
                if (def_slot == LITERAL_BOUND_PENDING) return true;
                return def_slot == use_slot;
            }
        }

        // Underscore (not in literals): match anything, bind nothing
        if (std.mem.eql(u8, name, "_")) return true;

        // Pattern variable: bind to input. Fields are set individually
        // because a struct literal re-initializes the 8KB ellipsis_values
        // field (safety fill), which dominated expansion time on
        // macro-heavy code.
        if (count.* >= MAX_BINDINGS) return false;
        bindings[count.*].name = name;
        bindings[count.*].value = input;
        bindings[count.*].depth = 0;
        bindings[count.*].is_list = false;
        bindings[count.*].ellipsis_count = 0;
        count.* += 1;
        return true;
    }

    // Constants: match via equality
    if (types.isFixnum(pattern)) {
        return types.isFixnum(input) and pattern == input;
    }
    if (types.isFlonum(pattern)) {
        return types.isFlonum(input) and pattern == input;
    }
    if (types.isBool(pattern)) {
        return pattern == input;
    }
    if (types.isChar(pattern)) {
        return pattern == input;
    }
    if (types.isString(pattern) and types.isString(input)) {
        const sp = types.toObject(pattern).as(types.SchemeString);
        const si = types.toObject(input).as(types.SchemeString);
        return std.mem.eql(u8, sp.data, si.data);
    }

    // Nil matches nil
    if (pattern == types.NIL) return input == types.NIL;

    // Vector pattern: #(p1 ... pn) matches a vector input
    if (types.isVector(pattern)) {
        if (!types.isVector(input)) return false;
        const the_gc = gc orelse return false;
        const pvec = types.toObject(pattern).as(types.Vector);
        const ivec = types.toObject(input).as(types.Vector);
        const plist = vectorToList(the_gc, pvec.data) catch return false;
        const ilist = vectorToList(the_gc, ivec.data) catch return false;
        return matchListPattern(plist, ilist, literals, bindings, count, gc, literal_bound, use_check);
    }

    // List pattern
    if (types.isPair(pattern)) {
        return matchListPattern(pattern, input, literals, bindings, count, gc, literal_bound, use_check);
    }

    return false;
}

fn matchListPattern(pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize, gc: ?*GC, literal_bound: []const u32, use_check: UseSiteBindingCheck) bool {
    var pat = pattern;
    var inp = input;

    while (pat != types.NIL) {
        // Unwrap a usertext marker BEFORE inspecting this iteration's shape.
        // matchPattern's own top only unwraps its immediate pattern_in/
        // input_in parameters; a marker pair spliced into a dotted-tail
        // position by a generating macro's own template instantiation (a
        // pattern-variable value that's a LIST, substituted into `. p`) is
        // never wrapped in an extra cons cell of its own -- it becomes the
        // literal cdr of the preceding pair, e.g. `(s . (marker . (%a)))` =
        // `(s marker %a)` when walked. Without re-unwrapping here on every
        // loop iteration (not just at entry), that marker pair surfaces as
        // an ordinary-looking extra list element on a LATER iteration,
        // shifting every remaining pattern/input position by one and
        // breaking the match entirely (#1787: SRFI 148's em-syntax-rules
        // generates exactly this shape for every rule it emits,
        // `(_ :prepare s . p)`). unwrapUsertext is a no-op on anything that
        // isn't actually a marker pair, so this is safe to apply
        // unconditionally. Two more spine walks need the same unwrap --
        // expandMacro's keyword-skip and countPairs/matchEllipsis.
        pat = unwrapUsertext(pat);
        inp = unwrapUsertext(inp);
        if (!types.isPair(pat)) {
            // Dotted pattern tail
            return matchPattern(pat, inp, literals, bindings, count, gc, literal_bound, use_check);
        }

        const pat_elem = types.car(pat);
        const pat_rest = types.cdr(pat);

        // Check if next element is ellipsis. Unwrap user-text splices: an
        // `...` substituted into a generated macro's pattern still functions
        // as an ellipsis there (Taylor Campbell's ellipsis test).
        if (pat_rest != types.NIL and types.isPair(pat_rest)) {
            const maybe_ellipsis = unwrapUsertext(types.car(pat_rest));
            if (types.isSymbol(maybe_ellipsis) and isEllipsis(types.symbolName(maybe_ellipsis))) {
                // Ellipsis: pat_elem matches zero or more input elements
                const after_ellipsis = types.cdr(pat_rest);
                return matchEllipsis(pat_elem, after_ellipsis, inp, literals, bindings, count, gc, literal_bound, use_check);
            }
        }

        // Regular element: input must be a pair
        if (!types.isPair(inp)) return false;
        if (!matchPattern(pat_elem, types.car(inp), literals, bindings, count, gc, literal_bound, use_check)) return false;

        pat = pat_rest;
        inp = types.cdr(inp);
    }

    return inp == types.NIL;
}

fn countPairs(v: Value) ?usize {
    // Cycle detection (tortoise-hare) to avoid looping forever on
    // cyclic structures produced via datum labels.
    var slow = v;
    var fast = v;
    while (types.isPair(fast)) {
        fast = types.cdr(fast);
        if (!types.isPair(fast)) break;
        fast = types.cdr(fast);
        if (types.isPair(slow)) slow = types.cdr(slow);
        if (slow == fast) return null;
    }

    // Both callers (matchEllipsis, below) count a PATTERN or INPUT spine, so
    // a usertext marker sitting in that spine — a chunk a generating macro
    // spliced into a dotted-tail position — is a wrapper, not an element.
    // Counting it makes the ellipsis reserve one element too many for the
    // tail, so the split lands one position early: the trailing pattern
    // still matches (the marker symbol binds the element the ellipsis
    // should have taken), silently producing a SHORT ellipsis binding
    // rather than an error. unwrapUsertext is a no-op on anything else; a
    // forged cyclic marker chain still terminates on the MAX_ELLIPSIS_VALUES
    // bound below.
    var n: usize = 0;
    var cur = unwrapUsertext(v);
    while (types.isPair(cur)) {
        n += 1;
        if (n > MAX_ELLIPSIS_VALUES) return null;
        cur = unwrapUsertext(types.cdr(cur));
    }
    return n;
}

fn matchEllipsis(elem_pattern: Value, rest_pattern: Value, input: Value, literals: []const Value, bindings: *[MAX_BINDINGS]Binding, count: *usize, gc: ?*GC, literal_bound: []const u32, use_check: UseSiteBindingCheck) bool {
    // Scratch buffers, hoisted out of the repetition loop and left
    // uninitialized: matchPattern only writes entries below sub_count, and a
    // safety fill of the ~1MB array per repetition is what made match-style
    // macros unusably slow. Declared under a safety-off function scope so
    // ReleaseSafe's 0xAA fill of `= undefined` locals is not emitted; the
    // whole body runs in the safety-on block below (see expandMacro;
    // kaappi#1802).
    @setRuntimeSafety(false);
    var sub_bindings: [MAX_BINDINGS]Binding = undefined;
    var elem_var_names: [128][]const u8 = undefined;
    {
        @setRuntimeSafety(true);
        // Count how many elements the rest_pattern needs (handles improper lists)
        const rest_len = countPairs(rest_pattern) orelse return false;
        const input_len = countPairs(input) orelse return false;

        if (input_len < rest_len) return false;
        const repeat_count = input_len - rest_len;

        var elem_var_count: usize = 0;
        var var_overflow = false;
        collectPatternVars(elem_pattern, literals, &elem_var_names, &elem_var_count, &var_overflow);
        if (var_overflow) return false;

        // Create list bindings for each pattern variable found in the ellipsis
        // sub-pattern. Field-wise assignment: see matchPattern.
        const base_count = count.*;
        for (0..elem_var_count) |vi| {
            if (count.* >= MAX_BINDINGS) return false;
            bindings[count.*].name = elem_var_names[vi];
            bindings[count.*].value = types.NIL;
            bindings[count.*].depth = 1;
            bindings[count.*].is_list = true;
            bindings[count.*].ellipsis_count = 0;
            count.* += 1;
        }

        // Same spine unwrapping as countPairs: the repetition walk must step
        // over marker cells rather than consume one as an element.
        var inp = unwrapUsertext(input);
        for (0..repeat_count) |_| {
            var sub_count: usize = 0;
            if (!types.isPair(inp)) return false;
            if (!matchPattern(elem_pattern, types.car(inp), literals, &sub_bindings, &sub_count, gc, literal_bound, use_check))
                return false;

            // Append each sub-binding value to the corresponding list binding
            for (0..sub_count) |si| {
                for (base_count..count.*) |bi| {
                    if (std.mem.eql(u8, bindings[bi].name, sub_bindings[si].name)) {
                        if (bindings[bi].ellipsis_count >= MAX_ELLIPSIS_VALUES) return false;
                        if (sub_bindings[si].is_list) {
                            // Nested ellipsis: build list from inner values
                            if (gc) |g| {
                                var inner_list: Value = types.NIL;
                                var k = sub_bindings[si].ellipsis_count;
                                while (k > 0) {
                                    k -= 1;
                                    inner_list = g.allocPair(sub_bindings[si].ellipsis_values[k], inner_list) catch return false;
                                }
                                bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = inner_list;
                                bindings[bi].depth = sub_bindings[si].depth + 1;
                            } else {
                                bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = sub_bindings[si].value;
                            }
                        } else {
                            bindings[bi].ellipsis_values[bindings[bi].ellipsis_count] = sub_bindings[si].value;
                        }
                        bindings[bi].ellipsis_count += 1;
                        break;
                    }
                }
            }

            inp = unwrapUsertext(types.cdr(inp));
        }

        // Match remaining input against rest_pattern
        if (unwrapUsertext(rest_pattern) == types.NIL) return inp == types.NIL;
        return matchListPattern(rest_pattern, inp, literals, bindings, count, gc, literal_bound, use_check);
    }
}

fn collectPatternVars(pattern: Value, literals: []const Value, names: *[128][]const u8, count: *usize, overflowed: *bool) void {
    if (types.isSymbol(pattern)) {
        const name = types.symbolName(pattern);
        if (std.mem.eql(u8, name, "_")) return;
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name))
                return;
        }
        if (isEllipsis(name)) return;
        if (count.* >= 128) {
            overflowed.* = true;
            return;
        }
        names[count.*] = name;
        count.* += 1;
        return;
    }

    if (types.isPair(pattern)) {
        collectPatternVars(types.car(pattern), literals, names, count, overflowed);
        collectPatternVars(types.cdr(pattern), literals, names, count, overflowed);
    }
    if (types.isVector(pattern)) {
        const vec = types.toObject(pattern).as(types.Vector);
        for (vec.data) |elem| {
            collectPatternVars(elem, literals, names, count, overflowed);
        }
    }
}

// ---------------------------------------------------------------------------
// Template instantiation
// ---------------------------------------------------------------------------

// Context flags carried in the high bits of intro_scope. Scope ids come from
// a small monotonically increasing counter, so the top bits are free.
// renameForHygiene must mask off every flag that doesn't change renaming
// behavior so scope-table entries stay consistent across contexts.
const ESCAPE_FLAG: u32 = 0x80000000; // inside (... <template>) ellipsis escape
const QUOTE_FLAG: u32 = 0x40000000; // inside (quote ...): substitute, hygiene-rename (#1801)
const BINDING_FLAG: u32 = 0x20000000; // identifier is in binding position
const NESTED_SR_FLAG: u32 = 0x10000000; // inside a nested syntax-rules template
const LET_PAIR_FLAG: u32 = 0x08000000; // template is a single let-binding (var init) pair
// Re-walking a usertext-marker-protected splice (an enclosing expansion's
// pattern-var value, spliced verbatim into a nested syntax-rules template) in
// substitute-only mode. Reuses QUOTE_FLAG's "substitute, expand ellipses"
// walk shape, but MUST suppress renameForHygiene's QUOTE_FLAG rename (#1801):
// unlike a literal identifier written directly in a quote form, this
// identifier is use-site DATA from an enclosing expansion, never a
// template-introduced identifier of the CURRENT one, so it must always pass
// through unrenamed -- exactly the pre-#1801 QUOTE_FLAG behavior.
const VERBATIM_FLAG: u32 = 0x00800000;
// Quasiquote nesting depth (0-7, saturating). Symbols under `quasiquote` are
// DATA — they must not be hygiene-renamed — but a depth-matching `unquote`
// re-enters expression territory where renaming resumes. Three bits cover any
// realistic template nesting; like the flag bits above, they assume expansion
// scope ids stay below the flag region.
const QQ_DEPTH_MASK: u32 = 0x07000000;
const QQ_DEPTH_ONE: u32 = 0x01000000;

// Provenance marker for pattern-var values substituted into a NESTED
// syntax-rules template (a generated macro's spec). When that generated
// macro later expands, its "template" mixes its own skeleton text with
// spliced user text; without provenance, the user identifiers get hygiene-
// renamed as if template-introduced — under a different scope at every
// generation, severing binders from references (SRFI 257's CPS protocol,
// #1644). Substituted chunks are wrapped as (<marker> . value) and unwrapped
// verbatim by the next instantiation (or by matchPattern for pattern-side
// splices), so user text is never re-walked.
pub const USERTEXT_MARKER = "__hyg-usertext";

pub fn isUsertextPair(v: Value) bool {
    if (!types.isPair(v)) return false;
    const h = types.car(v);
    return types.isSymbol(h) and std.mem.eql(u8, types.symbolName(h), USERTEXT_MARKER);
}

pub fn unwrapUsertext(v: Value) Value {
    // Construction never stacks wrappers (both wrap sites skip values that
    // are already marked), so a legitimate chain is exactly one layer. The
    // bound defends against user data forged as marker pairs — including a
    // cyclic #0=(__hyg-usertext . #0#) — which must not hang the walk. The
    // marker name lives in the __hyg_ namespace the expander already
    // reserves (renameForHygiene never renames it), so forged data is
    // out-of-contract in the same way forged __hyg_N_x identifiers are.
    var cur = v;
    var hops: u8 = 0;
    while (isUsertextPair(cur) and hops < 64) : (hops += 1) cur = types.cdr(cur);
    return cur;
}

/// Strip user-text markers from a fully-instantiated expansion, in place,
/// so compilation sees plain forms. Subtrees headed by `syntax-rules` are
/// skipped: specs of macros the expansion DEFINES keep their markers for
/// their own later instantiation. Cyclic inputs (a macro invoked with a
/// datum-label literal like #0=(1 . #0#)) terminate: the cdr spine carries
/// a tortoise-hare check, and nested descent is depth-capped. Markers are
/// created only at pattern-var substitution boundaries in the freshly built
/// template skeleton — never inside the (possibly cyclic) user data a chunk
/// wraps — and skeleton nesting is bounded by the expansion-depth/step
/// limits, far below this cap; matching the expander's fixed-limit design
/// (MAX_MACRO_EXPANSION_DEPTH, MAX_BINDINGS, MAX_SCOPE_ENTRIES). Should a
/// marker ever survive in code position anyway, compileForm still treats
/// it as transparent.
pub fn stripUsertextMarkers(gc: *GC, expr: Value) void {
    stripUsertextWalk(gc, expr, 4096);
}

fn stripUsertextWalk(gc: *GC, expr: Value, depth: u16) void {
    if (depth == 0) return;
    if (types.isVector(expr)) {
        const vec = types.toObject(expr).as(types.Vector);
        for (vec.data, 0..) |elem, i| {
            if (isUsertextPair(elem)) {
                const unwrapped = unwrapUsertext(elem);
                if (isUsertextPair(unwrapped)) continue; // forged cycle: opaque
                gc.writeBarrier(types.toObject(expr), unwrapped);
                vec.data[i] = unwrapped;
            }
            stripUsertextWalk(gc, vec.data[i], depth - 1);
        }
        return;
    }
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "syntax-rules")) return;
    var cur = expr;
    var hare = expr;
    // Iterative cdr-walk with per-node car handling keeps recursion depth
    // bounded by tree depth, not list length.
    while (true) {
        const car_v = types.car(cur);
        if (isUsertextPair(car_v)) {
            const unwrapped = unwrapUsertext(car_v);
            // A forged cyclic marker chain unwraps to itself — leave it as
            // opaque data rather than descending into the cycle.
            if (!isUsertextPair(unwrapped)) {
                gc.writeBarrier(types.toObject(cur), unwrapped);
                types.setCar(cur, unwrapped);
                stripUsertextWalk(gc, types.car(cur), depth - 1);
            }
        } else {
            stripUsertextWalk(gc, car_v, depth - 1);
        }
        const cdr_v = types.cdr(cur);
        if (isUsertextPair(cdr_v)) {
            const unwrapped = unwrapUsertext(cdr_v);
            if (isUsertextPair(unwrapped)) return; // forged cycle: opaque data
            gc.writeBarrier(types.toObject(cur), unwrapped);
            types.setCdr(cur, unwrapped);
            // Re-examine the new cdr in place (it may be a pair to continue
            // into, or an atom that ends the walk).
            continue;
        }
        if (types.isVector(cdr_v)) {
            stripUsertextWalk(gc, cdr_v, depth - 1);
            return;
        }
        if (!types.isPair(cdr_v)) return;
        cur = cdr_v;
        // Tortoise-hare on the cdr spine (cf. countPairs): unwraps above
        // only splice marker pairs out, so advancing the hare over the
        // possibly-rewritten spine stays safe.
        if (types.isPair(hare)) hare = types.cdr(hare);
        if (types.isPair(hare)) hare = types.cdr(hare);
        if (hare == cur) return;
    }
}

/// Strip hygienic rename prefixes (`__hyg_N_`) from every symbol reachable
/// from a fully-expanded `quote`/quasiquote-literal datum, returning the
/// (possibly different) top-level value. renameForHygiene now hygiene-renames
/// a template-introduced identifier inside `(quote ...)` exactly like any
/// other, so that two separate macro expansions producing "the same" quoted
/// identifier stay distinguishable via bound-identifier=?/free-identifier=?
/// while still pure, uncompiled syntax (#1801). This function is the other
/// half of that fix: called from every site that compiles a quoted datum
/// into a literal runtime Value (plain quote, quasiquote's literal atoms),
/// it removes those renames so the actual VALUE is unaffected -- ordinary
/// macros that quote a fixed tag symbol still need `(eq? (macro) (macro))`
/// to hold once the code runs. Mirrors stripUsertextWalk's in-place mutation
/// and cycle/depth guards.
pub fn stripHygieneFromDatum(gc: *GC, expr: Value) !Value {
    if (types.isSymbol(expr)) return stripSymbolRename(gc, expr);
    if (types.isPair(expr) or types.isVector(expr)) {
        var root = expr;
        gc.pushRoot(&root);
        defer gc.popRoot();
        try stripHygieneWalk(gc, expr, 4096);
    }
    return expr;
}

/// Rename a single symbol back to its base name if it carries a hygienic
/// prefix, else return it unchanged. Factored out so stripHygieneWalk (which
/// must recurse into itself for nested pairs/vectors) doesn't call back into
/// stripHygieneFromDatum -- two functions with inferred error sets calling
/// each other is a dependency loop Zig 0.16 rejects outright.
fn stripSymbolRename(gc: *GC, sym: Value) !Value {
    const name = types.symbolName(sym);
    const stripped = types.stripHygienicPrefix(name);
    if (stripped.len == name.len) return sym;
    return gc.allocSymbol(stripped);
}

fn stripHygieneWalk(gc: *GC, expr: Value, depth: u16) !void {
    if (depth == 0) return;
    if (types.isVector(expr)) {
        const vec = types.toObject(expr).as(types.Vector);
        for (vec.data, 0..) |elem, i| {
            if (types.isSymbol(elem)) {
                const stripped = try stripSymbolRename(gc, elem);
                if (stripped != elem) {
                    gc.writeBarrier(types.toObject(expr), stripped);
                    vec.data[i] = stripped;
                }
            } else {
                try stripHygieneWalk(gc, elem, depth - 1);
            }
        }
        return;
    }
    if (!types.isPair(expr)) return;
    var cur = expr;
    var hare = expr;
    while (true) {
        const car_v = types.car(cur);
        if (types.isSymbol(car_v)) {
            const stripped = try stripSymbolRename(gc, car_v);
            if (stripped != car_v) {
                gc.writeBarrier(types.toObject(cur), stripped);
                types.setCar(cur, stripped);
            }
        } else {
            try stripHygieneWalk(gc, car_v, depth - 1);
        }
        const cdr_v = types.cdr(cur);
        if (types.isSymbol(cdr_v)) {
            const stripped = try stripSymbolRename(gc, cdr_v);
            if (stripped != cdr_v) {
                gc.writeBarrier(types.toObject(cur), stripped);
                types.setCdr(cur, stripped);
            }
            return;
        }
        if (types.isVector(cdr_v)) {
            try stripHygieneWalk(gc, cdr_v, depth - 1);
            return;
        }
        if (!types.isPair(cdr_v)) return;
        cur = cdr_v;
        // Tortoise-hare on the cdr spine, same as stripUsertextWalk: this
        // walk only rewrites symbols in place, never restructures pairs, so
        // advancing the hare over the (possibly rewritten-in-place) spine
        // stays safe.
        if (types.isPair(hare)) hare = types.cdr(hare);
        if (types.isPair(hare)) hare = types.cdr(hare);
        if (hare == cur) return;
    }
}

/// Whether an ellipsis element template references any outer list binding —
/// the condition under which instantiateEllipsis can find a repeat count.
/// Inside a nested syntax-rules template, an ellipsis whose element
/// references none belongs to the inner macro and must be preserved.
fn ellipsisReferencesOuter(elem: Value, bindings: []Binding) bool {
    for (bindings) |b| {
        if (b.is_list and templateReferencesVar(elem, b.name)) {
            if (templateReferencesVarDirectly(elem, b.name) or b.depth > 1) return true;
        }
    }
    return false;
}

fn instantiateTemplate(gc: *GC, template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);

        // 1. Pattern variable -- substitute with matched value (from use site)
        for (bindings) |b| {
            if (std.mem.eql(u8, b.name, name)) {
                // Inside a nested syntax-rules template (and outside quote),
                // mark the spliced value so the generated macro's own
                // expansion later inserts it verbatim instead of re-walking
                // it as template text (see USERTEXT_MARKER).
                if ((intro_scope & NESTED_SR_FLAG) != 0 and
                    (intro_scope & QUOTE_FLAG) == 0 and
                    (types.isSymbol(b.value) or types.isPair(b.value)))
                {
                    if (isUsertextPair(b.value)) return b.value; // already protected
                    var val_root = b.value;
                    gc.pushRoot(&val_root);
                    defer gc.popRoot();
                    const marker = try gc.allocSymbol(USERTEXT_MARKER);
                    return gc.allocPair(marker, val_root);
                }
                if (!b.is_list) return b.value;
                // Shouldn't use a list binding at depth 0 without ellipsis
                return b.value;
            }
        }

        // 2. Literal keyword -- keep as-is
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), name)) {
                return template;
            }
        }

        // 3. Well-known form or built-in -- keep as-is
        if (isWellKnown(name)) {
            return template;
        }

        // 4. Macro's own keyword (for recursive calls) -- keep as-is
        if (macro_keyword) |kw| {
            if (std.mem.eql(u8, kw, name)) {
                return template;
            }
        }

        // 4b. Known macro keyword (for mutual recursion in letrec-syntax) -- keep as-is
        if (macros) |m| {
            if (m.contains(name)) {
                return template;
            }
        }

        // 5. Template-introduced identifier -- rename for hygiene
        return renameForHygiene(gc, name, intro_scope, globals);
    }

    if (types.isVector(template)) {
        const vec = types.toObject(template).as(types.Vector);
        const as_list = vectorToList(gc, vec.data) catch return error.OutOfMemory;
        const result_list = try instantiateTemplate(gc, as_list, bindings, intro_scope, literals, macro_keyword, globals, macros);
        return listToVector(gc, result_list) catch return error.OutOfMemory;
    }

    if (!types.isPair(template)) return template;

    // A user-text splice from an enclosing expansion. The chunk is use-site
    // text, so hygiene renaming must not touch it — but it may reference
    // THIS macro's pattern variables (define-match-pattern builds the
    // generated macro's rules out of user text), so substitution and
    // ellipsis expansion still apply. That combination is exactly the
    // quote-mode walk: substitute, expand ellipses, rename nothing. The
    // wrapper is PRESERVED: the chunk may land inside yet another generated
    // syntax-rules spec (SRFI 257's accumulator rebinds) and must stay
    // protected for that next generation too. Markers are stripped once,
    // at the compile boundary (stripUsertextMarkers).
    if (isUsertextPair(template)) {
        const inner = unwrapUsertext(template);
        // A forged cyclic marker chain unwraps to itself: treat as opaque data.
        if (isUsertextPair(inner)) return inner;
        // A marker-protected chunk that is ITSELF, directly, a `(quote X)`
        // form (e.g. em-gensym's own `'g` template text, captured wholesale
        // as em-syntax-rules's own `template` pattern-var value and spliced,
        // marker-protected, into the generated macro's stored transformer)
        // is not opaque use-site data -- it's the ORIGINAL macro author's own
        // literal template text, merely routed through em-syntax-rules's
        // multi-step desugaring plumbing. Such an identifier must still get
        // a fresh hygiene rename per invocation (#1801), so this case is
        // excluded from VERBATIM_FLAG and falls through to the normal quote
        // handling below. A chunk that merely CONTAINS a quote/quasiquote
        // somewhere within a larger structure -- e.g. `(em `(let ((e ...))
        // ...))`, where the let-bound `e` must stay verbatim to match a
        // reference threaded through a completely separate expansion event
        // (SRFI 148's own CK-machine, which compiles sub-pieces at different
        // times) -- or a bare symbol (an ordinary pattern-var's actual
        // use-site value, e.g. SRFI 257's accumulator rebinds) keeps the
        // original, always-verbatim treatment: only the EXACT `(quote
        // <datum>)` shape at the very top of the protected chunk counts,
        // never one merely nested deeper inside.
        const is_direct_quote = types.isPair(inner) and
            types.isSymbol(types.car(inner)) and
            std.mem.eql(u8, types.symbolName(types.car(inner)), "quote") and
            types.isPair(types.cdr(inner)) and
            types.cdr(types.cdr(inner)) == types.NIL;
        const verbatim_bits: u32 = if (is_direct_quote) 0 else VERBATIM_FLAG;
        const new_inner = try instantiateTemplate(gc, inner, bindings, (intro_scope | QUOTE_FLAG | verbatim_bits) & ~NESTED_SR_FLAG, literals, macro_keyword, globals, macros);
        if (isUsertextPair(new_inner)) return new_inner; // already protected
        if (!types.isSymbol(new_inner) and !types.isPair(new_inner)) return new_inner;
        var inner_root = new_inner;
        gc.pushRoot(&inner_root);
        defer gc.popRoot();
        const marker = try gc.allocSymbol(USERTEXT_MARKER);
        return gc.allocPair(marker, inner_root);
    }

    const in_escape = (intro_scope & ESCAPE_FLAG) != 0;

    // Check for (quote <datum>) — substitute pattern vars but skip hygiene
    // renaming. Must be a genuine, exactly-2-element quote form (R7RS quote
    // is strictly unary): a template sub-list that merely STARTS with the
    // symbol `quote` for an unrelated reason (e.g. passing the bare symbol
    // `quote` as one argument among several to some other macro/procedure)
    // is not a quote form at all, and treating it as one silently discarded
    // every element after the second (e.g. `(op quote free-identifier=?
    // more...)` instantiated as `(op (quote free-identifier=?))`, dropping
    // `more...`).
    const tmpl_head = types.car(template);
    if (types.isSymbol(tmpl_head) and std.mem.eql(u8, types.symbolName(tmpl_head), "quote")) {
        const q_rest = types.cdr(template);
        if (q_rest != types.NIL and types.isPair(q_rest)) {
            if (types.cdr(q_rest) == types.NIL) {
                const quoted = types.car(q_rest);
                const new_quoted = try instantiateTemplate(gc, quoted, bindings, intro_scope | QUOTE_FLAG, literals, macro_keyword, globals, macros);
                var nq_root = new_quoted;
                gc.pushRoot(&nq_root);
                defer gc.popRoot();
                const tail = try gc.allocPair(nq_root, types.NIL);
                return gc.allocPair(tmpl_head, tail);
            }
            // More than 2 elements: `quote` is not forming a quote special
            // form here, just an ordinary (possibly data) value in head
            // position -- fall through to regular pair processing so the
            // rest of the list survives instead of being silently dropped.
        } else {
            return template;
        }
    }

    // Quasiquote: its symbols are data (no renaming, like quote), but a
    // depth-matching unquote/unquote-splicing switches back to expression
    // mode where renaming resumes. Track nesting in QQ_DEPTH bits. Inside a
    // plain (quote ...) context (QUOTE_FLAG set, depth 0), quasiquote and
    // unquote are ordinary data — leave them to the regular walk.
    if (types.isSymbol(tmpl_head)) {
        const hname = types.symbolName(tmpl_head);
        const qq_depth = (intro_scope & QQ_DEPTH_MASK) / QQ_DEPTH_ONE;
        const q_rest = types.cdr(template);
        const unary = q_rest != types.NIL and types.isPair(q_rest) and types.cdr(q_rest) == types.NIL;
        if (unary and std.mem.eql(u8, hname, "quasiquote")) {
            const in_plain_quote = (intro_scope & QUOTE_FLAG) != 0 and qq_depth == 0;
            if (!in_plain_quote) {
                const new_depth = if (qq_depth < 7) qq_depth + 1 else 7;
                const sub_scope = (intro_scope & ~QQ_DEPTH_MASK) | QUOTE_FLAG | (new_depth * QQ_DEPTH_ONE);
                const new_inner = try instantiateTemplate(gc, types.car(q_rest), bindings, sub_scope, literals, macro_keyword, globals, macros);
                var ni_root = new_inner;
                gc.pushRoot(&ni_root);
                defer gc.popRoot();
                const tail = try gc.allocPair(ni_root, types.NIL);
                return gc.allocPair(tmpl_head, tail);
            }
        } else if (unary and qq_depth > 0 and
            (std.mem.eql(u8, hname, "unquote") or std.mem.eql(u8, hname, "unquote-splicing")))
        {
            const new_depth = qq_depth - 1;
            var sub_scope = (intro_scope & ~QQ_DEPTH_MASK) | (new_depth * QQ_DEPTH_ONE);
            if (new_depth == 0) sub_scope &= ~QUOTE_FLAG;
            const new_inner = try instantiateTemplate(gc, types.car(q_rest), bindings, sub_scope, literals, macro_keyword, globals, macros);
            var ni_root = new_inner;
            gc.pushRoot(&ni_root);
            defer gc.popRoot();
            const tail = try gc.allocPair(ni_root, types.NIL);
            return gc.allocPair(tmpl_head, tail);
        }
    }

    // Check for ellipsis escape: (... <template>) — treat ... as literal inside
    //
    // Both ellipsis checks below unwrap a usertext marker first: a nested
    // syntax-rules template's ordinary (non-quoted) position can receive a
    // custom ellipsis identifier substituted from an OUTER pattern variable
    // (SRFI 147/148's generating-macro pattern), which NESTED_SR_FLAG's
    // marking protocol wraps so the generating macro's own later expansion
    // doesn't re-walk it as template text. Only a quoted position skips the
    // wrap (QUOTE_FLAG suppresses it, see the pattern-variable substitution
    // case above) -- an ordinary template position needs the unwrap to even
    // recognize the ellipsis at all; without it, `(x my-ellipsis)` never
    // matches "element followed by ellipsis" and my-ellipsis is emitted
    // literally (as an unresolvable wrapped pair) instead of splicing x's
    // repetitions.
    const elem = types.car(template);
    const rest = types.cdr(template);
    const elem_unwrapped = unwrapUsertext(elem);
    if (!in_escape and types.isSymbol(elem_unwrapped) and isEllipsis(types.symbolName(elem_unwrapped))) {
        if (rest != types.NIL and types.isPair(rest) and types.cdr(rest) == types.NIL) {
            const inner = types.car(rest);
            return instantiateTemplate(gc, inner, bindings, intro_scope | ESCAPE_FLAG, literals, macro_keyword, globals, macros);
        }
        return template;
    }

    // Check for ellipsis in template: (Te ...) — skip inside escape context
    if (!in_escape and rest != types.NIL and types.isPair(rest)) {
        const maybe_ellipsis = unwrapUsertext(types.car(rest));
        if (types.isSymbol(maybe_ellipsis) and isEllipsis(types.symbolName(maybe_ellipsis))) {
            // Inside a nested syntax-rules template, an ellipsis whose
            // element references no outer list binding belongs to the inner
            // macro: keep the element (with outer scalar substitution and
            // hygiene applied) and the ellipsis token(s) literally instead
            // of expanding to zero repetitions.
            if ((intro_scope & NESTED_SR_FLAG) != 0 and !ellipsisReferencesOuter(elem, bindings)) {
                const new_elem = try instantiateTemplate(gc, elem, bindings, intro_scope, literals, macro_keyword, globals, macros);
                var elem_root = new_elem;
                gc.pushRoot(&elem_root);
                defer gc.popRoot();
                // Collect the run of consecutive ellipsis tokens
                var tokens: Value = types.NIL;
                gc.pushRoot(&tokens);
                defer gc.popRoot();
                var cur = rest;
                while (types.isPair(cur)) {
                    const tok = types.car(cur);
                    if (types.isSymbol(tok) and isEllipsis(types.symbolName(tok))) {
                        tokens = try gc.allocPair(tok, tokens);
                        cur = types.cdr(cur);
                    } else break;
                }
                const new_tail = try instantiateTemplate(gc, cur, bindings, intro_scope, literals, macro_keyword, globals, macros);
                var result = new_tail;
                gc.pushRoot(&result);
                defer gc.popRoot();
                while (types.isPair(tokens)) {
                    result = try gc.allocPair(types.car(tokens), result);
                    tokens = types.cdr(tokens);
                }
                return gc.allocPair(elem_root, result);
            }
            // Replicate elem for each ellipsis binding
            const after = types.cdr(rest);
            return instantiateEllipsis(gc, elem, after, bindings, intro_scope, literals, macro_keyword, globals, macros);
        }
    }

    // A single (var init) let-binding pair delegated from an ellipsis
    // repetition (instantiateLetBindings): the var is in binding position,
    // the init is not. Without this, repeated template-introduced binders
    // skip the binding-position rename and capture use-site references.
    if ((intro_scope & LET_PAIR_FLAG) != 0) {
        const base = intro_scope & ~LET_PAIR_FLAG;
        const new_var = try instantiateTemplate(gc, elem, bindings, base | BINDING_FLAG, literals, macro_keyword, globals, macros);
        var var_root = new_var;
        gc.pushRoot(&var_root);
        defer gc.popRoot();
        const new_init = try instantiateTemplate(gc, rest, bindings, base & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
        return gc.allocPair(var_root, new_init);
    }

    // Nested syntax-rules: outer pattern variables substitute into its
    // patterns, literals, and templates (R7RS template semantics), but its
    // own ellipses must be preserved — set the context flag for the subtree.
    if (types.isSymbol(elem) and std.mem.eql(u8, types.symbolName(elem), "syntax-rules")) {
        const nested_scope = (intro_scope | NESTED_SR_FLAG) & ~BINDING_FLAG;
        var car_root = elem;
        gc.pushRoot(&car_root);
        defer gc.popRoot();
        const new_cdr = try instantiateTemplate(gc, rest, bindings, nested_scope, literals, macro_keyword, globals, macros);
        return gc.allocPair(car_root, new_cdr);
    }

    // Detect binding forms and set binding-position flag for variable names
    if (types.isSymbol(elem)) {
        const form_name = types.symbolName(elem);
        const is_let_form = std.mem.eql(u8, form_name, "let") or
            std.mem.eql(u8, form_name, "let*") or
            std.mem.eql(u8, form_name, "letrec") or
            std.mem.eql(u8, form_name, "letrec*");
        if (is_let_form) {
            const new_car = try instantiateTemplate(gc, elem, bindings, intro_scope, literals, macro_keyword, globals, macros);
            var car_root = new_car;
            gc.pushRoot(&car_root);
            defer gc.popRoot();
            const let_rest = types.cdr(template);
            if (let_rest != types.NIL and types.isPair(let_rest)) {
                const binding_list = types.car(let_rest);
                const body = types.cdr(let_rest);
                const new_bindings = try instantiateLetBindings(gc, binding_list, bindings, intro_scope | BINDING_FLAG, literals, macro_keyword, globals, macros);
                var bindings_root = new_bindings;
                gc.pushRoot(&bindings_root);
                defer gc.popRoot();
                const new_body = try instantiateTemplate(gc, body, bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
                var body_root = new_body;
                gc.pushRoot(&body_root);
                defer gc.popRoot();
                const inner = try gc.allocPair(bindings_root, body_root);
                return gc.allocPair(car_root, inner);
            }
        }
    }

    // Regular pair: recurse
    const new_car = try instantiateTemplate(gc, types.car(template), bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    var car_root = new_car;
    gc.pushRoot(&car_root);
    defer gc.popRoot();
    const new_cdr = try instantiateTemplate(gc, types.cdr(template), bindings, intro_scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    return gc.allocPair(car_root, new_cdr);
}

fn instantiateLetBindings(gc: *GC, binding_list: Value, bindings: []Binding, scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) !Value {
    if (binding_list == types.NIL) return types.NIL;
    if (!types.isPair(binding_list)) return instantiateTemplate(gc, binding_list, bindings, scope, literals, macro_keyword, globals, macros);
    const pair = types.car(binding_list);
    // Ellipsis after a binding element: ((var init) ...) — expand the
    // repetitions via the regular ellipsis machinery, then continue
    // let-binding processing on whatever follows the ellipsis token(s).
    // Consecutive extra ellipses (((var init) ... ...), R7RS 4.3.2
    // flattening) are collected into a synthetic rest-template so
    // instantiateEllipsis applies its existing flattening logic.
    const after = types.cdr(binding_list);
    if (types.isPair(after)) {
        const nxt = types.car(after);
        if (types.isSymbol(nxt) and isEllipsis(types.symbolName(nxt))) {
            var synth_rest: Value = types.NIL;
            gc.pushRoot(&synth_rest);
            defer gc.popRoot();
            var rest_after = types.cdr(after);
            while (types.isPair(rest_after)) {
                const tok = types.car(rest_after);
                if (types.isSymbol(tok) and isEllipsis(types.symbolName(tok))) {
                    synth_rest = try gc.allocPair(tok, synth_rest);
                    rest_after = types.cdr(rest_after);
                } else break;
            }
            // Inside a nested syntax-rules template with no outer list
            // binding referenced, the ellipsis belongs to the inner macro:
            // keep the pair and the ellipsis token(s) literally.
            if ((scope & NESTED_SR_FLAG) != 0 and !ellipsisReferencesOuter(pair, bindings)) {
                const new_pair = try instantiateTemplate(gc, pair, bindings, scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
                var pair_root = new_pair;
                gc.pushRoot(&pair_root);
                defer gc.popRoot();
                const tail = try instantiateLetBindings(gc, rest_after, bindings, scope, literals, macro_keyword, globals, macros);
                var result = tail;
                gc.pushRoot(&result);
                defer gc.popRoot();
                result = try gc.allocPair(nxt, result);
                while (types.isPair(synth_rest)) {
                    result = try gc.allocPair(types.car(synth_rest), result);
                    synth_rest = types.cdr(synth_rest);
                }
                return gc.allocPair(pair_root, result);
            }
            const segment = try instantiateEllipsis(gc, pair, synth_rest, bindings, (scope & ~BINDING_FLAG) | LET_PAIR_FLAG, literals, macro_keyword, globals, macros);
            var seg_root = segment;
            gc.pushRoot(&seg_root);
            defer gc.popRoot();
            const tail = try instantiateLetBindings(gc, rest_after, bindings, scope, literals, macro_keyword, globals, macros);
            if (seg_root == types.NIL) return tail;
            var last = seg_root;
            while (types.isPair(types.cdr(last))) last = types.cdr(last);
            gc.writeBarrier(types.toObject(last), tail);
            types.setCdr(last, tail);
            return seg_root;
        }
    }
    if (!types.isPair(pair)) {
        const new_pair = try instantiateTemplate(gc, pair, bindings, scope, literals, macro_keyword, globals, macros);
        var pair_root = new_pair;
        gc.pushRoot(&pair_root);
        defer gc.popRoot();
        const new_rest = try instantiateLetBindings(gc, types.cdr(binding_list), bindings, scope, literals, macro_keyword, globals, macros);
        return gc.allocPair(pair_root, new_rest);
    }
    const var_name = types.car(pair);
    const init_and_rest = types.cdr(pair);
    const new_var = try instantiateTemplate(gc, var_name, bindings, scope, literals, macro_keyword, globals, macros);
    var var_root = new_var;
    gc.pushRoot(&var_root);
    defer gc.popRoot();
    const new_init = try instantiateTemplate(gc, init_and_rest, bindings, scope & ~BINDING_FLAG, literals, macro_keyword, globals, macros);
    var init_root = new_init;
    gc.pushRoot(&init_root);
    defer gc.popRoot();
    const new_pair = try gc.allocPair(var_root, init_root);
    var np_root = new_pair;
    gc.pushRoot(&np_root);
    defer gc.popRoot();
    const new_rest = try instantiateLetBindings(gc, types.cdr(binding_list), bindings, scope, literals, macro_keyword, globals, macros);
    return gc.allocPair(np_root, new_rest);
}

fn templateReferencesVar(template: Value, name: []const u8) bool {
    if (types.isSymbol(template)) {
        return std.mem.eql(u8, types.symbolName(template), name);
    }
    if (types.isPair(template)) {
        return templateReferencesVar(types.car(template), name) or
            templateReferencesVar(types.cdr(template), name);
    }
    return false;
}

/// Like templateReferencesVar, but skips sub-expressions consumed by a
/// nested inner ellipsis — i.e. elements immediately followed by `...`.
/// A binding found only inside such a sub-expression is "indirectly"
/// referenced and should not drive the outer ellipsis's repeat count.
fn templateReferencesVarDirectly(template: Value, name: []const u8) bool {
    if (types.isSymbol(template)) {
        return std.mem.eql(u8, types.symbolName(template), name);
    }
    if (types.isPair(template)) {
        const head = types.car(template);
        const tail = types.cdr(template);
        if (types.isPair(tail)) {
            const next = types.car(tail);
            if (types.isSymbol(next) and isEllipsis(types.symbolName(next))) {
                var rest = types.cdr(tail);
                while (types.isPair(rest)) {
                    const r = types.car(rest);
                    if (types.isSymbol(r) and isEllipsis(types.symbolName(r))) {
                        rest = types.cdr(rest);
                    } else break;
                }
                return templateReferencesVarDirectly(rest, name);
            }
        }
        return templateReferencesVarDirectly(head, name) or
            templateReferencesVarDirectly(tail, name);
    }
    return false;
}

/// Checks whether a candidate variable and any Pass-1 driver variable both
/// appear inside the SAME inner `(elem ...)` sub-template.  When they do,
/// the candidate shares a pattern group with the driver and should be
/// consumed per-iteration (SRFI 149's excess-ellipsis replication).  When
/// they don't — the candidate's only inner `(x ...)` contains no driver —
/// the candidate is from an independent group and should be passed through
/// wholesale (issue #1721).
fn sharesInnerEllipsisWithDriver(template: Value, candidate_name: []const u8, bindings: []const Binding, referenced: *const [MAX_BINDINGS]bool) bool {
    if (!types.isPair(template)) return false;

    const head = types.car(template);
    const tail = types.cdr(template);

    if (types.isPair(tail)) {
        const next = types.car(tail);
        if (types.isSymbol(next) and isEllipsis(types.symbolName(next))) {
            // `head` is consumed by an inner ellipsis.  Check whether it
            // references both the candidate and any Pass-1 driver.
            if (templateReferencesVar(head, candidate_name)) {
                for (bindings, 0..) |b, bi| {
                    if (referenced[bi] and templateReferencesVar(head, b.name)) {
                        return true;
                    }
                }
            }
            // Skip past consecutive ellipses and check the rest of the list.
            var rest = types.cdr(tail);
            while (types.isPair(rest)) {
                const r = types.car(rest);
                if (types.isSymbol(r) and isEllipsis(types.symbolName(r))) {
                    rest = types.cdr(rest);
                } else break;
            }
            return sharesInnerEllipsisWithDriver(rest, candidate_name, bindings, referenced);
        }
    }

    return sharesInnerEllipsisWithDriver(head, candidate_name, bindings, referenced) or
        sharesInnerEllipsisWithDriver(tail, candidate_name, bindings, referenced);
}

fn instantiateEllipsis(gc: *GC, elem_template: Value, rest_template: Value, bindings: []Binding, intro_scope: u32, literals: []const Value, macro_keyword: ?[]const u8, globals: ?*std.StringHashMap(Value), macros: ?*const std.StringHashMap(Value)) (std.mem.Allocator.Error || ExpandError)!Value {
    // Per-iteration sub-binding scratch, hoisted out of the loop and written
    // field-by-field there: whole-struct assignment re-initializes or copies
    // the 8KB ellipsis_values field each time, which dominated expansion time
    // on macro-heavy code (ellipsis_values is only read when is_list).
    // Declared under a safety-off function scope so ReleaseSafe's 0xAA fill
    // of `= undefined` locals is not emitted; the whole body runs in the
    // safety-on block below (see expandMacro; kaappi#1802).
    @setRuntimeSafety(false);
    var sub_bindings: [MAX_BINDINGS]Binding = undefined;
    {
        @setRuntimeSafety(true);
        // Find the repeat count from ellipsis bindings referenced in elem_template.
        // All referenced list bindings must have equal counts (R7RS). Bindings
        // with depth > 1 (nested ellipses) participate too: their ellipsis_count
        // at this level is the outer repetition count, and each iteration below
        // unpacks them one level for the inner ellipsis to consume.
        var repeat_count: usize = 0;
        var count_set = false;
        var referenced: [MAX_BINDINGS]bool = @splat(false);
        var indirect: [MAX_BINDINGS]bool = @splat(false);

        for (bindings, 0..) |b, bi| {
            if (b.is_list and (templateReferencesVarDirectly(elem_template, b.name) or
                (b.depth > 1 and templateReferencesVar(elem_template, b.name))))
            {
                referenced[bi] = true;
                if (!count_set) {
                    repeat_count = b.ellipsis_count;
                    count_set = true;
                } else if (b.ellipsis_count != repeat_count) {
                    return ExpandError.EllipsisCountMismatch;
                }
            }
        }

        for (bindings, 0..) |b, bi| {
            if (b.is_list and !referenced[bi] and templateReferencesVar(elem_template, b.name)) {
                if (sharesInnerEllipsisWithDriver(elem_template, b.name, bindings, &referenced)) {
                    referenced[bi] = true;
                    if (!count_set) {
                        repeat_count = b.ellipsis_count;
                        count_set = true;
                    } else if (b.ellipsis_count != repeat_count) {
                        return ExpandError.EllipsisCountMismatch;
                    }
                } else {
                    indirect[bi] = true;
                }
            }
        }

        // R7RS 4.3.2 (kaappi#1791): no pattern variable at this ellipsis
        // depth drove the repeat count, so this is not "zero repetitions" —
        // it's a template bug (most often a typo'd bare `...` where the
        // literal-ellipsis escape `(... ...)` was meant, kaappi#1787).
        // Silently producing zero copies here previously let the malformed
        // expansion continue and fail far away with a misleading error.
        //
        // This can never fire for the legitimate "ellipsis belongs to a
        // nested syntax-rules template's own grammar" case: both call sites
        // of this function (instantiateTemplate and instantiateLetBindings)
        // already special-case `NESTED_SR_FLAG and !ellipsisReferencesOuter`
        // *before* calling here, and `ellipsisReferencesOuter` is exactly
        // the same predicate — over the same elem_template/bindings — as
        // the `count_set` computation above. So `!count_set` here implies
        // `ellipsisReferencesOuter` was false, which means the caller could
        // only have reached this call with NESTED_SR_FLAG unset.
        if (!count_set) return ExpandError.EllipsisNoPatternVariable;

        // Consecutive ellipses (R7RS 4.3.2): (x ... ...) flattens depth-2
        // bindings into a single list.  Count and strip leading ellipsis
        // tokens from rest_template so the tail instantiation sees only the
        // non-ellipsis remainder.
        var extra_ellipsis: u32 = 0;
        var true_rest = rest_template;
        while (types.isPair(true_rest)) {
            const head = types.car(true_rest);
            if (types.isSymbol(head) and isEllipsis(types.symbolName(head))) {
                extra_ellipsis += 1;
                true_rest = types.cdr(true_rest);
            } else {
                break;
            }
        }

        // First instantiate the rest (after all consumed ellipses)
        const result = try instantiateTemplate(gc, true_rest, bindings, intro_scope, literals, macro_keyword, globals, macros);
        var result_root = result;
        gc.pushRoot(&result_root);
        defer gc.popRoot();

        // When extra ellipses are present, build the synthetic template
        // (elem_template ... ...) once outside the loop — it is invariant
        // across iterations and instantiateTemplate only reads it.
        var synth = types.NIL;
        if (extra_ellipsis > 0) {
            gc.pushRoot(&synth);
            const ellipsis_name = active_custom_ellipsis orelse "...";
            var ei: u32 = 0;
            while (ei < extra_ellipsis) : (ei += 1) {
                const dots = try gc.allocSymbol(ellipsis_name);
                synth = try gc.allocPair(dots, synth);
            }
            synth = try gc.allocPair(elem_template, synth);
        }
        defer if (extra_ellipsis > 0) gc.popRoot();

        // Generate copies in reverse so we build the list from right to left.
        var i = repeat_count;
        while (i > 0) {
            i -= 1;
            // Create sub-bindings with the i-th value for each referenced list
            // binding. Unreferenced list bindings are skipped: their
            // ellipsis_count can be smaller than repeat_count (e.g. two
            // ellipsis groups of different lengths in one template), so
            // indexing ellipsis_values[i] would read uninitialized data.
            var sub_count: usize = 0;
            for (bindings, 0..) |b, bi| {
                if (b.is_list) {
                    if (!referenced[bi] and !indirect[bi]) continue;
                    if (indirect[bi]) {
                        sub_bindings[sub_count].name = b.name;
                        sub_bindings[sub_count].value = types.NIL;
                        sub_bindings[sub_count].depth = b.depth;
                        sub_bindings[sub_count].is_list = true;
                        sub_bindings[sub_count].ellipsis_count = b.ellipsis_count;
                        var ec: usize = 0;
                        while (ec < b.ellipsis_count and ec < MAX_ELLIPSIS_VALUES) : (ec += 1) {
                            sub_bindings[sub_count].ellipsis_values[ec] = b.ellipsis_values[ec];
                        }
                        sub_count += 1;
                        continue;
                    }
                    if (b.depth > 1) {
                        // Nested ellipsis: unpack list into sub-binding
                        sub_bindings[sub_count].name = b.name;
                        sub_bindings[sub_count].value = types.NIL;
                        sub_bindings[sub_count].depth = b.depth - 1;
                        sub_bindings[sub_count].is_list = true;
                        var list_val = b.ellipsis_values[i];
                        var ev_count: usize = 0;
                        while (types.isPair(list_val) and ev_count < MAX_ELLIPSIS_VALUES) {
                            sub_bindings[sub_count].ellipsis_values[ev_count] = types.car(list_val);
                            ev_count += 1;
                            list_val = types.cdr(list_val);
                        }
                        sub_bindings[sub_count].ellipsis_count = ev_count;
                    } else {
                        sub_bindings[sub_count].name = b.name;
                        sub_bindings[sub_count].value = b.ellipsis_values[i];
                        sub_bindings[sub_count].depth = 0;
                        sub_bindings[sub_count].is_list = false;
                        sub_bindings[sub_count].ellipsis_count = 0;
                    }
                } else {
                    sub_bindings[sub_count].name = b.name;
                    sub_bindings[sub_count].value = b.value;
                    sub_bindings[sub_count].depth = b.depth;
                    sub_bindings[sub_count].is_list = false;
                    sub_bindings[sub_count].ellipsis_count = 0;
                }
                sub_count += 1;
            }

            if (extra_ellipsis == 0) {
                const expanded = try instantiateTemplate(gc, elem_template, sub_bindings[0..sub_count], intro_scope, literals, macro_keyword, globals, macros);
                var expanded_root = expanded;
                gc.pushRoot(&expanded_root);
                result_root = try gc.allocPair(expanded_root, result_root);
                gc.popRoot();
            } else {
                const expanded_list = try instantiateTemplate(gc, synth, sub_bindings[0..sub_count], intro_scope, literals, macro_keyword, globals, macros);

                // Splice expanded_list (a proper list) into result_root.
                if (expanded_list != types.NIL and types.isPair(expanded_list)) {
                    var tail = expanded_list;
                    while (types.isPair(types.cdr(tail))) {
                        tail = types.cdr(tail);
                    }
                    gc.writeBarrier(types.toObject(tail), result_root);
                    types.setCdr(tail, result_root);
                    result_root = expanded_list;
                }
            }
        }

        return result_root;
    }
}

// ---------------------------------------------------------------------------
// Hygienic renaming
// ---------------------------------------------------------------------------

/// Rename a template-introduced identifier for hygiene. Within a single
/// macro invocation (identified by `scope`), the same original name always
/// maps to the same gensym, ensuring internal references stay consistent
/// while avoiding capture of user bindings.
fn substitutePatternVarsOnly(gc: *GC, template: Value, bindings: []Binding) !Value {
    if (types.isSymbol(template)) {
        const name = types.symbolName(template);
        for (bindings) |b| {
            if (std.mem.eql(u8, b.name, name)) return b.value;
        }
        return template;
    }
    if (!types.isPair(template)) return template;
    const new_car = try substitutePatternVarsOnly(gc, types.car(template), bindings);
    var car_root = new_car;
    gc.pushRoot(&car_root);
    const new_cdr = try substitutePatternVarsOnly(gc, types.cdr(template), bindings);
    gc.popRoot();
    return gc.allocPair(car_root, new_cdr);
}

fn scopeTableContains(scope: u32, name: []const u8) bool {
    for (scope_table[0..scope_table_count]) |entry| {
        if (entry.scope == scope and std.mem.eql(u8, entry.original_name, name)) return true;
    }
    return false;
}

fn renameForHygiene(gc: *GC, name: []const u8, scope: u32, globals: ?*std.StringHashMap(Value)) !Value {
    // Already renamed by an enclosing expansion: macro-generating macros
    // bake __hyg_ names into the inner macro's stored template. Gensyms are
    // globally unique, so renaming again cannot prevent any capture — it
    // only severs the reference from the binding created by the generating
    // expansion (issue #919: __hyg_N___hyg_M_march-hare undefined). The same
    // holds for the named-let loop gensym (__nlet_N_name): named-let desugars
    // during compilation, interleaved with macro expansion, so its loop name
    // can flow back through a macro whose template re-emits it (e.g. SRFI 257's
    // ~etc, where the recursive (loop ...) call rides inside a submatch
    // argument). Re-renaming it splits the reference from the letrec binding.
    // Checked before the quote branch below too, so a quoted occurrence of an
    // already-renamed name is passed through rather than re-minted.
    //
    // The same holds for a def_env_binding_prefix-marked name (#1812): a
    // macro template can itself contain ANOTHER macro's whole definition
    // (e.g. SRFI 41's stream-match, a syntax-rules template whose body is a
    // letrec-syntax defining smp/smt) — the outer expansion walks and
    // hygiene-renames every free identifier in that nested spec too,
    // including ones already marked with this prefix by THIS transformer's
    // own active_def_env check below. If the nested macro (smp/smt) is
    // itself top-level/REPL-scoped (its own def_env is null, as here — it's
    // defined via letrec-syntax at the *use* site, not within any library),
    // its own later expansion would otherwise see the prefixed name as a
    // fresh, unrecognized identifier and re-wrap it with a __hyg_ gensym,
    // severing it from anything vm_dispatch's prefix parser can resolve.
    if (std.mem.startsWith(u8, name, "__hyg_") or std.mem.startsWith(u8, name, "__nlet_") or
        std.mem.startsWith(u8, name, types.def_env_binding_prefix))
        return gc.allocSymbol(name);

    // A usertext-marker splice being re-walked in substitute-only mode: this
    // name is use-site data from an ENCLOSING expansion, not a template-
    // introduced identifier of this one, so it must never be renamed --
    // regardless of QUOTE_FLAG, which is also set here purely to get the
    // rest of the quote-mode walk (substitute, expand ellipses). See
    // VERBATIM_FLAG's own comment.
    if ((scope & VERBATIM_FLAG) != 0) return gc.allocSymbol(name);

    if ((scope & QUOTE_FLAG) != 0) {
        // A template-introduced identifier inside `(quote ...)` is still an
        // IDENTIFIER at the macro-expansion level, not yet inert data: two
        // separate expansions of e.g. `(define-syntax gensym (syntax-rules ()
        // ((gensym) 'g)))` must stay distinguishable via
        // bound-identifier=?/free-identifier=?-style comparisons built out of
        // further macro expansion (nested define-syntax/literal matching),
        // even though `g` will eventually print/compare as the plain symbol
        // `g` once actually compiled into a literal runtime value (#1801).
        // So a quoted, template-introduced identifier is hygiene-renamed
        // exactly like a non-quoted one -- deduped within THIS expansion via
        // the same clean_scope lookup (needed so a nested syntax-rules
        // template's quoted reference to its OWN pattern variable `y` in
        // `((_ y) '(fixed y))` picks up the SAME rename the pattern side
        // already claimed) -- and the compiler strips the `__hyg_` prefix
        // back off wherever it compiles a REAL `(quote ...)` datum to a
        // literal Value (stripHygieneFromDatum, called from quote and
        // quasiquote compilation), so ordinary uses of `'sym` in a template
        // still behave exactly as before once the code actually runs: two
        // unrelated macro expansions that both quote the same literal tag
        // still produce `eq?` symbols.
        const clean_scope = scope & ~(BINDING_FLAG | NESTED_SR_FLAG | LET_PAIR_FLAG | QQ_DEPTH_MASK | QUOTE_FLAG);
        for (scope_table[0..scope_table_count]) |entry| {
            if (entry.scope == clean_scope and std.mem.eql(u8, entry.original_name, name)) {
                return gc.allocSymbol(entry.renamed_to);
            }
        }
        return mintHygienicRename(gc, name, clean_scope);
    }

    const in_binding = (scope & BINDING_FLAG) != 0;
    // Strip context flags that don't change renaming, so the same template
    // identifier gets the same gensym inside and outside those contexts
    // (e.g. an outer binding referenced from a nested syntax-rules template).
    const clean_scope = scope & ~(BINDING_FLAG | NESTED_SR_FLAG | LET_PAIR_FLAG | QQ_DEPTH_MASK);
    const gmod = @import("globals.zig");

    // #1812: a free reference bound in the macro's OWN definition-
    // environment library (def_env — set only for a library-defined
    // transformer, never a top-level/REPL one) must resolve through THAT
    // library's own environment, not whatever the use site's mutable
    // globals table currently holds for the same name — checked before the
    // `globals` block below so it takes priority over a same-named entry
    // that merely happens to also exist in the use site's table (e.g. one
    // copyTransformerFreeRefs planted there at import time). Same
    // shadowing guard as the isProcedure/VOID branches below: a template
    // binding of the same name still wins.
    //
    // Guarded by `active_def_env != globals`: when they're the SAME map,
    // this expansion is compiling within the macro's own defining library,
    // which hasn't necessarily finished loading yet — lookupDefEnvBinding
    // resolves by canonical name through vm.libraries, which only gains an
    // entry once a library's declaration processing completes in full
    // (handleDefineLibrary registers it last). A macro used by a LATER
    // declaration in that same body would resolve fine (loading finished
    // by then), but one used by an EARLIER/self-referential declaration
    // would spuriously raise "undefined variable" (confirmed: this is
    // exactly how SRFI 35's own make-condition-type reference broke while
    // SRFI 35 itself is still loading). The existing get_global/call_global
    // path already resolves this case correctly via func.env pointing
    // straight at the same live lib_env, no registration required, so just
    // fall through to it unchanged.
    //
    // ALSO guarded by "not a true (scheme base) binding" (lookupBaseBinding):
    // a library merely re-exporting/importing a standard procedure like
    // call-with-values, raise-continuable, with-exception-handler, call/cc,
    // or dynamic-wind is not the "genuinely library-internal helper" case
    // #1812 targets, and several compiler spots (compileCallWithValuesTail's
    // is_tail dispatch in compiler.zig, similarly for apply/call/cc/eval)
    // recognize these by exact bare name — confirmed by tracing SRFI 248's
    // guard macro, whose tail-position (call-with-values (lambda () ...) k)
    // silently lost its dedicated tail-call handling once call-with-values
    // was renamed, breaking multiple-value passing to k. Universal, rarely-
    // shadowed builtins aren't worth chasing every such exact-name spot for;
    // leaving them exactly as renameForHygiene already treated them (the
    // isProcedure branch below, unprefixed) sidesteps the whole class.
    if (active_def_env) |denv| {
        if (active_def_lib_name) |libname| {
            if (denv != globals and !in_binding and !scopeTableContains(clean_scope, name) and
                denv.contains(name) and gmod.lookupBaseBinding(name) == null)
            {
                var buf: [512]u8 = undefined;
                return gc.allocSymbol(gmod.buildDefEnvBindingSymbolName(&buf, libname, name));
            }
        }
    }

    if (globals) |g| {
        const glk = gmod.acquireGlobalsRead(g);
        defer gmod.releaseGlobalsRead(glk);
        if (g.get(name)) |val| {
            if (types.isProcedure(val) or types.isTransformer(val)) {
                // A template binding of the same name in this expansion
                // shadows the global procedure (e.g. a template let variable
                // named exp must not resolve to the builtin exp), so the
                // reference must follow the rename recorded for the binding.
                if (!in_binding and !scopeTableContains(clean_scope, name)) {
                    return gc.allocSymbol(name);
                }
            } else if (val == types.VOID) {
                // VOID entries are sentinels planted by the compiler's body
                // prescan (compileBody/compileLetBody) for internal defines
                // that appear later in the same body — the template reference
                // must keep its name so it resolves to that binding (R7RS
                // 5.3.2 letrec* body semantics). But if this expansion already
                // renamed the name as a template-introduced binding, the
                // reference must follow the rename instead.
                if (!in_binding and !scopeTableContains(clean_scope, name)) {
                    return gc.allocSymbol(name);
                }
            }
        }
    }
    if (gmod.globals_ctx) |gctx| {
        gctx.lockShared();
        const found = gctx.globals.get(name);
        gctx.unlockShared();
        if (found) |val| {
            if (types.isTransformer(val)) return gc.allocSymbol(name);
        }
    }

    // A free template reference to a definition-site LOCAL variable. When the
    // expansion happens in the same function frame, fall through: the rename +
    // captured-locals slot alias resolves it shadow-proof. But when the macro's
    // output lands in a nested lambda (a different frame), no slot alias can
    // reach the outer frame — keep the name so the reference compiles through
    // the regular local/upvalue path. Without this, user code that a macro
    // splices into a nested syntax-rules template (SRFI 257's submatch/
    // if-new-var protocol) loses its free variables to the rename (#1644).
    if (!in_binding and !scopeTableContains(clean_scope, name)) {
        for (active_def_local_refs) |ref| {
            if (std.mem.eql(u8, ref, name)) {
                if (!active_use_check.resolvesInFrame(name)) {
                    return gc.allocSymbol(name);
                }
                break;
            }
        }
    }

    for (scope_table[0..scope_table_count]) |entry| {
        if (entry.scope == clean_scope and std.mem.eql(u8, entry.original_name, name)) {
            return gc.allocSymbol(entry.renamed_to);
        }
    }

    return mintHygienicRename(gc, name, clean_scope);
}

/// Generate a fresh hygienic name for a truly new template-introduced
/// identifier and record it in scope_table (keyed by clean_scope) so later
/// references to the same original name within this expansion, quoted or
/// not, resolve to the same rename. Callers have already checked
/// scope_table for an existing entry.
fn mintHygienicRename(gc: *GC, name: []const u8, clean_scope: u32) !Value {
    const gensym_id = freshGensymId();
    var buf: [128]u8 = undefined;
    const len = std.fmt.bufPrint(&buf, "__hyg_{d}_{s}", .{ gensym_id, name }) catch
        return gc.allocSymbol(name);

    const sym_val = try gc.allocSymbol(len);
    const renamed_persistent = types.symbolName(sym_val);

    if (scope_table_count >= MAX_SCOPE_ENTRIES) return ExpandError.ScopeTableFull;
    scope_table[scope_table_count] = .{
        .original_name = name,
        .scope = clean_scope,
        .renamed_to = renamed_persistent,
    };
    scope_table_count += 1;

    return sym_val;
}
