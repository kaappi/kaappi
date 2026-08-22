//! WebAssembly C-ABI surface for bounded-step execution (kaappi#2283).
//!
//! Compiled only into the wasm32-wasi build (imported from `main.zig` under
//! `is_wasm`). It wraps a single VM + GC + `Stepper` in module globals and
//! exports a small C API a host — the browser playground — drives instead of
//! the blocking WASI `_start`:
//!
//!   1. `kaappi_step_alloc(len)`  → pointer the host writes the program into
//!   2. `kaappi_step_setup(p,len)`→ fresh VM, compile-as-you-go stepper armed
//!   3. `kaappi_step_run(budget)` → run ≤budget instructions, hand control back
//!   4. `kaappi_step_stop()`      → request cooperative termination
//!   5. `kaappi_step_reset()`     → tear down, ready for the next program
//!
//! stdout/stderr stream through the host's WASI `fd_write` as each `display`/
//! `write` runs (fd 1/2 are unbuffered — primitives_io.isBufferedFdPort), so a
//! host drains output between chunks without any extra flush. The batch WASI
//! `_start` path (main.zig) is untouched; this is purely additive.

const std = @import("std");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const vm_step = @import("vm_step.zig");
const Stepper = vm_step.Stepper;

const allocator = std.heap.wasm_allocator;

/// `kaappi_step_run` return codes.
const RUN_RUNNING: i32 = 0; // budget spent (or a form paused); call again
const RUN_DONE: i32 = 1; // program finished, no error
const RUN_ERROR: i32 = 2; // program finished, but some form errored
const RUN_NOT_READY: i32 = -1; // no active program (setup not called)

/// `kaappi_step_setup` return codes.
const SETUP_OK: i32 = 0;
const SETUP_VM_INIT_FAILED: i32 = -1;
const SETUP_BAD_ARGS: i32 = -2;

// All three are heap-allocated so their addresses stay stable: `vm_instance`
// and the GC root marker reach the VM by address, and the Stepper's stop flag
// is wired into `vm.terminate_flag` by address.
var g_gc: ?*memory.GC = null;
var g_vm: ?*vm_mod.VM = null;
var g_stepper: ?*Stepper = null;
/// The active program's source, owned here and borrowed by the live Stepper.
var g_active_source: ?[]u8 = null;
/// A buffer handed out by `kaappi_step_alloc` and not yet consumed by `setup`.
/// Kept distinct from `g_active_source` so `setup` can tear the previous
/// program down (freeing *its* source) without touching the incoming one.
var g_incoming_source: ?[]u8 = null;

/// Allocate `len` bytes in linear memory for the host to write program source
/// into, then pass back to `kaappi_step_setup`. Returns null on OOM. The buffer
/// is owned by the runtime from here on and is freed by setup/reset.
pub export fn kaappi_step_alloc(len: usize) callconv(.c) ?[*]u8 {
    const buf = allocator.alloc(u8, len) catch return null;
    // A prior alloc that was never consumed by setup would leak; free it.
    if (g_incoming_source) |s| allocator.free(s);
    g_incoming_source = buf;
    return buf.ptr;
}

