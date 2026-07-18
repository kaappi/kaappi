const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const types = @import("types.zig");
const memory_mod = @import("memory.zig");
const shared_channel = @import("shared_channel.zig");
const shared_buffer = @import("shared_buffer.zig");
const GC = memory_mod.GC;

const Value = types.Value;
const Object = types.Object;
const Pair = types.Pair;
const Vector = types.Vector;
const Closure = types.Closure;
const Function = types.Function;
const Symbol = types.Symbol;
const SchemeString = types.SchemeString;
const NativeFn = types.NativeFn;
const Flonum = types.Flonum;
const Bytevector = types.Bytevector;
const Transformer = types.Transformer;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const Promise = types.Promise;
const HashTable = types.HashTable;
const FfiLibrary = types.FfiLibrary;
const FfiFunction = types.FfiFunction;
const FfiCallback = types.FfiCallback;
const Bignum = types.Bignum;
const Rational = types.Rational;
const RandomSource = types.RandomSource;
const Ephemeron = types.Ephemeron;
const Guardian = types.Guardian;
const TransportCell = types.TransportCell;

const build_options = @import("build_options");
const GC_THRESHOLD: usize = build_options.gc_initial_threshold;

fn clockNs() u64 {
    return platform.monotonicNs();
}

pub fn collect(gc: *GC) void {
    gc.stats.collections += 1;
    gc.minor_cycle_count += 1;

    const mark_start = clockNs();
    if (gc.minor_cycle_count >= 8) {
        gc.minor_cycle_count = 0;
        fullCollect(gc);
    } else {
        minorCollect(gc);
    }
    const mark_end = clockNs();
    gc.stats.total_mark_ns +%= mark_end -% mark_start;
    if (!gc.stress)
        gc.gc_threshold = @max(GC_THRESHOLD, gc.object_count * 4);
}

fn minorCollect(gc: *GC) void {
    clearOldMarks(gc);
    markRoots(gc);
    for (gc.remembered_set.items) |obj| {
        markObjectContents(gc, obj);
    }
    processWeakRefs(gc);
    sweepYoung(gc);
    pruneRememberedSet(gc);
}

fn clearOldMarks(gc: *GC) void {
    var obj = gc.old_objects;
    while (obj) |o| {
        o.flags.marked = false;
        obj = o.next;
    }
}

fn pruneRememberedSet(gc: *GC) void {
    var write_idx: usize = 0;
    for (gc.remembered_set.items) |obj| {
        if (referencesYoung(gc, obj)) {
            gc.remembered_set.items[write_idx] = obj;
            write_idx += 1;
        }
    }
    gc.remembered_set.shrinkRetainingCapacity(write_idx);
}

