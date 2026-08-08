const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const timings = @import("timings.zig");
const Value = types.Value;
const GC = memory.GC;

// Template instantiation + hygiene renaming live in expander_instantiate.zig
// (split for file size); they share this file's threadlocal expansion context.
const instantiate_mod = @import("expander_instantiate.zig");
const instantiateTemplate = instantiate_mod.instantiateTemplate;
const renameForHygiene = instantiate_mod.renameForHygiene;

// Expansion is reachable from child-thread compile paths (SRFI 18 threads
// compile with their own VM); per-expansion context must be threadlocal so
// concurrent compilers cannot clobber each other's state.
pub threadlocal var active_custom_ellipsis: ?[]const u8 = null;
threadlocal var active_literals: []const Value = &.{};

pub fn isEllipsis(name: []const u8) bool {
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

/// Template-introduced keywords that keep their exact spelling even though
/// the compiler recognizes them — the complement of the operator keywords
/// that are hygiene-renamed (see instantiateTemplate step 3, kaappi#2074).
/// These must stay bare because something matches them structurally by
/// spelling, not by effective-name dispatch:
///
///  * the definition/library forms (`define`, `define-syntax`,
///    `define-values`, `define-record-type`, `let-syntax`, `letrec-syntax`,
///    `import`, `export`, `define-library`, `include`, `include-ci`) —
///    matched by the body scanner, the transformer-spec resolver, and the
///    library loader on raw forms;
///  * `syntax-rules` — the head of a nested transformer spec, matched bare
///    by resolveTransformerSpecRec;
///  * the aux syntax `else` and the pattern markers `...` and `_`, matched
///    bare by cond/case/guard clause processing and the pattern matcher;
///  * `quote`/`quasiquote`/`unquote`/`unquote-splicing` — a bare one of
///    these used as a VALUE (e.g. `(list quote)`) must still evaluate to the
///    symbol itself, so the symbol walk leaves them alone; the `(quote ...)`
///    / `(quasiquote ...)` FORM heads are renamed separately by the form
///    branches in instantiateTemplate.
const reserved_template_forms = [_][]const u8{
    "define",         "define-syntax", "define-values",    "define-record-type",
    "let-syntax",     "letrec-syntax", "syntax-rules",     "quote",
    "quasiquote",     "unquote",       "unquote-splicing", "else",
    "...",            "_",             "import",           "export",
    "define-library", "include",       "include-ci",
};

/// True when a template-introduced identifier must keep its exact spelling
/// (see `reserved_template_forms`). Every other well-known form is a
/// compiler keyword the expander can hygiene-rename: the compiler
/// recognizes it through effective-name stripping, and renaming makes a
/// use-site local of the same spelling unable to capture it (kaappi#2074).
pub fn isTemplateReserved(name: []const u8) bool {
    for (&reserved_template_forms) |rt| {
        if (std.mem.eql(u8, rt, name)) return true;
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

pub fn freshGensymId() u32 {
    return @atomicRmw(u32, &gensym_counter, .Add, 1, .monotonic) + 1;
}

/// Tracks renamings within a single macro invocation so that the same
/// template identifier maps to the same gensym consistently.
pub const ScopeEntry = struct {
    original_name: []const u8,
    scope: u32,
    renamed_to: []const u8,
};

pub const MAX_SCOPE_ENTRIES = 256;
// The scope table is a per-expansion dedup cache, saved/restored around each
// expansion — cross-thread sharing of it could interleave restorations and
// split a binding's rename from its references, so it is threadlocal (like
// the active_* expansion context above).
pub threadlocal var scope_table: [MAX_SCOPE_ENTRIES]ScopeEntry = undefined;
pub threadlocal var scope_table_count: usize = 0;

// ---------------------------------------------------------------------------
// Pattern variable binding
// ---------------------------------------------------------------------------

pub const MAX_BINDINGS = 128;
pub const MAX_ELLIPSIS_VALUES = 1024;

pub fn vectorToList(gc: *GC, data: []const Value) !Value {
    var result: Value = types.NIL;
    var i = data.len;
    while (i > 0) {
        i -= 1;
        result = try gc.allocPair(data[i], result);
    }
    return result;
}

pub fn listToVector(gc: *GC, list: Value) !Value {
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

pub const Binding = struct {
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
pub threadlocal var active_def_local_refs: []const []const u8 = &.{};
pub threadlocal var active_use_check: UseSiteBindingCheck = .{};

// Per-expansion context for renameForHygiene (#1812): the transformer's own
// definition environment (a library's lib_env) and its canonical name, so a
// free reference bound there can be marked to resolve through that specific
// library's environment at runtime instead of the use site's mutable
// globals table. Both null for a top-level/REPL-defined transformer.
pub threadlocal var active_def_env: ?*std.StringHashMap(Value) = null;
pub threadlocal var active_def_lib_name: ?[]const u8 = null;

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
    const gc = memory.gc_instance orelse return error.InvalidBytecode; // no GC: internal invariant
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
/// the reserved forms and in-scope macro keywords keep their names,
/// everything else goes through renameForHygiene under this invocation's
/// scope — globals-bound names stay unrenamed (definition-environment
/// resolution), fresh names gensym consistently. The operator keywords
/// among well_known_forms are renamed like any other template identifier
/// (kaappi#2074), matching syntax-rules.
fn erRenameSymbol(gc: *GC, name: []const u8) anyerror!Value {
    if (isTemplateReserved(name)) return gc.allocSymbol(name);
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
            // Seed the binding's depth from the PATTERN structure rather
            // than the constant 1: the per-repetition `sub.depth + 1` update
            // below never runs when the ellipsis matches ZERO repetitions,
            // so a nested variable -- ((b ...) ...) matched against () --
            // would otherwise stay at depth 1, under-reporting its true
            // depth and breaking the depth/driver checks in
            // instantiateEllipsis (kaappi#682). `nesting + 1` agrees with
            // the per-repetition formula whenever a repetition does run.
            bindings[count.*].depth = @intCast((patternVarNesting(elem_pattern, elem_var_names[vi], literals) orelse 0) + 1);
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

/// Ellipsis nesting depth of pattern variable `name` inside `pattern` — the
/// number of inner ellipses enclosing it, 0 for a variable directly in the
/// pattern (so its full pattern depth is `1 + nesting` at the ellipsis site
/// that created the binding). Mirrors the ellipsis detection in
/// matchListPattern: an element followed by an ellipsis token is one level
/// deeper; the ellipsis-escape `(... ...)` contributes no variable. Used to
/// seed ellipsis bindings whose match was EMPTY (see matchEllipsis) and to
/// compute the template consumption depth of a binding in
/// expander_instantiate.zig.
pub fn patternVarNesting(pattern: Value, name: []const u8, literals: []const Value) ?u32 {
    return patternVarNestingWalk(pattern, name, literals, 0);
}

fn patternVarNestingWalk(pattern: Value, name: []const u8, literals: []const Value, nesting: u32) ?u32 {
    if (types.isSymbol(pattern)) {
        const nm = types.symbolName(pattern);
        if (isEllipsis(nm)) return null;
        for (literals) |lit| {
            if (types.isSymbol(lit) and std.mem.eql(u8, types.symbolName(lit), nm)) return null;
        }
        if (std.mem.eql(u8, nm, "_")) return null;
        if (std.mem.eql(u8, nm, name)) return nesting;
        return null;
    }
    if (types.isPair(pattern)) {
        var p = pattern;
        while (types.isPair(p)) {
            const elem = types.car(p);
            const rest = types.cdr(p);
            // (elem ...): an inner ellipsis — variables in elem sit one
            // level deeper; the tail after the ellipsis stays at this level.
            if (types.isPair(rest)) {
                const maybe_ell = types.car(rest);
                if (types.isSymbol(maybe_ell) and isEllipsis(types.symbolName(maybe_ell))) {
                    if (patternVarNestingWalk(elem, name, literals, nesting + 1)) |d| return d;
                    p = types.cdr(rest);
                    continue;
                }
            }
            if (patternVarNestingWalk(elem, name, literals, nesting)) |d| return d;
            p = rest;
        }
        // Dotted tail: (a ... . z) — walk the final non-pair at this level.
        if (p != types.NIL) {
            if (patternVarNestingWalk(p, name, literals, nesting)) |d| return d;
        }
        return null;
    }
    if (types.isVector(pattern)) {
        // Vector patterns match through list semantics (matchPattern
        // vectorToList's them before matchListPattern), so an element
        // followed by the ellipsis identifier inside the vector data sits
        // one level deeper — same shape as the list branch above.
        const vec = types.toObject(pattern).as(types.Vector);
        var i: usize = 0;
        while (i < vec.data.len) : (i += 1) {
            if (i + 1 < vec.data.len and types.isSymbol(vec.data[i + 1]) and
                isEllipsis(types.symbolName(vec.data[i + 1])))
            {
                if (patternVarNestingWalk(vec.data[i], name, literals, nesting + 1)) |d| return d;
                i += 1; // skip the ellipsis token
                continue;
            }
            if (patternVarNestingWalk(vec.data[i], name, literals, nesting)) |d| return d;
        }
        return null;
    }
    return null;
}

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