/// Compile-as-you-go setup over the source at `ptr[0..len]` (typically the
/// buffer `kaappi_step_alloc` returned; any live linear-memory span works — its
/// bytes are borrowed until reset). Builds a fresh VM so each program starts
/// clean, discarding any previous one. Returns SETUP_OK or a negative code.
pub export fn kaappi_step_setup(ptr: [*]const u8, len: usize) callconv(.c) i32 {
    teardown();

    const gc = allocator.create(memory.GC) catch return SETUP_VM_INIT_FAILED;
    gc.* = memory.GC.init(allocator);
    memory.setGCInstance(gc);

    const vm = allocator.create(vm_mod.VM) catch {
        gc.deinit();
        allocator.destroy(gc);
        return SETUP_VM_INIT_FAILED;
    };
    vm.* = vm_mod.VM.init(gc) catch {
        gc.deinit();
        allocator.destroy(gc);
        allocator.destroy(vm);
        return SETUP_VM_INIT_FAILED;
    };
    vm.heap_owned = true;
    vm_mod.setVMInstance(vm);

    if (setupLibraries(vm)) |_| {} else |_| {
        vm.deinit();
        gc.deinit();
        allocator.destroy(gc);
        return SETUP_VM_INIT_FAILED;
    }

    // If the source did not come from kaappi_step_alloc, copy it so the Stepper
    // borrows a buffer with a lifetime we control.
    const src = ownedSource(ptr, len) catch {
        vm.deinit();
        gc.deinit();
        allocator.destroy(gc);
        return SETUP_BAD_ARGS;
    };

    const stepper = allocator.create(Stepper) catch {
        vm.deinit();
        gc.deinit();
        allocator.destroy(gc);
        return SETUP_VM_INIT_FAILED;
    };
    stepper.init(vm, src, "<playground>");

    g_gc = gc;
    g_vm = vm;
    g_stepper = stepper;
    g_active_source = src;
    return SETUP_OK;
}

/// Run at most `budget` bytecode instructions of the active program, then hand
/// control back. Returns RUN_RUNNING (call again), RUN_DONE, or RUN_ERROR.
pub export fn kaappi_step_run(budget: u32) callconv(.c) i32 {
    const stepper = g_stepper orelse return RUN_NOT_READY;
    return switch (stepper.step(budget)) {
        .running => RUN_RUNNING,
        .done => if (stepper.had_error) RUN_ERROR else RUN_DONE,
    };
}

/// Request cooperative termination of the running program. The next
/// `kaappi_step_run` observes the flag at the dispatch safepoint, unwinds the
/// current form (running its dynamic-wind after-thunks), and returns RUN_DONE.
pub export fn kaappi_step_stop() callconv(.c) void {
    if (g_stepper) |s| s.requestStop();
}

/// Tear down the active program and VM, and release any unconsumed
/// `kaappi_step_alloc` buffer. Safe to call at any time; a subsequent
/// `kaappi_step_setup` starts fresh.
pub export fn kaappi_step_reset() callconv(.c) void {
    teardown();
    if (g_incoming_source) |s| {
        allocator.free(s);
        g_incoming_source = null;
    }
}

fn setupLibraries(vm: *vm_mod.VM) !void {
    try primitives.registerAll(vm);
    try vm_mod.vm_bootstrap.install(vm);
    try library.registerStandardLibraries(&vm.libraries, vm.globals);
}

/// Take ownership of the caller's source span. When it is exactly the buffer
/// `kaappi_step_alloc` handed out, adopt it in place (host wrote into it);
/// otherwise copy the span so the Stepper borrows a lifetime we control. Either
/// way the incoming-buffer slot is cleared — ownership has moved to the caller.
fn ownedSource(ptr: [*]const u8, len: usize) ![]u8 {
    if (g_incoming_source) |s| {
        if (s.ptr == ptr and s.len == len) {
            g_incoming_source = null;
            return s;
        }
    }
    const copy = try allocator.dupe(u8, ptr[0..len]);
    if (g_incoming_source) |s| {
        allocator.free(s);
        g_incoming_source = null;
    }
    return copy;
}

/// Tear down the active program and VM. Does NOT touch `g_incoming_source`: a
/// buffer the host just allocated for the *next* program must survive here, so
/// `setup` can dismantle the previous program before consuming it.
fn teardown() void {
    if (g_stepper) |s| {
        s.deinit();
        allocator.destroy(s);
        g_stepper = null;
    }
    if (g_vm) |v| {
        v.deinit(); // heap_owned: also destroys the VM struct
        g_vm = null;
    }
    if (g_gc) |gc| {
        gc.deinit();
        allocator.destroy(gc);
        g_gc = null;
    }
    if (g_active_source) |s| {
        allocator.free(s);
        g_active_source = null;
    }
}