fn referencesYoung(gc: *GC, obj: *Object) bool {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            if (isYoungPointer(gc, pair.car) or isYoungPointer(gc, pair.cdr)) return true;
        },
        .vector => {
            const vec = obj.as(types.Vector);
            for (vec.data) |item| {
                if (isYoungPointer(gc, item)) return true;
            }
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            if (isYoungPointer(gc, types.makePointer(&ri.record_type.header))) return true;
            for (ri.fields) |field| {
                if (isYoungPointer(gc, field)) return true;
            }
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            if (isYoungPointer(gc, ht.equiv_fn) or isYoungPointer(gc, ht.hash_fn)) return true;
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    if (isYoungPointer(gc, entry.key) or isYoungPointer(gc, entry.value)) return true;
                }
            }
        },
        .closure => {
            const cls = obj.as(Closure);
            if (isYoungPointer(gc, types.makePointer(&cls.func.header))) return true;
            for (cls.upvalues) |uv| {
                if (isYoungPointer(gc, uv)) return true;
            }
        },
        .promise => {
            if (isYoungPointer(gc, obj.as(Promise).value)) return true;
        },
        .parameter => {
            const param = obj.as(types.ParameterObject);
            if (isYoungPointer(gc, param.value) or isYoungPointer(gc, param.converter)) return true;
        },
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| {
                if (isYoungPointer(gc, lit)) return true;
            }
            for (tx.patterns) |pat| {
                if (isYoungPointer(gc, pat)) return true;
            }
            for (tx.templates) |tmpl| {
                if (isYoungPointer(gc, tmpl)) return true;
            }
            if (isYoungPointer(gc, tx.def_env_val)) return true;
            for (tx.let_syntax_peer_vals) |pv| {
                if (isYoungPointer(gc, pv)) return true;
            }
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            if (isYoungPointer(gc, err.message) or isYoungPointer(gc, err.irritants) or isYoungPointer(gc, err.uncaught_reason)) return true;
        },
        .continuation => {
            const cont = obj.as(Continuation);
            for (cont.registers) |reg| {
                if (isYoungPointer(gc, reg)) return true;
            }
            for (cont.frames[0..cont.frame_count]) |frame| {
                if (frame.closure) |cls| {
                    if (isYoungPointer(gc, types.makePointer(&cls.header))) return true;
                }
                if (frame.native) |nf| {
                    if (isYoungPointer(gc, types.makePointer(&nf.header))) return true;
                }
            }
            for (cont.handlers[0..cont.handler_count]) |handler| {
                if (isYoungPointer(gc, handler.handler)) return true;
            }
            for (cont.wind_records[0..cont.wind_count]) |wr| {
                if (isYoungPointer(gc, wr.before) or isYoungPointer(gc, wr.after)) return true;
            }
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            for (mv.values) |val| {
                if (isYoungPointer(gc, val)) return true;
            }
        },
        .rational => {
            const rat = obj.as(Rational);
            if (isYoungPointer(gc, rat.numerator) or isYoungPointer(gc, rat.denominator)) return true;
        },
        .ffi_function => {
            if (isYoungPointer(gc, obj.as(FfiFunction).library)) return true;
        },
        .ffi_callback => {
            if (isYoungPointer(gc, obj.as(FfiCallback).closure)) return true;
        },
        .fiber => {
            const fiber_mod = @import("fiber.zig");
            const fiber = obj.as(fiber_mod.Fiber);
            if (isYoungPointer(gc, fiber.thunk) or isYoungPointer(gc, fiber.result) or
                isYoungPointer(gc, fiber.waiting_on) or isYoungPointer(gc, fiber.name) or
                isYoungPointer(gc, fiber.specific) or isYoungPointer(gc, fiber.io_buffer) or
                isYoungPointer(gc, fiber.rv_demand_on)) return true;
            if (fiber.current_exception) |exc| {
                if (isYoungPointer(gc, exc)) return true;
            }
            if (isYoungPointer(gc, fiber.continuation_value)) return true;
            for (fiber.frames[0..fiber.frame_count]) |f| {
                if (f.closure) |cls| {
                    if (isYoungPointer(gc, types.makePointer(&cls.header))) return true;
                }
                if (f.native) |nf| {
                    if (isYoungPointer(gc, types.makePointer(&nf.header))) return true;
                }
                const window = f.frameWindow();
                const end: usize = @min(@as(usize, f.base) + window, fiber.registers.len);
                var r: usize = f.base;
                while (r < end) : (r += 1) {
                    if (isYoungPointer(gc, fiber.registers[r])) return true;
                }
            }
            for (fiber.handler_stack[0..fiber.handler_count]) |h| {
                if (isYoungPointer(gc, h.handler)) return true;
            }
            for (fiber.wind_stack[0..fiber.wind_count]) |wr| {
                if (isYoungPointer(gc, wr.before) or isYoungPointer(gc, wr.after)) return true;
            }
            var pit = fiber.param_overrides.valueIterator();
            while (pit.next()) |v| {
                if (isYoungPointer(gc, v.*)) return true;
            }
            // Keeps this arm in lockstep with markFiberState (the
            // waiting_on/rv_demand_on pairing convention). For fibers the
            // whole remembered-set path is belt-and-braces, not
            // load-bearing: every scheduler-resident fiber is marked as an
            // unconditional root each collection (markVMRoots ->
            // FiberScheduler.markRoots), minor collections included, so
            // markFiberState re-traces owned_mutexes every cycle whether or
            // not this prune keeps the fiber. Checked here anyway so the
            // safety of pruning never silently starts depending on that
            // root-marking invariant.
            for (fiber.owned_mutexes.items) |m_val| {
                if (isYoungPointer(gc, m_val)) return true;
            }
        },
        .channel => {
            const ch = obj.as(types.Channel);
            if (isYoungPointer(gc, ch.head) or isYoungPointer(gc, ch.tail)) return true;
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            if (isYoungPointer(gc, m.name) or isYoungPointer(gc, m.owner) or isYoungPointer(gc, m.specific)) return true;
        },
        .condition_variable => {
            const cv = obj.as(types.ConditionVariable);
            if (isYoungPointer(gc, cv.name) or isYoungPointer(gc, cv.specific)) return true;
        },
        .function => {
            const func = obj.as(Function);
            for (func.constants.items) |c| {
                if (isYoungPointer(gc, c)) return true;
            }
            if (func.global_cache) |cache| {
                for (cache) |c| {
                    if (isYoungPointer(gc, c)) return true;
                }
            }
            if (isYoungPointer(gc, func.env_val)) return true;
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            for (nc.upvalues) |uv| {
                if (isYoungPointer(gc, uv)) return true;
            }
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            var vit = se.env.valueIterator();
            while (vit.next()) |val| {
                if (isYoungPointer(gc, val.*)) return true;
            }
        },
        // Weak structures never actually enter the remembered set (they are
        // never mutated after allocation), but for completeness these report
        // any young field: an over-approximation is always safe here.
        .ephemeron => {
            const eph = obj.as(Ephemeron);
            if (isYoungPointer(gc, eph.key) or isYoungPointer(gc, eph.value)) return true;
        },
        .guardian => {
            const g = obj.as(Guardian);
            for (g.registered.items) |e| {
                if (isYoungPointer(gc, e.watched) or isYoungPointer(gc, e.payload)) return true;
            }
            for (g.ready.items) |e| {
                if (isYoungPointer(gc, e.watched) or isYoungPointer(gc, e.payload)) return true;
            }
        },
        .transport_cell => {
            const tc = obj.as(TransportCell);
            if (isYoungPointer(gc, tc.key) or isYoungPointer(gc, tc.value)) return true;
        },
        .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector, .bignum, .record_type, .ffi_library, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time => {},
    }
    return false;
}

fn isYoungPointer(gc: *GC, val: Value) bool {
    if (!types.isPointer(val)) return false;
    const obj = types.toObject(val);
    // Foreign objects are never traced by this GC, so a reference to one
    // never needs a remembered-set entry — and reading its generation bit
    // would race the owning GC's collection cycle.
    if (obj.owner != gc.id) return false;
    return obj.flags.generation == 0;
}

fn fullCollect(gc: *GC) void {
    clearOldMarks(gc);
    markRoots(gc);
    processWeakRefs(gc);
    sweep(gc);
    sweepOld(gc);
    gc.remembered_set.clearRetainingCapacity();
}

