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
