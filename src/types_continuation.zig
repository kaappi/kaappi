const build_options = @import("build_options");
const types = @import("types.zig");
const Value = types.Value;
const Object = types.Object;
const Closure = types.Closure;
const NativeFn = types.NativeFn;

// ---------------------------------------------------------------------------
// Continuation types (R7RS 6.10)
// ---------------------------------------------------------------------------

/// Saved call frame for continuation capture.
pub const SavedFrame = struct {
    closure: ?*Closure,
    native: ?*NativeFn,
    code: []const u8,
    ip: usize,
    base: u32,
    dst: u16,
    saved_wind_count: u16,
    // Mirrors CallFrame.returns_to_native (see vm.zig): the frame's result
    // belongs to a re-entrant native Zig caller, so returning it into a
    // caller frame register after that native has died is an error.
    returns_to_native: bool,
    // Frame birth id (see CallFrame.seq in vm.zig). The u64 also forces
    // 8-byte alignment on wasm32, keeping the struct size a multiple of
    // @sizeOf(Value) without manual padding.
    seq: u64,
};

/// Saved exception handler for continuation capture. Deliberately the *same*
/// type as the live `ExceptionHandler` so `captureContinuation` can hand the
/// live handler stack straight to `allocContinuation` — no per-capture
/// conversion buffer on a path that runs once per call/cc.
pub const SavedHandler = ExceptionHandler;

/// Saved dynamic-wind record.
pub const WindRecord = struct {
    before: Value,
    after: Value,
};

// --- Live execution frame types (used by VM, fiber, and GC) ---

pub const INITIAL_FRAME_CAPACITY: usize = build_options.max_frames;
pub const INITIAL_REGISTER_CAPACITY: usize = build_options.max_registers;
pub const MAX_FRAME_LIMIT: usize = 32768;
pub const MAX_REGISTER_LIMIT: usize = 65536;
pub const MAX_HANDLERS = 64;
pub const MAX_WINDS = 64;

/// Per-fiber initial storage (KEP-0001 Phase 2, resolved question 5) —
/// deliberately much smaller than the VM's own INITIAL_REGISTER_CAPACITY/
/// INITIAL_FRAME_CAPACITY. Fibers grow their own arrays geometrically as
/// needed (see FiberScheduler.saveCurrentFiber); most fibers never touch
/// more than a handful of frames, so starting small keeps per-fiber
/// preallocation cheap even with thousands of concurrently-live fibers.
pub const INITIAL_FIBER_REGISTER_CAPACITY: usize = 256;
pub const INITIAL_FIBER_FRAME_CAPACITY: usize = 32;

pub const ExceptionHandler = struct {
    handler: Value,
    frame_count: usize,
    // SRFI 248 (with-unwind-handler): when true, raise/raise-continuable
    // invoke this handler in place *without* popping it, so a continuation
    // captured during handling snapshots the handler and a later resume
    // re-arms it. Ordinary (scheme base) handlers leave this false.
    sticky: bool = false,
};

pub const CallFrame = struct {
    closure: ?*Closure,
    native: ?*NativeFn = null,
    code: []const u8,
    ip: usize,
    base: u32,
    dst: u16,
    saved_wind_count: u16 = 0,
    returns_to_native: bool = false,
    seq: u64 = 0,

    pub fn frameWindow(self: CallFrame) usize {
        return if (self.closure) |cls| blk: {
            const lc = cls.func.locals_count;
            break :blk if (lc == 0) 256 else @as(usize, lc);
        } else 256;
    }
};

/// A captured continuation (R7RS call/cc).
/// Contains a snapshot of the VM state at the point of capture.
pub const Continuation = struct {
    header: Object,
    registers: []Value,
    frames: []SavedFrame,
    frame_count: usize,
    handlers: []SavedHandler,
    handler_count: usize,
    wind_records: []WindRecord,
    wind_count: usize,
    dst_reg: u16, // register offset within frame where result goes
    dst_base: u32, // base register of the return frame
    // Single backing allocation holding registers, frames, handlers and winds
    // contiguously. The four slices above are views into this buffer; it is
    // freed as one block on sweep. Empty for escape continuations.
    backing: []Value,
    // --- Escape continuations (call/ec) ---
    // An escape continuation captures no snapshot: it only records the stack
    // depths to unwind *back* to (the call/ec point is still live on the stack).
    // When is_escape is true the four slices above are empty and frame_count/
    // handler_count/wind_count are 0 (so GC mark loops are no-ops); the unwind
    // targets live in the target_* fields below. `valid` is cleared once the
    // call/ec call returns, after which invoking the continuation is an error.
    is_escape: bool = false,
    valid: bool = true,
    target_frame_count: usize = 0,
    target_wind_count: usize = 0,
    target_handler_count: usize = 0,
};

/// Multiple return values (R7RS values/call-with-values).
pub const MultipleValues = struct {
    header: Object,
    values: []Value,
};