/// SRFI-254 weak-reference resolution, run after the strong mark phase and
/// before sweeping. Reaches a fixpoint over two interacting weak structures:
///
///   * Ephemerons — the value is retained (marked strongly) only once the key
///     is proven reachable; keys reachable solely through an ephemeron's own
///     value never qualify, so an ephemeron whose value references its key
///     still breaks. Ephemerons whose key never becomes reachable are broken.
///
///   * Object guardians — a registered element whose watched object is still
///     reachable keeps its representative alive (tying the representative's
///     lifetime to the object, so a resurrected element never hands back a
///     reclaimed representative). An element whose watched object is
///     unreachable is resurrected: both fields are marked and the element moves
///     to the guardian's ready queue for a zero-argument `(g)` call.
///
/// Ephemerons are processed before guardians each round so that a key kept
/// alive only by a still-live ephemeron value is seen before any guardian
/// decision; resurrecting a guardian element can in turn make an ephemeron key
/// reachable, so the whole thing iterates until neither makes progress.
/// Transport cell guardians hold their cells strongly (marked during the strong
/// phase) and never resurrect on this non-moving collector, so they need no
/// work here.
fn processWeakRefs(gc: *GC) void {
    while (true) {
        var progress = false;

        // Ephemerons: retain the value of every ephemeron whose key is now
        // reachable, and drop it from the pending set.
        var i: usize = 0;
        while (i < gc.pending_ephemerons.items.len) {
            const eph_val = gc.pending_ephemerons.items[i];
            const eph = types.toObject(eph_val).as(Ephemeron);
            if (weakReachable(gc, eph.key)) {
                markValue(gc, eph.key);
                markValue(gc, eph.value);
                _ = gc.pending_ephemerons.swapRemove(i); // moved last into i
                progress = true;
            } else {
                i += 1;
            }
        }

        // Object guardians: resurrect registered elements whose watched object
        // is unreachable; keep the representatives of the rest alive.
        var gi: usize = 0;
        while (gi < gc.pending_guardians.items.len) : (gi += 1) {
            const g = types.toObject(gc.pending_guardians.items[gi]).as(Guardian);
            var j: usize = 0;
            while (j < g.registered.items.len) {
                const e = g.registered.items[j];
                if (weakReachable(gc, e.watched)) {
                    // Retain the representative strongly while its element is
                    // registered, tying its lifetime to the watched object.
                    // This is a deliberate choice for a non-refcounted
                    // collector: a representative reachable only through the
                    // element could otherwise be swept before the element is
                    // resurrected, leaving `(g)` to hand back freed memory. The
                    // bounded cost is that a representative which transitively
                    // references another guarded object can delay that object's
                    // resurrection — harmless, since SRFI-254 leaves the order
                    // in which elements become available unspecified.
                    if (!weakReachable(gc, e.payload)) {
                        markValue(gc, e.payload);
                        progress = true;
                    }
                    j += 1;
                } else {
                    markValue(gc, e.watched);
                    markValue(gc, e.payload);
                    g.ready.append(gc.allocator, e) catch @panic("GC guardian: ready queue OOM");
                    _ = g.registered.swapRemove(j); // moved last into j
                    progress = true;
                }
            }
        }

        if (!progress) break;
    }

    // Any ephemeron still pending has a key that never became reachable: break
    // it. Clearing both fields (not just the key) keeps ephemeron-value
    // memory-safe, since the value is no longer marked and may now be swept.
    for (gc.pending_ephemerons.items) |eph_val| {
        const eph = types.toObject(eph_val).as(Ephemeron);
        eph.broken = true;
        eph.key = types.FALSE;
        eph.value = types.FALSE;
    }
    gc.pending_ephemerons.clearRetainingCapacity();
    gc.pending_guardians.clearRetainingCapacity();
}

/// True when `v` will survive this collection independently of any weak
/// structure: immediates are never collected, foreign-owned objects are the
/// other GC's responsibility, and same-GC heap objects survive iff marked.
fn weakReachable(gc: *GC, v: Value) bool {
    if (!types.isPointer(v)) return true;
    const obj = types.toObject(v);
    if (obj.owner != gc.id) return true;
    return obj.flags.marked;
}

fn sweepYoung(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.flags.marked) {
            o.flags.marked = false;
            o.flags.survive_count +|= 1;
            if (o.flags.survive_count >= 2) {
                const next = o.next;
                if (prev) |p| {
                    p.next = next;
                } else {
                    gc.objects = next;
                }
                o.flags.generation = 1;
                o.flags.survive_count = 0;
                o.next = gc.old_objects;
                gc.old_objects = o;
                obj = next;
            } else {
                prev = o;
                obj = o.next;
            }
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

fn sweepOld(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.old_objects;
    while (obj) |o| {
        if (o.flags.marked) {
            o.flags.marked = false;
            prev = o;
            obj = o.next;
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.old_objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

fn markObjectContents(gc: *GC, obj: *Object) void {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            markValue(gc, pair.car);
            markValue(gc, pair.cdr);
        },
        .vector => {
            const vec = obj.as(Vector);
            for (vec.data) |v| markValue(gc, v);
        },
        .closure => {
            const cls = obj.as(Closure);
            markValue(gc, types.makePointer(&cls.func.header));
            for (cls.upvalues) |uv| markValue(gc, uv);
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            markValue(gc, ht.equiv_fn);
            markValue(gc, ht.hash_fn);
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    markValue(gc, entry.key);
                    markValue(gc, entry.value);
                }
            }
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            markValue(gc, types.makePointer(&ri.record_type.header));
            for (ri.fields) |field| markValue(gc, field);
        },
        .promise => {
            const p = obj.as(Promise);
            markValue(gc, p.value);
        },
        .parameter => {
            const param = obj.as(types.ParameterObject);
            markValue(gc, param.value);
            markValue(gc, param.converter);
        },
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| markValue(gc, lit);
            for (tx.patterns) |pat| markValue(gc, pat);
            for (tx.templates) |tmpl| markValue(gc, tmpl);
            markValue(gc, tx.def_env_val);
            for (tx.let_syntax_peer_vals) |pv| markValue(gc, pv);
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            markValue(gc, err.message);
            markValue(gc, err.irritants);
            markValue(gc, err.uncaught_reason);
        },
        .continuation => {
            const cont = obj.as(Continuation);
            for (cont.registers) |reg| markValue(gc, reg);
            for (cont.frames[0..cont.frame_count]) |frame| {
                if (frame.closure) |cls| markValue(gc, types.makePointer(&cls.header));
                if (frame.native) |nf| markValue(gc, types.makePointer(&nf.header));
            }
            for (cont.handlers[0..cont.handler_count]) |handler| markValue(gc, handler.handler);
            for (cont.wind_records[0..cont.wind_count]) |wr| {
                markValue(gc, wr.before);
                markValue(gc, wr.after);
            }
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            for (mv.values) |val| markValue(gc, val);
        },
        .rational => {
            const rat = obj.as(Rational);
            markValue(gc, rat.numerator);
            markValue(gc, rat.denominator);
        },
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            markValue(gc, ffi_fn.library);
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            markValue(gc, cb.closure);
        },
        .fiber => {
            const fiber_mod = @import("fiber.zig");
            const fiber = obj.as(fiber_mod.Fiber);
            fiber_mod.markFiberState(gc, fiber);
        },
        .channel => {
            const ch = obj.as(types.Channel);
            markValue(gc, ch.head);
            markValue(gc, ch.tail);
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            markValue(gc, m.name);
            markValue(gc, m.owner);
            markValue(gc, m.specific);
        },
        .condition_variable => {
            const cv = obj.as(types.ConditionVariable);
            markValue(gc, cv.name);
            markValue(gc, cv.specific);
        },
        .function => {
            const func = obj.as(Function);
            for (func.constants.items) |c| markValue(gc, c);
            if (func.global_cache) |cache| {
                for (cache) |c| markValue(gc, c);
            }
            markValue(gc, func.env_val);
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            for (nc.upvalues) |uv| markValue(gc, uv);
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            var vit = se.env.valueIterator();
            while (vit.next()) |val| markValue(gc, val.*);
        },
        .ephemeron => registerPendingEphemeron(gc, obj),
        .guardian => markGuardianStrong(gc, obj),
        .transport_cell => {
            const tc = obj.as(TransportCell);
            markValue(gc, tc.key);
            markValue(gc, tc.value);
        },
        .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector, .bignum, .record_type, .ffi_library, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time => {},
    }
}

