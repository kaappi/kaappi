const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const types = @import("types.zig");
const types_port = @import("types_port.zig");
const memory_mod = @import("memory.zig");
const GC = memory_mod.GC;

const Value = types.Value;
const Object = types.Object;
const Pair = types.Pair;
const Vector = types.Vector;
const Closure = types.Closure;
const Function = types.Function;
const Bytevector = types.Bytevector;
const Transformer = types.Transformer;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const Promise = types.Promise;
const HashTable = types.HashTable;
const FfiFunction = types.FfiFunction;
const FfiCallback = types.FfiCallback;
const Bignum = types.Bignum;
const Rational = types.Rational;
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
    // #1961: the minor mark is generational. `minor_marking` makes
    // markValueInner treat the old generation as opaque, so this mark costs
    // O(live young) plus the remembered containers' scanned fields — not
    // O(live heap). Mark-bit invariant, which is why no clearOldMarks pass
    // exists anywhere: the only writes of flags.marked are inside
    // markValueInner (young objects only during a minor — the opacity check
    // returns before marking an old one — and both generations during a
    // full), and every sweep clears the marks it observes before the
    // collection ends, so no collection ever sees a stale mark.
    gc.minor_marking = true;
    defer gc.minor_marking = false;
    markRoots(gc);
    for (gc.remembered_set.items) |obj| {
        markObjectContents(gc, obj);
    }
    processWeakRefs(gc);
    // #1687: between mark and sweep, so slots the sweep is about to
    // quarantine can't be released before the next mark phase checks them.
    gc.quarantineReleaseToCap();
    sweepYoung(gc);
    pruneRememberedSet(gc);
}

fn pruneRememberedSet(gc: *GC) void {
    var write_idx: usize = 0;
    for (gc.remembered_set.items) |obj| {
        if (referencesYoung(gc, obj)) {
            gc.remembered_set.items[write_idx] = obj;
            write_idx += 1;
        } else {
            // #2196: dropped from the set, so clear the dedup flag — a later
            // old->young write to this container must be free to re-queue it.
            // Only touch the flag on containers we own (foreign containers are
            // appended without the flag; see writeBarrier).
            if (obj.owner == gc.id) obj.flags.in_remembered_set = false;
        }
    }
    gc.remembered_set.shrinkRetainingCapacity(write_idx);
}

