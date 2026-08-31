//! Per-`ObjectTag` reachability under a forced collection — the coverage the
//! five exhaustive per-tag switches cannot provide (audit v2, Phase 7B).
//!
//! Zig's exhaustiveness check guarantees that `markObjectContents`,
//! `markValueInner` and `referencesYoung` (gc_collect.zig) plus `objectSize`
//! and `freeObject` (gc_sweep.zig) each have an *arm* for all 41 tags. Nothing
//! guarantees what is *inside* an arm: a tag whose arm forgets one of its
//! Value fields compiles cleanly and traces nothing, and the referent is
//! silently freed while still live.
//!
//! `Port` used to be the worst case — its satellites were hand-written at all
//! five sites, and `markValueInner` deliberately duplicated `markPortValues`
//! rather than calling it. Phase 7A measured that (a third Value-bearing field
//! was missed by 3 of the 5, or by all 5 for a brand-new satellite, in both
//! cases an observed use-after-free) and replaced the triplicate with one
//! enumeration, `types_port.forEachValue`, plus `satelliteBytes` /
//! `destroySatellites` for the two sweep arms. The port cases below now guard
//! that single walker; "port satellite walkers" at the end is its own
//! mutation test, deriving the expected Value count from `@typeInfo`
//! independently of the walk it checks.
//!
//! Every *other* tag still hand-writes its three mark arms, so the runtime
//! cases here remain the only check on them.
//!
//! Two runtime shapes, because the three mark-graph switches are reached by
//! two different paths:
//!
//!   * `expectTraced` (Test A) roots the container, so `markRoots` →
//!     `markValue` → **`markValueInner`** is the only thing that can keep the
//!     referent alive.
//!   * `expectRememberedTrace` (Test B) promotes the container to the old
//!     generation, repoints a field at a fresh young object through
//!     `writeBarrier`, and then drops the root before a *minor* collection.
//!     Old objects are never swept by a minor collection, so the container
//!     survives while being unreachable from every root — which makes the
//!     remembered-set walk (**`markObjectContents`**, its only caller) the
//!     only thing that can mark the referent, and `pruneRememberedSet`'s
//!     retention decision (**`referencesYoung`**) directly observable.
//!
//! Every Test A case ends with a discriminating control: with the container
//! unrooted the same referents MUST be reclaimed. Without it "still alive"
//! proves nothing — an assertion that cannot fail is not a test.
//!
//! Liveness is decided by walking the GC's own `objects`/`old_objects` lists
//! for the referent's address, never by dereferencing it: a swept referent is
//! freed (and, in Debug/gc-stress builds, poisoned), so reading it back would
//! be the very use-after-free this file exists to detect.
//!
//! `objectSize` and `freeObject` are *not* reachability switches — a wrong
//! arm there leaks or double-frees rather than losing a referent, which
//! `std.testing.allocator`'s own leak check already catches on every test in
//! this file (each one allocates through the GC and tears it down).
//!
//! The comptime inventory at the bottom is the compiler-enforced half: it
//! pins the exact field list of every heap struct these switches dispatch on,
//! so adding a field is a build error until someone has looked at the arms.

const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");
const fiber_mod = @import("fiber.zig");
const globals_mod = @import("globals.zig");
const th = @import("testing_helpers.zig");

const Value = types.Value;
const Object = types.Object;

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// A referent the container under test must keep alive. `id` is the `car` a
/// pair referent must still hold afterwards; it is null for the handful of
/// referents that have to be some other type (a `*RecordType` for
/// `RecordType.parent`, a `*Function` for `Closure.func`, ...), where pointer
/// identity plus the tag is the whole check.
const Ref = struct {
    val: Value,
    id: ?i64 = null,
};

/// A fresh young heap object nothing else references, tagged with `id` so a
/// surviving referent can be told apart from a recycled slot.
fn young(gc: *memory.GC, id: i64) !Value {
    return gc.allocPair(types.makeFixnum(id), types.NIL);
}

fn ref(val: Value, id: i64) Ref {
    return .{ .val = val, .id = id };
}

/// True iff `obj` is still on one of this GC's object lists. Deliberately
/// never dereferences `obj` itself.
fn isLive(gc: *memory.GC, obj: *Object) bool {
    var cur = gc.objects;
    while (cur) |o| : (cur = o.next) if (o == obj) return true;
    cur = gc.old_objects;
    while (cur) |o| : (cur = o.next) if (o == obj) return true;
    return false;
}

fn inRemembered(gc: *memory.GC, obj: *Object) bool {
    for (gc.remembered_set.items) |o| if (o == obj) return true;
    return false;
}

fn expectAlive(gc: *memory.GC, r: Ref) !void {
    const obj = types.toObject(r.val);
    if (!isLive(gc, obj)) {
        std.debug.print("\nreferent was reclaimed while its container was reachable\n", .{});
        return error.ReferentCollected;
    }
    if (r.id) |id| try std.testing.expectEqual(types.makeFixnum(id), obj.as(types.Pair).car);
}

fn expectDead(gc: *memory.GC, r: Ref) !void {
    if (isLive(gc, types.toObject(r.val))) {
        std.debug.print("\nreferent survived with nothing referencing it — " ++
            "this case's positive assertions prove nothing\n", .{});
        return error.ControlNotDiscriminating;
    }
}

/// `collect()` runs a full collection every 8th cycle; drive the choice
/// explicitly instead of depending on the cycle counter's history.
fn forceMinor(gc: *memory.GC) void {
    gc.minor_cycle_count = 0;
    gc.collect();
}

fn forceFull(gc: *memory.GC) void {
    gc.minor_cycle_count = 7;
    gc.collect();
}

/// Two surviving minor collections promote a young object to the old
/// generation (`sweepYoung`: `survive_count >= 2`).
fn promoteToOld(gc: *memory.GC, v: Value) !void {
    var root = v;
    gc.pushRoot(&root);
    forceMinor(gc);
    forceMinor(gc);
    gc.popRoot();
    try std.testing.expectEqual(@as(u1, 1), types.toObject(v).flags.generation);
}

/// Test A — `markValueInner`, via the root set.
fn expectTraced(gc: *memory.GC, container: Value, refs: []const Ref) !void {
    var root = container;
    gc.pushRoot(&root);
    forceMinor(gc);
    for (refs) |r| try expectAlive(gc, r);
    forceFull(gc);
    for (refs) |r| try expectAlive(gc, r);
    gc.popRoot();

    // Discriminating control.
    forceFull(gc);
    for (refs) |r| try expectDead(gc, r);
}

/// Test B — `markObjectContents` and `referencesYoung`, via the remembered
/// set. `container` must already be old and carry a `writeBarrier`-recorded
/// young reference to every entry in `refs`.
fn expectRememberedTrace(gc: *memory.GC, container: Value, refs: []const Ref) !void {
    const cobj = types.toObject(container);
    try std.testing.expectEqual(@as(u1, 1), cobj.flags.generation);
    // Without this the case would be vacuous: nothing would walk the object.
    try std.testing.expect(inRemembered(gc, cobj));

    forceMinor(gc);
    for (refs) |r| try expectAlive(gc, r);

    // The referents survived exactly one minor collection, so they are still
    // young — `referencesYoung` must therefore still say yes and the entry
    // must still be there. A missing field in that arm drops the entry, and
    // with it every later collection's only route to these referents.
    try std.testing.expect(inRemembered(gc, cobj));
}

/// Every test here drives collection by hand: `enabled = false` stops
/// allocation from collecting underneath the setup (so intermediates need no
/// rooting), and makes the suite behave identically under `-Dgc-stress=true`,
/// where an implicit collection at every allocation would otherwise reclaim
/// a container before its fields were even filled in.
fn newGc() memory.GC {
    var gc = memory.GC.init(std.testing.allocator);
    gc.enabled = false;
    return gc;
}

fn dummyNative(_: []const Value) anyerror!Value {
    return types.NIL;
}

fn dummyNativeClosure(_: ?*@import("vm.zig").VM, _: [*]const Value, _: u64, _: [*]const Value) callconv(.c) u64 {
    return types.NIL;
}

/// A throwaway non-null address for the `*anyopaque` handles a few
/// constructors demand (an FFI symbol, a `DIR*`). Never dereferenced: the
/// FFI arms only trace `library`/`closure`, and the directory arm's handle is
/// cleared before any sweep can reach `dirIterDestroy`.
var opaque_handle: u64 = 0;

// ---------------------------------------------------------------------------
// Tags with Value-bearing fields — Test A (markValueInner)
// ---------------------------------------------------------------------------

test "gc tracing: pair traces car and cdr" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const c = try gc.allocPair(a, b);
    try expectTraced(&gc, c, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing: vector traces every element" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const c = try young(&gc, 3);
    const v = try gc.allocVector(&.{ a, types.makeFixnum(0), b, c });
    try expectTraced(&gc, v, &.{ ref(a, 1), ref(b, 2), ref(c, 3) });
}

test "gc tracing: closure traces func and upvalues" {
    var gc = newGc();
    defer gc.deinit();
    const func = try gc.allocFunction();
    func.upvalue_count = 2;
    const cls = try gc.allocClosure(func);
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const c = types.toObject(cls).as(types.Closure);
    c.upvalues[0] = a;
    c.upvalues[1] = b;
    try expectTraced(&gc, cls, &.{
        .{ .val = types.makePointer(&func.header) },
        ref(a, 1),
        ref(b, 2),
    });
}

test "gc tracing: function traces constants, global cache and env_val" {
    var gc = newGc();
    defer gc.deinit();
    const func = try gc.allocFunction();
    const konst = try young(&gc, 1);
    const cached = try young(&gc, 2);
    const env = try young(&gc, 3);
    try func.constants.append(gc.allocator, konst);
    const cache = try gc.allocator.alloc(Value, 1);
    cache[0] = cached;
    func.global_cache = cache;
    func.env_val = env;
    try expectTraced(&gc, types.makePointer(&func.header), &.{
        ref(konst, 1), ref(cached, 2), ref(env, 3),
    });
}

test "gc tracing: native_closure traces upvalues" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const nc = try gc.allocNativeClosure(&dummyNativeClosure, &.{ a, b }, 0, "probe");
    try expectTraced(&gc, nc, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing: record_type traces parent" {
    var gc = newGc();
    defer gc.deinit();
    const parent = try gc.allocRecordType("parent", 0);
    const child = try gc.allocRecordTypeExtended(
        "child",
        types.toObject(parent).as(types.RecordType),
        &.{},
        &.{},
        null,
        false,
        false,
    );
    try expectTraced(&gc, child, &.{.{ .val = parent }});
}

test "gc tracing: record_instance traces record_type and fields" {
    var gc = newGc();
    defer gc.deinit();
    const rt = try gc.allocRecordType("probe", 2);
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const ri = try gc.allocRecordInstance(types.toObject(rt).as(types.RecordType), &.{ a, b });
    try expectTraced(&gc, ri, &.{ .{ .val = rt }, ref(a, 1), ref(b, 2) });
}

test "gc tracing: hash_table traces equiv/hash procs and every occupied entry" {
    var gc = newGc();
    defer gc.deinit();
    const eq = try young(&gc, 1);
    const hash = try young(&gc, 2);
    const key = try young(&gc, 3);
    const val = try young(&gc, 4);
    const ht_val = try gc.allocHashTable(8);
    const ht = types.toObject(ht_val).as(types.HashTable);
    ht.equiv_fn = eq;
    ht.hash_fn = hash;
    ht.compare_mode = .custom;
    ht.entries[0] = .{ .key = key, .value = val, .hash = 0, .state = .occupied };
    ht.count = 1;
    try expectTraced(&gc, ht_val, &.{ ref(eq, 1), ref(hash, 2), ref(key, 3), ref(val, 4) });
}

test "gc tracing: promise traces value" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const p = try gc.allocPromise(true, a);
    try expectTraced(&gc, p, &.{ref(a, 1)});
}

