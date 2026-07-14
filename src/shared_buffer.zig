const std = @import("std");
const shared_object = @import("shared_object.zig");

/// KEP-0002/KEP-0003 second shared-object type (the first is SharedChannel):
/// a refcounted, immutable byte buffer allocated from the process-global
/// allocator, outside every GC heap, so it can be shared across threads and
/// outlive any single VM/GC.
///
/// Lever D of the Phase 7 elision matrix (kaappi#1472): a large bytevector
/// crossing a channel is snapshotted into one of these ONCE, then shared by
/// refcount on every subsequent hop instead of being re-copied. A GC-managed
/// bytevector "backs onto" a SharedBuffer by borrowing its `bytes` slice and
/// holding one refcount (see types.Bytevector.shared); the collector releases
/// that refcount when the bytevector is swept (gc_collect.freeObject), and the
/// buffer frees itself at the last release.
///
/// Immutable by contract: a backed bytevector that is about to be mutated first
/// copies its bytes into private storage and drops its reference
/// (GC.unshareBytevector), so no writer ever touches shared bytes. This is what
/// makes sharing safe under Scheme's copy semantics -- the receiver still has a
/// logically independent, mutable value; the copy is just deferred until (if
/// ever) it is written.
pub const SharedBuffer = struct {
    header: shared_object.Header,
    bytes: []u8,

    /// Snapshot `src` into a fresh immutable buffer, refcount 1 (the creating
    /// bytevector's reference). The one copy lever D pays.
    pub fn create(src: []const u8) !*SharedBuffer {
        const self = try std.heap.c_allocator.create(SharedBuffer);
        errdefer std.heap.c_allocator.destroy(self);
        const buf = try std.heap.c_allocator.alloc(u8, src.len);
        @memcpy(buf, src);
        self.* = .{ .header = undefined, .bytes = buf };
        shared_object.init(&self.header, destroyHook);
        return self;
    }

    /// +1: a new backing bytevector was created (deepCopy's alias arm).
    pub fn retain(self: *SharedBuffer) void {
        shared_object.retain(&self.header);
    }

    /// -1: a backing bytevector was freed or copied-on-write. Frees the buffer
    /// at zero.
    pub fn release(self: *SharedBuffer) void {
        shared_object.release(&self.header);
    }

    fn destroyHook(header: *shared_object.Header) void {
        const self: *SharedBuffer = @fieldParentPtr("header", header);
        std.heap.c_allocator.free(self.bytes);
        std.heap.c_allocator.destroy(self);
    }
};
