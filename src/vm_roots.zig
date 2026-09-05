//! GC root marking for the VM: the `root_marker` the GC calls each
//! collection, the child-thread `CollectionState` protocol that decides when
//! a VM's registers/frames are quiescent enough to mark (#1933), and the
//! `isGcRootedEnvMap` invariant check backing the compiler's untraced-env-map
//! guard (#1962).

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const memory = @import("memory.zig");

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;

/// Mark the VM's live roots during a GC cycle: the register window of every
/// active call frame, the frame closures, the exception-handler stack,
/// dynamic-wind thunks, the in-flight exception, and the global/macro tables.
///
/// Without this, a collection triggered mid-execution (e.g. while capturing a
/// continuation in a tight loop) would free objects reachable only through the
/// VM — including the closures and bytecode currently executing — leading to
/// use-after-free. Registered as the GC's `root_marker`.
pub fn markVMRoots(gc: *memory.GC) void {
    const vm = vm_mod.vm_instance orelse return;
    if (vm.gc != gc) return; // only mark the VM that owns this GC
    markVmRoots(gc, vm);
}

/// Mark every Value `vm` keeps live: the register window of every active call
/// frame, the frame closures, the exception-handler stack, dynamic-wind
/// thunks, the in-flight exception, the parameter overrides, the thread
/// handle, and — when this VM owns the shared tables — the global/macro/
/// library values. Called with the VM's OWN gc by its own markVMRoots, and
/// with the ROOT gc by markLiveChildRoots for each live child VM: in the
/// latter case the child is quiescent (stopped at a safepoint or parked, see
/// CollectionState), so reading its frames/registers races nothing, and
/// markValue's foreign-owner skip keeps the parent's collector off the
/// child's own heap objects (kaappi#1933).
pub fn markVmRoots(gc: *memory.GC, vm: *VM) void {
    for (vm.frames[0..vm.frame_count]) |f| {
        if (f.closure) |cls| gc.markValue(types.makePointer(&cls.header));
        if (f.native) |nf| gc.markValue(types.makePointer(&nf.header));
        const window = f.frameWindow();
        const end: usize = @min(@as(usize, f.base) + window, vm.registers.len);
        var r: usize = f.base;
        while (r < end) : (r += 1) gc.markValue(vm.registers[r]);
    }

    for (vm.handler_stack[0..vm.handler_count]) |h| gc.markValue(h.handler);

    for (vm.wind_stack[0..vm.wind_count]) |wr| {
        gc.markValue(wr.before);
        gc.markValue(wr.after);
    }

    if (vm.current_exception) |exc| gc.markValue(exc);
    if (vm.callback_error_value) |exc| gc.markValue(exc);
    gc.markValue(vm.continuation_value);
    gc.markValue(vm.default_random_source);
    gc.markValue(vm.default_channel_comparator);
    // Foreign (parent-heap) for a child thread, so markValue skips it; the
    // parent roots the handle. Marked here for the same reason every other
    // Value field is: a same-heap value would be kept alive by it (#2125).
    if (vm.thread_handle) |h| gc.markValue(h);

    // Only mark globals/macros when this VM owns them. Child threads
    // share the parent's maps — the parent GC keeps those values alive.
    // Marking them here would write mark bits on parent-heap objects
    // without synchronization (data race).
    if (vm.owns_globals) {
        var git = vm.globals.valueIterator();
        while (git.next()) |v| gc.markValue(v.*);
        var mit = vm.macros.valueIterator();
        while (mit.next()) |v| gc.markValue(v.*);
        var uit = vm.record_uid_registry.valueIterator();
        while (uit.next()) |v| gc.markValue(v.*);
        var spit = vm.syntax_properties.valueIterator();
        while (spit.next()) |v| gc.markValue(v.*);
    }

    var pit = vm.param_overrides.valueIterator();
    while (pit.next()) |v| gc.markValue(v.*);

    if (vm.owns_globals) {
        var lit = vm.libraries.libraries.valueIterator();
        while (lit.next()) |lib| {
            var eit = lib.exports.valueIterator();
            while (eit.next()) |v| gc.markValue(v.*);
            if (lib.lib_env) |env| {
                var eit2 = env.valueIterator();
                while (eit2.next()) |v| gc.markValue(v.*);
            }
        }
        // Envs of replaced libraries stay reachable through closures that
        // were compiled against them (#820).
        for (vm.libraries.retired_envs.items) |env| {
            var eit = env.valueIterator();
            while (eit.next()) |v| gc.markValue(v.*);
        }
        // Priors detached into the rollback journal (#2518 review of #2510):
        // from `take` until its frame commits or rolls back, a displaced
        // library lives here rather than in `libraries` — without this walk
        // a mid-load collection would sweep exactly the exports and env a
        // rollback must put back.
        for (vm.lib_rollback_regs.items) |*rec| {
            if (rec.prior) |*prior| {
                var eit = prior.exports.valueIterator();
                while (eit.next()) |v| gc.markValue(v.*);
                if (prior.lib_env) |env| {
                    var eit2 = env.valueIterator();
                    while (eit2.next()) |v| gc.markValue(v.*);
                }
            }
        }
        // The pristine `.internal` primitives (#1856): only compiler-
        // synthesized references reach them, so a user `define` of the same
        // name is all it takes for globals to stop holding them.
        var iit = vm.libraries.internal_bindings.valueIterator();
        while (iit.next()) |v| gc.markValue(v.*);
        // The run-time builtin gate's reference values (kaappi#2469): a user
        // redefinition of `apply` drops the pristine primitive from globals,
        // and every `guard_builtin` compiled before it still compares
        // against it.
        for (vm.libraries.fast_path_pristine) |v| gc.markValue(v);
    }

    // Mark library environments being built by handleDefineLibrary
    for (vm.pending_lib_envs[0..vm.pending_lib_env_count]) |maybe_env| {
        if (maybe_env) |env| {
            var eit = env.valueIterator();
            while (eit.next()) |v| gc.markValue(v.*);
        }
    }

    // Mark fiber scheduler state (suspended fibers' execution state)
    if (vm.scheduler) |sched| {
        sched.markRoots(gc);
    }
    // Belt-and-braces: see Reactor.markRoots's doc comment.
    if (vm.reactor) |r| {
        r.markRoots(gc);
    }
}