test "gc tracing: parameter traces value and converter" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const p = try gc.allocParameter(a, b);
    try expectTraced(&gc, p, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing: port traces all six custom-backend callbacks" {
    var gc = newGc();
    defer gc.deinit();
    const rd = try young(&gc, 1);
    const wr = try young(&gc, 2);
    const gp = try young(&gc, 3);
    const sp = try young(&gc, 4);
    const cl = try young(&gc, 5);
    const fl = try young(&gc, 6);
    const port = try gc.allocCustomPort(true, true, false, rd, wr, gp, sp, cl, fl);
    try expectTraced(&gc, port, &.{
        ref(rd, 1), ref(wr, 2), ref(gp, 3), ref(sp, 4), ref(cl, 5), ref(fl, 6),
    });
}

test "gc tracing: port traces transcode wrapped_port" {
    var gc = newGc();
    defer gc.deinit();
    const wrapped = try young(&gc, 1);
    const port = try gc.allocTranscodedPort(wrapped, true, false, .utf8, .lf, .replace);
    try expectTraced(&gc, port, &.{ref(wrapped, 1)});
}

test "gc tracing: transformer traces rules, proc, def_env_val and peer vals" {
    var gc = newGc();
    defer gc.deinit();
    const lit = try young(&gc, 1);
    const pat = try young(&gc, 2);
    const tmpl = try young(&gc, 3);
    const proc = try young(&gc, 4);
    const env = try young(&gc, 5);
    const peer = try young(&gc, 6);
    const tx_val = try gc.allocTransformer(&.{lit}, &.{pat}, &.{tmpl});
    const tx = types.toObject(tx_val).as(types.Transformer);
    tx.kind = .er_macro;
    tx.proc = proc;
    tx.def_env_val = env;
    const peers = try gc.allocator.alloc(Value, 1);
    peers[0] = peer;
    tx.let_syntax_peer_vals = peers;
    try expectTraced(&gc, tx_val, &.{
        ref(lit, 1), ref(pat, 2), ref(tmpl, 3), ref(proc, 4), ref(env, 5), ref(peer, 6),
    });
}

test "gc tracing: error_object traces message, irritants and uncaught_reason" {
    var gc = newGc();
    defer gc.deinit();
    const msg = try young(&gc, 1);
    const irr = try young(&gc, 2);
    const reason = try young(&gc, 3);
    const err = try gc.allocErrorObject(msg, irr);
    types.toObject(err).as(types.ErrorObject).uncaught_reason = reason;
    try expectTraced(&gc, err, &.{ ref(msg, 1), ref(irr, 2), ref(reason, 3) });
}

test "gc tracing: continuation traces registers, frames, handlers and winds" {
    var gc = newGc();
    defer gc.deinit();
    const reg = try young(&gc, 1);
    const handler = try young(&gc, 2);
    const before = try young(&gc, 3);
    const after = try young(&gc, 4);
    const func = try gc.allocFunction();
    const cls = try gc.allocClosure(func);
    const nf = try gc.allocNativeFn("probe", &dummyNative, .{ .exact = 0 });

    const registers = [_]Value{ reg, types.makeFixnum(0) };
    const frames = [_]types.SavedFrame{.{
        .closure = types.toObject(cls).as(types.Closure),
        .native = types.toObject(nf).as(types.NativeFn),
        .code = &.{},
        .ip = 0,
        .base = 0,
        .dst = 0,
        .saved_wind_count = 0,
        .returns_to_native = false,
        .seq = 0,
    }};
    const handlers = [_]types.SavedHandler{.{ .handler = handler, .frame_count = 0 }};
    const winds = [_]types.WindRecord{.{ .before = before, .after = after }};

    const cont = try gc.allocContinuation(&registers, &frames, 1, &handlers, 1, &winds, 1, 0, 0);
    try expectTraced(&gc, cont, &.{
        ref(reg, 1),
        ref(handler, 2),
        ref(before, 3),
        ref(after, 4),
        .{ .val = cls },
        .{ .val = nf },
    });
}

test "gc tracing: multiple_values traces every value" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const mv = try gc.allocMultipleValues(&.{ a, types.TRUE, b });
    try expectTraced(&gc, mv, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing: complex traces real and imaginary components" {
    var gc = newGc();
    defer gc.deinit();
    const r = try young(&gc, 1);
    const i = try young(&gc, 2);
    const cx = try gc.allocComplex(r, i);
    try expectTraced(&gc, cx, &.{ ref(r, 1), ref(i, 2) });
}

test "gc tracing: rational traces numerator and denominator" {
    var gc = newGc();
    defer gc.deinit();
    const n = try young(&gc, 1);
    const d = try young(&gc, 2);
    const rat = try gc.allocRational(n, d);
    try expectTraced(&gc, rat, &.{ ref(n, 1), ref(d, 2) });
}

test "gc tracing: ffi_function traces library" {
    var gc = newGc();
    defer gc.deinit();
    const lib = try young(&gc, 1);
    const fn_val = try gc.allocFfiFunction(@ptrCast(&opaque_handle), lib, "probe", &.{}, .void_type);
    try expectTraced(&gc, fn_val, &.{ref(lib, 1)});
}

test "gc tracing: ffi_callback traces closure" {
    var gc = newGc();
    defer gc.deinit();
    const cls = try young(&gc, 1);
    // Slot 255 is past NUM_SLOTS, so freeObject's releaseSlot is a no-op and
    // this never disturbs a real callback registration.
    const cb = try gc.allocFfiCallback(cls, 255, @ptrCast(&opaque_handle));
    try expectTraced(&gc, cb, &.{ref(cls, 1)});
}

test "gc tracing: channel traces head and tail" {
    var gc = newGc();
    defer gc.deinit();
    const head = try young(&gc, 1);
    const tail = try young(&gc, 2);
    const ch_val = try gc.allocChannel();
    const ch = types.toObject(ch_val).as(types.Channel);
    ch.head = head;
    ch.tail = tail;
    try expectTraced(&gc, ch_val, &.{ ref(head, 1), ref(tail, 2) });
}

test "gc tracing: process traces its three pipe ports" {
    var gc = newGc();
    defer gc.deinit();
    const stdin_port = try young(&gc, 1);
    const stdout_port = try young(&gc, 2);
    const stderr_port = try young(&gc, 3);
    const proc = try gc.allocProcess(123, 0);
    proc.stdin_port = stdin_port;
    proc.stdout_port = stdout_port;
    proc.stderr_port = stderr_port;
    try expectTraced(&gc, types.makePointer(&proc.header), &.{
        ref(stdin_port, 1),
        ref(stdout_port, 2),
        ref(stderr_port, 3),
    });
    // Reaped in teardown: allocProcess enrolled it in unreaped_processes,
    // and freeObject (via the sweep the next collection runs) removes it —
    // the pid is bogus, but it is never waited on: the sweep and
    // freeObject's last-resort reap tolerate a dead pid (ECHILD).
    gc.collectFull();
}

test "gc tracing: mutex traces name, owner and specific" {
    var gc = newGc();
    defer gc.deinit();
    const name = try young(&gc, 1);
    const owner = try young(&gc, 2);
    const owner_thread = try young(&gc, 4);
    const specific = try young(&gc, 3);
    const m_val = try gc.allocMutex(name);
    const m = types.toObject(m_val).as(types.Mutex);
    m.owner = owner;
    m.owner_thread = owner_thread;
    m.specific = specific;
    try expectTraced(&gc, m_val, &.{ ref(name, 1), ref(owner, 2), ref(owner_thread, 4), ref(specific, 3) });
}

test "gc tracing: condition_variable traces name and specific" {
    var gc = newGc();
    defer gc.deinit();
    const name = try young(&gc, 1);
    const specific = try young(&gc, 2);
    const cv_val = try gc.allocConditionVariable(name);
    types.toObject(cv_val).as(types.ConditionVariable).specific = specific;
    try expectTraced(&gc, cv_val, &.{ ref(name, 1), ref(specific, 2) });
}