/// Record a reachable ephemeron for the post-mark weak fixpoint without tracing
/// its key or value — those are decided by processWeakRefs.
fn registerPendingEphemeron(gc: *GC, obj: *Object) void {
    gc.pending_ephemerons.append(gc.allocator, types.makePointer(obj)) catch
        @panic("GC: pending ephemerons OOM");
}

/// Mark the strongly-held fields of a reachable guardian and, for an object
/// guardian, record it for the resurrection fixpoint. A transport cell
/// guardian holds its registered cells strongly (they never resurrect on this
/// non-moving collector); an object guardian holds only its ready (already
/// resurrected) elements strongly, its registered elements being weak. Marking
/// uses gc.markValue so it composes whether called from the worklist drain or
/// the remembered-set walk.
fn markGuardianStrong(gc: *GC, obj: *Object) void {
    const g = obj.as(Guardian);
    if (g.is_transport) {
        for (g.registered.items) |e| markValue(gc, e.watched);
        for (g.ready.items) |e| markValue(gc, e.watched);
    } else {
        for (g.ready.items) |e| {
            markValue(gc, e.watched);
            markValue(gc, e.payload);
        }
        gc.pending_guardians.append(gc.allocator, types.makePointer(obj)) catch
            @panic("GC: pending guardians OOM");
    }
}

fn markRoots(gc: *GC) void {
    for (gc.arg_roots[0..gc.arg_root_count]) |v| {
        markValue(gc, v);
    }
    if (gc.slice_roots) |sr| {
        for (sr) |v| markValue(gc, v);
    }
    for (gc.root_buffer[0..gc.root_count]) |root| {
        markValue(gc, root.*);
    }
    for (gc.extra_roots.items) |v| {
        markValue(gc, v);
    }
    // Mark active FFI callback closures
    const ffi_cb = @import("ffi_callback.zig");
    ffi_cb.markCallbackRoots(gc);
    // Mark interned symbols. Use a blocking lock to prevent iterating
    // while another thread's put() rehashes the HashMap. Deadlock is not
    // possible: allocSymbol — the only other acquirer of symbol_mutex, taken
    // unconditionally by parent and child alike — never calls maybeCollect,
    // so a thread can never enter GC marking (which takes this same lock)
    // while already holding it in allocSymbol.
    memory_mod.spinLock(&memory_mod.symbol_mutex);
    defer memory_mod.spinUnlock(&memory_mod.symbol_mutex);
    var it = gc.symbols.valueIterator();
    while (it.next()) |v| {
        markValue(gc, v.*);
    }
    // Mark VM-owned roots (live registers, call frames, handlers, winds).
    if (gc.root_marker) |mark| mark(gc);
}

pub fn markValue(gc: *GC, v: Value) void {
    // Use an explicit worklist to avoid native stack overflow on deeply
    // nested pair/vector structures (issue #864). The worklist lives on
    // the GC struct so its capacity persists across calls — no per-call
    // alloc/free churn (issue #1428).
    const is_root_call = !gc.marking;
    gc.marking = true;

    markValueInner(gc, v, &gc.mark_worklist);

    // Re-entrant call (e.g. markFiberState → gc.markValue): the outer
    // drain loop will process items we just pushed.
    if (!is_root_call) return;

    while (gc.mark_worklist.items.len > 0) {
        const item = gc.mark_worklist.pop().?;
        markValueInner(gc, item, &gc.mark_worklist);
    }
    gc.marking = false;

    // Cap retained capacity so one pathologically wide object (e.g. a
    // 10M-element vector) doesn't keep ~80 MB allocated forever.
    const max_retained = 64 * 1024;
    if (gc.mark_worklist.capacity > max_retained)
        gc.mark_worklist.clearAndFree(gc.allocator);
}

