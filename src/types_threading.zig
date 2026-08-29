const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;

pub const Channel = struct {
    header: Object,
    head: Value,
    tail: Value,
    /// Local queue length (KEP-0002 §6) -- O(1) capacity admission checks
    /// instead of walking the head/tail pair list. Unused once `shared` is
    /// set (the SharedChannel tracks its own queue_len).
    queue_len: u32 = 0,
    /// null = unbounded (today's semantics). 0 = rendezvous (KEP-0002 §6
    /// as amended, kaappi#1601): send admission is bounded by `rv_demand`
    /// instead of a static capacity. Local-representation only; carried
    /// into the SharedChannel by promoteChannel on promotion.
    capacity: ?u32 = null,
    /// Rendezvous demand (capacity == 0 only): the number of receivers
    /// currently committed to this channel — each parked receive holds one
    /// demand token (Fiber.rv_demand_on), acquired at its park decision and
    /// released on every terminal exit. The send-admission bound for a
    /// rendezvous channel. Meaningless (always 0) for capacity != 0.
    rv_demand: u32 = 0,
    /// KEP-0002 §6: end-of-stream. Local-representation only; carried into
    /// the SharedChannel by promoteChannel on promotion.
    closed: bool = false,
    /// Set exactly once, by the owning thread (KEP-0002 §2). Actually
    /// `*shared_channel.SharedChannel` once promoted; kept opaque so the
    /// types layer doesn't import a feature module, matching the
    /// FfiLibrary.handle / DirectoryObject.dir precedent for external
    /// handles.
    shared: ?*anyopaque = null,
};

// ---------------------------------------------------------------------------
// SRFI-18 types (mutex, condition variable, time)
// ---------------------------------------------------------------------------

pub const Mutex = struct {
    header: Object,
    name: Value,
    /// The fiber that owns the mutex, used for abandonment tracking
    /// (abandonFiberMutexes compares identity on this). For an OS-thread
    /// child this is the child-heap current fiber -- NOT a value the
    /// parent's GC owns, so mutex-state must not hand it out.
    owner: Value,
    /// The owning thread handle as the caller knows it: the fiber value
    /// make-thread returned for an OS-thread child (parent heap), or the
    /// owner fiber itself for a local/main thread. What mutex-state
    /// returns for the owned state (#2125). Kept in sync with `owner` at
    /// every write site.
    owner_thread: Value = types.VOID,
    locked: bool,
    abandoned: bool,
    specific: Value,
    /// kaappi#2395: cross-OS-thread waiter registrations (actually
    /// `*reactor.NotifierList`), lazily installed by the first thread that
    /// parks on this mutex from its own scheduler and rung by every
    /// unlock/abandon so the waiter's reactor wakes instead of polling.
    /// Kept opaque so the types layer doesn't import a feature module —
    /// the `Channel.shared` precedent. Freed in freeObject's `.mutex` arm.
    cross_waiters: ?*anyopaque = null,
};

pub const ConditionVariable = struct {
    header: Object,
    name: Value,
    specific: Value,
    // Bumped (atomically) by condition-variable-signal!/-broadcast!. Each OS
    // thread runs its own independent FiberScheduler, so a waiter parked by a
    // *different* thread never observes that thread's local wakeOneCondVarWaiter/
    // wakeAllCondVarWaiters bookkeeping; re-checking this counter is how a
    // cross-thread waiter detects a signal happened (woken by the notifier
    // ring below since kaappi#2395; a 1 ms poll before that).
    signal_generation: u64 = 0,
    /// kaappi#2395: cross-OS-thread waiter registrations (actually
    /// `*reactor.NotifierList`), rung by signal!/broadcast! right after the
    /// generation bump. Same opaque-slot convention as `Mutex.cross_waiters`;
    /// freed in freeObject's `.condition_variable` arm.
    cross_waiters: ?*anyopaque = null,
};

pub const TimeType = enum(u8) {
    utc,
    tai,
    monotonic,
    duration,
};

pub const Srfi18Time = struct {
    header: Object,
    seconds: i64,
    nanoseconds: i64,
    time_type: TimeType,
};