test "gc tracing: scheme_environment traces every binding" {
    var gc = newGc();
    defer gc.deinit();
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const map = try gc.allocator.create(std.StringHashMap(Value));
    map.* = std.StringHashMap(Value).init(gc.allocator);
    try map.put("a", a);
    try map.put("b", b);
    const env = try gc.allocEnvironment(map, true, false);
    try expectTraced(&gc, env, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing: .owned == false environment wrapper skips its map (#2377)" {
    var gc = newGc();
    defer gc.deinit();
    // interaction-environment shape: the map plays the owning VM's globals,
    // whose values are root-marked every collection (markVmRoots) — the
    // wrapper's own trace must not walk it. The map stays the test's to
    // free: freeObject leaves an .owned == false wrapper's map alone.
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const map = try gc.allocator.create(std.StringHashMap(Value));
    map.* = std.StringHashMap(Value).init(gc.allocator);
    try map.put("a", a);
    try map.put("b", b);
    defer {
        map.deinit();
        gc.allocator.destroy(map);
    }
    const env = try gc.allocEnvironment(map, false, false);
    try std.testing.expect(!types.toObject(env).as(types.SchemeEnvironment).owned);

    // Root-marked simulation: the wrapper and one separately-rooted map
    // value survive minor and full collections with both mark arms
    // skipping the walk.
    var env_root = env;
    gc.pushRoot(&env_root);
    var a_root = a;
    gc.pushRoot(&a_root);
    forceMinor(&gc);
    try expectAlive(&gc, ref(a, 1));
    forceFull(&gc);
    try expectAlive(&gc, ref(a, 1));
    gc.popRoot();
    gc.popRoot();

    // Discriminating control: with only the wrapper rooted, the un-rooted
    // map value must be reclaimed — before #2377 the wrapper's redundant
    // walk re-marked it through every collection.
    var only_wrapper = env;
    gc.pushRoot(&only_wrapper);
    forceFull(&gc);
    try expectDead(&gc, ref(b, 2));
    gc.popRoot();
}

test "gc tracing: transport_cell traces value, holds key weakly (#2006)" {
    var gc = newGc();
    defer gc.deinit();
    const k = try young(&gc, 1);
    const v = try young(&gc, 2);
    const tc = try gc.allocTransportCell(k, v);

    var root = tc;
    gc.pushRoot(&root);
    forceMinor(&gc);
    // The value is a strong field, kept alive by the rooted cell alone.
    try expectAlive(&gc, ref(v, 2));
    // The key field is weakly holding (SRFI-254): nothing else roots `k`, so
    // its location was reclaimed and the cell broke.
    const cell = types.toObject(tc).as(types.TransportCell);
    try std.testing.expect(cell.broken);
    try std.testing.expectEqual(types.FALSE, cell.key);
    forceFull(&gc);
    try expectAlive(&gc, ref(v, 2));
    gc.popRoot();

    // Discriminating control.
    forceFull(&gc);
    try expectDead(&gc, ref(v, 2));
}

test "gc tracing: fiber traces every Value-bearing field" {
    var gc = newGc();
    defer gc.deinit();
    const thunk = try young(&gc, 1);
    const fiber = try gc.allocFiber(thunk, 1);
    const fiber_val = types.makePointer(&fiber.header);

    const result = try young(&gc, 2);
    const waiting_on = try young(&gc, 3);
    const rv_demand_on = try young(&gc, 4);
    const name = try young(&gc, 5);
    const specific = try young(&gc, 6);
    const reg = try young(&gc, 7);
    const handler = try young(&gc, 8);
    const before = try young(&gc, 9);
    const after = try young(&gc, 10);
    const param = try young(&gc, 11);
    const exc = try young(&gc, 12);
    const cont_val = try young(&gc, 13);
    const io_buffer = try young(&gc, 14);
    const owned_mutex = try young(&gc, 15);

    const func = try gc.allocFunction();
    func.locals_count = 8;
    const cls = try gc.allocClosure(func);
    const nf = try gc.allocNativeFn("probe", &dummyNative, .{ .exact = 0 });

    fiber.result = result;
    fiber.waiting_on = waiting_on;
    fiber.rv_demand_on = rv_demand_on;
    fiber.name = name;
    fiber.specific = specific;
    fiber.current_exception = exc;
    fiber.continuation_value = cont_val;
    fiber.io_buffer = io_buffer;
    fiber.frames[0] = .{
        .closure = types.toObject(cls).as(types.Closure),
        .native = types.toObject(nf).as(types.NativeFn),
        .code = &.{},
        .ip = 0,
        .base = 0,
        .dst = 0,
    };
    fiber.frame_count = 1;
    fiber.registers[3] = reg;
    fiber.handler_stack[0] = .{ .handler = handler, .frame_count = 0 };
    fiber.handler_count = 1;
    fiber.wind_stack[0] = .{ .before = before, .after = after };
    fiber.wind_count = 1;
    try fiber.param_overrides.put(1, param);
    try fiber.owned_mutexes.append(gc.allocator, owned_mutex);

    try expectTraced(&gc, fiber_val, &.{
        ref(thunk, 1),        ref(result, 2),     ref(waiting_on, 3),
        ref(rv_demand_on, 4), ref(name, 5),       ref(specific, 6),
        ref(reg, 7),          ref(handler, 8),    ref(before, 9),
        ref(after, 10),       ref(param, 11),     ref(exc, 12),
        ref(cont_val, 13),    ref(io_buffer, 14), ref(owned_mutex, 15),
        .{ .val = cls },      .{ .val = nf },
    });
}

// --- SRFI 254 weak structures: traced, but conditionally ------------------

test "gc tracing: ephemeron retains its value while the key is reachable" {
    var gc = newGc();
    defer gc.deinit();
    const key = try young(&gc, 1);
    const val = try young(&gc, 2);
    const eph = try gc.allocEphemeron(key, val);

    // The key must be independently reachable: an ephemeron does not hold
    // its own key (that is the whole point of the type).
    var key_root = key;
    gc.pushRoot(&key_root);
    var eph_root = eph;
    gc.pushRoot(&eph_root);
    forceMinor(&gc);
    try expectAlive(&gc, ref(val, 2));
    forceFull(&gc);
    try expectAlive(&gc, ref(val, 2));
    gc.popRoot(); // eph_root
    gc.popRoot(); // key_root

    forceFull(&gc);
    try expectDead(&gc, ref(val, 2));
}

test "gc tracing: ephemeron with an unreachable key breaks rather than retaining" {
    var gc = newGc();
    defer gc.deinit();
    const key = try young(&gc, 1);
    const val = try young(&gc, 2);
    const eph = try gc.allocEphemeron(key, val);

    var eph_root = eph;
    gc.pushRoot(&eph_root);
    defer gc.popRoot();
    forceFull(&gc);

    // The ephemeron itself survives (it is rooted); its key and value do not.
    try std.testing.expect(isLive(&gc, types.toObject(eph)));
    try expectDead(&gc, ref(key, 1));
    try expectDead(&gc, ref(val, 2));
    const e = types.toObject(eph).as(types.Ephemeron);
    try std.testing.expect(e.broken);
    try std.testing.expectEqual(types.FALSE, e.key);
    try std.testing.expectEqual(types.FALSE, e.value);
}

test "gc tracing: object guardian keeps ready elements alive (weak resurrection)" {
    var gc = newGc();
    defer gc.deinit();
    const watched = try young(&gc, 1);
    const payload = try young(&gc, 2);
    const g_val = try gc.allocGuardian(false);
    const g = types.toObject(g_val).as(types.Guardian);
    try g.ready.append(gc.allocator, .{ .watched = watched, .payload = payload });
    // Ready (resurrected) elements are NOT traced during the strong phase
    // (#2011) — that marking made every other guardian's probe on the same
    // object answer "reachable" — but processWeakRefs' settle pass keeps
    // them alive, so liveness here is the settle pass, not markValueInner.
    try expectTraced(&gc, g_val, &.{ ref(watched, 1), ref(payload, 2) });
}

test "gc tracing: transport guardian holds registered cells strongly" {
    var gc = newGc();
    defer gc.deinit();
    const k = try young(&gc, 1);
    const v = try young(&gc, 2);
    const cell = try gc.allocTransportCell(k, v);
    const g_val = try gc.allocGuardian(true);
    const g = types.toObject(g_val).as(types.Guardian);
    try g.registered.append(gc.allocator, .{ .watched = cell, .payload = cell });

    var root = g_val;
    gc.pushRoot(&root);
    forceMinor(&gc);
    // The cell is strong, and marking it reaches its value through the
    // `.transport_cell` arm. The key is weakly holding (#2006): with nothing
    // else rooting `k`, it dies while the cell and its guardian are rooted,
    // and the cell breaks.
    try expectAlive(&gc, .{ .val = cell });
    try expectAlive(&gc, ref(v, 2));
    try expectDead(&gc, ref(k, 1));
    const tc = types.toObject(cell).as(types.TransportCell);
    try std.testing.expect(tc.broken);
    try std.testing.expectEqual(types.FALSE, tc.key);
    forceFull(&gc);
    try expectAlive(&gc, .{ .val = cell });
    try expectAlive(&gc, ref(v, 2));
    gc.popRoot();

    // Discriminating control.
    forceFull(&gc);
    try expectDead(&gc, .{ .val = cell });
    try expectDead(&gc, ref(v, 2));
}

test "gc tracing: object guardian resurrects a registered element" {
    var gc = newGc();
    defer gc.deinit();
    const watched = try young(&gc, 1);
    const payload = try young(&gc, 2);
    const g_val = try gc.allocGuardian(false);
    const g = types.toObject(g_val).as(types.Guardian);
    try g.registered.append(gc.allocator, .{ .watched = watched, .payload = payload });

    var root = g_val;
    gc.pushRoot(&root);
    defer gc.popRoot();
    forceFull(&gc);

    // `watched` is unreachable, so the element is resurrected: both fields
    // are kept alive (weakly, #2011) and it moves to the ready queue.
    try expectAlive(&gc, ref(watched, 1));
    try expectAlive(&gc, ref(payload, 2));
    try std.testing.expectEqual(@as(usize, 0), g.registered.items.len);
    try std.testing.expectEqual(@as(usize, 1), g.ready.items.len);
}

// ---------------------------------------------------------------------------
// Tags with no Value-bearing field
// ---------------------------------------------------------------------------
//
// Nothing to trace, so reachability is vacuous — but the tag must still be
// *swept* correctly, and its `freeObject` arm must release exactly what it
// owns (checked by std.testing.allocator's leak detector on GC.deinit).
// The comptime inventory below is what actually guards these against
// silently gaining a Value field.

test "gc tracing: leaf tags survive while rooted and are reclaimed when not" {
    var gc = newGc();
    defer gc.deinit();

    const dir = try gc.allocDirectoryObject(@ptrCast(&opaque_handle), false);
    // Not a real DIR*; clear it before any sweep can hand it to
    // platform.dirIterDestroy.
    types.toObject(dir).as(types.DirectoryObject).dir = null;

    // Interned symbols are permanent roots (`gc.symbols` is walked by
    // markRoots and never swept), so the symbol is the one leaf that
    // legitimately survives the control below — kept out of `leaves`.
    const sym = try gc.allocSymbol("gc-tracing-probe");

    const leaves = [_]Value{
        try gc.allocString("probe"),
        try gc.allocNativeFn("probe", &dummyNative, .{ .exact = 0 }),
        try gc.allocBytevector(&.{ 1, 2, 3 }),
        try gc.allocNumericVector(.f64, &.{ 0, 0, 0, 0, 0, 0, 0, 0 }),
        try gc.allocComplex(types.makeFixnum(1), types.makeFixnum(2)),
        try gc.allocBignumFromI64(1 << 62),
        try gc.allocFfiLibrary(null, "probe"),
        try gc.allocUserInfo("u", 0, 0, "/", "/bin/sh", "U"),
        try gc.allocGroupInfo("g", 0),
        try gc.allocRandomSource(1),
        try gc.allocSrfi18Time(1, 2, .utc),
        dir,
        try gc.allocFileInfo(.{
            .size = 0,
            .mtime = 0,
            .atime = 0,
            .ctime = 0,
            .dev = 0,
            .ino = 0,
            .nlinks = 0,
            .rdev = 0,
            .blksize = 0,
            .blocks = 0,
            .mode = 0,
            .uid = 0,
            .gid = 0,
            .file_type = .regular,
        }),
    };

    // Record each tag now: after the control collection the objects are
    // freed (and poisoned in Debug/gc-stress builds), so `obj.tag` may not
    // be read then.
    var tags: [leaves.len]types.ObjectTag = undefined;
    for (leaves, 0..) |l, i| tags[i] = types.toObject(l).tag;

    // Root them all through one vector, then collect.
    const holder = try gc.allocVector(&leaves);
    var root = holder;
    gc.pushRoot(&root);
    forceMinor(&gc);
    forceFull(&gc);
    for (leaves, tags) |l, tag| {
        if (!isLive(&gc, types.toObject(l))) {
            std.debug.print("\nleaf tag {t} was reclaimed while rooted\n", .{tag});
            return error.ReferentCollected;
        }
    }
    try std.testing.expect(isLive(&gc, types.toObject(sym)));
    gc.popRoot();

    forceFull(&gc);
    for (leaves, tags) |l, tag| {
        if (isLive(&gc, types.toObject(l))) {
            std.debug.print("\nleaf tag {t} survived unrooted\n", .{tag});
            return error.ControlNotDiscriminating;
        }
    }
    try std.testing.expect(isLive(&gc, types.toObject(sym)));
}

// ---------------------------------------------------------------------------
// Test B — markObjectContents + referencesYoung, via the remembered set
// ---------------------------------------------------------------------------

test "gc tracing (remembered set): pair" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocPair(types.NIL, types.NIL);
    try promoteToOld(&gc, c);
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const p = types.toObject(c).as(types.Pair);
    p.car = a;
    p.cdr = b;
    gc.writeBarrier(&p.header, a);
    try expectRememberedTrace(&gc, c, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing (remembered set): vector" {
    var gc = newGc();
    defer gc.deinit();
    const v = try gc.allocVectorFill(2, types.NIL);
    try promoteToOld(&gc, v);
    const a = try young(&gc, 1);
    const vec = types.toObject(v).as(types.Vector);
    vec.data[1] = a;
    gc.writeBarrier(&vec.header, a);
    try expectRememberedTrace(&gc, v, &.{ref(a, 1)});
}

test "gc tracing (remembered set): closure" {
    var gc = newGc();
    defer gc.deinit();
    const func = try gc.allocFunction();
    func.upvalue_count = 1;
    const cls = try gc.allocClosure(func);
    try promoteToOld(&gc, cls);
    const a = try young(&gc, 1);
    const c = types.toObject(cls).as(types.Closure);
    c.upvalues[0] = a;
    gc.writeBarrier(&c.header, a);
    try expectRememberedTrace(&gc, cls, &.{ref(a, 1)});
}

test "gc tracing (remembered set): function" {
    var gc = newGc();
    defer gc.deinit();
    const func = try gc.allocFunction();
    const fv = types.makePointer(&func.header);
    try promoteToOld(&gc, fv);
    const konst = try young(&gc, 1);
    const env = try young(&gc, 2);
    try func.constants.append(gc.allocator, konst);
    func.env_val = env;
    gc.writeBarrier(&func.header, konst);
    try expectRememberedTrace(&gc, fv, &.{ ref(konst, 1), ref(env, 2) });
}

test "gc tracing (remembered set): native_closure" {
    var gc = newGc();
    defer gc.deinit();
    const nc = try gc.allocNativeClosure(&dummyNativeClosure, &.{types.NIL}, 0, "probe");
    try promoteToOld(&gc, nc);
    const a = try young(&gc, 1);
    const n = types.toObject(nc).as(types.NativeClosure);
    n.upvalues[0] = a;
    gc.writeBarrier(&n.header, a);
    try expectRememberedTrace(&gc, nc, &.{ref(a, 1)});
}

test "gc tracing (remembered set): record_type parent" {
    var gc = newGc();
    defer gc.deinit();
    const child = try gc.allocRecordType("child", 0);
    try promoteToOld(&gc, child);
    const parent = try gc.allocRecordType("parent", 0);
    const rt = types.toObject(child).as(types.RecordType);
    rt.parent = types.toObject(parent).as(types.RecordType);
    gc.writeBarrier(&rt.header, parent);
    try expectRememberedTrace(&gc, child, &.{.{ .val = parent }});
}

test "gc tracing (remembered set): record_instance" {
    var gc = newGc();
    defer gc.deinit();
    const rt = try gc.allocRecordType("probe", 1);
    const ri = try gc.allocRecordInstance(types.toObject(rt).as(types.RecordType), &.{types.NIL});
    try promoteToOld(&gc, ri);
    const a = try young(&gc, 1);
    const inst = types.toObject(ri).as(types.RecordInstance);
    inst.fields[0] = a;
    gc.writeBarrier(&inst.header, a);
    try expectRememberedTrace(&gc, ri, &.{ref(a, 1)});
}

test "gc tracing (remembered set): hash_table" {
    var gc = newGc();
    defer gc.deinit();
    const ht_val = try gc.allocHashTable(8);
    try promoteToOld(&gc, ht_val);
    const eq = try young(&gc, 1);
    const key = try young(&gc, 2);
    const val = try young(&gc, 3);
    const ht = types.toObject(ht_val).as(types.HashTable);
    ht.equiv_fn = eq;
    ht.compare_mode = .custom;
    ht.entries[2] = .{ .key = key, .value = val, .hash = 2, .state = .occupied };
    ht.count = 1;
    gc.writeBarrier(&ht.header, key);
    try expectRememberedTrace(&gc, ht_val, &.{ ref(eq, 1), ref(key, 2), ref(val, 3) });
}

test "gc tracing (remembered set): promise" {
    var gc = newGc();
    defer gc.deinit();
    const p = try gc.allocPromise(false, types.NIL);
    try promoteToOld(&gc, p);
    const a = try young(&gc, 1);
    const pr = types.toObject(p).as(types.Promise);
    pr.value = a;
    pr.forced = true;
    gc.writeBarrier(&pr.header, a);
    try expectRememberedTrace(&gc, p, &.{ref(a, 1)});
}

test "gc tracing (remembered set): parameter" {
    var gc = newGc();
    defer gc.deinit();
    const p = try gc.allocParameter(types.NIL, types.NIL);
    try promoteToOld(&gc, p);
    const a = try young(&gc, 1);
    const b = try young(&gc, 2);
    const param = types.toObject(p).as(types.ParameterObject);
    param.value = a;
    param.converter = b;
    gc.writeBarrier(&param.header, a);
    try expectRememberedTrace(&gc, p, &.{ ref(a, 1), ref(b, 2) });
}

test "gc tracing (remembered set): port custom backend" {
    var gc = newGc();
    defer gc.deinit();
    const port = try gc.allocCustomPort(
        true,
        true,
        false,
        types.FALSE,
        types.FALSE,
        types.FALSE,
        types.FALSE,
        types.FALSE,
        types.FALSE,
    );
    try promoteToOld(&gc, port);
    const rd = try young(&gc, 1);
    const fl = try young(&gc, 2);
    const p = types.toObject(port).as(types.Port);
    p.custom_backend.?.read_proc = rd;
    p.custom_backend.?.flush_proc = fl;
    gc.writeBarrier(&p.header, rd);
    try expectRememberedTrace(&gc, port, &.{ ref(rd, 1), ref(fl, 2) });
}

test "gc tracing (remembered set): port transcode" {
    var gc = newGc();
    defer gc.deinit();
    const port = try gc.allocTranscodedPort(types.FALSE, true, false, .utf8, .lf, .replace);
    try promoteToOld(&gc, port);
    const wrapped = try young(&gc, 1);
    const p = types.toObject(port).as(types.Port);
    p.transcode.?.wrapped_port = wrapped;
    gc.writeBarrier(&p.header, wrapped);
    try expectRememberedTrace(&gc, port, &.{ref(wrapped, 1)});
}

test "gc tracing (remembered set): transformer" {
    var gc = newGc();
    defer gc.deinit();
    const tx_val = try gc.allocTransformer(&.{types.NIL}, &.{types.NIL}, &.{types.NIL});
    try promoteToOld(&gc, tx_val);
    const lit = try young(&gc, 1);
    const pat = try young(&gc, 2);
    const tmpl = try young(&gc, 3);
    const proc = try young(&gc, 4);
    const env = try young(&gc, 5);
    const tx = types.toObject(tx_val).as(types.Transformer);
    tx.literals[0] = lit;
    tx.patterns[0] = pat;
    tx.templates[0] = tmpl;
    tx.proc = proc;
    tx.def_env_val = env;
    gc.writeBarrier(&tx.header, proc);
    try expectRememberedTrace(&gc, tx_val, &.{
        ref(lit, 1), ref(pat, 2), ref(tmpl, 3), ref(proc, 4), ref(env, 5),
    });
}

test "gc tracing (remembered set): error_object" {
    var gc = newGc();
    defer gc.deinit();
    const e = try gc.allocErrorObject(types.NIL, types.NIL);
    try promoteToOld(&gc, e);
    const msg = try young(&gc, 1);
    const irr = try young(&gc, 2);
    const reason = try young(&gc, 3);
    const err = types.toObject(e).as(types.ErrorObject);
    err.message = msg;
    err.irritants = irr;
    err.uncaught_reason = reason;
    gc.writeBarrier(&err.header, msg);
    try expectRememberedTrace(&gc, e, &.{ ref(msg, 1), ref(irr, 2), ref(reason, 3) });
}

test "gc tracing (remembered set): continuation" {
    var gc = newGc();
    defer gc.deinit();
    const registers = [_]Value{types.NIL};
    const frames = [_]types.SavedFrame{.{
        .closure = null,
        .native = null,
        .code = &.{},
        .ip = 0,
        .base = 0,
        .dst = 0,
        .saved_wind_count = 0,
        .returns_to_native = false,
        .seq = 0,
    }};
    const handlers = [_]types.SavedHandler{.{ .handler = types.NIL, .frame_count = 0 }};
    const winds = [_]types.WindRecord{.{ .before = types.NIL, .after = types.NIL }};
    const cont = try gc.allocContinuation(&registers, &frames, 1, &handlers, 1, &winds, 1, 0, 0);
    try promoteToOld(&gc, cont);

    const reg = try young(&gc, 1);
    const handler = try young(&gc, 2);
    const before = try young(&gc, 3);
    const after = try young(&gc, 4);
    const func = try gc.allocFunction();
    const cls = try gc.allocClosure(func);
    const nf = try gc.allocNativeFn("probe", &dummyNative, .{ .exact = 0 });

    const k = types.toObject(cont).as(types.Continuation);
    k.registers[0] = reg;
    k.handlers[0].handler = handler;
    k.wind_records[0] = .{ .before = before, .after = after };
    k.frames[0].closure = types.toObject(cls).as(types.Closure);
    k.frames[0].native = types.toObject(nf).as(types.NativeFn);
    gc.writeBarrier(&k.header, reg);

    try expectRememberedTrace(&gc, cont, &.{
        ref(reg, 1),     ref(handler, 2), ref(before, 3), ref(after, 4),
        .{ .val = cls }, .{ .val = nf },
    });
}

test "gc tracing (remembered set): multiple_values" {
    var gc = newGc();
    defer gc.deinit();
    const mv = try gc.allocMultipleValues(&.{ types.NIL, types.NIL });
    try promoteToOld(&gc, mv);
    const a = try young(&gc, 1);
    const m = types.toObject(mv).as(types.MultipleValues);
    m.values[1] = a;
    gc.writeBarrier(&m.header, a);
    try expectRememberedTrace(&gc, mv, &.{ref(a, 1)});
}

test "gc tracing (remembered set): complex" {
    var gc = newGc();
    defer gc.deinit();
    const cx = try gc.allocComplex(types.makeFixnum(1), types.makeFixnum(2));
    try promoteToOld(&gc, cx);
    const r = try young(&gc, 1);
    const i = try young(&gc, 2);
    const c = types.toObject(cx).as(types.Complex);
    c.real = r;
    c.imag = i;
    gc.writeBarrier(&c.header, r);
    gc.writeBarrier(&c.header, i);
    try expectRememberedTrace(&gc, cx, &.{ ref(r, 1), ref(i, 2) });
}

test "gc tracing (remembered set): rational" {
    var gc = newGc();
    defer gc.deinit();
    const rat = try gc.allocRational(types.makeFixnum(1), types.makeFixnum(2));
    try promoteToOld(&gc, rat);
    const n = try young(&gc, 1);
    const d = try young(&gc, 2);
    const r = types.toObject(rat).as(types.Rational);
    r.numerator = n;
    r.denominator = d;
    gc.writeBarrier(&r.header, n);
    try expectRememberedTrace(&gc, rat, &.{ ref(n, 1), ref(d, 2) });
}

test "gc tracing (remembered set): ffi_function" {
    var gc = newGc();
    defer gc.deinit();
    const fn_val = try gc.allocFfiFunction(@ptrCast(&opaque_handle), types.NIL, "probe", &.{}, .void_type);
    try promoteToOld(&gc, fn_val);
    const lib = try young(&gc, 1);
    const f = types.toObject(fn_val).as(types.FfiFunction);
    f.library = lib;
    gc.writeBarrier(&f.header, lib);
    try expectRememberedTrace(&gc, fn_val, &.{ref(lib, 1)});
}

test "gc tracing (remembered set): ffi_callback" {
    var gc = newGc();
    defer gc.deinit();
    const cb = try gc.allocFfiCallback(types.NIL, 255, @ptrCast(&opaque_handle));
    try promoteToOld(&gc, cb);
    const cls = try young(&gc, 1);
    const c = types.toObject(cb).as(types.FfiCallback);
    c.closure = cls;
    gc.writeBarrier(&c.header, cls);
    try expectRememberedTrace(&gc, cb, &.{ref(cls, 1)});
}

test "gc tracing (remembered set): channel" {
    var gc = newGc();
    defer gc.deinit();
    const ch_val = try gc.allocChannel();
    try promoteToOld(&gc, ch_val);
    const head = try young(&gc, 1);
    const tail = try young(&gc, 2);
    const ch = types.toObject(ch_val).as(types.Channel);
    ch.head = head;
    ch.tail = tail;
    gc.writeBarrier(&ch.header, head);
    try expectRememberedTrace(&gc, ch_val, &.{ ref(head, 1), ref(tail, 2) });
}

test "gc tracing (remembered set): mutex" {
    var gc = newGc();
    defer gc.deinit();
    const m_val = try gc.allocMutex(types.NIL);
    try promoteToOld(&gc, m_val);
    const name = try young(&gc, 1);
    const owner = try young(&gc, 2);
    const owner_thread = try young(&gc, 4);
    const specific = try young(&gc, 3);
    const m = types.toObject(m_val).as(types.Mutex);
    m.name = name;
    m.owner = owner;
    m.owner_thread = owner_thread;
    m.specific = specific;
    gc.writeBarrier(&m.header, owner);
    gc.writeBarrier(&m.header, owner_thread);
    try expectRememberedTrace(&gc, m_val, &.{ ref(name, 1), ref(owner, 2), ref(owner_thread, 4), ref(specific, 3) });
}

test "gc tracing (remembered set): condition_variable" {
    var gc = newGc();
    defer gc.deinit();
    const cv_val = try gc.allocConditionVariable(types.NIL);
    try promoteToOld(&gc, cv_val);
    const name = try young(&gc, 1);
    const specific = try young(&gc, 2);
    const cv = types.toObject(cv_val).as(types.ConditionVariable);
    cv.name = name;
    cv.specific = specific;
    gc.writeBarrier(&cv.header, name);
    try expectRememberedTrace(&gc, cv_val, &.{ ref(name, 1), ref(specific, 2) });
}

test "gc tracing (remembered set): scheme_environment" {
    var gc = newGc();
    defer gc.deinit();
    const map = try gc.allocator.create(std.StringHashMap(Value));
    map.* = std.StringHashMap(Value).init(gc.allocator);
    const env = try gc.allocEnvironment(map, true, false);
    try promoteToOld(&gc, env);
    const a = try young(&gc, 1);
    try map.put("a", a);
    gc.writeBarrier(types.toObject(env), a);
    try expectRememberedTrace(&gc, env, &.{ref(a, 1)});
}

test "gc tracing (remembered set): transport_cell" {
    var gc = newGc();
    defer gc.deinit();
    const tc = try gc.allocTransportCell(types.NIL, types.NIL);
    try promoteToOld(&gc, tc);
    const k = try young(&gc, 1);
    const v = try young(&gc, 2);
    const cell = types.toObject(tc).as(types.TransportCell);
    cell.key = k;
    cell.value = v;
    gc.writeBarrier(&cell.header, k);
    // The value is strong: the remembered-set walk (markObjectContents) keeps
    // it alive. The key is weakly holding (#2006): the walk defers it to
    // processWeakRefs, which breaks the cell once nothing else roots `k`.
    try expectRememberedTrace(&gc, tc, &.{ref(v, 2)});
    try expectDead(&gc, ref(k, 1));
    const after = types.toObject(tc).as(types.TransportCell);
    try std.testing.expect(after.broken);
    try std.testing.expectEqual(types.FALSE, after.key);
}

test "gc tracing (remembered set): fiber" {
    var gc = newGc();
    defer gc.deinit();
    const fiber = try gc.allocFiber(types.NIL, 1);
    const fiber_val = types.makePointer(&fiber.header);
    try promoteToOld(&gc, fiber_val);

    const thunk = try young(&gc, 1);
    const reg = try young(&gc, 2);
    const handler = try young(&gc, 3);
    const before = try young(&gc, 4);
    const after = try young(&gc, 5);
    const param = try young(&gc, 6);
    const owned_mutex = try young(&gc, 7);
    const io_buffer = try young(&gc, 8);

    fiber.thunk = thunk;
    fiber.io_buffer = io_buffer;
    fiber.frames[0] = .{ .closure = null, .code = &.{}, .ip = 0, .base = 0, .dst = 0 };
    fiber.frame_count = 1;
    fiber.registers[3] = reg;
    fiber.handler_stack[0] = .{ .handler = handler, .frame_count = 0 };
    fiber.handler_count = 1;
    fiber.wind_stack[0] = .{ .before = before, .after = after };
    fiber.wind_count = 1;
    try fiber.param_overrides.put(1, param);
    try fiber.owned_mutexes.append(gc.allocator, owned_mutex);
    gc.writeBarrier(&fiber.header, thunk);

    // `.fiber` is the one arm that is shared rather than duplicated:
    // markObjectContents and markValueInner both delegate to
    // fiber.markFiberState, so this case and the Test A one above cover the
    // same code. referencesYoung's `.fiber` arm is still hand-written, and
    // its own comment says the remembered-set path is belt-and-braces there
    // because a scheduler-resident fiber is an unconditional root — this
    // fiber belongs to no scheduler, so the path is exercised for real.
    try expectRememberedTrace(&gc, fiber_val, &.{
        ref(thunk, 1),       ref(reg, 2),       ref(handler, 3),
        ref(before, 4),      ref(after, 5),     ref(param, 6),
        ref(owned_mutex, 7), ref(io_buffer, 8),
    });
}

// ---------------------------------------------------------------------------
// Write barrier
// ---------------------------------------------------------------------------

test "gc write barrier: records an old container pointing at a young value" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocPair(types.NIL, types.NIL);
    try promoteToOld(&gc, c);
    const cobj = types.toObject(c);
    try std.testing.expect(!inRemembered(&gc, cobj));

    const a = try young(&gc, 1);
    cobj.as(types.Pair).car = a;
    gc.writeBarrier(cobj, a);
    try std.testing.expect(inRemembered(&gc, cobj));
}

test "gc write barrier: no entry for a young container or a non-pointer value" {
    var gc = newGc();
    defer gc.deinit();

    // Young container: minor collections mark it from the roots anyway.
    const y = try gc.allocPair(types.NIL, types.NIL);
    const a = try young(&gc, 1);
    gc.writeBarrier(types.toObject(y), a);
    try std.testing.expect(!inRemembered(&gc, types.toObject(y)));

    // Old container, immediate value: nothing to remember.
    const o = try gc.allocPair(types.NIL, types.NIL);
    try promoteToOld(&gc, o);
    gc.writeBarrier(types.toObject(o), types.makeFixnum(7));
    try std.testing.expect(!inRemembered(&gc, types.toObject(o)));
}

test "gc write barrier: an entry whose young referent is gone is pruned" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocPair(types.NIL, types.NIL);
    try promoteToOld(&gc, c);
    const cobj = types.toObject(c);

    const a = try young(&gc, 1);
    cobj.as(types.Pair).car = a;
    gc.writeBarrier(cobj, a);
    try std.testing.expect(inRemembered(&gc, cobj));

    // Repoint at an immediate: `referencesYoung` must now say no, and
    // pruneRememberedSet must drop the stale entry.
    cobj.as(types.Pair).car = types.makeFixnum(7);
    forceMinor(&gc);
    try std.testing.expect(!inRemembered(&gc, cobj));
    try expectDead(&gc, ref(a, 1));
}

