const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const types = @import("types.zig");
const Value = types.Value;

/// Minimal portable reader-writer spinlock (Zig 0.16 has no blocking
/// std.Thread.RwLock; std.Io.RwLock needs an Io instance). Writer-preferring:
/// once a writer sets its bit, new readers spin, existing readers drain, then
/// the writer runs. Critical sections here are single hash-map operations, so
/// contention is short -- but a holder the kernel preempts mid-operation is
/// not, and waiters back off through `platform.spinBackoff` (spin, yield,
/// then sleep) rather than spinning it into starvation (kaappi#2446). Not
/// reentrant — never nest acquisitions.
pub const GlobalsRwLock = struct {
    /// Bit 31 = writer holds/wants the lock; low 31 bits = active readers.
    state: std.atomic.Value(u32) = .init(0),

    const WRITER: u32 = 0x8000_0000;

    pub fn lockShared(self: *GlobalsRwLock) void {
        var spins: u32 = 0;
        while (true) : (spins +|= 1) {
            const s = self.state.load(.monotonic);
            if (s & WRITER == 0) {
                if (self.state.cmpxchgWeak(s, s + 1, .acquire, .monotonic) == null) return;
            }
            platform.spinBackoff(spins);
        }
    }

    pub fn unlockShared(self: *GlobalsRwLock) void {
        _ = self.state.fetchSub(1, .release);
    }

    pub fn lock(self: *GlobalsRwLock) void {
        var spins: u32 = 0;
        while (true) : (spins +|= 1) {
            const s = self.state.load(.monotonic);
            if (s & WRITER == 0) {
                if (self.state.cmpxchgWeak(s, s | WRITER, .acquire, .monotonic) == null) break;
            }
            platform.spinBackoff(spins);
        }
        var drain_spins: u32 = 0;
        while (self.state.load(.acquire) != WRITER) : (drain_spins +|= 1) platform.spinBackoff(drain_spins);
    }

    pub fn unlock(self: *GlobalsRwLock) void {
        self.state.store(0, .release);
    }
};

/// Thread-local snapshot of the VM's globals state, set by setVMInstance()
/// and used by the compiler/expander for thread-safe globals access without
/// importing vm.zig.
pub const GlobalsContext = struct {
    globals: *std.StringHashMap(Value),
    globals_lock: *GlobalsRwLock,
    owns_globals: bool,

    pub fn lockShared(self: GlobalsContext) void {
        if (!self.owns_globals) self.globals_lock.lockShared();
    }

    pub fn unlockShared(self: GlobalsContext) void {
        if (!self.owns_globals) self.globals_lock.unlockShared();
    }
};

pub threadlocal var globals_ctx: ?GlobalsContext = null;

pub fn setGlobalsContext(ctx: GlobalsContext) void {
    globals_ctx = ctx;
}

pub fn clearGlobalsContext() void {
    globals_ctx = null;
}

/// Take the exclusive globals lock if `map` is the current thread's shared
/// globals map, for compile-time code that only holds a map pointer (body
/// prescans, macro-expansion temp globals). Returns the lock to hand to
/// releaseGlobalsWrite, or null when no locking applies: `map` is a library
/// env, or no VM is registered on this thread yet (startup — no child
/// threads can exist before the first execute()).
pub fn acquireGlobalsWrite(map: *const std.StringHashMap(Value)) ?*GlobalsRwLock {
    const ctx = globals_ctx orelse return null;
    if (@as(*const std.StringHashMap(Value), ctx.globals) != map) return null;
    ctx.globals_lock.lock();
    return ctx.globals_lock;
}

pub fn releaseGlobalsWrite(lock_arg: ?*GlobalsRwLock) void {
    if (lock_arg) |l| l.unlock();
}

/// Shared-lock counterpart of acquireGlobalsWrite for read-only compile-time
/// access. No-ops on the owner thread (its reads cannot race its own writes).
pub fn acquireGlobalsRead(map: *const std.StringHashMap(Value)) ?*GlobalsRwLock {
    const ctx = globals_ctx orelse return null;
    if (ctx.owns_globals) return null;
    if (@as(*const std.StringHashMap(Value), ctx.globals) != map) return null;
    ctx.globals_lock.lockShared();
    return ctx.globals_lock;
}

pub fn releaseGlobalsRead(lock_arg: ?*GlobalsRwLock) void {
    if (lock_arg) |l| l.unlockShared();
}