/// #1933 (stop-the-world): a child VM's reported execution state, read by
/// the collecting parent (markLiveChildRoots) to decide whether the VM's
/// registers/frames are quiescent enough to mark:
///
///   .running   — bytecode is (or may resume) executing; registers/frames
///                can change at any moment. The parent must wait for a
///                safepoint or a park. This is also the state inside a
///                bounded native call (a primitive, a nested dispatch), which
///                returns to the dispatch loop promptly and hits the safepoint
///                within 1024 instructions.
///   .stopped   — at the dispatch-loop safepoint, between instructions, with
///                `collection_stop` set. Quiescent; the parent marks and then
///                clears `collection_stop` to let the child resume.
///   .parked    — blocked in a wait (reactor poll, the capped cross-thread
///                polling loops). Quiescent while reported; the resume path
///                (setCollectionRunning) re-checks `collection_stop` before
///                letting bytecode run, so a parent that observed this state
///                can always mark it frozen.
///   .in_native — inside an FFI call (callFfi) or a raw thread join
///                (reapOsThread): may block indefinitely and never reaches
///                the safepoint. Quiescent while reported; the FFI callbacks
///                that re-enter Scheme switch back to `.running` for their
///                extent (see callWithArgs), and the resume path re-checks
///                `collection_stop` the same way.
///
/// Transitions are plain atomics on the child side and are never observed
/// by the parent except while the child's own GC is guaranteed not to be
/// touching these objects — see the safepoint/park protocol in
/// markLiveChildRoots.
pub const CollectionState = enum(u8) { running, parked, stopped, in_native };

/// #1962: whether `map` is one of the environment maps `markVmRoots`
/// traces unconditionally each collection -- every registered library's
/// `lib_env`, a `retired_env` of a replaced library, an in-flight
/// `pending_lib_env`, or the library env currently being compiled
/// (`current_lib_env`, which becomes one of the former once its
/// `define-library` finishes registering). A `Function.env` /
/// `Transformer.def_env` pointing at such a map stays reachable with a NIL
/// paired `env_val` / `def_env_val`; any other map must carry a non-NIL,
/// GC-traced paired value or its bindings are lost at the next collection.
/// Pointer-identity match; runs only from the debug/test assertion guard,
/// so the O(libraries) scan never costs a release build anything.
pub fn isGcRootedEnvMap(vm: *VM, map: *std.StringHashMap(Value)) bool {
    if (vm.current_lib_env) |e| {
        if (e == map) return true;
    }
    var lit = vm.libraries.libraries.valueIterator();
    while (lit.next()) |lib| {
        if (lib.lib_env) |e| {
            if (e == map) return true;
        }
    }
    for (vm.libraries.retired_envs.items) |e| {
        if (e == map) return true;
    }
    // A prior detached into the rollback journal is just as rooted
    // (#2518 review) — it returns to `libraries` when the frame resolves.
    for (vm.lib_rollback_regs.items) |*rec| {
        if (rec.prior) |*prior| {
            if (prior.lib_env) |e| {
                if (e == map) return true;
            }
        }
    }
    for (vm.pending_lib_envs[0..vm.pending_lib_env_count]) |maybe| {
        if (maybe) |e| {
            if (e == map) return true;
        }
    }
    return false;
}