// Pins the property #1961 established: a minor collection is a
// **generational** mark. `markValueInner` treats the old generation as
// opaque, so an old container is traced by a minor collection only through
// the remembered set — which makes `gc.writeBarrier` (plus the promotion
// scan in sweepYoung) load-bearing. A forgotten barrier is a
// use-after-free: the young referent is swept while the old container still
// points at it. (Before #1961 the minor mark was a full transitive mark, and
// this test asserted the exact opposite — that the referent survived — which
// is what told whoever made the mark generational that every mutation site
// needed auditing first.)
test "gc write barrier: a minor collection does not mark through an old object with no remembered-set entry" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocPair(types.NIL, types.NIL);
    try promoteToOld(&gc, c);

    var root = c;
    gc.pushRoot(&root);
    defer gc.popRoot();

    const a = try young(&gc, 1);
    types.toObject(c).as(types.Pair).car = a; // deliberately no writeBarrier
    try std.testing.expect(!inRemembered(&gc, types.toObject(c)));

    forceMinor(&gc);
    // The root keeps `c` itself alive (old objects survive every minor),
    // but the old generation is opaque to the mark and `c` is not
    // remembered, so `a` has no route to survival. It is freed, not merely
    // unmarked — reading it back here would be the use-after-free this test
    // exists to pin, so liveness is checked by list membership only.
    try expectDead(&gc, ref(a, 1));
}

