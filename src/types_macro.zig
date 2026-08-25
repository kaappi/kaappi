const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;
const NIL = types.NIL;

pub const CapturedLocal = struct {
    name: []const u8,
    slot: u16,
};

/// Which expansion mechanism a Transformer uses (SRFI 211). `syntax_rules`
/// is the R7RS pattern/template engine (literals/patterns/templates below);
/// the other two are procedural — `proc` holds a Scheme procedure the
/// expander invokes at macro-expansion time (expander.expandProceduralMacro):
/// `er_macro` receives (form rename compare), `lisp_macro` receives the
/// whole macro-use datum.
pub const TransformerKind = enum(u8) { syntax_rules, er_macro, lisp_macro };

pub const Transformer = struct {
    header: Object,
    literals: []Value,
    patterns: []Value,
    templates: []Value,
    num_rules: u16,
    kind: TransformerKind = .syntax_rules,
    /// Procedural transformer body (kind != .syntax_rules); NIL otherwise.
    /// GC-traced in all gc_collect switches alongside def_env_val.
    proc: Value = NIL,
    // Guards captureLocalsOnTransformer/computeBoundFreeRefs (compiler_macro.zig's
    // finalizeTransformer) against running twice on the same object: a
    // transformer resolved via a bare-keyword alias or begin-wrapped helper
    // reference (SRFI 147) can be the exact same Value returned to two or
    // more different binding sites, and each of those functions allocates
    // and unconditionally overwrites a slice field with no free of the old
    // one -- a second call on top of the first leaks the first allocation.
    finalized: bool = false,
    // Guards compileLetSyntax's R7RS 4.3.1 sibling-suppression snapshot
    // (let_syntax_peer_names/vals below) the same way `finalized` guards
    // captured_locals/bound_free_refs, and for a stronger reason than just
    // avoiding a leak: recomputing it a second time is not merely
    // redundant, it's WRONG. A transformer's free references must resolve
    // according to its own true point of origin (the one let-syntax/
    // letrec-syntax/define-syntax that actually created it), not whatever
    // OTHER, unrelated let-syntax form later happens to alias it by name
    // or by begin-wrapped reference (SRFI 147) -- confirmed via direct
    // reproduction: redefining an outer binding between two such forms
    // changed a shared helper's already-resolved answer, proving a second
    // computation silently overwrote the first with a different, wrong
    // snapshot rather than just wasting an allocation.
    peers_computed: bool = false,
    captured_locals: []CapturedLocal = &.{},
    // The defining library's lib_env (or a restricted env), for def-env-scoped
    // free-reference resolution. INVARIANT (#1962), identical to `Function.env`:
    // no GC switch traces this raw pointer -- it is GC-reachable ONLY through
    // the paired `def_env_val` below, EXCEPT when it is one of the VM-rooted
    // library registries (`markVmRoots`), in which case `def_env_val` may be NIL
    // because the registry keeps the bindings alive. Construction sites must
    // satisfy this; `globals.assertEnvMapInvariant` checks it in debug/test.
    def_env: ?*std.StringHashMap(Value) = null,
    def_env_val: Value = NIL,
    /// Canonical name (e.g. "demo.srmac") of the library def_env belongs to,
    /// set alongside it in compileDefineSyntax. Null exactly when def_env is
    /// null (a top-level/REPL-defined macro, never a library one). Lets
    /// renameForHygiene build a def_env_binding_prefix-marked reference that
    /// survives being imported anywhere (#1812).
    def_lib_name: ?[]const u8 = null,
    custom_ellipsis: ?[]const u8 = null,
    literal_bound: []u32 = &.{},
    let_syntax_peer_names: [][]const u8 = &.{},
    let_syntax_peer_vals: []Value = &.{},
    bound_free_refs: [][]const u8 = &.{},
    // Template free references that were lexically bound (compiler locals,
    // including enclosing frames) at macro definition time. renameForHygiene
    // keeps these unrenamed when the use site cannot reach them via the
    // captured-locals slot alias (i.e. the reference crosses a lambda frame),
    // so they resolve through the normal local/upvalue path instead.
    def_site_local_refs: [][]const u8 = &.{},
};