/// Callback for cond-expand library existence checks. Registered by the VM
/// so the compiler can check library availability without importing vm.zig.
pub const LibraryExistsFn = *const fn (lib_name: []const u8, lib_name_list: Value) bool;
pub var library_exists_checker: ?LibraryExistsFn = null;

pub fn libraryExists(lib_name: []const u8, lib_name_list: Value) bool {
    if (library_exists_checker) |checker| return checker(lib_name, lib_name_list);
    return false;
}

/// Callback for cond-expand `srfi-<n>` feature-identifier checks (#1649).
/// Registered by the VM so the compiler's evalFeatureReq can answer these
/// without importing vm.zig, exactly as library_exists_checker does for the
/// `(library ...)` form. Returns false for any name that is not a supported
/// `srfi-<n>` feature id.
pub const SrfiFeatureFn = *const fn (name: []const u8) bool;
pub var srfi_feature_checker: ?SrfiFeatureFn = null;

pub fn srfiFeatureAvailable(name: []const u8) bool {
    if (srfi_feature_checker) |checker| return checker(name);
    return false;
}

/// Callback resolving `name` to its pristine `(scheme base)` binding — the
/// value captured when the VM registered its standard libraries, before any
/// user or library code could have run. Registered by the VM so compiler-
/// synthesized code can reference the true original procedure instead of
/// whatever `name` currently resolves to in vm.globals, which ordinary
/// top-level `define`s (and library-level redefinitions, e.g. SRFI 101
/// replacing `list`) are free to overwrite. Used by let-values/let*-values's
/// internal desugaring, which otherwise resolves its own hard-coded
/// references to `list`/`apply`/`call-with-values` exactly as if the user
/// had written those names at the use site (#1715).
pub const BaseBindingFn = *const fn (name: []const u8) ?Value;
pub var base_binding_lookup: ?BaseBindingFn = null;

pub fn lookupBaseBinding(name: []const u8) ?Value {
    if (base_binding_lookup) |lookup| return lookup(name);
    return null;
}

/// SRFI 211 (procedural macros): evaluate a datum in the VM's global
/// environment at macro-expansion time — the RHS of an
/// `(er-macro-transformer <expr>)` / `(lisp-transformer <expr>)`
/// transformer spec, or a `define-property` value expression. Registered
/// by vm.setVMInstance, mirroring library_exists_checker: the compiler and
/// expander cannot import vm.zig. The global (not lexical) environment is
/// deliberate phase separation: transformer code cannot see enclosing
/// runtime locals, which have no values at expansion time.
pub const EvalDatumFn = *const fn (expr: Value) anyerror!Value;
pub var eval_datum_for_macro: ?EvalDatumFn = null;

/// SRFI 211: invoke a Scheme procedure from inside the expander — the
/// procedural transformer call itself, and the SRFI 213 capture-lookup
/// re-entry. Registered by vm.setVMInstance alongside eval_datum_for_macro.
pub const CallProcFn = *const fn (proc: Value, args: []const Value) anyerror!Value;
pub var call_proc_for_macro: ?CallProcFn = null;

/// #1846: retrieve the VM's last recorded error detail -- the message and
/// irritants of whatever Scheme-level condition a procedural macro
/// transformer raised (via call_proc_for_macro above), or the type-error text
/// of a failing primitive call inside it (e.g. `(car 7)`). Registered by
/// vm.setVMInstance alongside call_proc_for_macro. Read by
/// compiler_macro.zig's error.TransformerFailed arms to populate
/// compiler.syntax_error_detail -- the same channel `syntax-error` already
/// reports through -- so the real condition reaches the user instead of a
/// bare "invalid syntax".
pub const ErrorDetailFn = *const fn () []const u8;
pub var error_detail_for_macro: ?ErrorDetailFn = null;

/// #2403: the write side of error_detail_for_macro. The expander's own
/// native procedures (`rename`) reject inputs the way a primitive would --
/// with a precise message in the VM's error detail -- but cannot call
/// vm.setErrorDetail directly, so they go through this registration exactly
/// as its read-side sibling. When no VM is registered the call is a no-op
/// and mapNativeError's fallback text reports the failure instead.
pub const SetErrorDetailFn = *const fn (msg: []const u8) void;
pub var set_error_detail_for_macro: ?SetErrorDetailFn = null;