// The companion to the case above: the same store WITH the barrier keeps the
// referent alive — the remembered-set walk (markObjectContents) is its only
// route to survival, since the container is old and unrooted-reachable.
test "gc write barrier: a remembered old container keeps its young referent through a minor collection" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocPair(types.NIL, types.NIL);
    try promoteToOld(&gc, c);

    var root = c;
    gc.pushRoot(&root);

    const a = try young(&gc, 1);
    types.toObject(c).as(types.Pair).car = a;
    gc.writeBarrier(types.toObject(c), a);
    try std.testing.expect(inRemembered(&gc, types.toObject(c)));

    gc.popRoot();
    forceMinor(&gc);
    try expectAlive(&gc, ref(a, 1));
}

// #1961 promotion scan: the write barrier only fires for a container that is
// already old, so an old→young edge created while the container was young (a
// barrier there is a correct no-op) would go unrecorded when sweepYoung
// promotes it. The scan at promotion records it, keeping the remembered set
// complete without any barrier change at the mutation sites.
test "gc promotion scan: a promoted container with young referents enters the remembered set" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocPair(types.NIL, types.NIL);
    var root = c;
    gc.pushRoot(&root);

    // One survival leaves c young with survive_count 1...
    forceMinor(&gc);
    // ...then a fresh young referent is stored (still correctly barrier-less:
    // c is young, so a minor collection traces it from the root anyway)...
    const a = try young(&gc, 1);
    types.toObject(c).as(types.Pair).car = a;
    // ...and the next minor promotes c while a — one survival so far — stays
    // young. The promotion scan must record the edge.
    forceMinor(&gc);
    try std.testing.expectEqual(@as(u1, 1), types.toObject(c).flags.generation);
    try std.testing.expectEqual(@as(u1, 0), types.toObject(a).flags.generation);
    try std.testing.expect(inRemembered(&gc, types.toObject(c)));

    // With the root dropped, the remembered-set walk is a's only anchor.
    gc.popRoot();
    forceMinor(&gc);
    try expectAlive(&gc, ref(a, 1));

    // a survived that minor, so both ends of the edge are now old and
    // referencesYoung says no — the entry is pruned and the flag cleared, so
    // a later old→young write to c is free to re-queue it (#2196).
    try std.testing.expect(!inRemembered(&gc, types.toObject(c)));
    try std.testing.expect(!types.toObject(c).flags.in_remembered_set);
}

// #1961 (review): an old function's constants list is a barriered container.
// The compiler's addConstant, the .sbc deserializer, and the bytecode-file
// tests all funnel through GC.appendFunctionConstant, so this drives the
// real mechanism; the control half pins why it must — a function can be
// promoted long before its constants list stops growing.
test "gc: an old function's constants list is a barriered container (#1961)" {
    var gc = newGc();
    defer gc.deinit();
    const f1 = try gc.allocFunction();
    const f1_val = types.makePointer(&f1.header);
    try promoteToOld(&gc, f1_val);
    const f2 = try gc.allocFunction();
    const f2_val = types.makePointer(&f2.header);
    try promoteToOld(&gc, f2_val);

    // The store every producer makes: append + barrier on the function.
    const a = try young(&gc, 1);
    try gc.appendFunctionConstant(f1, a);
    // The old function survives every minor unrooted; the barrier's entry is
    // a's only route to survival.
    forceMinor(&gc);
    try expectAlive(&gc, ref(a, 1));

    // Control — the same store without the barrier (the pre-#1961 shape)
    // loses the referent.
    const b = try young(&gc, 2);
    f2.constants.append(gc.allocator, b) catch unreachable;
    forceMinor(&gc);
    try expectDead(&gc, ref(b, 2));
}

// #1961 (review): a function's global_cache is a barriered container for the
// same reason — a cached value can be orphaned by a later rebinding before
// this function's own next global op clears the slot, and the minor mark
// reaches the orphan only through the remembered set. The opcode handlers
// barrier each cache store; this pins that store shape at the mechanism
// level (the dispatch path itself is exercised end-to-end by gc-stress).
test "gc: an old function's global_cache is a barriered container (#1961)" {
    var gc = newGc();
    defer gc.deinit();
    const f1 = try gc.allocFunction();
    const f1_val = types.makePointer(&f1.header);
    try promoteToOld(&gc, f1_val);
    const f2 = try gc.allocFunction();
    const f2_val = types.makePointer(&f2.header);
    try promoteToOld(&gc, f2_val);

    const cache1 = try gc.allocator.alloc(Value, 1);
    @memset(cache1, types.VOID);
    f1.global_cache = cache1;
    const a = try young(&gc, 1);
    cache1[0] = a;
    gc.writeBarrier(types.toObject(f1_val), a); // the handlers' store shape
    forceMinor(&gc);
    try expectAlive(&gc, ref(a, 1));

    const cache2 = try gc.allocator.alloc(Value, 1);
    @memset(cache2, types.VOID);
    f2.global_cache = cache2;
    const b = try young(&gc, 2);
    cache2[0] = b; // no barrier — the pre-fix shape
    forceMinor(&gc);
    try expectDead(&gc, ref(b, 2));
}

// #1961 (review): a fiber retired from its scheduler slot (retireSlot queues
// the slot for reuse, then the retire paths run saveCurrentFiber AFTER it)
// loses the unconditional markFiberState pass while staying heap-reachable
// through a joiner's waiting_on or any handle. saveCurrentFiber's answer is
// to enroll an old fiber in the remembered set wholesale — its bulk snapshot
// (memcpy'd registers/frames/handlers/winds, current_exception,
// continuation_value) has no per-field barriers. This pins that mechanism:
// an unbarriered snapshot store into a non-resident old fiber survives only
// via rememberObject.
test "gc: a retired old fiber's snapshot survives via the remembered set (#1961)" {
    var gc = newGc();
    defer gc.deinit();
    const fiber = try gc.allocFiber(types.NIL, 1);
    const fiber_val = types.makePointer(&fiber.header);
    try promoteToOld(&gc, fiber_val);

    // Simulate the retire-path save: young values written straight into the
    // fiber's snapshot fields, no per-field barriers (saveCurrentFiber's
    // memcpy shape), then the wholesale enrollment.
    const exc = try young(&gc, 1);
    fiber.current_exception = exc;
    fiber.registers[3] = try young(&gc, 2);
    fiber.frames[0] = .{ .closure = null, .code = &.{}, .ip = 0, .base = 0, .dst = 0 };
    fiber.frame_count = 1;
    gc.rememberObject(types.toObject(fiber_val));

    // The fiber is not scheduler-resident and nothing roots it; it survives
    // every minor anyway (old), and the remembered entry keeps the snapshot
    // values alive with it.
    forceMinor(&gc);
    try expectAlive(&gc, ref(exc, 1));

    // Control: the same snapshot store without the enrollment loses the
    // values — the old fiber is opaque and nothing else references them.
    const fiber2 = try gc.allocFiber(types.NIL, 2);
    const fiber2_val = types.makePointer(&fiber2.header);
    try promoteToOld(&gc, fiber2_val);
    const lost = try young(&gc, 3);
    fiber2.current_exception = lost; // no rememberObject
    forceMinor(&gc);
    try expectDead(&gc, ref(lost, 3));
}

