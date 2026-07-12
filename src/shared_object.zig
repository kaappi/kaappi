const std = @import("std");

/// KEP-0002 §1: the generic shared-object protocol. A shared object is a
/// refcounted structure allocated from the process-global allocator
/// (std.heap.c_allocator), outside every GC heap, so it can outlive any
/// single thread's VM/GC. `SharedChannel` (src/shared_channel.zig) is the
/// first instance; KEP-0003's SharedBuffer is the declared second.
///
/// Every reference to a shared object is a counted "stub" -- an ordinary
/// GC-managed heap object owning exactly one refcount. `init` accounts for
/// the promoting/creating stub (refcount 1); `retain`/`release` are the
/// +1/-1 for every other stub created/freed afterward. The final `release`
/// runs the type's own destroy hook, which may recursively release other
/// shared objects' refcounts (e.g. a drained envelope releasing the stubs
/// it contains).
pub const Header = struct {
    refcount: std.atomic.Value(u32),
    destroyFn: *const fn (*Header) void,
};

/// Leak-check hook (KEP-0002 §1 rule 5 / §7): every live shared object not
/// yet destroyed. The unit suite asserts this returns to its pre-test
/// baseline once every handle a test took has been released -- an
/// undestroyed shared object at that point is a bug.
var live_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);

/// Initialize a freshly allocated header with refcount 1 -- the promoting
/// or creating stub is the first counted reference.
pub fn init(header: *Header, destroyFn: *const fn (*Header) void) void {
    header.* = .{
        .refcount = std.atomic.Value(u32).init(1),
        .destroyFn = destroyFn,
    };
    _ = live_count.fetchAdd(1, .monotonic);
}

/// +1: a new stub was created (deepCopy's alias arm, including a stub
/// allocated inside an envelope heap).
pub fn retain(header: *Header) void {
    // Incrementing from a location that already holds a valid reference
    // needs no synchronization with any concurrent releaser (same
    // justification as Arc::clone / intrusive_ptr_add_ref).
    _ = header.refcount.fetchAdd(1, .monotonic);
}

/// -1: a stub was freed (a heap collection, a child heap torn down at
/// thread-join!, an envelope.deinit()). Runs the type's destroy hook
/// exactly once, at the transition to zero.
pub fn release(header: *Header) void {
    // acq_rel: the decrement that takes refcount to zero must happen-after
    // every prior retain/release on other threads (so destroyFn never runs
    // while another thread is still mid-retain), and destroyFn's own reads
    // of the object must happen-after all of those releases.
    if (header.refcount.fetchSub(1, .acq_rel) == 1) {
        header.destroyFn(header);
        _ = live_count.fetchSub(1, .monotonic);
    }
}

pub fn liveCount() usize {
    return live_count.load(.monotonic);
}