/// SRFI 213 (identifier properties): set/get on the VM-owned property
/// table, keyed by the effective (hygiene-stripped) names of the property's
/// identifier and key. Registered by vm.setVMInstance; the table's Values
/// are GC roots via markVMRoots.
pub const SyntaxPropertySetFn = *const fn (id: []const u8, key: []const u8, val: Value) anyerror!void;
pub var syntax_property_set: ?SyntaxPropertySetFn = null;
pub const SyntaxPropertyGetFn = *const fn (id: []const u8, key: []const u8) ?Value;
pub var syntax_property_get: ?SyntaxPropertyGetFn = null;

/// Marks a compiler-synthesized global-variable reference as one that must
/// resolve through `lookupBaseBinding` instead of vm.globals (#1715).
/// get_global/call_global (vm_dispatch.zig) check for this prefix before
/// doing an ordinary by-name lookup, and strip it via `stripBaseBindingPrefix`
/// when found. Re-exported from types.zig, where it also lets
/// isContinuationBarrier recognize a prefixed name as equivalent to its bare
/// counterpart (types.zig can't depend on this module, which depends on it).
///
/// This has to be a naming convention on an ordinary symbol constant, not a
/// resolved value embedded directly in the constant pool: the .sbc bytecode
/// cache's writeConstant has no tag for procedure values, and silently
/// downgrades anything it doesn't recognize to `'()` (bytecode_file_write.zig)
/// -- so a pre-resolved NativeFn constant would read back as nil after a
/// cache round-trip. A symbol is the one constant kind the format already
/// preserves exactly, so resolution has to stay a runtime lookup, done fresh
/// every time get_global/call_global executes regardless of whether the
/// bytecode was just compiled or loaded from cache.
pub const base_binding_prefix = types.base_binding_prefix;

/// Build the marked symbol name for `name` (see `base_binding_prefix`).
/// Writes into `buf` and returns the written slice; `buf` must be at least
/// `base_binding_prefix.len + name.len` bytes (callers use a fixed buffer
/// sized for the short, fixed set of names this is used for).
pub fn baseBindingSymbolName(buf: []u8, name: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}{s}", .{ base_binding_prefix, name }) catch name;
}

/// Allocate the `base_binding_prefix`-marked symbol for `name`: a
/// compiler-synthesized reference that must always mean the standard
/// procedure, or the internal primitive (#1856), rather than whatever the
/// program being compiled has bound that name to. Returns the plain symbol
/// unprefixed only if the name is longer than the fixed buffer, matching
/// `baseBindingSymbolName`'s own overflow behavior.
///
/// Lives here rather than on `Compiler` (which has
/// `trueBuiltinRefOrSymbol`, a thin wrapper over this) so `vm_records.zig`'s
/// `define-record-type` desugarer can use it from its `VMError` paths too.
pub fn baseBindingSymbol(gc: *@import("memory.zig").GC, name: []const u8) !Value {
    var buf: [96]u8 = undefined;
    return gc.allocSymbol(baseBindingSymbolName(&buf, name));
}

/// If `name` carries `base_binding_prefix`, return the unprefixed suffix;
/// otherwise return null.
pub fn stripBaseBindingPrefix(name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, name, base_binding_prefix)) return null;
    return name[base_binding_prefix.len..];
}

/// Callback returning the canonical name of the library currently being
/// compiled (vm.loading_library_name, set by handleDefineLibrary for the
/// whole duration of that library's declaration processing, including any
/// define-syntax within it) -- null outside library compilation. Registered
/// by the VM so compiler_macro.compileDefineSyntax can stamp a transformer's
/// def_lib_name without the compiler importing vm.zig (#1812).
pub const CurrentLibNameFn = *const fn () ?[]const u8;
pub var current_lib_name_lookup: ?CurrentLibNameFn = null;

pub fn currentLibName() ?[]const u8 {
    if (current_lib_name_lookup) |lookup| return lookup();
    return null;
}

/// Callback resolving `origname` in the library named `libname`'s own
/// lib_env -- the value bound there when that library finished loading,
/// immune to whatever the use site's vm.globals does with the same name.
/// Registered by the VM (mirrors base_binding_lookup, generalized from the
/// one well-known `(scheme base)` library to any library a macro was
/// defined in). Used by get_global/call_global/lookupGlobalLocked
/// (vm_dispatch.zig) to resolve a def_env_binding_prefix-marked name (#1812).
pub const DefEnvBindingFn = *const fn (libname: []const u8, origname: []const u8) ?Value;
pub var def_env_binding_lookup: ?DefEnvBindingFn = null;

pub fn lookupDefEnvBinding(libname: []const u8, origname: []const u8) ?Value {
    if (def_env_binding_lookup) |lookup| return lookup(libname, origname);
    return null;
}