// #1961: the whole point of the generational minor mark, pinned directly off
// the skip counter — a minor collection whose roots reach old objects must
// not trace them, while a full collection (which sweeps the old generation)
// still must.
test "gc minor mark: skips the old generation, full mark does not (#1961)" {
    var gc = newGc();
    defer gc.deinit();
    // A chain of old pairs hanging off one old head.
    var head = try gc.allocPair(types.NIL, types.NIL);
    gc.pushRoot(&head);
    var tail = head;
    for (0..64) |i| {
        const next = try gc.allocPair(types.makeFixnum(@intCast(i)), types.NIL);
        types.toObject(tail).as(types.Pair).cdr = next;
        tail = next;
    }
    try promoteToOld(&gc, head);

    const skips_before = gc.stats.minor_old_skips;
    forceMinor(&gc);
    // The root walk reached `head` (and only `head` — the cdr chain is old
    // and opaque), so the boundary fired at least once...
    try std.testing.expect(gc.stats.minor_old_skips > skips_before);
    // ...and exactly once per old object the walk attempted: the head only,
    // because the chain behind it is never entered.
    try std.testing.expectEqual(skips_before + 1, gc.stats.minor_old_skips);

    forceFull(&gc);
    // A full collection marks both generations — no new skips.
    try std.testing.expectEqual(skips_before + 1, gc.stats.minor_old_skips);
    gc.popRoot();
}

// #1961: a minor collection never sweeps the old generation, so the weak
// probes must treat every old object as alive — an ephemeron whose key is
// old must not break (breaking is destructive: both fields are cleared)
// just because the key carries no mark during a minor.
test "gc weak refs: an old ephemeron key does not break in a minor collection (#1961)" {
    var gc = newGc();
    defer gc.deinit();
    const key = try young(&gc, 1);
    try promoteToOld(&gc, key);

    const val = try young(&gc, 2);
    const eph_val = try gc.allocEphemeron(key, val);
    const eph = types.toEphemeron(eph_val);
    var root = eph_val;
    gc.pushRoot(&root);

    // The key is old garbage-in-waiting (only the ephemeron's weak field
    // references it), but a minor collection cannot free it — so the
    // ephemeron must not break and the value must stay retained.
    forceMinor(&gc);
    try std.testing.expect(!eph.broken);
    try expectAlive(&gc, ref(val, 2));

    // Control: the next FULL collection sweeps the old generation, sees the
    // key as the garbage it is, and breaks the ephemeron — proving the minor
    // above deferred the decision rather than losing it.
    forceFull(&gc);
    try std.testing.expect(eph.broken);
    gc.popRoot();
}

// #1961: same rule for guardians — a registered element watching an old
// object must stay registered through a minor collection (the object cannot
// die in one), instead of being resurrected early.
test "gc weak refs: a guardian watching an old object does not resurrect in a minor collection (#1961)" {
    var gc = newGc();
    defer gc.deinit();
    const watched = try young(&gc, 1);
    try promoteToOld(&gc, watched);

    const rep = try young(&gc, 2);
    const g_val = try gc.allocGuardian(false);
    const g = types.toGuardian(g_val);
    try g.registered.append(gc.allocator, .{ .watched = watched, .payload = rep });
    gc.writeBarrier(types.toObject(g_val), watched);
    gc.writeBarrier(types.toObject(g_val), rep);

    var root = g_val;
    gc.pushRoot(&root);
    forceMinor(&gc);
    try std.testing.expectEqual(@as(usize, 0), g.ready.items.len);
    try std.testing.expectEqual(@as(usize, 1), g.registered.items.len);

    // Control: the next FULL collection sees the old watched object as the
    // garbage it is and resurrects the element — the deferred decision,
    // taken exactly when the object can actually die.
    forceFull(&gc);
    try std.testing.expectEqual(@as(usize, 1), g.ready.items.len);
    try std.testing.expectEqual(@as(usize, 0), g.registered.items.len);
    gc.popRoot();
}

// ---------------------------------------------------------------------------
// Comptime inventory
// ---------------------------------------------------------------------------

/// Pins the exact field list of a heap struct (or a satellite one of the GC
/// switches reaches through). A field added, removed or renamed here is a
/// build error until someone has decided whether it holds a `Value` and, if
/// so, updated all five per-tag switches. This is the only compiler-enforced
/// check on the *inside* of those arms: exhaustiveness only proves an arm
/// exists. `Value` is `u64`, so no comptime type test can tell a real Value
/// apart from `profile_calls: u64` — pinning the whole field list is what
/// makes the guard sound.
fn expectFields(comptime T: type, comptime pinned: []const []const u8) void {
    comptime {
        var actual: []const u8 = "";
        for (@typeInfo(T).@"struct".fields, 0..) |f, i| {
            actual = actual ++ (if (i == 0) "" else ", ") ++ f.name;
        }
        var want: []const u8 = "";
        for (pinned, 0..) |p, i| {
            want = want ++ (if (i == 0) "" else ", ") ++ p;
        }
        if (!std.mem.eql(u8, actual, want)) @compileError(
            "GC tracing inventory out of date for " ++ @typeName(T) ++ "\n" ++
                "  pinned: " ++ want ++ "\n" ++
                "  actual: " ++ actual ++ "\n" ++
                "If the change adds or removes a Value-bearing field, update ALL of\n" ++
                "  gc_collect.zig: markObjectContents, markValueInner, referencesYoung\n" ++
                "  gc_sweep.zig:   objectSize, freeObject\n" ++
                "and add a case to src/tests_gc_tracing.zig. Then re-pin here.\n" ++
                "EXCEPT for Port, CustomBacking and TranscodeState: all five sites\n" ++
                "derive from types_port.forEachValue / satelliteBytes /\n" ++
                "destroySatellites, so a new Value field there needs no GC edit at\n" ++
                "all -- only this re-pin. A new *satellite* (a `?*T` field on Port)\n" ++
                "is a hard build error until it is listed in types_port.satellites.",
        );
    }
}

test "gc tracing: heap-struct field inventory is unchanged" {
    // The 41 ObjectTag members, in enum order.
    expectFields(types.Pair, &.{ "header", "car", "cdr" });
    expectFields(types.Symbol, &.{ "header", "name", "interned" });
    expectFields(types.SchemeString, &.{ "header", "data", "len" });
    expectFields(types.Closure, &.{ "header", "func", "upvalues" });
    expectFields(types.NativeFn, &.{
        "header",        "func",            "name",                "arity",
        "profile_calls", "profile_time_ns", "profile_alloc_bytes",
    });
    expectFields(types.Vector, &.{ "header", "data" });
    expectFields(types.Bytevector, &.{ "header", "data", "shared" });
    // `input_closed`/`output_closed` (kaappi#1998) are plain bools, not
    // Value-bearing, so they add no marking or sweeping obligation -- only
    // this re-pin.
    expectFields(types.Port, &.{
        "header",         "fd",             "is_input",        "is_output",
        "is_open",        "input_closed",   "output_closed",   "name",
        "owns_name",      "peek_byte",      "peek_extra",      "peek_extra_len",
        "fold_case",      "is_string_port", "string_data",     "string_pos",
        "string_out_buf", "string_out_len", "string_out_cap",  "string_out_pos",
        "is_binary",      "read_buf",       "read_buf_len",    "random_gen",
        "nonblocking",    "write_buf",      "write_buf_start", "write_buf_len",
        "fd_state",       "custom_backend", "transcode",
    });
    // `has_protocol` (kaappi#1974) is a plain bool and `identity`
    // (kaappi#1932) a plain u64 -- neither is Value-bearing, so they add no
    // marking or sweeping obligation, only this re-pin.
    expectFields(types.RecordType, &.{
        "header", "name",            "num_fields",        "own_field_count",
        "parent", "own_field_names", "own_field_mutable", "uid",
        "sealed", "is_opaque",       "has_protocol",      "identity",
    });
    expectFields(types.Function, &.{
        "header",          "code",                 "constants",           "arity",
        "locals_count",    "upvalue_count",        "is_variadic",         "name",
        "owns_name",       "source_line",          "source_name",         "debug_locals",
        "line_table",      "global_cache",         "cache_version",       "env",
        "env_val",         "restricted_globals",   "profile_instrs",      "profile_calls",
        "profile_time_ns", "profile_inclusive_ns", "profile_alloc_bytes",
    });
    expectFields(types.Flonum, &.{ "header", "value" });
    expectFields(types.Transformer, &.{
        "header",               "literals",        "patterns",            "templates",
        "num_rules",            "kind",            "proc",                "finalized",
        "peers_computed",       "captured_locals", "def_env",             "def_env_val",
        "def_lib_name",         "custom_ellipsis", "literal_bound",       "let_syntax_peer_names",
        "let_syntax_peer_vals", "bound_free_refs", "def_site_local_refs",
    });
    expectFields(types.ErrorObject, &.{
        "header", "message", "irritants", "error_type", "uncaught_reason", "code", "posix_errno",
    });
    expectFields(types.RecordInstance, &.{ "header", "record_type", "fields" });
    expectFields(types.Continuation, &.{
        "header",   "registers",          "frames",            "frame_count",
        "handlers", "handler_count",      "wind_records",      "wind_count",
        "dst_reg",  "dst_base",           "backing",           "is_escape",
        "valid",    "target_frame_count", "target_wind_count", "target_handler_count",
    });
    expectFields(types.MultipleValues, &.{ "header", "values" });
    expectFields(types.Complex, &.{ "header", "real", "imag" });
    expectFields(types.Promise, &.{ "header", "forced", "forcing", "value" });
    expectFields(types.ParameterObject, &.{ "header", "value", "converter" });
    expectFields(types.FfiLibrary, &.{ "header", "handle", "name" });
    expectFields(types.FfiFunction, &.{
        "header", "symbol", "library", "name", "param_types", "return_type", "param_count",
    });
    expectFields(types.FfiCallback, &.{ "header", "closure", "slot_index", "fn_ptr", "active" });
    expectFields(types.HashTable, &.{
        "header", "entries", "count", "capacity", "compare_mode", "equiv_fn", "hash_fn",
    });
    expectFields(types.Bignum, &.{ "header", "limbs", "len", "positive" });
    expectFields(types.Rational, &.{ "header", "numerator", "denominator" });
    expectFields(types.FileInfo, &.{
        "header", "size",   "mtime",     "atime",   "ctime",  "dev",
        "ino",    "nlinks", "rdev",      "blksize", "blocks", "mode",
        "uid",    "gid",    "file_type",
    });
    expectFields(types.UserInfo, &.{
        "header", "name", "uid", "gid", "home_dir", "shell", "full_name",
    });
    expectFields(types.GroupInfo, &.{ "header", "name", "gid" });
    expectFields(types.DirectoryObject, &.{ "header", "dir", "include_dotfiles" });
    expectFields(types.RandomSource, &.{ "header", "prng" });
    expectFields(fiber_mod.Fiber, &.{
        "header",            "registers",            "frames",             "frame_count",
        "handler_stack",     "handler_count",        "wind_stack",         "wind_count",
        "current_exception", "continuation_invoked", "continuation_value", "status",
        "thunk",             "result",               "waiting_on",         "id",
        "name",              "specific",             "param_overrides",    "deadline_ns",
        "timed_out",         "driving",              "terminated",         "os_thread",
        "live_descendants",  "io_fd",                "io_interest",        "io_buffer",
        "sched_idx",         "queued",               "rv_demand_on",       "owned_mutexes",
    });
    expectFields(types.Channel, &.{
        "header", "head", "tail", "queue_len", "capacity", "rv_demand", "closed", "shared",
    });
    expectFields(types.Mutex, &.{
        "header", "name", "owner", "owner_thread", "locked", "abandoned", "specific",
    });
    expectFields(types.ConditionVariable, &.{
        "header", "name", "specific", "signal_generation",
    });
    expectFields(types.Srfi18Time, &.{ "header", "seconds", "nanoseconds", "time_type" });
    expectFields(types.NativeClosure, &.{ "header", "fn_ptr", "upvalues", "arity", "name" });
    expectFields(types.SchemeEnvironment, &.{ "header", "env", "owned", "immutable" });
    expectFields(types.Ephemeron, &.{ "header", "key", "value", "broken" });
    expectFields(types.Guardian, &.{ "header", "is_transport", "registered", "ready" });
    expectFields(types.TransportCell, &.{ "header", "key", "value", "broken" });
    expectFields(types.NumericVector, &.{ "header", "kind", "data" });
    // Only the three port fields are Value-bearing; pid/wait_handle/status/
    // pgid are scalars -- marking/sweeping obligations stop at the ports.
    // The fibers parked in process-wait live in the reactor's own registry
    // (Reactor.procs, KEP-0022 Phase 2), traced by Reactor.markRoots, not
    // through the Process object.
    expectFields(types.Process, &.{
        "header",     "pid",         "wait_handle", "status",
        "stdin_port", "stdout_port", "stderr_port", "pgid",
    });

    // Satellites the switches reach *through* — the highest-risk group,
    // because a new field here is invisible at the ObjectTag level entirely.
    expectFields(types.CustomBacking, &.{
        "read_proc",         "write_proc", "get_position_proc",
        "set_position_proc", "close_proc", "flush_proc",
    });
    // `pending_cr` (kaappi#1997) is a plain bool, not Value-bearing, so it
    // adds no marking or sweeping obligation -- only this re-pin.
    expectFields(types.TranscodeState, &.{
        "wrapped_port", "codec", "eol_style", "error_mode", "pending_cr",
    });
    // `hash` (kaappi#2024) caches the key's hash so `rehash` never calls a
    // Scheme hash procedure while the old entry array is live. Like `state`
    // it is not Value-bearing, so it adds no marking or sweeping obligation
    // -- only this re-pin.
    expectFields(types.HashEntry, &.{ "key", "value", "hash", "state" });
    expectFields(types.GuardEntry, &.{ "watched", "payload" });
    expectFields(types.WindRecord, &.{ "before", "after" });
    expectFields(types.ExceptionHandler, &.{ "handler", "frame_count", "sticky" });
    expectFields(types.SavedFrame, &.{
        "closure", "native",           "code",              "ip",  "base",
        "dst",     "saved_wind_count", "returns_to_native", "seq",
    });
    expectFields(types.CallFrame, &.{
        "closure", "native",           "code",              "ip",  "base",
        "dst",     "saved_wind_count", "returns_to_native", "seq",
    });
}