fn markValueInner(gc: *GC, v: Value, worklist: *std.ArrayList(Value)) void {
    var cur = v;
    while (true) {
        if (!types.isPointer(cur)) return;
        const obj = types.toObject(cur);
        // Never mark or trace an object owned by another GC. Its owner keeps
        // it alive (shared globals are marked by the parent, interned symbols
        // are never swept, a thread's thunk is extra-rooted until join), and
        // writing this GC's mark bits into it would corrupt the owner's
        // concurrent mark/sweep cycle — the owner would see a spurious
        // "already marked" object, skip tracing its children, and sweep live
        // descendants (#958).
        if (obj.owner != gc.id) return;
        if (obj.flags.marked) return;
        obj.flags.marked = true;

        if (obj.tag == .pair) {
            const pair = obj.as(Pair);
            const car = pair.car;
            const cdr = pair.cdr;
            const car_is_ptr = types.isPointer(car);
            const cdr_is_ptr = types.isPointer(cdr);
            if (car_is_ptr and cdr_is_ptr) {
                // Push car onto worklist instead of recursing -- this is
                // the key change that prevents stack overflow on deep
                // structures like (((((...)))))).
                worklist.append(gc.allocator, car) catch @panic("GC mark: worklist OOM");
                cur = cdr;
            } else if (cdr_is_ptr) {
                cur = cdr;
            } else {
                cur = car;
            }
            continue;
        }
        break;
    }

    // Non-pair heap object -- already marked above, now trace its fields.
    const obj = types.toObject(cur);
    switch (obj.tag) {
        .pair => unreachable,
        .closure => {
            const cls = obj.as(Closure);
            worklist.append(gc.allocator, types.makePointer(&cls.func.header)) catch @panic("GC mark: worklist OOM");
            for (cls.upvalues) |uv| {
                worklist.append(gc.allocator, uv) catch @panic("GC mark: worklist OOM");
            }
        },
        .function => {
            const func = obj.as(Function);
            for (func.constants.items) |c| {
                worklist.append(gc.allocator, c) catch @panic("GC mark: worklist OOM");
            }
            if (func.global_cache) |cache| {
                for (cache) |c| worklist.append(gc.allocator, c) catch @panic("GC mark: worklist OOM");
            }
            worklist.append(gc.allocator, func.env_val) catch @panic("GC mark: worklist OOM");
        },
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| {
                worklist.append(gc.allocator, lit) catch @panic("GC mark: worklist OOM");
            }
            for (tx.patterns) |pat| {
                worklist.append(gc.allocator, pat) catch @panic("GC mark: worklist OOM");
            }
            for (tx.templates) |tmpl| {
                worklist.append(gc.allocator, tmpl) catch @panic("GC mark: worklist OOM");
            }
            worklist.append(gc.allocator, tx.def_env_val) catch @panic("GC mark: worklist OOM");
            for (tx.let_syntax_peer_vals) |pv| {
                worklist.append(gc.allocator, pv) catch @panic("GC mark: worklist OOM");
            }
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            worklist.append(gc.allocator, err.message) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, err.irritants) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, err.uncaught_reason) catch @panic("GC mark: worklist OOM");
        },
        .record_type => {},
        .record_instance => {
            const ri = obj.as(RecordInstance);
            worklist.append(gc.allocator, types.makePointer(&ri.record_type.header)) catch @panic("GC mark: worklist OOM");
            for (ri.fields) |field| {
                worklist.append(gc.allocator, field) catch @panic("GC mark: worklist OOM");
            }
        },
        .continuation => {
            const cont = obj.as(Continuation);
            for (cont.registers) |reg| {
                worklist.append(gc.allocator, reg) catch @panic("GC mark: worklist OOM");
            }
            for (cont.frames[0..cont.frame_count]) |frame| {
                if (frame.closure) |cls| {
                    worklist.append(gc.allocator, types.makePointer(&cls.header)) catch @panic("GC mark: worklist OOM");
                }
                if (frame.native) |nf| {
                    worklist.append(gc.allocator, types.makePointer(&nf.header)) catch @panic("GC mark: worklist OOM");
                }
            }
            for (cont.handlers[0..cont.handler_count]) |handler| {
                worklist.append(gc.allocator, handler.handler) catch @panic("GC mark: worklist OOM");
            }
            for (cont.wind_records[0..cont.wind_count]) |wr| {
                worklist.append(gc.allocator, wr.before) catch @panic("GC mark: worklist OOM");
                worklist.append(gc.allocator, wr.after) catch @panic("GC mark: worklist OOM");
            }
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            for (mv.values) |val| {
                worklist.append(gc.allocator, val) catch @panic("GC mark: worklist OOM");
            }
        },
        .vector => {
            const vec = obj.as(Vector);
            // Push all elements except the last onto the worklist;
            // iterate the last element directly via tail call.
            if (vec.data.len > 0) {
                for (vec.data[0 .. vec.data.len - 1]) |elem| {
                    worklist.append(gc.allocator, elem) catch @panic("GC mark: worklist OOM");
                }
                markValueInner(gc, vec.data[vec.data.len - 1], worklist);
            }
        },
        .promise => {
            const p = obj.as(Promise);
            worklist.append(gc.allocator, p.value) catch @panic("GC mark: worklist OOM");
        },
        .parameter => {
            const param = obj.as(types.ParameterObject);
            worklist.append(gc.allocator, param.value) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, param.converter) catch @panic("GC mark: worklist OOM");
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            if (ht.equiv_fn != 0) worklist.append(gc.allocator, ht.equiv_fn) catch @panic("GC mark: worklist OOM");
            if (ht.hash_fn != 0) worklist.append(gc.allocator, ht.hash_fn) catch @panic("GC mark: worklist OOM");
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    worklist.append(gc.allocator, entry.key) catch @panic("GC mark: worklist OOM");
                    worklist.append(gc.allocator, entry.value) catch @panic("GC mark: worklist OOM");
                }
            }
        },
        .rational => {
            const rat = obj.as(Rational);
            worklist.append(gc.allocator, rat.numerator) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, rat.denominator) catch @panic("GC mark: worklist OOM");
        },
        .ffi_library => {},
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            worklist.append(gc.allocator, ffi_fn.library) catch @panic("GC mark: worklist OOM");
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            worklist.append(gc.allocator, cb.closure) catch @panic("GC mark: worklist OOM");
        },
        .fiber => {
            const fiber_mod = @import("fiber.zig");
            const fiber = obj.as(fiber_mod.Fiber);
            fiber_mod.markFiberState(gc, fiber);
        },
        .channel => {
            const ch = obj.as(types.Channel);
            worklist.append(gc.allocator, ch.head) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, ch.tail) catch @panic("GC mark: worklist OOM");
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            worklist.append(gc.allocator, m.name) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, m.owner) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, m.specific) catch @panic("GC mark: worklist OOM");
        },
        .condition_variable => {
            const cv = obj.as(types.ConditionVariable);
            worklist.append(gc.allocator, cv.name) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, cv.specific) catch @panic("GC mark: worklist OOM");
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            for (nc.upvalues) |uv| worklist.append(gc.allocator, uv) catch @panic("GC mark: worklist OOM");
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            var vit = se.env.valueIterator();
            while (vit.next()) |val| worklist.append(gc.allocator, val.*) catch @panic("GC mark: worklist OOM");
        },
        .ephemeron => {
            // Weak key, conditional value: the ephemeron object survives (it
            // is already marked above), but its key/value are left to
            // processWeakRefs. Recording it here is what limits the fixpoint to
            // reachable ephemerons.
            gc.pending_ephemerons.append(gc.allocator, cur) catch @panic("GC mark: pending ephemerons OOM");
        },
        .guardian => {
            const g = obj.as(Guardian);
            if (g.is_transport) {
                // Transport cells are held strongly; marking each cell traces
                // its key/value via the .transport_cell arm.
                for (g.registered.items) |e| worklist.append(gc.allocator, e.watched) catch @panic("GC mark: worklist OOM");
                for (g.ready.items) |e| worklist.append(gc.allocator, e.watched) catch @panic("GC mark: worklist OOM");
            } else {
                // Ready (resurrected) elements are strong; registered elements
                // are weak and handled by processWeakRefs.
                for (g.ready.items) |e| {
                    worklist.append(gc.allocator, e.watched) catch @panic("GC mark: worklist OOM");
                    worklist.append(gc.allocator, e.payload) catch @panic("GC mark: worklist OOM");
                }
                gc.pending_guardians.append(gc.allocator, cur) catch @panic("GC mark: pending guardians OOM");
            }
        },
        .transport_cell => {
            const tc = obj.as(TransportCell);
            worklist.append(gc.allocator, tc.key) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, tc.value) catch @panic("GC mark: worklist OOM");
        },
        .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector, .bignum, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time => {},
    }
}