/// Callback storing `val` into the library named `libname`'s own lib_env
/// binding `origname`, for a template `(set! <def-env-free-ref> ...)` (a
/// macro's expansion mutating a library-internal variable it references).
/// Returns whether the binding existed to be set. Registered by the VM,
/// mirroring lookupDefEnvBinding's shape. Used by set_global (vm_dispatch.zig)
/// to resolve a def_env_binding_prefix-marked assignment target (#1812).
pub const DefEnvBindingSetFn = *const fn (libname: []const u8, origname: []const u8, val: Value) bool;
pub var def_env_binding_set: ?DefEnvBindingSetFn = null;

pub fn setDefEnvBinding(libname: []const u8, origname: []const u8, val: Value) bool {
    if (def_env_binding_set) |setter| return setter(libname, origname, val);
    return false;
}

/// Callback reporting whether a `*StringHashMap(Value)` is one of the VM's
/// GC-rooted environment registries -- the maps `vm.markVmRoots` traces
/// unconditionally on every collection (each registered library's `lib_env`,
/// a `retired_env` of a replaced library, an in-flight `pending_lib_env`, or
/// the library env currently being compiled, `current_lib_env`). Registered by
/// the VM so the compiler can enforce the `Function.env` / `Transformer.def_env`
/// invariant without importing vm.zig -- the same indirection #1812's
/// `current_lib_name_lookup` uses (#1962).
pub const EnvMapRootedFn = *const fn (map: *std.StringHashMap(Value)) bool;
pub var env_map_rooted_lookup: ?EnvMapRootedFn = null;

/// The invariant every `Function.env` / `Transformer.def_env` must satisfy:
/// the raw map pointer is GC-reachable ONLY through its paired traced Value
/// (`env_val` / `def_env_val`) -- EXCEPT when the map is one of the VM-rooted
/// library registries (see `env_map_rooted_lookup`), in which case the paired
/// value is allowed to be NIL because the registry keeps every binding alive
/// independently. Returns true when the pairing is sound. Holds vacuously when
/// no VM has registered the callback (a bare-GC unit test), since then no
/// collection can observe the field either (#1962).
pub fn envMapInvariantHolds(map: *std.StringHashMap(Value), paired_val: Value) bool {
    if (paired_val != types.NIL) return true; // route 1: paired, traced value
    const lookup = env_map_rooted_lookup orelse return true;
    return lookup(map); // route 2: a VM-rooted registry map
}

/// Debug/test-only guard for `envMapInvariantHolds`. Compiled out entirely in
/// release builds (ReleaseSafe/ReleaseFast), so it never changes shipped
/// behavior or costs a registry scan there; in Debug and test builds it fires
/// deterministically the moment a future call site mints a `Function`/
/// `Transformer` holding a private map with a NIL paired value -- the exact
/// latent hazard #1962 was filed for, which would otherwise silently lose
/// every binding at the next collection and look identical to the safe sites.
pub fn assertEnvMapInvariant(map: *std.StringHashMap(Value), paired_val: Value) void {
    if (comptime !(builtin.mode == .Debug or builtin.is_test)) return;
    std.debug.assert(envMapInvariantHolds(map, paired_val));
}

pub const def_env_binding_prefix = types.def_env_binding_prefix;
pub const def_env_binding_sep = types.def_env_binding_sep;

/// Build the `def_env_binding_prefix`-marked symbol name for `libname`'s
/// binding `origname` (see `def_env_binding_prefix`). Writes into `buf` and
/// returns the written slice; falls back to the bare `origname` if `buf` is
/// too small (matching `baseBindingSymbolName`'s own overflow behavior) --
/// silently skipping the protection for a pathologically long library/
/// binding name is preferable to erroring out of compilation entirely.
pub fn buildDefEnvBindingSymbolName(buf: []u8, libname: []const u8, origname: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}{s}{s}{s}", .{ def_env_binding_prefix, libname, def_env_binding_sep, origname }) catch origname;
}

/// If `name` carries `def_env_binding_prefix`, split off the embedded
/// library name and original binding name; otherwise return null.
pub fn parseDefEnvBindingSymbolName(name: []const u8) ?struct { libname: []const u8, origname: []const u8 } {
    if (!std.mem.startsWith(u8, name, def_env_binding_prefix)) return null;
    const rest = name[def_env_binding_prefix.len..];
    const sep = std.mem.indexOf(u8, rest, def_env_binding_sep) orelse return null;
    return .{ .libname = rest[0..sep], .origname = rest[sep + def_env_binding_sep.len ..] };
}