test "gc tracing: every ObjectTag has a case in this file" {
    // The runtime cases above cover every tag that carries a Value; the
    // remaining ones are covered by "leaf tags survive while rooted".
    // `.flonum` is the one tag with no allocator at all — `allocFlonum`
    // returns a NaN-boxed immediate, so no heap Flonum is ever created (the
    // tag, its struct and its five arms are vestigial). Keep this count in
    // step with ObjectTag so a new tag cannot be added without landing here.
    try std.testing.expectEqual(@as(usize, 42), @typeInfo(types.ObjectTag).@"enum".fields.len);
}

// ---------------------------------------------------------------------------
// Port satellite walkers (audit v2, Phase 7A)
// ---------------------------------------------------------------------------
//
// The three mark arms and the two sweep arms all derive from
// `types_port.forEachValue` / `satelliteBytes` / `destroySatellites`. The
// cases below are what stands between a dropped field and a use-after-free:
// one enumeration means one place to break, not five places to disagree.
//
// The measurement that motivated the unification, re-runnable by reverting it:
// a third Value-bearing field on `Port` compiled clean under `zig build` and
// was missed by 3 of the 5 sites (a bare `Value`, or one on an existing
// satellite) or by all 5 (a brand-new satellite). Each was an observed
// `ReferentCollected` — a live use-after-free — and the satellite case leaked
// as well. `zig build test` was never silent: the field-list pin above caught
// all three. The gates in `types_port.zig` now catch the satellite case in the
// *product* build too.
//
// "reaches every declared Value field" is the mutation test proper: it counts
// the expectation from `@typeInfo` rather than from the walk it checks, over a
// port carrying both satellites at once — a shape no runtime path builds, and
// the only one that exercises the whole enumeration in a single walk.

const types_port = @import("types_port.zig");

/// Records every Value the walker yields, so a case can assert the exact set
/// rather than "something was traced".
const Collector = struct {
    seen: *std.ArrayList(Value),
    allocator: std.mem.Allocator,

    fn visit(self: Collector, v: Value) bool {
        self.seen.append(self.allocator, v) catch @panic("collector OOM");
        return false;
    }
};

/// Stops the walk once `limit` Values have been seen — exercises the
/// short-circuit `referencesYoung` depends on.
const Stopper = struct {
    count: *usize,
    limit: usize,

    fn visit(self: Stopper, _: Value) bool {
        self.count.* += 1;
        return self.count.* >= self.limit;
    }
};

fn collectValues(gc: *memory.GC, port: Value, out: *std.ArrayList(Value)) void {
    _ = types_port.forEachValue(
        types.toObject(port).as(types.Port),
        Collector{ .seen = out, .allocator = gc.allocator },
        Collector.visit,
    );
}

/// Every `Value`-typed field a fully-populated port reaches, counted straight
/// from `@typeInfo` — deliberately *not* by asking `forEachValue`, so the two
/// disagree the moment the walker drops a field.
fn declaredValueCount() usize {
    comptime var n: usize = 0;
    comptime {
        for (@typeInfo(types.Port).@"struct".fields) |f| {
            if (f.type == Value) n += 1;
        }
        for (@typeInfo(types.CustomBacking).@"struct".fields) |f| {
            if (f.type == Value) n += 1;
        }
        for (@typeInfo(types.TranscodeState).@"struct".fields) |f| {
            if (f.type == Value) n += 1;
        }
    }
    return n;
}

test "gc tracing: forEachValue yields exactly the Values a port holds" {
    var gc = newGc();
    defer gc.deinit();
    var seen: std.ArrayList(Value) = .empty;
    defer seen.deinit(gc.allocator);

    // A port with no satellite holds no Values at all.
    const plain = try gc.allocStringOutputPort();
    collectValues(&gc, plain, &seen);
    try std.testing.expectEqual(@as(usize, 0), seen.items.len);

    // A custom port yields its six callbacks, in declaration order.
    seen.clearRetainingCapacity();
    const cp = try gc.allocCustomPort(
        true,
        true,
        false,
        types.makeFixnum(1),
        types.makeFixnum(2),
        types.makeFixnum(3),
        types.makeFixnum(4),
        types.makeFixnum(5),
        types.makeFixnum(6),
    );
    collectValues(&gc, cp, &seen);
    try std.testing.expectEqualSlices(Value, &.{
        types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3),
        types.makeFixnum(4), types.makeFixnum(5), types.makeFixnum(6),
    }, seen.items);

    // A transcoded port yields its wrapped port and nothing else — the three
    // enum fields beside it must not be mistaken for Values.
    seen.clearRetainingCapacity();
    const tp = try gc.allocTranscodedPort(types.makeFixnum(9), true, false, .utf8, .lf, .replace);
    collectValues(&gc, tp, &seen);
    try std.testing.expectEqualSlices(Value, &.{types.makeFixnum(9)}, seen.items);
}

test "gc tracing: forEachValue reaches every declared Value field" {
    var gc = newGc();
    defer gc.deinit();

    // Both satellites at once. No runtime path builds this port (a port is
    // either custom or transcoded), but it is the only shape that exercises
    // the whole enumeration in one walk — which is the point: the count comes
    // from @typeInfo, so dropping any field from `forEachValue`, or adding one
    // it does not visit, fails here.
    const port = try gc.allocCustomPort(
        true,
        true,
        false,
        types.makeFixnum(1),
        types.makeFixnum(2),
        types.makeFixnum(3),
        types.makeFixnum(4),
        types.makeFixnum(5),
        types.makeFixnum(6),
    );
    const p = types.toObject(port).as(types.Port);
    const ts = try gc.allocator.create(types.TranscodeState);
    ts.* = .{
        .wrapped_port = types.makeFixnum(7),
        .codec = .utf8,
        .eol_style = .lf,
        .error_mode = .replace,
    };
    p.transcode = ts; // freed by destroySatellites when the port is swept

    var seen: std.ArrayList(Value) = .empty;
    defer seen.deinit(gc.allocator);
    collectValues(&gc, port, &seen);
    try std.testing.expectEqual(declaredValueCount(), seen.items.len);

    // ... and the count is not vacuously zero.
    try std.testing.expect(declaredValueCount() >= 7);
}

test "gc tracing: forEachValue short-circuits when the visitor says stop" {
    var gc = newGc();
    defer gc.deinit();
    const cp = try gc.allocCustomPort(
        true,
        true,
        false,
        types.FALSE,
        types.FALSE,
        types.FALSE,
        types.FALSE,
        types.FALSE,
        types.FALSE,
    );
    const p = types.toObject(cp).as(types.Port);

    var count: usize = 0;
    try std.testing.expect(types_port.forEachValue(p, Stopper{ .count = &count, .limit = 3 }, Stopper.visit));
    try std.testing.expectEqual(@as(usize, 3), count);

    // A visitor that never stops walks everything and reports `false` —
    // `referencesYoung`'s "no young referent" answer.
    count = 0;
    try std.testing.expect(!types_port.forEachValue(p, Stopper{ .count = &count, .limit = 99 }, Stopper.visit));
    try std.testing.expectEqual(@as(usize, 6), count);
}

test "gc tracing: satelliteBytes accounts for each attached satellite" {
    var gc = newGc();
    defer gc.deinit();

    const plain = try gc.allocStringOutputPort();
    try std.testing.expectEqual(
        @as(usize, 0),
        types_port.satelliteBytes(types.toObject(plain).as(types.Port)),
    );

    const cp = try gc.allocCustomPort(true, true, false, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE);
    try std.testing.expectEqual(
        @sizeOf(types.CustomBacking),
        types_port.satelliteBytes(types.toObject(cp).as(types.Port)),
    );

    const tp = try gc.allocTranscodedPort(types.FALSE, true, false, .utf8, .lf, .replace);
    try std.testing.expectEqual(
        @sizeOf(types.TranscodeState),
        types_port.satelliteBytes(types.toObject(tp).as(types.Port)),
    );

    const rp = try gc.allocRandomPort(.{ .kind = .determinized });
    try std.testing.expectEqual(
        @sizeOf(types.RandomGen),
        types_port.satelliteBytes(types.toObject(rp).as(types.Port)),
    );

    // objectSize must report strictly more than the bare struct for a port
    // that owns anything — the property the derived sum exists to keep.
    try std.testing.expect(
        @import("gc_sweep.zig").objectSize(types.toObject(cp)) > @sizeOf(types.Port),
    );
}

