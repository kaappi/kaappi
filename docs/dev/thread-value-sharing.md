# Cross-thread value sharing

What may cross an SRFI-18 thread boundary, by which route, and what the
engine actually checks. Written for kaappi#1937, which found that the
`gc_deep_copy.zig` uncopyable-tag list — the thing that reads like the
authoritative answer — governs one of the two routes and not the other.

**The short version.** A value reaches another thread by one of two
routes, and they have separate, unrelated enforcement:

| route | how a value travels | what enforces the rules |
|---|---|---|
| **copy** | deep-copied into the other heap | the uncopyable-tag list, one central check |
| **globals** | reached by pointer, no copy | per-type owner checks in individual primitives — present for exactly four types, plus (since kaappi#1924) a general rejection of any store of a heap pointer into a container the running thread does not own (interned symbols excepted) |

The tag list is not a statement about what can cross a thread boundary.
It is a statement about what can be *copied*. Eight of the eleven tags
on it are freely reachable through a top-level `define`, and for two of
them that is the only supported way to share them at all.

## The copy route

Three boundaries deep-copy, and all three go through
`gc_deep_copy.deepCopyValue`:

- `thread-start!` — the thunk closure, copied into a
  `shared_channel.Envelope` on the **parent** thread before the child is
  spawned, then out of the envelope into the child's heap
  (`primitives_srfi18.zig`).
- `thread-join!` — the result, or the uncaught exception, copied into an
  envelope on the **child** as it exits, then out into the parent's heap
  at the join. A refusal therefore happens child-side and reaches the
  parent as a stored `failed` status, not as a live error.
- `channel-send` / `channel-receive` — the message payload, the same way.

Each traversal is a separate `deepCopy`; the envelope exists so neither
thread ever walks the other's live heap.

"Deep-copied thunk closure" means the closure's **lexical captures**. A
thunk that names a top-level binding captures nothing: the child resolves
that name through the shared globals map at run time, so the value never
enters the copy at all. This is the whole reason the two routes exist as
separate things.

The copy route's tag switch is not a two-way sort into *copied* or
*refused*. It has a distinct middle class — **aliased** — where the arm
returns the source object to the destination heap **by pointer** instead of
duplicating it. Soundness in that class is not automatic: an aliased object
outlives its source heap's collector only if the arm first promotes it to a
shared, refcounted representation and checks that the running thread is
entitled to share it. Exactly one tag earns the class — `channel` — and its
arm does all three. An arm that aliases *without* them hands the receiver a
pointer neither collector accounts for; that was the FFI bug #2027 removed by
moving `ffi-library`/`ffi-function` out of the aliased class and into the
*copied* one (below). So the switch has three outcomes, not two:

| class | what the arm returns | members |
|---|---|---|
| **copied** | a fresh object in the destination heap | pairs, vectors, strings, records, `native-fn`, `ffi-library`, `ffi-function`, `file-info`/`user-info`/`group-info`, `srfi18-time`, `random-source`, … |
| **aliased** | the source object, by pointer, after promotion + refcount + an ownership check | `channel` only |
| **refused** | `error.UncopyableType` | the eleven below |

`gc_deep_copy.zig` refuses eleven tags outright:

```text
port  continuation  fiber  mutex  condition_variable  ffi_callback
directory_object  scheme_environment  ephemeron  guardian  transport_cell
```

`file-info`, `user-info` and `group-info` used to sit here too; they are
pure value records (scalars plus owned string bytes, like `SchemeString`)
and have copied by value since kaappi#1978, so a `file-info` can be the
join result of a child thread. `directory_object` among the SRFI-170 types
is still genuinely uncopyable — it owns a live `DIR*`.

Channels are the sole **aliased** tag, and so **not** on that refusal list.
Their arm promotes the channel to a shared, refcounted representation and
aliases it — the promotion, the refcount, and the ownership check (next
paragraph) together are what make aliasing sound here, and what make a
lexically captured channel the supported way to share one (KEP-0002 §2). No
other tag may alias, because no other arm carries those three safeguards.

That arm carries the globals-route check too, in the one direction where
it means something. A copy **out of** the running thread's heap — into
the private `Envelope` heap every cross-thread hand-off goes through — is
refused unless the running thread owns the channel; a copy **in**, out of
an envelope some entitled thread already built, is not re-checked, since
the envelope's objects belong to that private heap rather than to the
importer. The direction, not the channel's promotion state, is what
decides: until kaappi#1934 an already-promoted channel skipped the check
its unpromoted twin failed, so a thread that read one out of a shared
global could still hand it down to a child, and that child got a working
stub for a channel nobody gave it.

FFI handles are not on that list either, and — since #2027 — no longer in
the aliased class: `ffi-library` and `ffi-function` are **copied**, and only
the callback is refused. The dlopen handle and the
symbol address are process-global and are shared by value; it is the
wrapper object that gets duplicated into the receiving heap, exactly as
`native-fn` duplicates the object around a static function pointer. Until
kaappi#2027 the arm aliased them instead, which handed the receiver a
pointer neither collector accounts for — a child-created handle was freed
by the child's own collector, running or not, and read back in the parent
as `(0.0 . 0.0)`. One consequence to know: `ffi-close` nulls the handle in
one wrapper only, so a copy on another heap no longer reports the library
as closed. (Closing a library another thread is calling was already
undefined; this moves where it is diagnosed, not whether it is safe.)

Record types are copied, and the copy is **the same type**. Type identity
is `RecordType.identity`, a process-global counter carried across every
copy boundary, not the RecordType address — which each copy necessarily
changes. Until kaappi#1932 it was the address, so a record returned by
`thread-join!` printed as a well-formed `#<<pt> 1 2>` while `pt?` answered
`#f` and every accessor raised. Generativity is unaffected: two evaluations
of a `define-record-type` form still mint two identities.

A refusal surfaces as `error.UncopyableType`, which the boundary turns
into a catchable error naming neither the type nor the offending value:

```text
uncaught exception in thread: thread thunk contains an uncopyable type
(port, continuation, fiber, mutex, condition variable, FFI callback,
directory object, environment, ephemeron, guardian, or transport cell),
or a channel owned by another thread
```

## Channel identity across stubs (kaappi#2394)

Every cross-thread hand-off of a channel mints a **stub** on the receiving
heap (`gc_deep_copy.zig`'s `.channel` arm → `allocChannelStub`): a fresh
`types.Channel` whose `shared` pointer targets the one refcounted
`SharedChannel`. Receiving the same channel twice therefore yields two stubs
that are *not* `eq?`/`eqv?`/`equal?` — distinct heap objects — even though no
channel operation can tell them apart. KEP-0002 §2 once promised an `eqv?`
that compares the `shared` pointer; the KEP's 2026-08-27 as-implemented
amendment dropped that, and kaappi#2394 settled the promise as an explicit
comparator surface in `(kaappi fibers)` instead — extending `eqv?` per-type
is what SRFI-128 comparators exist for:

- `channel=? a b` — `#t` iff both are channels backing the same
  `SharedChannel` (or the same unpromoted local channel; the mixed case only
  arises for genuinely different channels, since promotion rewrites the
  original in place and every stub is born promoted).
- `channel-hash ch [bound]` — hashes the channel's identity, consistent with
  `channel=?` by construction; mirrors `(hash obj [bound])` (SRFI 69).
- `channel-comparator` — `(make-comparator channel? channel=? #f
  channel-hash)`, built by calling the **real** `(srfi 128)`
  `make-comparator`, so `comparator?` and the field accessors agree with
  every hand-built comparator and the native `extractComparatorFns` bridge
  recognizes the record. It is cached on the VM like
  `default_random_source` — repeat calls return the same record — and its
  three procedures are `(kaappi fibers)`'s pristine registry exports,
  immune to top-level shadowing of those names.

The reply-channel/registry idiom:

```scheme
(define registry (make-hash-table channel=? channel-hash)) ; or (channel-comparator)
(hash-table-set! registry stub 'reply-to) ; any stub of the channel finds it
```

The hash input is the channel's identity **for its whole life**, not the
representation-of-the-moment: its own tagged Value while unpromoted, and —
once promoted — the `SharedChannel.identity_seed` `promoteChannel` preserved
from exactly that Value before publishing. A table keyed before the first
cross-thread send therefore still finds its entry after promotion rewrites
the original in place, and every stub hashes the one seed. The seed is
hashed with `identityHash` — a pure function of the bits that never
dereferences them (the original object may since have been swept or live on
another heap; `valueHash` would be wrong there, its dispatch reads `.tag`
through pointer bits) — so if the original is later collected and its
address reused, the collision is benign and deterministic: equality still
compares `shared` pointers. For a live unpromoted channel the result equals
plain `(hash ch)`'s identity arm on every target, wasm32's 32-bit `usize`
included.

`channel=?` and `channel-hash` read channel fields, so they carry the same
foreign-owner check as `channel-send`, now factored as
`primitives_fiber.checkChannelOwner` (a channel reached through a shared
global is a diagnosis, not a comparison); `channel?` stays exempt as a total
predicate.

`(srfi 113)` sets honor their comparator since kaappi#2394: `113.sld`'s
`%make-empty-set`/`%make-empty-bag` pass the comparator to
`make-hash-table`, which unwraps the record into its equality/hash pair —
and the native `detectMode` keeps the fast path for the standard
comparators, whose equality fields hold the real `eq?`/`eqv?`/`equal?`, so
`make-eq-comparator` sets pay nothing for the fix. Before it, every set's
backing table was built with a zero-argument `make-hash-table` (default
`equal?`) and any non-`equal?` comparator silently deduped by pointer.

**Loading `(srfi 128)` safely across threads.** `vm.libraries` reaches
child VMs as a struct copy (unlike `globals`, which got the pointer+lock
treatment — see `vm.zig`'s `initForThread`), and `markVmRoots` gates
library marking behind `owns_globals`. A library load from a non-root
VM would therefore put() into bucket storage the root reads unlocked
and leave non-root exports unmarked by every collector.
`threadStartImpl` closes this by pre-loading `(srfi 128)` on the root
VM before any child exists (`ensureComparatorLibraryLoaded`, which
refuses to load off-root; best-effort — the process's first
`thread-start!` is necessarily the root, so the load is always
pre-children, and a read-only no-op afterwards once it succeeded), and
an `embedded_libraries` entry keeps the library loadable under
`--sandbox`, on WASM, and — as the last resort after a disk miss — on a
binary with no lib tree to read at all.

**Library registry mutation across threads (kaappi#2510).** The same
struct-copied registry has a second hazard, written down when the #2510
rollback made failing loads mutate it. A failed `.sld` load now calls
`LibraryRegistry.unregister` (`src/library.zig`): it removes map
entries, appends the retired `lib_env` to `retired_envs` (which can
realloc), and deinit's the `Library` — all shared storage, since
`VM.initForThread` copies `vm.libraries` by value — while another
thread may still hold a `*Library` from `get` or `processImportSet`'s
registry short-circuit. `register`-replacement (any re-import of a
registered name) already carried this hazard class, so this is not a
regression of #2510, but `unregister` is the first shared mutator that
*deinit's a `Library`* another thread can be holding a pointer into.
The #2518 review's restore-on-rollback adds `take` and `restore` to the
same class, with one more twist: between them a displaced `Library`
lives in the loading thread's per-VM rollback journal, outside the map
— invisible to the owning GC's root walk, exactly like a `retired_envs`
append made from a child. The practical rule is the one the paragraph
above gives by another route: don't lazy-load libraries from child
threads — pre-load on the root before spawning.

## The globals route

`VM.initForThread` shares the **root** VM's `globals` map **by pointer**,
resolved through the parent chain: a child uses the same map its parent
uses, so every thread's pointer is the root's map (kaappi#2129). A
child thread reading a top-level binding gets the root's object itself,
in the root's heap, with no copy and no check at the point of access.

Four types defend themselves at the primitive level, by comparing
`Object.owner` against the running thread's `GC.id`:

| type | check | sites |
|---|---|---|
| channel | `channel belongs to another thread; pass it through the thread thunk to share it` | `primitives_fiber.zig` — `channel-send`, `channel-receive`, `channel-close!`, `channel-closed?`, `channel=?`, `channel-hash` |
| thread handle | `thread belongs to another OS thread; a thread handle may only be used by the thread that created it` | `primitives_srfi18.zig` `checkThreadOwner` — `thread-name`, `thread-specific`, `thread-specific-set!`, `thread-start!`, `thread-terminate!`, `thread-join!` |
| fiber | `fiber-join: fiber belongs to another thread; a fiber may only be joined by the thread that spawned it` | `primitives_fiber.zig` — `fiber-join` (kaappi#2001) |
| guardian | `guardian belongs to another thread; a guardian may only be used by the thread that created it` | `vm_calls.zig` `invokeGuardian` — both the register and the retrieve call shapes, object and transport-cell guardians alike (kaappi#2008) |

The last two were added because their damage was not the general
mutate-a-shared-global hazard. `fiber-join` *returned* the parent's own
heap object to the child as its documented result — a `set-car!` in the
child was observed by the parent — and reported a nonexistent deadlock
for a still-running foreign fiber. A guardian's `registered`/`ready` are
raw Zig `ArrayList`s, the only ones reachable for mutation from Scheme
across a heap boundary: a child appended to the parent's list with the
child's own allocator and no lock, which aborted the process with an
empty stdout and stderr, and registered child-heap objects the parent's
collector later read out of the freed child arena.

The three predicates that take these types — `channel?`, `thread?`,
`fiber?` — are deliberately exempt: a total predicate must answer, not
raise.

Nothing else is checked. Every other type on the uncopyable list is fully
usable from a child thread through a global.

The map's *generation counter* is shared the same way. Every function
caches the globals it resolves (`Function.global_cache`, validated by
`cache_version` against the current generation), and the generation lives
on the `GlobalsRwLock` object every VM chained to the map holds by pointer
(`GlobalsRwLock.version`, read through `VM.globalVersion`). Until
kaappi#2483 it was a per-VM field that `initForThread` neither copied nor
shared, so a child's caches were invalidated only by the child's own
rebindings: after the root redefined a global, a child that had already
cached it kept calling the old binding, and a `guard_builtin`
(kaappi#2469) in the child stayed on its fast path after the root
redefined the builtin. Two ordering rules keep the shared counter honest
across threads: a writer bumps it inside the locked region that made the
store and re-validates its own slot with the value *that* bump returned,
and a reader snapshots it once *before* the map read and stamps the
snapshot — a fresh load after the read could bless a value another thread
had rebound in between (`VM.bumpGlobalVersion`, `VM.globalVersion`).

**The native tier follows the same protocol.** The LLVM backend's global
entry points in `src/runtime_exports.zig` — `kaappi_set_global` (every
natively compiled `set!` on a top-level variable), `kaappi_global_lookup`
(every global reference the emitter lowers to a call), and the fixnum
fallbacks' `callPrimitive` lookup — wrap their map access in
`VM.lockGlobalsShared`/`unlockGlobalsShared` and bump the generation inside
the locked region, mirroring the interpreter's `set_global` opcode and
`lookupGlobalLocked`. This matters for the same reason it does in the VM: a
natively compiled closure deep-copied into a child thread (`.native_closure`
copies the object around the static `fn_ptr`) runs via `callNativeClosure`,
which passes the **calling** VM — so its global reads and stores reach the
shared map as child-thread accesses, where an unlocked `getPtr`/`get` can
race another thread's rehashing `put` and touch a freed bucket array
(kaappi#2487). `kaappi_set_global` also carries the #1924 owner check
before it takes the lock: a child storing its own heap's object into the
shared map is refused, exactly as the `set_global` opcode's
`raiseCrossHeapStoreVM` refuses it — but fatally (exit with the same
diagnostic text), since a `void` runtime export cannot raise a catchable
Scheme error. `kaappi_define_global` needs neither: it only ever runs at
top level on the owner thread (internal defines are rejected in native
lambda bodies, kaappi#819).

## The actual matrix

Verified at `e24e594e`, ReleaseSafe, isolated `KAAPPI_HOME` — except the
two **copied** rows, which describe behaviour that commit predates and
which were verified on kaappi#1932 / kaappi#2027's own branch. Their
regression suites are named under "Keeping it honest" below. "capture"
means bound in a `let` and closed over by the thunk; "global" means bound
with a top-level `define` and named by the thunk.

| type | capture | global | status |
|---|---|---|---|
| thread handle (fiber) | refused | refused | **coherent** — usable only by its creating thread |
| fiber (`spawn`) | refused | refused (kaappi#2001) | **coherent** — same rule, arrived at later |
| channel | **aliased — the supported way** | refused | **coherent** — one supported route, and it is checked |
| mutex | refused | works | **inverted** — the only way to share one is the route the list refuses |
| condition variable | refused | works | **inverted** — same |
| port | refused | works | unchecked (see below) |
| continuation | refused | no error, does not resume the parent | unchecked — kaappi#1936 |
| `scheme-environment` | refused | works (`eval` in it succeeds) | unchecked |
| `file-info` / `user-info` / `group-info` | **copied by value** | works | **coherent** since kaappi#1978 — pure value records, now copy like `SchemeString` |
| directory object | refused | works | unchecked |
| ffi-library / ffi-function | **copied** | works | **coherent** since kaappi#2027 — the wrapper crosses, the process-global handle is shared by value |
| record type / instance | **copied, same type** | works | **coherent** since kaappi#1932 — identity is a counter carried by the copy, not the address |
| guardian | refused | refused (kaappi#2008) | **coherent** — the raw-container mutation made a check mandatory |
| ephemeron | refused | works | unchecked — bound to one GC's collection cycle, but nothing mutates a raw container through it |
| transport cell | refused | — | unreachable from Scheme: on this non-moving collector a transport-cell guardian always yields `#f` |
| ffi-callback | refused | works | unchecked — the copy refusal is now pinned both directions (`srfi18-deepcopy-matrix-audit.scm`, two-pointer signature); a global runs the parent-heap closure, like a custom port |

Two rows deserve their own note.

**Mutexes and condition variables are inverted relative to channels.**
The two appear side by side in every concurrency example, and the correct
idiom is exactly opposite:

```scheme
;; channel — MUST be captured lexically
(define (worker)
  (let ((ch (make-channel)))
    (thread-start! (make-thread (lambda () (channel-send ch 'done))))
    (channel-receive ch)))

;; mutex — MUST be a top-level global
(define m (make-mutex))
(thread-start! (make-thread (lambda () (mutex-lock! m) (mutex-unlock! m))))
```

Swap the two and both break, each in its own way: the captured mutex is
refused by the copy at `thread-start!`, and the global channel raises
from inside `channel-send`. A mutex left locked by a dead child correctly
reads `abandoned` from the parent (kaappi#1458), so the globals route is
genuinely supported here, not merely tolerated.

**A port through a global is not sound "because ports hold no Values".**
That is true of the plain string- and fd-backed ports whose mutable state
is byte offsets and buffers — a shared input port advances one position
for both threads, and a shared output port interleaves in call order:

```text
parent writes "P1;", child writes "CHILD;", parent writes "P2;"
  ⟹  "P1;CHILD;P2;"
```

But SRFI 181 gave `Port` two Value-bearing fields, `custom_backend` (five
Scheme callbacks) and `transcode` (a wrapped port). A custom port reached
through a global runs **the parent's closures on the child thread**, and
those closures are ordinary Scheme subject to kaappi#1924's
mutate-through-a-global hazard. Verified: a child reading from a custom
textual input port really does execute the parent-heap `read!` procedure
and really does advance the parent's own state. So the port row is not
one rule — it is "sound for the representations that hold no Values, and
the general mutation hazard for the ones that do".

## Why the checks were not simply extended to the globals route

kaappi#1937 offered this as one of two fixes. It cannot be done
uniformly, because for two of the eleven tags the globals route is the
*only* route: refusing a foreign mutex or condition variable would remove
the sole supported way to synchronise threads, and SRFI-18 has no other.
Ports through globals would break too, and the issue itself argues that
case is fine. A per-type check is possible — `Object.owner` is on every
heap object, so the mechanism is already there and the channel and thread
cases show the shape — but it is a per-type decision about a per-type
idiom, not one sweep.

That per-site decision is exactly how the general mutation hazard
(kaappi#1924) was settled. A child writing a value into a shared
parent-heap container — a record field, a vector slot, a pair, a
hash-table entry, a promise's memoised value, or the globals map itself —
leaves a pointer the parent's collector skips as foreign and the child's
collector cannot see a reference to, so the value is freed by the child's
GC or at its join while the container still holds it. The store is now
**rejected before it happens** (`memory.crossHeapStoreViolation`, checked
at every general mutation site): a thread may store into a heap object it
owns values from any heap, but never into a container it does not own.
The rejection is unconditional on the value's owner — even a value owned
by the container's own foreign heap is refused, because storing a young
value into an old container requires the OWNER's generational write
barrier (a remembered-set edge), and the owner's remembered set cannot be
touched cross-thread. This is not a per-type check on a value (any type
may be stored into an owned container); it is a per-store check on the
container's owner. The one sanctioned engine-level exception is the mutex
owner pair in `mutex-lock!`: locking a shared parent-heap mutex from a
child must record the child's own fiber as owner so a dying fiber can
abandon it, and the mutex site deliberately does not call the check.
The remaining unsound cases have their own issues (kaappi#1936; a
mutex-specific/condvar-specific store from a child is now rejected like
any other foreign-container store, closing the residual the #2127
quarantine used to detect).

Two rows have since been decided that way, one each: the fiber
(kaappi#2001) and the guardian (kaappi#2008). Both had a route-specific
failure no general mutation rule covers — an API that hands the foreign
object back as its result, and a raw Zig container mutated from two
allocators — and neither had a competing idiom to protect, since the copy
route refuses them outright. That is the bar for adding a check here: not
"is the globals route unsound for this type" (it broadly is), but "does
this type have damage of its own, and no supported idiom to lose".

What this document fixes is the narrower thing that made the state
misleading: the tag list read as a guarantee it never provided.

## Where these rules were written down before

Scattered, and each in a place that only answers one question:

- `lib/srfi/120.sld`'s header — the channel rule, and the general warning
  that a top-level binding "reaches the ORIGINAL object from the wrong
  heap". Correct, but discoverable only from the timer library.
- `tests/scheme/srfi/srfi18-cross-heap-abandoned-mutex.scm`'s header —
  the mutex rule, stated exactly right, inside a regression test.
- `tests/scheme/srfi/srfi18-cross-thread-channels.scm`'s header —
  KEP-0002's two motivation paths.
- `CLAUDE.md`'s "OS threads (SRFI-18)" section — the copy route only.

Nothing anywhere noted that channels and mutexes differ, which is the
finding that motivated this file.

## Implementation map

`thread-start!` spawns real OS threads via `std.Thread.spawn`. Each child
thread gets its own VM and GC with an independent heap.

| Piece | Where | What it does |
|-------|-------|--------------|
| `vm_instance`, `gc_instance` | `src/vm.zig`, `src/memory.zig` | `threadlocal` — the running thread's VM and GC |
| `GC.initForThread` | `src/memory.zig` | Per-thread GC, sharing the **root's** symbol table (chained through the parent chain; a joined middle thread's own tables stay empty, kaappi#2129) |
| `GC.deepCopy` / `deepCopyValue` | `src/memory.zig` (impl in `gc_deep_copy.zig`) | Deep-copies values between GC heaps; owns the 11-tag refusal list |
| `VM.initForThread` | `src/vm.zig` | Per-thread VM, sharing the **root's** globals and libraries **by pointer** |
| `VM.owns_globals` | `src/vm.zig` | Stops a child VM freeing the shared maps on deinit |
| `GlobalsRwLock.version` | `src/globals.zig` | kaappi#2483: the globals generation every per-function global cache is validated against, on the lock object all threads share by pointer — so the root's rebinding invalidates a child's cache and vice versa |
| `kaappi_set_global` / `kaappi_global_lookup` | `src/runtime_exports.zig` | kaappi#2487: the native backend's global store and read — shared lock around getPtr+store+bump and the map read when reached from a child VM, mirroring `set_global` / `lookupGlobalLocked` |
| `symbol_mutex` | `src/memory.zig` | Spinlock protecting concurrent symbol interning |
| `child_resources` | `src/primitives_srfi18.zig` | Global map holding child GC/VM references; entries are freed at `thread-join!` or, when the join retires them because the thread still has live descendants, by the last descendant's `threadEntryFn` defer once the subtree drains (kaappi#2129) |
| `markLiveChildRoots` | `src/primitives_srfi18.zig` | kaappi#1933: registered on the **root** GC as `gc.child_marker`; the root's collector stops every live child at a dispatch-loop safepoint (or finds it already parked / in an FFI call) and marks its roots with the root's gc, so a parent-heap object referenced only from a live child's registers is never freed under it. Children spawned mid-collection spin on `collection_in_progress` before their first shared-globals read. The child side reports `collection_state` (`.running`/`.parked`/`.stopped`/`.in_native`) from the safepoint (`stopForCollection`), the park (`parkOnReactor`) and FFI (`callFfi`) sites |
| `crossHeapStoreViolation` | `src/memory.zig` | kaappi#1924: the rejection predicate checked before every general store into a heap object — a store into a container owned by another GC is allowed only when the value is owned by that same GC. The `mutex-lock!` owner pair is the deliberate exception |
| `Object.owner` vs `GC.id` | `src/gc_collect.zig` | Every heap object records its owning GC; marking skips objects owned by another GC, so a child's collections never write mark bits on parent-heap objects reached through shared globals (kaappi#958) |
| `SharedChannel.identity_seed` | `src/shared_channel.zig` | kaappi#2394: the promoting channel's tagged Value, written before `ch.shared` publishes — the hash identity every stub of the channel shares for its whole life |
| `ensureComparatorLibraryLoaded` | `src/primitives_fiber.zig`, called from `threadStartImpl` | kaappi#2394: best-effort pre-load of `(srfi 128)` on the spawning VM, so no child VM ever lazy-loads into the struct-copied registry (see the channel-identity section) |

The deep copy happens at exactly three boundaries: the thunk closure at
`thread-start!`, the result (or uncaught exception) at `thread-join!`, and a
channel message in each direction.

### When a thread's heap may be freed (kaappi#2129)

A thread's fiber handle lives in the heap of the thread that created it,
and every descendant dereferences its own handle — the dispatch-loop
safepoint polls its `terminated` flag every 1024 instructions, and the
terminal `status` store happens at exit — for its whole life, not just its
startup prologue. `thread-join!` therefore must not free the joined thread's
GC/VM while any thread it started is still live. Each fiber carries a
`live_descendants` count (incremented by `threadStartImpl` before spawning,
released by the child's `threadEntryFn` defer once the child's own subtree
has drained); `reapOsThread` frees immediately only when the count is zero,
and otherwise **retires** the `child_resources` entry, leaving the GC/VM
allocated so the descendant can keep dereferencing its handle. The last
descendant's defer frees the retired entry once its subtree drains, so the
retirement is bounded unless a descendant genuinely never finishes (then the
resources last until process exit, the kaappi#1792 pattern). `thread-join!`
itself still returns immediately — it never waits for the joined thread's
descendants.

## Keeping it honest

`tests/scheme/srfi/srfi18-sharing-model.scm` pins both routes for the ten
types that cover every distinct enforcement shape in the matrix: thread
handle, fiber, channel, mutex, condition variable, port (both
directions), continuation, environment, ephemeron, guardian. It is
deliberately a *characterisation* test — it asserts what the engine does today, including
the rows this document calls unchecked, so that a change to any of them
fails visibly and lands here rather than silently widening the gap between
the code and this table.

The four SRFI-170 record types are left out on purpose: `user-info` raises
"unsupported" on Windows and this suite runs there, and those rows add no
enforcement shape the nine already cover. (The three *copyable* ones —
`file-info`, `user-info`, `group-info` — have their own cross-boundary
coverage in `tests/scheme/audit/srfi18-deepcopy-matrix-audit.scm` and
`tests/scheme/audit/primitives_filesystem-audit.scm` section H since
kaappi#1978.) `ffi-callback` is exercised instead in
`tests/scheme/audit/srfi18-deepcopy-matrix-audit.scm` — a *callback* needs no
loaded library, only a supported signature (the two-pointer shape from
`callback-error.scm`), and that suite pins both copy-route directions as
refused; the transport cell is unreachable, as above.

Two smaller checks live elsewhere and are worth knowing about rather than
duplicating: `src/tests_deepcopy.zig` asserts the port and continuation
refusals at the `GC.deepCopy` level directly, and
`src/tests_shared_channel.zig` asserts that a channel *message* carrying a
port is refused the same way.

Channel identity across stubs (previous section) has its own coverage:
`tests/scheme/smoke/channel-identity-2394.scm` runs the
two-stubs-one-channel scenario end to end (both `make-hash-table` flavors,
the SRFI-128 comparator contract), and `src/tests_fibers.zig` carries the
unit-level versions (local identity, stub unification, table dedup, lazy
comparator construction).

The two copied rows added above have their own regression suites, each
covering all four boundaries (into the child, out of it, the raise path, a
channel message): `tests/scheme/srfi/srfi18-record-identity-1932.scm` and
`tests/scheme/ffi/thread-boundary-2027.scm`. Both carry the control that
constrains the fix — a second look-alike record type that must stay
disjoint, and the parent-owned FFI handle a blanket refusal would have
broken. `tests/scheme/audit/srfi18-deepcopy-matrix-audit.scm` remains the
per-tag enumeration.