/// True iff `obj` (an old container) directly references a young object of
/// this GC. Drives `pruneRememberedSet` and — since #1961 — the promotion
/// scan in `sweepYoung`: this is the predicate that decides whether a freshly
/// promoted object carries old→young edges the remembered set must record.
pub fn referencesYoung(gc: *GC, obj: *Object) bool {
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
        // SRFI 237: `parent` is the only heap pointer on RecordType.
        .record_type => {
            const rt = obj.as(RecordType);
            if (rt.parent) |p| {
                if (isYoungPointer(gc, types.makePointer(&p.header))) return true;
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
        // Port's Value fields live behind owned satellite pointers, so they
        // are enumerated once in types_port.forEachValue rather than by hand
        // here, in markObjectContents and in markValueInner (audit v2, 7A).
        // The visitor returning `true` keeps this arm's short-circuit.
        .port => return types_port.forEachValue(obj.as(Port), gc, youngVisitor),
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
            if (isYoungPointer(gc, tx.proc)) return true;
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
        .complex => {
            const cx = obj.as(types.Complex);
            if (isYoungPointer(gc, cx.real) or isYoungPointer(gc, cx.imag)) return true;
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
        .process => {
            const proc = obj.as(types.Process);
            if (isYoungPointer(gc, proc.stdin_port) or
                isYoungPointer(gc, proc.stdout_port) or
                isYoungPointer(gc, proc.stderr_port)) return true;
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            if (isYoungPointer(gc, m.name) or isYoungPointer(gc, m.owner) or isYoungPointer(gc, m.owner_thread) or isYoungPointer(gc, m.specific)) return true;
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
            // #1961 (review): an .owned == false wrapper's map IS the
            // owning VM's root-marked globals map (interaction-environment
            // is the only such constructor) — every value in it is marked
            // each collection by markVmRoots regardless, so the wrapper
            // never carries a remembered-set-relevant young edge; for a
            // child-thread wrapper the values are foreign to this GC and
            // isYoungPointer would skip them anyway. Returning false here
            // keeps the promotion scan and the full-collect re-scan from
            // enrolling the wrapper, which would otherwise re-walk all of
            // globals (mark + prune) once per minor while any global value
            // stays young.
            if (!se.owned) return false;
            var vit = se.env.valueIterator();
            while (vit.next()) |val| {
                if (isYoungPointer(gc, val.*)) return true;
            }
        },
        // Weak structures reach the remembered set only via the promotion
        // scan and — for guardians, whose `registered` list grows at every
        // registration — the writeBarrier in invokeGuardian (an old guardian
        // registering a young object is an old→young edge like any other,
        // #1961). Ephemerons and transport cells are immutable after
        // allocation, so for them the promotion scan is the only route; an
        // over-approximation is always safe here.
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
        .symbol, .string, .native_fn, .flonum, .bytevector, .bignum, .ffi_library, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time, .numeric_vector => {},
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

pub fn fullCollect(gc: *GC) void {
    // #1961: a full collection marks both generations — old objects are
    // traced and swept here, so they must not be opaque. minorCollect's
    // defer guarantees the flag is already false; this makes the
    // requirement local instead of transitive.
    gc.minor_marking = false;
    // #2196: drain the remembered_set up front. A full collect marks from
    // roots over both generations, so it never consults the set — and doing
    // this before sweepOld frees any old object means every entry is still
    // live when we clear its dedup flag (clearing after the sweep would be a
    // use-after-free). Every surviving old container is then free to re-queue
    // itself on its next old->young write.
    drainRememberedSet(gc);
    // No clearOldMarks here either — see minorCollect's mark-bit invariant:
    // the previous collection (minor or full) left every mark clear.
    markRoots(gc);
    processWeakRefs(gc);
    // #1687: see minorCollect.
    gc.quarantineReleaseToCap();
    sweep(gc);
    sweepOld(gc);
}

fn drainRememberedSet(gc: *GC) void {
    // Only clear the flag on containers we own (foreign containers never had it
    // set by this GC; see writeBarrier).
    for (gc.remembered_set.items) |obj| {
        if (obj.owner == gc.id) obj.flags.in_remembered_set = false;
    }
    gc.remembered_set.clearRetainingCapacity();
}

/// SRFI-254 weak-reference resolution, run after the strong mark phase and
/// before sweeping. Reaches a fixpoint over two interacting weak structures:
///
///   * Ephemerons — the value is retained (marked strongly) only once the key
///     is proven live; keys kept alive solely through an ephemeron's own
///     value never qualify, so an ephemeron whose value references its key
///     still breaks. Ephemerons whose key never becomes live are broken.
///
///   * Object guardians — a registered element whose watched object is still
///     reachable keeps its representative alive (weakly: the representative
///     survives but nothing it references becomes reachable). An element
///     whose watched object is unreachable is resurrected: it moves to the
///     guardian's ready queue and both its fields are kept alive, ready for a
///     zero-argument `(g)` call.
///
/// Ephemerons are processed before guardians each round so that a key kept
/// alive only by a still-live ephemeron value is seen before any guardian
/// decision; the two structures feed each other, so the whole thing iterates
/// until neither makes progress.
///
/// The one rule that shapes the whole function is the resurrection
/// hypothetical (#2011): "if all locations denoted by the fields of guarded
/// elements or by resurrected elements of all guardians were weakly
/// resurrected." Weak resurrection means *kept alive without being
/// reachable* — so guardian probes (which use `weakReachable`, marked bits
/// only) must never see a ready-queue hold or a same-collection
/// resurrection, or a second guardian watching the same object starves for
/// as long as the first holds it. Two consequences:
///
///   * every registered element of every guardian is probed against the
///     frozen mark state *before* any element is resurrected in that round,
///     so N guardians (or N registrations) watching one object all fire in
///     the same collection;
///   * ready-queue contents are recorded in `weak_resurrected` instead of
///     being marked, and only `keptAlive` — the probe used by ephemeron and
///     transport-cell keys, which the spec keeps alive rather than ignores —
///     consults that set.
///
/// Transport cells (SRFI-254: "the content of the key field is stored in a
/// weakly holding location") hold their value strongly but defer the key to
/// the post-fixpoint pass below, which breaks every cell whose key is
/// neither reachable nor kept alive (#2006). Cells never *transport* on this
/// non-moving collector, so a transport cell guardian's ready queue stays
/// empty and `(tg)` always returns `#f` — that part is conformant; the
/// breaking is what the strong key hold used to lose.
fn processWeakRefs(gc: *GC) void {
    // Settled: one full round has run since the settle pass last marked
    // something without any of the three resolution phases making progress.
    // The settle pass's marking can itself discover weak structures (an
    // ephemeron reachable only from a resurrected representative, say), and
    // those discoveries get one more round before the break/break/materialize
    // tail runs — without the flag, a marking-only settle would loop forever.
    var settled = false;
    while (true) {
        var progress = false;

        // Ephemerons: retain the value of every ephemeron whose key is kept
        // alive, and drop it from the pending set. The key itself is not
        // marked here: a key kept alive only by a weak resurrection must not
        // become *reachable* to a guardian probe in a later round (#2011);
        // the settle pass materializes its survival instead.
        var i: usize = 0;
        while (i < gc.pending_ephemerons.items.len) {
            const eph_val = gc.pending_ephemerons.items[i];
            const eph = types.toObject(eph_val).as(Ephemeron);
            if (keptAlive(gc, eph.key)) {
                markValue(gc, eph.value);
                _ = gc.pending_ephemerons.swapRemove(i); // moved last into i
                progress = true;
            } else {
                i += 1;
            }
        }

        // Object guardians. Probe sub-pass first, apply sub-pass second, so
        // that every probe in a round sees the same mark state: the resurrect
        // branch used to mark the watched object on the spot, and a later
        // entry (in this or another guardian) then probed it as reachable
        // and starved (#2011).
        var gi: usize = 0;
        while (gi < gc.pending_guardians.items.len) : (gi += 1) {
            const g = types.toObject(gc.pending_guardians.items[gi]).as(Guardian);

            // Probe: partition registered elements by the frozen mark state.
            // No marking, no mutation — nothing here can change an answer a
            // later probe would give.
            var resurrect: std.ArrayList(types.GuardEntry) = .empty;
            defer resurrect.deinit(gc.allocator);
            var keep_len: usize = 0;
            for (g.registered.items) |e| {
                if (weakReachable(gc, e.watched)) {
                    g.registered.items[keep_len] = e;
                    keep_len += 1;
                } else {
                    resurrect.append(gc.allocator, e) catch
                        @panic("GC guardian: resurrect buffer OOM");
                }
            }
            g.registered.shrinkRetainingCapacity(keep_len);

            // Apply. Resurrected elements move to the ready queue, their
            // watched object and representative kept alive weakly — never
            // marked, never reachable. Kept elements retain their
            // representative the same way: the representative is reachable
            // only through the element, and the spec makes the fields of
            // guarded elements part of the weak-resurrection hypothetical.
            for (g.registered.items) |e| {
                if (!keptAlive(gc, e.payload)) {
                    noteWeakResurrection(gc, e.payload);
                    progress = true;
                }
            }
            for (resurrect.items) |e| {
                noteWeakResurrection(gc, e.watched);
                noteWeakResurrection(gc, e.payload);
                g.ready.append(gc.allocator, e) catch @panic("GC guardian: ready queue OOM");
                progress = true;
            }
        }

        if (progress) {
            settled = false;
            continue;
        }
        if (settled) break;

        // Settle: materialize the weak resurrections — everything the set
        // holds (ready queues, freshly resurrected elements, retained
        // representatives) must survive the sweep, now that every weak
        // decision of this round is made. Iterated by index: the marking can
        // reach a guardian not yet registered (one only referenced from a
        // resurrected representative), and markValueInner appends it to
        // pending_guardians mid-loop. Residual, deliberately kept: a guardian
        // discovered *by this marking* probes in the next round against the
        // now-materialized marks, so an entry of its watching an already
        // weakly-resurrected object keeps rather than fires — the same
        // bounded representative-delay corner the previous implementation
        // had for every guardian, now narrowed to settle-discovered ones.
        var si: usize = 0;
        while (si < gc.pending_guardians.items.len) : (si += 1) {
            const g = types.toObject(gc.pending_guardians.items[si]).as(Guardian);
            for (g.ready.items) |e| {
                markValue(gc, e.watched);
                markValue(gc, e.payload);
            }
            for (g.registered.items) |e| markValue(gc, e.payload);
        }
        settled = true;
    }

    // Any ephemeron still pending has a key that never became live: break
    // it. Clearing both fields (not just the key) keeps ephemeron-value
    // memory-safe, since the value is no longer marked and may now be swept.
    for (gc.pending_ephemerons.items) |eph_val| {
        const eph = types.toObject(eph_val).as(Ephemeron);
        eph.broken = true;
        eph.key = types.FALSE;
        eph.value = types.FALSE;
    }

    // Transport cells: the key field is weakly holding, so a cell whose key
    // is neither reachable nor kept alive breaks — the key location was
    // reclaimed and reads as #f from now on (#2006). The value field is an
    // ordinary strong field, marked during the strong phase, and survives
    // regardless.
    for (gc.pending_transport_cells.items) |cell_val| {
        const tc = types.toObject(cell_val).as(TransportCell);
        if (!keptAlive(gc, tc.key)) {
            tc.broken = true;
            tc.key = types.FALSE;
        }
    }

    gc.pending_ephemerons.clearRetainingCapacity();
    gc.pending_guardians.clearRetainingCapacity();
    gc.pending_transport_cells.clearRetainingCapacity();
    gc.weak_resurrected.clearRetainingCapacity();
}

/// Record `v` as weakly resurrected this collection: kept alive (the settle
/// pass marks it before the sweep) but not reachable — guardian probes never
/// see it, so every guardian watching it fires (#2011).
fn noteWeakResurrection(gc: *GC, v: Value) void {
    if (!types.isPointer(v)) return;
    const obj = types.toObject(v);
    if (obj.owner != gc.id) return;
    gc.weak_resurrected.put(obj, {}) catch
        @panic("GC: weak resurrection set OOM");
}

/// True when `v` survives this collection: an immediate, a foreign-owned
/// object, a strongly marked object — or a location SRFI-254 *keeps alive*
/// (a guardian's ready queue holds it, or it was just resurrected). Ephemeron
/// keys and transport-cell keys probe with this: a kept-alive key was not
/// reclaimed, so its ephemeron does not break and its cell does not break.
/// Guardian probes deliberately use plain weakReachable instead — a weakly
/// resurrected object is not reachable, so every guardian watching it must
/// still resurrect it (#2011).
fn keptAlive(gc: *GC, v: Value) bool {
    if (!types.isPointer(v)) return true;
    const obj = types.toObject(v);
    // #1687: same freed-header trap as weakReachable — this probe runs in
    // the same mark phase against the same potentially dangling values.
    if (comptime memory_mod.uaf_detection) {
        if (obj.owner == memory_mod.FREED_OWNER)
            @panic("GC: marking freed object (use-after-free)");
    }
    if (obj.owner != gc.id) return true;
    // #1961: a minor collection never sweeps the old generation, so every
    // old object trivially survives one — and none of them carries a mark
    // (markValueInner leaves the old generation opaque). Answer alive and
    // defer the weak decision to the next full collection, where old garbage
    // is unmarked and visible; breaking an ephemeron or resurrecting a
    // guardian entry over an old key during a minor would be destructive and
    // wrong.
    if (gc.minor_marking and obj.flags.generation == 1) return true;
    return obj.flags.marked or gc.weak_resurrected.contains(obj);
}

/// True when `v` will survive this collection independently of any weak
/// structure: immediates are never collected, foreign-owned objects are the
/// other GC's responsibility, and same-GC heap objects survive iff marked.
/// This is the *guardian* probe — a weakly resurrected object kept alive by
/// a ready queue answers false here on purpose (#2011); ephemeron and
/// transport-cell keys use keptAlive instead.
fn weakReachable(gc: *GC, v: Value) bool {
    if (!types.isPointer(v)) return true;
    const obj = types.toObject(v);
    // #1687: same freed-header trap as markValueInner — this probe runs in
    // the same mark phase, and a dangling ephemeron key would otherwise be
    // "not reachable", silently broken, and never marked (so never caught).
    if (comptime memory_mod.uaf_detection) {
        if (obj.owner == memory_mod.FREED_OWNER)
            @panic("GC: marking freed object (use-after-free)");
    }
    if (obj.owner != gc.id) return true;
    // #1961: same as keptAlive — an old object survives every minor
    // collection, so a guardian entry watching one must stay registered
    // here instead of being resurrected early.
    if (gc.minor_marking and obj.flags.generation == 1) return true;
    return obj.flags.marked;
}

// -- Sweep phase (delegated to gc_sweep.zig) --
//
// Same-name aliases keep this file's minorCollect/fullCollect call sites and
// external `gc_collect.freeObject` references resolving unchanged.
const gc_sweep = @import("gc_sweep.zig");
const sweepYoung = gc_sweep.sweepYoung;
const sweepOld = gc_sweep.sweepOld;
const sweep = gc_sweep.sweep;
pub const freeObject = gc_sweep.freeObject;

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
        .record_type => {
            const rt = obj.as(RecordType);
            if (rt.parent) |p| markValue(gc, types.makePointer(&p.header));
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
        .port => _ = types_port.forEachValue(obj.as(Port), gc, markVisitor),
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| markValue(gc, lit);
            for (tx.patterns) |pat| markValue(gc, pat);
            for (tx.templates) |tmpl| markValue(gc, tmpl);
            markValue(gc, tx.def_env_val);
            markValue(gc, tx.proc);
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
        .complex => {
            const cx = obj.as(types.Complex);
            markValue(gc, cx.real);
            markValue(gc, cx.imag);
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
        .process => {
            const proc = obj.as(types.Process);
            markValue(gc, proc.stdin_port);
            markValue(gc, proc.stdout_port);
            markValue(gc, proc.stderr_port);
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            markValue(gc, m.name);
            markValue(gc, m.owner);
            markValue(gc, m.owner_thread);
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
            // #2377: an .owned == false wrapper's map IS the owning VM's
            // root-marked globals map (interaction-environment is the only
            // such constructor) — markVmRoots marks every value in it each
            // collection regardless, so walking it here was idempotent
            // redundancy. Mirrors the referencesYoung guard; a child-thread
            // wrapper's values are foreign to this GC and the owner check
            // in markValueInner skips them anyway.
            if (!se.owned) return;
            var vit = se.env.valueIterator();
            while (vit.next()) |val| markValue(gc, val.*);
        },
        .ephemeron => registerPendingEphemeron(gc, obj),
        .guardian => markGuardianStrong(gc, obj),
        .transport_cell => {
            // The value field is strong; the key field is weakly holding
            // (SRFI-254) and is resolved by processWeakRefs (#2006).
            const tc = obj.as(TransportCell);
            markValue(gc, tc.value);
            registerPendingTransportCell(gc, obj);
        },
        .symbol, .string, .native_fn, .flonum, .bytevector, .bignum, .ffi_library, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time, .numeric_vector => {},
    }
}

// -- The three actions types_port.forEachValue drives (audit v2, 7A) --
//
// One enumeration of a port's Values, three different things to do with
// each. This is what replaced the hand-kept triplicate: markPortValues
// (recursive, for markObjectContents), an inline worklist.append list in
// markValueInner, and an inline isYoungPointer list in referencesYoung.
// Each visitor keeps its own arm's exact previous semantics -- in
// particular markValueInner still appends to the caller's worklist rather
// than recursing through markValue, which is why it could not simply call
// markPortValues before.

/// referencesYoung: stop at the first young referent.
fn youngVisitor(gc: *GC, v: Value) bool {
    return isYoungPointer(gc, v);
}

/// markObjectContents: mark every referent, never stop early.
fn markVisitor(gc: *GC, v: Value) bool {
    markValue(gc, v);
    return false;
}

/// markValueInner: push every referent onto the caller's worklist.
const WorklistVisitor = struct {
    gc: *GC,
    worklist: *std.ArrayList(Value),

    fn visit(self: WorklistVisitor, v: Value) bool {
        self.worklist.append(self.gc.allocator, v) catch @panic("GC mark: worklist OOM");
        return false;
    }
};

/// Record a reachable ephemeron for the post-mark weak fixpoint without tracing
/// its key or value — those are decided by processWeakRefs.
fn registerPendingEphemeron(gc: *GC, obj: *Object) void {
    gc.pending_ephemerons.append(gc.allocator, types.makePointer(obj)) catch
        @panic("GC: pending ephemerons OOM");
}

/// Record a reachable transport cell for post-fixpoint key resolution without
/// tracing its key: the key field is weakly holding (SRFI-254), so its
/// liveness is decided by processWeakRefs once every other question is
/// settled (#2006). The value field is strong and is traced normally.
fn registerPendingTransportCell(gc: *GC, obj: *Object) void {
    gc.pending_transport_cells.append(gc.allocator, types.makePointer(obj)) catch
        @panic("GC: pending transport cells OOM");
}

/// Record a reachable object guardian for the resurrection fixpoint, and fold
/// the contents of its ready queue — elements resurrected by an earlier
/// collection and not yet retrieved — into the weak-resurrection set. Those
/// contents are kept alive without being reachable (#2011); the settle pass
/// of processWeakRefs materializes their survival once every weak decision
/// is made.
fn registerPendingGuardian(gc: *GC, obj: *Object) void {
    gc.pending_guardians.append(gc.allocator, types.makePointer(obj)) catch
        @panic("GC: pending guardians OOM");
    const g = obj.as(Guardian);
    for (g.ready.items) |e| {
        noteWeakResurrection(gc, e.watched);
        noteWeakResurrection(gc, e.payload);
    }
}

/// Mark the strongly-held fields of a reachable guardian and record the weak
/// structures for processWeakRefs. Marking uses gc.markValue so it composes
/// whether called from the worklist drain or the remembered-set walk.
///
/// A transport cell guardian holds its registered cells strongly — the cells
/// themselves, that is; each cell then defers its key via the
/// `.transport_cell` arm. Cells never transport on this non-moving
/// collector, so the ready queue stays empty and nothing ever resurrects.
///
/// An object guardian holds *nothing* strongly here. Its registered elements
/// are weak by definition, and its ready (already resurrected) elements are
/// weak resurrections (#2011): marking them in the strong phase made every
/// other guardian's probe on the same object answer "reachable", so a second
/// guardian starved for as long as the first held the object in its queue.
fn markGuardianStrong(gc: *GC, obj: *Object) void {
    const g = obj.as(Guardian);
    if (g.is_transport) {
        for (g.registered.items) |e| markValue(gc, e.watched);
        for (g.ready.items) |e| markValue(gc, e.watched);
    } else {
        registerPendingGuardian(gc, obj);
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
    {
        memory_mod.spinLock(&memory_mod.symbol_mutex);
        defer memory_mod.spinUnlock(&memory_mod.symbol_mutex);
        var it = gc.symbols.valueIterator();
        while (it.next()) |v| {
            markValue(gc, v.*);
        }
        // Mark VM-owned roots (live registers, call frames, handlers, winds).
        if (gc.root_marker) |mark| mark(gc);
    }
    // #1933: with live SRFI-18 children, also mark each child's roots (the
    // children are stopped at safepoints first — see markLiveChildRoots).
    // Must run OUTSIDE the symbol_mutex section: a child mid-init,
    // deep-copying its thunk (threadEntryFn → child_gc.deepCopy →
    // allocSymbol), can be blocked on that same mutex, and stopping it — the
    // parent waits for the child to park — would deadlock. Atomic load:
    // threadStartImpl registers the marker from any thread.
    if (@atomicLoad(?*const fn (*GC) void, &gc.child_marker, .acquire)) |mark| mark(gc);
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
        // #1687: a freed header is stamped FREED_OWNER before its slot is
        // released (and, under gc-stress, the slot is quarantined so this
        // read stays defined). Marking one means a dangling value reached
        // the mark phase — an unrooted-local bug like #1682. Panic here,
        // deterministically, instead of letting the foreign-owner skip
        // below absorb it silently.
        if (comptime memory_mod.uaf_detection) {
            if (obj.owner == memory_mod.FREED_OWNER)
                @panic("GC: marking freed object (use-after-free)");
        }
        // Never mark or trace an object owned by another GC. Its owner keeps
        // it alive (shared globals are marked by the parent, interned symbols
        // are never swept, a thread's thunk is extra-rooted until join), and
        // writing this GC's mark bits into it would corrupt the owner's
        // concurrent mark/sweep cycle — the owner would see a spurious
        // "already marked" object, skip tracing its children, and sweep live
        // descendants (#958).
        if (obj.owner != gc.id) return;
        // #1961: during a minor collection the old generation is opaque. Old
        // objects are never swept by sweepYoung, so they need no mark — and
        // not tracing them is what makes the minor mark cheap. Every live
        // old→young edge reaches this phase through the remembered-set walk
        // instead (writeBarrier at each mutation site plus the promotion
        // scan in sweepYoung), which is exactly why a missing barrier is a
        // use-after-free here, not a retention miss.
        if (gc.minor_marking and obj.flags.generation == 1) {
            gc.stats.minor_old_skips += 1;
            return;
        }
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
            worklist.append(gc.allocator, tx.proc) catch @panic("GC mark: worklist OOM");
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
        .record_type => {
            const rt = obj.as(RecordType);
            if (rt.parent) |p| {
                worklist.append(gc.allocator, types.makePointer(&p.header)) catch @panic("GC mark: worklist OOM");
            }
        },
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
        // Same enumeration as markObjectContents and referencesYoung, a
        // different action: this switch drives an explicit worklist rather
        // than recursing (audit v2, 7A).
        .port => _ = types_port.forEachValue(
            obj.as(Port),
            WorklistVisitor{ .gc = gc, .worklist = worklist },
            WorklistVisitor.visit,
        ),
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
        .complex => {
            const cx = obj.as(types.Complex);
            worklist.append(gc.allocator, cx.real) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, cx.imag) catch @panic("GC mark: worklist OOM");
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
        .process => {
            const proc = obj.as(types.Process);
            worklist.append(gc.allocator, proc.stdin_port) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, proc.stdout_port) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, proc.stderr_port) catch @panic("GC mark: worklist OOM");
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            worklist.append(gc.allocator, m.name) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, m.owner) catch @panic("GC mark: worklist OOM");
            worklist.append(gc.allocator, m.owner_thread) catch @panic("GC mark: worklist OOM");
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
            // #2377: same rationale as the markObjectContents arm — an
            // .owned == false wrapper's map is root-marked by markVmRoots
            // every collection, so queueing its values here was idempotent
            // redundancy.
            if (!se.owned) return;
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
                // Transport cells are held strongly; marking each cell defers
                // its key and traces its value via the `.transport_cell` arm.
                for (g.registered.items) |e| worklist.append(gc.allocator, e.watched) catch @panic("GC mark: worklist OOM");
                for (g.ready.items) |e| worklist.append(gc.allocator, e.watched) catch @panic("GC mark: worklist OOM");
            } else {
                // Both queues are weakly held — ready (resurrected) contents
                // are weak resurrections, registered elements await their
                // probe — so neither may be marked here (#2011).
                registerPendingGuardian(gc, obj);
            }
        },
        .transport_cell => {
            // Value strong, key deferred to processWeakRefs (#2006).
            const tc = obj.as(TransportCell);
            worklist.append(gc.allocator, tc.value) catch @panic("GC mark: worklist OOM");
            gc.pending_transport_cells.append(gc.allocator, cur) catch @panic("GC mark: pending transport cells OOM");
        },
        .symbol, .string, .native_fn, .flonum, .bytevector, .bignum, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time, .numeric_vector => {},
    }
}
