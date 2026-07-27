const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// Minimal portable reader-writer spinlock (Zig 0.16 has no blocking
/// std.Thread.RwLock; std.Io.RwLock needs an Io instance). Writer-preferring:
/// once a writer sets its bit, new readers spin, existing readers drain, then
/// the writer runs. Critical sections here are single hash-map operations, so
/// spinning is bounded and short. Not reentrant — never nest acquisitions.
pub const GlobalsRwLock = struct {
    /// Bit 31 = writer holds/wants the lock; low 31 bits = active readers.
    state: std.atomic.Value(u32) = .init(0),

    const WRITER: u32 = 0x8000_0000;

    pub fn lockShared(self: *GlobalsRwLock) void {
        while (true) {
            const s = self.state.load(.monotonic);
            if (s & WRITER == 0) {
                if (self.state.cmpxchgWeak(s, s + 1, .acquire, .monotonic) == null) return;
            }
            std.atomic.spinLoopHint();
        }
    }

    pub fn unlockShared(self: *GlobalsRwLock) void {
        _ = self.state.fetchSub(1, .release);
    }

    pub fn lock(self: *GlobalsRwLock) void {
        while (true) {
            const s = self.state.load(.monotonic);
            if (s & WRITER == 0) {
                if (self.state.cmpxchgWeak(s, s | WRITER, .acquire, .monotonic) == null) break;
            }
            std.atomic.spinLoopHint();
        }
        while (self.state.load(.acquire) != WRITER) std.atomic.spinLoopHint();
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

/// If `name` carries `base_binding_prefix`, return the unprefixed suffix;
/// otherwise return null.
pub fn stripBaseBindingPrefix(name: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, name, base_binding_prefix)) return null;
    return name[base_binding_prefix.len..];
}