fn sweep(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.flags.marked) {
            o.flags.marked = false;
            prev = o;
            obj = o.next;
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

fn objectSize(obj: *Object) usize {
    return switch (obj.tag) {
        .pair => @sizeOf(Pair),
        .symbol => @sizeOf(Symbol) + obj.as(Symbol).name.len,
        .string => @sizeOf(SchemeString) + obj.as(SchemeString).data.len,
        .closure => @sizeOf(Closure) + obj.as(Closure).upvalues.len * @sizeOf(Value),
        .function => blk: {
            const f = obj.as(Function);
            var s: usize = @sizeOf(Function);
            s += f.code.capacity;
            s += f.constants.capacity * @sizeOf(Value);
            if (f.global_cache) |c| s += c.len * @sizeOf(Value);
            break :blk s;
        },
        .native_fn => @sizeOf(NativeFn),
        .native_closure => @sizeOf(types.NativeClosure) + obj.as(types.NativeClosure).upvalues.len * @sizeOf(Value),
        .flonum => @sizeOf(Flonum),
        .vector => @sizeOf(Vector) + obj.as(Vector).data.len * @sizeOf(Value),
        // A backed bytevector (lever D) borrows its bytes from a SharedBuffer,
        // so only the struct counts against this heap.
        .bytevector => @sizeOf(Bytevector) + if (obj.as(Bytevector).shared == null) obj.as(Bytevector).data.len else 0,
        .transformer => blk: {
            const t = obj.as(Transformer);
            break :blk @sizeOf(Transformer) + t.literals.len * @sizeOf(Value) +
                t.patterns.len * @sizeOf(Value) + t.templates.len * @sizeOf(Value) +
                t.let_syntax_peer_vals.len * @sizeOf(Value);
        },
        .error_object => @sizeOf(types.ErrorObject),
        .record_type => @sizeOf(RecordType) + obj.as(RecordType).name.len,
        .record_instance => @sizeOf(RecordInstance) + obj.as(RecordInstance).fields.len * @sizeOf(Value),
        .port => blk: {
            const port = obj.as(Port);
            var s: usize = @sizeOf(Port);
            if (port.owns_name) s += port.name.len;
            if (port.string_data) |sd| s += sd.len;
            if (port.string_out_buf) |_| s += port.string_out_cap;
            if (port.read_buf) |rb| s += rb.len;
            if (port.write_buf) |wb| s += wb.len;
            if (port.random_gen) |_| s += @sizeOf(types.RandomGen);
            break :blk s;
        },
        .continuation => @sizeOf(Continuation) + obj.as(Continuation).backing.len * @sizeOf(Value),
        .multiple_values => @sizeOf(MultipleValues) + obj.as(MultipleValues).values.len * @sizeOf(Value),
        .complex => @sizeOf(types.Complex),
        .promise => @sizeOf(Promise),
        .parameter => @sizeOf(types.ParameterObject),
        .hash_table => @sizeOf(HashTable) + obj.as(HashTable).entries.len * @sizeOf(types.HashEntry),
        .ffi_library => @sizeOf(FfiLibrary) + obj.as(FfiLibrary).name.len,
        .ffi_function => blk: {
            const f = obj.as(FfiFunction);
            break :blk @sizeOf(FfiFunction) + f.name.len + f.param_types.len * @sizeOf(types.FfiType);
        },
        .ffi_callback => @sizeOf(FfiCallback),
        .bignum => @sizeOf(Bignum) + obj.as(Bignum).limbs.len * @sizeOf(u64),
        .rational => @sizeOf(Rational),
        .file_info => @sizeOf(types.FileInfo),
        .user_info => blk: {
            const ui = obj.as(types.UserInfo);
            break :blk @sizeOf(types.UserInfo) + ui.name.len + ui.home_dir.len + ui.shell.len + ui.full_name.len;
        },
        .group_info => @sizeOf(types.GroupInfo) + obj.as(types.GroupInfo).name.len,
        .directory_object => @sizeOf(types.DirectoryObject),
        .random_source => @sizeOf(RandomSource),
        .fiber => blk: {
            const fiber = obj.as(@import("fiber.zig").Fiber);
            break :blk @sizeOf(@import("fiber.zig").Fiber) +
                fiber.registers.len * @sizeOf(Value) +
                fiber.frames.len * @sizeOf(types.CallFrame);
        },
        .channel => @sizeOf(types.Channel),
        .mutex => @sizeOf(types.Mutex),
        .condition_variable => @sizeOf(types.ConditionVariable),
        .srfi18_time => @sizeOf(types.Srfi18Time),
        .scheme_environment => @sizeOf(types.SchemeEnvironment),
        .ephemeron => @sizeOf(Ephemeron),
        .guardian => blk: {
            const g = obj.as(Guardian);
            break :blk @sizeOf(Guardian) +
                (g.registered.capacity + g.ready.capacity) * @sizeOf(types.GuardEntry);
        },
        .transport_cell => @sizeOf(TransportCell),
    };
}

inline fn poisonAndDestroy(gc: *GC, comptime T: type, ptr: *T) void {
    if (builtin.mode == .Debug) {
        @memset(@as([*]u8, @ptrCast(ptr))[0..@sizeOf(T)], 0xAA);
    }
    gc.allocator.destroy(ptr);
}

pub fn freeObject(gc: *GC, obj: *Object) void {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            poisonAndDestroy(gc, Pair, pair);
        },
        .symbol => {
            const sym = obj.as(Symbol);
            gc.allocator.free(sym.name);
            poisonAndDestroy(gc, Symbol, sym);
        },
        .string => {
            const str = obj.as(SchemeString);
            gc.allocator.free(str.data);
            poisonAndDestroy(gc, SchemeString, str);
        },
        .closure => {
            const cls = obj.as(Closure);
            gc.allocator.free(cls.upvalues);
            poisonAndDestroy(gc, Closure, cls);
        },
        .function => {
            const func = obj.as(Function);
            func.code.deinit(gc.allocator);
            func.constants.deinit(gc.allocator);
            func.line_table.deinit(gc.allocator);
            if (func.global_cache) |cache| {
                gc.allocator.free(cache);
            }
            if (func.debug_locals.len > 0) {
                gc.allocator.free(func.debug_locals);
            }
            if (func.owns_name) {
                if (func.name) |n| gc.allocator.free(n);
            }
            poisonAndDestroy(gc, Function, func);
        },
        .native_fn => {
            const nf = obj.as(NativeFn);
            poisonAndDestroy(gc, NativeFn, nf);
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            gc.allocator.free(nc.upvalues);
            poisonAndDestroy(gc, types.NativeClosure, nc);
        },
        .flonum => {
            const flo = obj.as(Flonum);
            poisonAndDestroy(gc, Flonum, flo);
        },
        .vector => {
            const vec = obj.as(Vector);
            gc.allocator.free(vec.data);
            poisonAndDestroy(gc, Vector, vec);
        },
        .transformer => {
            const tx = obj.as(Transformer);
            gc.allocator.free(tx.literals);
            gc.allocator.free(tx.patterns);
            gc.allocator.free(tx.templates);
            if (tx.captured_locals.len > 0) gc.allocator.free(tx.captured_locals);
            if (tx.literal_bound.len > 0) gc.allocator.free(tx.literal_bound);
            if (tx.let_syntax_peer_names.len > 0) gc.allocator.free(tx.let_syntax_peer_names);
            if (tx.let_syntax_peer_vals.len > 0) gc.allocator.free(tx.let_syntax_peer_vals);
            if (tx.bound_free_refs.len > 0) gc.allocator.free(tx.bound_free_refs);
            poisonAndDestroy(gc, Transformer, tx);
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            poisonAndDestroy(gc, types.ErrorObject, err);
        },
        .record_type => {
            const rt = obj.as(RecordType);
            gc.allocator.free(rt.name);
            poisonAndDestroy(gc, RecordType, rt);
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            gc.allocator.free(ri.fields);
            poisonAndDestroy(gc, RecordInstance, ri);
        },
        .bytevector => {
            const bv = obj.as(Bytevector);
            // Lever D (kaappi#1472): a backed bytevector borrows its bytes from
            // a SharedBuffer -- release the reference (freeing the buffer at
            // zero) instead of freeing bytes this heap never owned.
            if (bv.shared) |raw| {
                const sb: *shared_buffer.SharedBuffer = @ptrCast(@alignCast(raw));
                sb.release();
            } else {
                gc.allocator.free(bv.data);
            }
            poisonAndDestroy(gc, Bytevector, bv);
        },
        .promise => {
            const p = obj.as(Promise);
            poisonAndDestroy(gc, Promise, p);
        },
        .port => {
            const port = obj.as(Port);
            // Close the fd if still open and not stdin/stdout/stderr
            if (port.is_open and port.fd > 2 and !port.is_string_port) {
                // Best-effort flush of buffered output before the fd is lost.
                // No parking is possible during a sweep, so a would-block
                // (EAGAIN) or any other failure just drops the remainder —
                // programs that need the data call flush-output-port or
                // close-port instead of leaking the port to the collector.
                if (port.write_buf) |wb| {
                    var start = port.write_buf_start;
                    while (start < port.write_buf_len) {
                        // A Windows socket port must send() — CRT _write
                        // cannot operate on a SOCKET handle — and a pipe
                        // port in emulated non-blocking mode must keep its
                        // quota gate: plain _write on a full pipe would
                        // block this sweep forever, exactly the would-block
                        // this loop promises to drop (#1608).
                        const remaining = port.write_buf_len - start;
                        const rc = if (platform.is_windows and port.fd_state.is_socket)
                            platform.sockSend(port.fd, wb.ptr + start, remaining)
                        else if (platform.is_windows and port.fd_state.is_pipe and port.nonblocking)
                            platform.pipeWrite(port.fd, wb.ptr + start, remaining)
                        else
                            platform.write(port.fd, wb.ptr + start, remaining);
                        if (rc < 0 and platform.errno(rc) == .INTR) continue;
                        if (rc <= 0) break;
                        start += @as(usize, @intCast(rc));
                    }
                }
                _ = platform.close(port.fd);
            }
            if (port.write_buf) |wb| {
                gc.allocator.free(wb);
            }
            if (port.owns_name) {
                gc.allocator.free(port.name);
            }
            if (port.read_buf) |rb| {
                gc.allocator.free(rb);
            }
            // Free string port buffers
            if (port.string_data) |sd| {
                gc.allocator.free(sd);
            }
            if (port.string_out_buf) |sb| {
                gc.allocator.free(sb);
            }
            if (port.random_gen) |g| {
                gc.allocator.destroy(g);
            }
            poisonAndDestroy(gc, Port, port);
        },
        .continuation => {
            const cont = obj.as(Continuation);
            // registers/frames/handlers/wind_records are all views into
            // the single backing allocation; free it once. Escape
            // continuations have no backing (empty slice).
            if (cont.backing.len > 0) gc.allocator.free(cont.backing);
            poisonAndDestroy(gc, Continuation, cont);
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            gc.allocator.free(mv.values);
            poisonAndDestroy(gc, MultipleValues, mv);
        },
        .complex => {
            const c = obj.as(types.Complex);
            poisonAndDestroy(gc, types.Complex, c);
        },
        .parameter => {
            const p = obj.as(types.ParameterObject);
            poisonAndDestroy(gc, types.ParameterObject, p);
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            gc.allocator.free(ht.entries);
            poisonAndDestroy(gc, HashTable, ht);
        },
        .ffi_library => {
            const lib = obj.as(FfiLibrary);
            // Do NOT dlclose here -- let ffi-close handle that explicitly
            gc.allocator.free(lib.name);
            poisonAndDestroy(gc, FfiLibrary, lib);
        },
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            gc.allocator.free(ffi_fn.name);
            gc.allocator.free(ffi_fn.param_types);
            poisonAndDestroy(gc, FfiFunction, ffi_fn);
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            if (cb.active) {
                const ffi_cb = @import("ffi_callback.zig");
                ffi_cb.releaseSlot(cb.slot_index);
            }
            poisonAndDestroy(gc, FfiCallback, cb);
        },
        .bignum => {
            const bn = obj.as(Bignum);
            gc.allocator.free(bn.limbs);
            poisonAndDestroy(gc, Bignum, bn);
        },
        .rational => {
            const rat = obj.as(Rational);
            poisonAndDestroy(gc, Rational, rat);
        },
        .file_info => {
            const fi = obj.as(types.FileInfo);
            poisonAndDestroy(gc, types.FileInfo, fi);
        },
        .user_info => {
            const ui = obj.as(types.UserInfo);
            gc.allocator.free(ui.name);
            gc.allocator.free(ui.home_dir);
            gc.allocator.free(ui.shell);
            gc.allocator.free(ui.full_name);
            poisonAndDestroy(gc, types.UserInfo, ui);
        },
        .group_info => {
            const gi = obj.as(types.GroupInfo);
            gc.allocator.free(gi.name);
            poisonAndDestroy(gc, types.GroupInfo, gi);
        },
        .directory_object => {
            const d = obj.as(types.DirectoryObject);
            if (d.dir) |dir| {
                platform.dirIterDestroy(@ptrCast(@alignCast(dir)));
                d.dir = null;
            }
            poisonAndDestroy(gc, types.DirectoryObject, d);
        },
        .random_source => {
            poisonAndDestroy(gc, RandomSource, obj.as(RandomSource));
        },
        .fiber => {
            const fiber = obj.as(@import("fiber.zig").Fiber);
            fiber.param_overrides.deinit();
            fiber.owned_mutexes.deinit(gc.allocator);
            gc.allocator.free(fiber.frames);
            gc.allocator.free(fiber.registers);
            poisonAndDestroy(gc, @import("fiber.zig").Fiber, fiber);
        },
        .channel => {
            const ch = obj.as(types.Channel);
            // KEP-0002 §1 rule 3: stubs are released by freeObject, from
            // ANY path -- a real GC sweep, a test's GC.deinit(), or an
            // envelope's own mini-GC tearing itself down through this same
            // function. No separate envelope-specific bookkeeping exists.
            if (ch.shared) |s| {
                const sc: *shared_channel.SharedChannel = @ptrCast(@alignCast(s));
                sc.release();
            }
            poisonAndDestroy(gc, types.Channel, ch);
        },
        .mutex => {
            poisonAndDestroy(gc, types.Mutex, obj.as(types.Mutex));
        },
        .condition_variable => {
            poisonAndDestroy(gc, types.ConditionVariable, obj.as(types.ConditionVariable));
        },
        .srfi18_time => {
            poisonAndDestroy(gc, types.Srfi18Time, obj.as(types.Srfi18Time));
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            if (se.owned) {
                se.env.deinit();
                gc.allocator.destroy(se.env);
            }
            poisonAndDestroy(gc, types.SchemeEnvironment, se);
        },
        .ephemeron => {
            poisonAndDestroy(gc, Ephemeron, obj.as(Ephemeron));
        },
        .guardian => {
            const g = obj.as(Guardian);
            g.registered.deinit(gc.allocator);
            g.ready.deinit(gc.allocator);
            poisonAndDestroy(gc, Guardian, g);
        },
        .transport_cell => {
            poisonAndDestroy(gc, TransportCell, obj.as(TransportCell));
        },
    }
}