test "gc tracing: destroySatellites frees every satellite a swept port owns" {
    // std.testing.allocator's leak check is the assertion: each port below is
    // dropped unrooted, so freeObject's .port arm must release its satellite.
    // Before 7A the `random_gen` / `custom_backend` / `transcode` frees were
    // three hand-written lines; a fourth satellite would have leaked here.
    var gc = newGc();
    defer gc.deinit();

    _ = try gc.allocCustomPort(true, true, false, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE);
    _ = try gc.allocTranscodedPort(types.FALSE, true, false, .utf8, .lf, .replace);
    _ = try gc.allocRandomPort(.{ .kind = .determinized });

    // A port carrying two satellites at once, so the walk cannot pass by
    // freeing only the first one it finds.
    const both = try gc.allocCustomPort(true, true, false, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE);
    const bp = types.toObject(both).as(types.Port);
    const ts = try gc.allocator.create(types.TranscodeState);
    ts.* = .{ .wrapped_port = types.FALSE, .codec = .utf8, .eol_style = .lf, .error_mode = .replace };
    bp.transcode = ts;

    forceFull(&gc);
    forceFull(&gc);
}

test "gc tracing: a port carrying both satellites traces both (all three arms)" {
    var gc = newGc();
    defer gc.deinit();
    const rd = try young(&gc, 1);
    const fl = try young(&gc, 2);
    const wrapped = try young(&gc, 3);

    const port = try gc.allocCustomPort(true, true, false, rd, types.FALSE, types.FALSE, types.FALSE, types.FALSE, fl);
    const p = types.toObject(port).as(types.Port);
    const ts = try gc.allocator.create(types.TranscodeState);
    ts.* = .{ .wrapped_port = wrapped, .codec = .utf8, .eol_style = .lf, .error_mode = .replace };
    p.transcode = ts;

    // Test A: markValueInner, via the root set.
    try expectTraced(&gc, port, &.{ ref(rd, 1), ref(fl, 2), ref(wrapped, 3) });
}

test "gc tracing (remembered set): a port carrying both satellites" {
    var gc = newGc();
    defer gc.deinit();
    const port = try gc.allocCustomPort(true, true, false, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE, types.FALSE);
    const p = types.toObject(port).as(types.Port);
    const ts = try gc.allocator.create(types.TranscodeState);
    ts.* = .{ .wrapped_port = types.FALSE, .codec = .utf8, .eol_style = .lf, .error_mode = .replace };
    p.transcode = ts;
    try promoteToOld(&gc, port);

    const rd = try young(&gc, 1);
    const wrapped = try young(&gc, 2);
    p.custom_backend.?.read_proc = rd;
    p.transcode.?.wrapped_port = wrapped;
    gc.writeBarrier(&p.header, rd);

    // Test B: markObjectContents plus referencesYoung, via the remembered set.
    try expectRememberedTrace(&gc, port, &.{ ref(rd, 1), ref(wrapped, 2) });
}

// ---------------------------------------------------------------------------
// #2196 — remembered-set deduplication
//
// A container mutated n times must appear in the remembered_set at most once,
// or the minor mark phase marks it n times (and marking a large container is
// O(capacity), making a fill quadratic in writes). These assert the count is
// bounded by the number of *distinct* containers, not the number of writes,
// while every distinct container still gets tracked.
// ---------------------------------------------------------------------------

test "gc remembered set (#2196): repeated writes to one container queue a single entry" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocVectorFill(4, types.NIL);
    try promoteToOld(&gc, c);
    const vec = types.toObject(c).as(types.Vector);

    // Fire the barrier many times, as a container mutated in a loop does
    // (hash-table-set! fires it twice per insert). Each iteration repoints a
    // slot at a fresh young object. gc.enabled is false, so no collection --
    // and no prune -- runs underneath the loop.
    var i: usize = 0;
    while (i < 500) : (i += 1) {
        const a = try young(&gc, @intCast(i));
        vec.data[i % 4] = a;
        gc.writeBarrier(&vec.header, a);
    }

    // Pre-fix: 500 identical entries. Post-fix: exactly one.
    try std.testing.expectEqual(@as(usize, 1), gc.remembered_set.items.len);
    try std.testing.expect(inRemembered(&gc, &vec.header));
    try std.testing.expect(vec.header.flags.in_remembered_set);
}

test "gc remembered set (#2196): writes to N distinct containers queue N entries" {
    var gc = newGc();
    defer gc.deinit();
    const N = 16;
    var containers: [N]*Object = undefined;
    var i: usize = 0;
    while (i < N) : (i += 1) {
        const c = try gc.allocPair(types.NIL, types.NIL);
        try promoteToOld(&gc, c);
        containers[i] = types.toObject(c);
    }

    // One old->young write per distinct container. Dedup must never suppress a
    // *different* container -- every reference still has to be tracked.
    for (containers) |cobj| {
        const a = try young(&gc, 0);
        cobj.as(types.Pair).car = a;
        gc.writeBarrier(cobj, a);
    }

    try std.testing.expectEqual(@as(usize, N), gc.remembered_set.items.len);
    for (containers) |cobj| {
        try std.testing.expect(inRemembered(&gc, cobj));
        try std.testing.expect(cobj.flags.in_remembered_set);
    }
}

test "gc remembered set (#2196): a container re-queues after the set drops it" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocVectorFill(1, types.NIL);
    try promoteToOld(&gc, c);
    const vec = types.toObject(c).as(types.Vector);

    // First old->young write: one entry, dedup flag set.
    const a = try young(&gc, 1);
    vec.data[0] = a;
    gc.writeBarrier(&vec.header, a);
    try std.testing.expectEqual(@as(usize, 1), gc.remembered_set.items.len);
    try std.testing.expect(vec.header.flags.in_remembered_set);

    // Overwrite the slot with an immediate, then collect. The container no
    // longer references young, so pruneRememberedSet drops it and must clear
    // the dedup flag.
    vec.data[0] = types.makeFixnum(0);
    forceMinor(&gc);
    try std.testing.expectEqual(@as(usize, 0), gc.remembered_set.items.len);
    try std.testing.expect(!vec.header.flags.in_remembered_set);

    // A fresh old->young write must re-queue exactly one entry -- proving the
    // flag was reset, so no old->young reference is ever silently dropped.
    const b = try young(&gc, 2);
    vec.data[0] = b;
    gc.writeBarrier(&vec.header, b);
    try std.testing.expectEqual(@as(usize, 1), gc.remembered_set.items.len);
    try std.testing.expect(vec.header.flags.in_remembered_set);
}

test "gc remembered set (#2196): a full collect drain resets every dedup flag" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocVectorFill(1, types.NIL);
    try promoteToOld(&gc, c);
    const vec = types.toObject(c).as(types.Vector);

    const a = try young(&gc, 1);
    vec.data[0] = a;
    gc.writeBarrier(&vec.header, a);
    try std.testing.expect(vec.header.flags.in_remembered_set);

    // Repoint at an immediate so the #1961 sweepOld re-scan has no old→young
    // edge to re-record. fullCollect drains the whole remembered_set and the
    // flag must be cleared there too — otherwise a surviving container that
    // keeps its stale flag would refuse to re-queue, silently dropping a
    // later old->young write. Root the container so the full collect keeps it.
    vec.data[0] = types.makeFixnum(0);
    var root = c;
    gc.pushRoot(&root);
    forceFull(&gc);
    gc.popRoot();
    try std.testing.expectEqual(@as(usize, 0), gc.remembered_set.items.len);
    try std.testing.expect(!vec.header.flags.in_remembered_set);

    // And it can be tracked again.
    const b = try young(&gc, 2);
    vec.data[0] = b;
    gc.writeBarrier(&vec.header, b);
    try std.testing.expectEqual(@as(usize, 1), gc.remembered_set.items.len);
    try std.testing.expect(vec.header.flags.in_remembered_set);
}

// #1961: a full collection drains the remembered set before marking but
// never promotes — young survivors stay generation 0 — so an old container
// whose young referent just survived the full would face the next minor
// with no entry. sweepOld re-records every surviving old→young edge while
// it already walks the old generation.
test "gc remembered set (#1961): a full collect re-records surviving old→young edges" {
    var gc = newGc();
    defer gc.deinit();
    const c = try gc.allocVectorFill(1, types.NIL);
    try promoteToOld(&gc, c);
    const vec = types.toObject(c).as(types.Vector);

    const a = try young(&gc, 1);
    vec.data[0] = a;
    gc.writeBarrier(&vec.header, a);

    var root = c;
    gc.pushRoot(&root);
    forceFull(&gc);
    // The vector survived the full still referencing young `a`, so the
    // re-scan must have re-queued it: the next minor's mark reaches `a` only
    // through that entry.
    try std.testing.expectEqual(@as(usize, 1), gc.remembered_set.items.len);
    try std.testing.expect(vec.header.flags.in_remembered_set);

    gc.popRoot();
    forceMinor(&gc);
    try expectAlive(&gc, ref(a, 1));
}

// ---------------------------------------------------------------------------
// #1962: the untraced env-map invariant (Function.env / Transformer.def_env)
//
// No GC switch traces these raw *StringHashMap pointers. They are safe only
// through their paired env_val/def_env_val, OR because the map is one of the
// VM-rooted library registries markVmRoots traces. `globals.assertEnvMapInvariant`
// makes that unwritten rule checkable at every construction site; these tests
// exercise the predicate it asserts on directly (an assertion firing panics,
// which a Zig test cannot catch, so the check is factored as a bool predicate).
// ---------------------------------------------------------------------------

test "gc tracing (#1962): env-map invariant predicate distinguishes the three routes" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // A genuinely private map: allocated here, never handed to any VM registry.
    // This is the shape a future unsafe call site would produce.
    var private = std.StringHashMap(Value).init(vm.gc.allocator);
    defer private.deinit();

    const non_nil = types.makeFixnum(7); // stands in for a real paired env_val

    // Route 1 -- paired with a non-NIL (traced) value: always sound, private or
    // not. This is the restricted-environment / (eval expr env) case.
    try std.testing.expect(globals_mod.envMapInvariantHolds(&private, non_nil));

    // The hazard #1962 is about: a private map with a NIL paired value is
    // reachable by nothing once collected. The predicate must reject it, which
    // is what turns `assertEnvMapInvariant` into a deterministic trip wire.
    try std.testing.expect(!globals_mod.envMapInvariantHolds(&private, types.NIL));

    // Route 2 -- the same NIL pairing is sound once the map is a VM-rooted
    // registry. Register `private` as an in-flight pending_lib_env exactly as
    // handleDefineLibrary does; markVmRoots now traces it, so NIL is fine.
    vm.pending_lib_envs[vm.pending_lib_env_count] = &private;
    vm.pending_lib_env_count += 1;
    defer vm.pending_lib_env_count -= 1;
    try std.testing.expect(vm.isGcRootedEnvMap(&private));
    try std.testing.expect(globals_mod.envMapInvariantHolds(&private, types.NIL));
}

test "gc tracing (#1962): current_lib_env and a registered library both count as rooted" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    var map = std.StringHashMap(Value).init(vm.gc.allocator);
    defer map.deinit();

    // current_lib_env is the library env actively being compiled -- one of the
    // maps markVmRoots traces, so a Function/Transformer minted against it may
    // carry a NIL paired value (the five known-safe library sites).
    try std.testing.expect(!vm.isGcRootedEnvMap(&map));
    const saved = vm.current_lib_env;
    vm.current_lib_env = &map;
    defer vm.current_lib_env = saved;
    try std.testing.expect(vm.isGcRootedEnvMap(&map));

    // A retired env of a replaced library is likewise traced (#820), so it too
    // is accepted with a NIL pairing.
    vm.current_lib_env = saved;
    try std.testing.expect(!vm.isGcRootedEnvMap(&map));
    try vm.libraries.retired_envs.append(vm.gc.allocator, &map);
    try std.testing.expect(vm.isGcRootedEnvMap(&map));
    _ = vm.libraries.retired_envs.pop();
}

test "gc tracing (#1962): with no VM registered the invariant holds vacuously" {
    // A bare-GC context (this file's own default) has no vm_instance, so the
    // rooted-map callback is unregistered. envMapInvariantHolds must not treat
    // that as a violation -- without a VM no collection observes the field.
    const prev = globals_mod.env_map_rooted_lookup;
    globals_mod.env_map_rooted_lookup = null;
    defer globals_mod.env_map_rooted_lookup = prev;

    var map = std.StringHashMap(Value).init(std.testing.allocator);
    defer map.deinit();
    try std.testing.expect(globals_mod.envMapInvariantHolds(&map, types.NIL));
    try std.testing.expect(globals_mod.envMapInvariantHolds(&map, types.makeFixnum(1)));
}
