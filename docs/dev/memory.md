# The value model and the garbage collector

How a Scheme value is represented, how heap objects are laid out, and how
the per-heap collector finds and frees garbage: the generational split, the
remembered set and its two feeders, the root set, weak references, the
child-thread protocol, deep copy, and the debug machinery that turns a
use-after-free into a deterministic panic. This is the as-built companion
to [KEP-0017](https://github.com/kaappi/keps/blob/main/keps/0017-gc-and-value-model.md)
(the design record). The rules a contributor follows while *writing* code
that allocates — root before allocating, barrier after storing, never
`defer popRoot()` across a push — stay in
[gc-safety-and-error-handling.md](gc-safety-and-error-handling.md) and
`.claude/rules/gc-safety.md`; this document is why those rules are what
they are.

The one-paragraph version: **a precise, non-moving, stop-the-world,
generational mark-and-sweep collector over an intrusive linked list, one
per OS thread.** Values are NaN-boxed 64-bit words; heap objects share a
header with a tag, a mark bit, a generation bit, a survive count and the id
of the GC that owns them. A minor collection marks only the young
generation and treats old objects as opaque, so every old-to-young edge
must be in the remembered set — which is why a missing write barrier is a
use-after-free, not a leak. Nothing scans the Zig stack: a `Value` held in
a Zig local across an allocation is invisible unless it is rooted.

## Where it sits

| File | Owns |
|------|------|
| `types.zig` | `Value`, the NaN-box encoding, `Object` and `ObjectTag`, `makePointer`/`toObject` |
| `memory.zig` | the `GC` struct, `writeBarrier`/`rememberObject`, `maybeCollect`, the root stack, the quarantine, `allocSliceNoFill`, `OomAllocator`, the `FREED_OWNER` sentinel |
| `gc_alloc.zig` | every `allocXxx` constructor and the allocation discipline |
| `gc_collect.zig` | `collect`, the minor and full cycles, `markRoots`, `markValueInner`, the remembered-set prune and drain, `processWeakRefs` |
| `gc_sweep.zig` | `sweepYoung` (with promotion), `sweepOld`, `objectSize`, `freeObject` and its poison/quarantine plumbing |
| `gc_deep_copy.zig` | the copy route across thread boundaries and its refusal list |
| `shared_object.zig`, `shared_buffer.zig`, `shared_channel.zig` | refcounted objects that live *outside* every GC heap (KEP-0002/0003) |
| `vm_roots.zig` | `markVmRoots`, the VM's contribution to the root set ([vm.md](vm.md)) |
| `primitives_srfi18.zig` | `markLiveChildRoots`, the parent-marks-children protocol |

`gc_instance` is a threadlocal pointer to the current thread's GC, set by
`setGCInstance`; each SRFI 18 thread has its own (`initForThread`).

## Values

`Value` is a `u64`, discriminated by its top 16 bits:

| Top bits | Meaning | Payload |
|----------|---------|---------|
| below `0xFFFC` | flonum | the raw `f64`, no heap allocation; real NaNs are canonicalized to `0x7FF8…` so they cannot collide with the tag space |
| `0xFFFC` | heap pointer | 48-bit address of the object's `header` |
| `0xFFFD` | fixnum | a signed `i48`, so ±2^47; overflow promotes to a bignum |
| `0xFFFE` | immediate | `NIL` 0, `FALSE` 1, `TRUE` 2, `VOID` 3, `EOF` 4, `UNDEFINED` 5; a character sets bit `0x80` with the codepoint above it |

Two consequences worth holding onto. `makePointer` is a plain OR with no
masking, so the model needs 48 addressable bits and no more — which is
what lets it hold on wasm32, where the `_align` field in the header forces
the 8-byte alignment 32-bit allocators do not guarantee. And a heap Value's
payload is always the address of the struct's `header` field:
`makePointer(&x.header)` in, `Object.as()` (`@fieldParentPtr`) out. Zig's
auto layout is free to move `header` off offset zero — it silently moved
`Port`'s to offset 48 once, #1618 — so a direct cast of the struct pointer
is a compile error by design.

## Heap objects

Every heap struct embeds `header: Object` as its first *declared* field:

```zig
pub const Object = struct {
    tag: ObjectTag,     // enum(u6): 42 tags today
    flags: Flags,       // packed u8: marked, generation:u1, survive_count:u2,
                        //            immutable, in_remembered_set
    owner: u32,         // id of the GC that tracks this object; FREED_OWNER once freed
    next: ?*Object,     // the intrusive allocation list
    _align: Align,      // 8-byte alignment on 32-bit targets
};
```

`ObjectTag` and the per-type tables are in
[architecture.md](architecture.md); adding a tag means updating the five
exhaustive switches listed in [adding-features.md](adding-features.md).
The GC keeps two intrusive lists, `objects` (young) and `old_objects`, and
`trackObject` stamps `owner`, links the object into the young list, and
updates the counts and per-tag stats.

There is **no free list, no bump pointer and no size class**: each object
is an individual `allocator.create(T)`, and the allocator behind it is the
C allocator in the shipped binary. Three consequences: the collector is
non-moving, so a raw pointer that escapes through the FFI stays valid and
`transport_cell` is an ordinary strong pair; `allocSliceNoFill` and its
siblings bypass the Zig convenience methods for the hot, size-proportional
buffers (vector data, bignum limbs, register files, continuation
snapshots), because those methods `0xAA`-fill in ReleaseSafe regardless
of the backing allocator (#1809, continuations −60%); and a single payload
is capped at `max_payload_bytes` (1 TiB) before the OS is asked, because an
overcommitting kernel would reserve `(make-bytevector 100000000000000)` and
let the OOM killer end the process at commit time
([freebsd.md](freebsd.md)).

## Allocation

Every `allocXxx` follows one discipline, and `allocPair` is its shortest
statement:

```zig
self.rootArgs2(car_val, cdr_val);   // Value arguments are auto-rooted
try self.maybeCollect();            // the only place a collection can start
self.clearArgRoots();
const pair = try self.allocator.create(Pair);
```

Callers therefore never root the Values they pass *into* an allocator; they
root the Values they hold *across* one. Allocators that receive a slice
(`allocVector`, `allocString`, bignum limbs) **copy it before collecting**
and point `slice_roots` at the copy, so a slice that aliases another heap
object's storage survives that object being swept (#1401). Five
allocators skip `maybeCollect` and can never trigger a collection:
`allocSymbol`, `allocFunction`, `allocNativeFn`, `allocTransformer`, and
the immediate-producing `allocFlonum`. That is a fact tests rely on, and
also why `oom_countdown` (below) cannot reach them.

`maybeCollect` collects when `enabled and (stress or object_count >=
gc_threshold)`, unless a `no_collect` window is open, in which case the
collection is deferred and counted. It separately enforces the absolute
`memory_limit` watermark (`--max-memory`): collect, and if still over,
`OutOfMemory`. `no_collect` is how the compiler pins unrooted transients
across a region — the expander's half-built result, a desugared
S-expression in a Zig local — and a `no_collect` increment that leaks on an
error return disables collection for the rest of the process, so it is
always paired with a `defer`.

**Symbols** are interned in a `StringHashMap` owned by the *root* GC and
aliased by every descendant (`shared_symbols`, chained to the root rather
than the immediate parent, #1935). Every access takes `symbol_mutex`, on the
parent side too, because a rehash frees the bucket array. A child that
interns a symbol stamps it with the root's id and appends it to the root's
`foreign_symbols` list, since the child's own object list dies at thread
teardown while the table still references the symbol. Interned symbols are
marked as roots every collection and never swept; SRFI 258 uninterned
symbols are ordinary collectable objects.

## The collection cycle

`collect` counts minor cycles and runs a **full collection every eighth
cycle, a minor collection otherwise**; afterwards the threshold becomes
`max(GC_THRESHOLD, object_count × 4)`, which is the heap-growth policy
(`-Dgc-threshold` sets `GC_THRESHOLD`, default 8192; `-Dgc-stress` collects
on every call instead). `collectFull` forces a full cycle out of schedule —
used to reclaim descriptors held by unreachable ports before reporting fd
exhaustion (#1993), since a minor sweep misses any fd holder already
promoted.

**Minor** (`minorCollect`): set `minor_marking`, mark from the roots, mark
the contents of every remembered container, resolve weak references,
release quarantined slots up to the cap, `sweepYoung`, prune the
remembered set. While `minor_marking` is set, `markValueInner` **returns at
any old object without marking or tracing it** — that is the whole cost
model: O(live young) plus the fields of remembered containers, not O(live
heap) (#1961). `GcStats.minor_old_skips` counts those returns; a test that
watches it stay positive over a large old heap is how the generational
claim is pinned.

**Full** (`fullCollect`): drain the remembered set up front (a full mark
never consults it), mark both generations from the roots, resolve weak
references, release quarantine, `sweep` the young list, `sweepOld`. Full
collections never promote.

**Promotion** happens in `sweepYoung`: a marked young object gets
`survive_count + 1`, and at 2 it moves to the old list with generation 1.
The mark bit is cleared by whichever sweep observes it, so no collection
ever sees a stale mark and there is no clear-marks pass.

### The remembered set and its two feeders

Because the minor mark stops at old objects, every live old→young edge
must be supplied by the remembered set. It is fed in two ways, and both
are load-bearing:

1. **`writeBarrier(container, new_val)`** after a store into a heap object's
   field: if the container is old and the value is a young object of this
   GC, enroll the container. Enrolment is deduplicated through the
   `in_remembered_set` flag (#2196): a large vector filled in a loop used to
   be re-marked once per write, making a fill quadratic. The flag belongs
   to the *owning* GC, so a foreign container (a shared global mutated
   across threads, the #1924 hazard) is appended without it.
2. **The promotion scan.** The barrier only fires for a container that is
   already old; an edge created while the container was young is recorded
   when `sweepYoung` promotes it, by scanning the object with
   `referencesYoung`. Its twin is the **full-collect re-scan** in
   `sweepOld`: the up-front drain emptied the set and a full collection
   never promotes, so every surviving old→young edge is re-recorded there.

`pruneRememberedSet` drops a container once none of its referents is young
any more; a later old→young store re-enrolls it. Two things deliberately
do not depend on the barrier: bulk state the collector re-traces wholesale
every cycle (each resident fiber's saved execution state, via
`FiberScheduler.markRoots`), and the root-marked maps (`vm.globals`, every
library `lib_env`), whose values are marked directly — `envStoreBarrier`
keeps that exclusion in one place. The full catalogue of barrier sites and
their reasons is in [gc-safety-and-error-handling.md](gc-safety-and-error-handling.md).

### The root set

`markRoots` marks, in order: `arg_roots` and `slice_roots` (the allocator
auto-roots), the push/pop **root stack** (`root_buffer`, growable from 1024
to `MAX_ROOT_CAPACITY` 65536, panic beyond), `extra_roots` (a dynamic list
for values with no natural owner: compiler-local macro transformers, the
expanded forms of a macro chain), the live FFI callback closures, the
interned symbol table (under `symbol_mutex`), then the VM's `root_marker`
(registers per live frame window, frames, handlers, winds, the globals and
library maps — [vm.md](vm.md)), and finally, outside the symbol lock, the
root GC's `child_marker` (below).

The root stack is positional, not per-variable: `popRoot` removes whatever
is on top, which is the LIFO footgun the rules document dwells on. A root
that leaks when the protected call fails is reclaimed at the pipeline
boundaries (`compileExpression*`, `vm_eval.eval`, `vm_calls.execute`) by
`truncateRoots`, which only ever shrinks (#1855).

Marking uses an explicit worklist on the GC struct rather than recursion,
so a deeply nested pair structure cannot overflow the native stack (#864);
the cdr spine of a list is iterated in place and only the car is pushed.
The worklist's retained capacity is capped at 1M entries, because on
macOS the freed large blocks stay resident and the buffer's regrowth after
every full collection accumulated ~65× the live heap in RSS (#2464).

### Weak references (SRFI 254)

`processWeakRefs` runs after the strong mark and before the sweep, to a
fixpoint over two interacting structures. An **ephemeron** retains its
value only once its key is proven alive; a key kept alive solely through an
ephemeron's own value never qualifies. An **object guardian** probes every
registered element against the *frozen* mark state before any element is
resurrected in that round, so N guardians watching one object all fire in
the same collection (#2011); resurrected elements move to the ready queue
and are kept alive *without becoming reachable* (`weak_resurrected`,
materialized into marks only once every weak decision is made). A
**transport cell** holds its value strongly and defers its weakly held key
to a post-fixpoint pass that breaks the cell if the key is neither
reachable nor kept alive (#2006); cells never transport on a non-moving
collector, so a transport-cell guardian's queue is always empty.

During a minor collection every old object trivially survives and carries
no mark, so both weak probes answer "alive" for an old object and defer
the decision to the next full collection; breaking an ephemeron over an
old key during a minor would be wrong, not merely early.

**Finalization** beyond this is deliberately thin: `freeObject` closes a
port's descriptor on sweep as a safety net, releases a shared buffer's
refcount, and gives an unreaped `Process` a last non-blocking reap. None
of it is a contract a program should rely on; `close-port` explicitly.

## Threads: one heap per thread

Each SRFI 18 OS thread runs its own VM on its own GC, and the collectors
stay out of each other's way by **ownership**: `markValueInner` returns
immediately for an object whose `owner` is not this GC's id (#958), and so
do `isYoungPointer`, the weak probes and deep copy's export check. A parent
heap object referenced from a child is the parent's job to keep alive, and
writing a child's mark bits into it would corrupt the parent's concurrent
cycle.

The exception is the one case ownership cannot see: a parent-heap object
referenced *only* from a live child's registers. The root GC therefore
registers `markLiveChildRoots` as its `child_marker` the first time a
thread is started (#1933). It arms `collection_stop` on every live child,
waits for each to leave `.running` — a child parks at the dispatch loop's
1024-instruction safepoint (`stopForCollection`), or already reports
`.parked` from a reactor wait or `.in_native` from an FFI call — marks the
child's registers and frames with the *parent's* GC (the foreign-owner
skip keeps it off the child's own objects), and releases them. It runs
outside `symbol_mutex`, because a child mid-init may be blocked on that
lock inside `allocSymbol`. The residual, documented and accepted: a
parent-heap object nested inside a child-*owned* container is still
invisible to the parent's collector.

Values cross a boundary by one of two routes, and the routes have separate
enforcement — [thread-value-sharing.md](thread-value-sharing.md) is the
full account. The **copy route** (`gc_deep_copy.zig`) deep-copies the
`thread-start!` thunk, the `thread-join!` result and every channel message
into the destination heap, iterating list spines rather than recursing
(#801), keeping a `visited` map so shared and cyclic structure copies once,
and carrying a record type's `identity` counter across so a record made
on a child still satisfies the parent's predicate (#1932: identity used to
be the address). It refuses twelve tags with `UncopyableType`: `port`,
`continuation`, `fiber`, `mutex`, `condition_variable`, `ffi_callback`,
`directory_object`, `scheme_environment`, `process`, and the three weak
types. A `channel` is neither copied nor refused: it is *promoted* to a
refcounted `SharedChannel` outside every heap and the receiver gets a
stub, and that arm's owner check keys off copy *direction*, not ownership
alone — on import the objects belong to a private envelope heap, never to
the importer, so re-checking there would reject every legal message
(#1934). The **globals route** shares the root's `globals` map by pointer
and copies nothing; only four types defend themselves there, inside
their own primitives.

A joined child's heap is freed on the parent thread, and its still-quarantined slots go to the
parent as `quarantine_heir` rather than back to the allocator — otherwise
the next parent allocation recycles a slot a parent value may still point
into and the freed-object sentinel is overwritten before the parent's next
mark can read it (#2127).

## Debug machinery

**Stress.** `-Dgc-stress=true` collects on every `maybeCollect`, which
turns a timing-dependent rooting or barrier bug into a deterministic
failure; the unit suite must stay green under it, and tests holding Values
in Zig locals across allocations root them for exactly this build.

**Deterministic use-after-free.** In Debug and gc-stress builds,
`freeObject` poisons the object and then stamps `owner` with
`FREED_OWNER`; `markValueInner` and both weak probes panic with
`GC: marking freed object (use-after-free)` on reading it, instead of
skipping the object as foreign (#1687). Under gc-stress the freed *header*
slots are additionally withheld in a quarantine, released oldest-first
only past 4 MiB and only between a later collection's mark and sweep, so a
dangling value marked several collections after the free still reads the
sentinel instead of a live object recycled into the same slot — the
silent-aliasing mode that let #1682 survive twelve nightly runs. Release
builds compile out both.

**OOM injection.** `oom_countdown` lets the next *n* `maybeCollect`-mediated
allocations succeed and fails the one after, sweepable over an allocation
index to drive a failure through every GC allocation a form performs; it
is the lever that reaches the expander's push/pop sites (#1855).
`OomAllocator` is its raw-allocator counterpart for the register files,
fiber snapshots, timer heap and bytecode pools that never go through
`maybeCollect` (#2435); it is thread-affine by design. Both compile out
of non-test builds. `FailingAllocator` cannot reach either surface, and
`memory_limit` fails within the first few allocations of any form.

**Observability.** `GcStats` (collections, mark and sweep time, freed
counts, peaks, per-tag allocation counts, deferred collections, minor old
skips) prints with `--gc-stats`; `kaappi features` reports the threshold
and whether stress is on; `KAAPPI_GC_THRESHOLD` overrides the threshold at
run time for a compiled program. There is no Scheme-level `(gc)`.

## Tests

| Suite | Covers |
|-------|--------|
| `src/tests_gc_tracing.zig` (89) | every root the marker must reach, per tag |
| `src/tests_gc_worklist.zig` (4) | deep structures and the worklist cap |
| `src/tests_gc_runtime_stress.zig` (7) | values held where the collector cannot see them (#2160/#2161) |
| `src/tests_gc_root_boundary.zig` (8) | the root-stack reset and the `oom_countdown` sweeps |
| `src/tests_deepcopy.zig` (33) | the copy route, refusals, identity, cross-heap freeing |
| `src/tests_endian.zig` (16) | the byte-order canary for the encoding (s390x) |
| `tests/scheme/smoke/gc-*.scm` and the `*-gc*.scm` siblings (27 files) | rooting under `-Dgc-threshold=1`, the generational minor (#1961), the remembered set through fibers, per-type mark coverage |
| `tests/scheme/coverage/gc-stress-coverage.scm` | the stress build's Scheme-level sweep |

Read `tests_gc_tracing.zig` before adding a heap type: the collector's five
switches have no compile-time check that a new tag's Value fields are
traced, and that suite is the check.

## What this design does not do

- **Compaction.** Non-moving is load-bearing: FFI pointers, `transport_cell`,
  the address-keyed `visited` map in deep copy and the quarantine all
  assume it.
- **Conservative stack scanning.** A Value in a Zig local is invisible.
  Every rooting rule follows from this one choice.
- **A shared heap across threads.** Ownership plus the copy route replace
  it; the cost is a deep copy at every boundary and the two-route
  inversion for mutexes versus channels.
- **Finalizers as a contract.** Guardians are the mechanism; port closing
  on sweep is a safety net.
