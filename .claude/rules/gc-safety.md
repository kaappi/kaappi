---
globs: ["src/primitives_*.zig", "src/memory.zig", "src/gc_*.zig", "src/vm*.zig", "src/compiler*.zig", "src/expander*.zig"]
description: GC safety requirements for heap-mutating code
---

# GC Safety Rules

When mutating heap objects (set-car!, set-cdr!, vector-set!, hash-table-set!,
string-set!, record field mutation):

- **Write barrier required**: call `gc.writeBarrier(container, new_val)` after
  storing a Value into a heap object field. Since #1961 the minor mark is
  generational: it stops at old objects and reaches their young referents
  only through the remembered set, so the barrier is load-bearing — omitting
  it means the young referent is swept while the old container still points
  at it (a use-after-free, not a leak). Edges created while the container is
  still young need no barrier at the store; the GC's promotion scan records
  them when the container is promoted. Bulk stores into a container the GC
  re-traces wholesale (a fiber's saved execution state, the root-marked
  globals/library maps) are covered by explicit root marking instead — when
  in doubt, add the barrier; it is cheap and deduplicated.

- **Root before allocating**: if you hold a pointer to a heap object and then
  allocate (which may trigger GC), root the value first with
  `gc.pushRoot(&val)` / `gc.popRoot()`. `pushRoot` is infallible — the root
  buffer grows geometrically and only panics on exceeding
  `GC.MAX_ROOT_CAPACITY` (65536), so no `try` or `catch` is needed.

- **Allocator Value arguments are auto-rooted**: `allocPair(car, cdr)` and
  other `allocXxx` functions that take Value arguments root them internally
  via `arg_roots` before `maybeCollect()`. Value slices (`allocVector`,
  `allocNativeClosure`, `allocMultipleValues`, `allocRecordInstance`,
  `makeList`) are rooted via `slice_roots`. Callers do NOT need to root
  Values that are passed directly as allocator arguments. However, Values
  held in local variables across multiple allocation calls still need
  manual rooting.

- **Allocators copy caller memory before collecting**: `allocXxx` functions
  that receive a slice (string bytes, limbs, Values) copy it into raw memory
  *before* `maybeCollect()`, so a slice that aliases another heap object's
  storage (e.g. `bignum.limbs`, `SchemeString.data`, `vec.data`) stays valid
  even if that object is collected. Preserve this order when editing them
  (#1401).

- **Root fresh results between allocations**: a Value returned by one
  allocating call is unrooted; holding it in a local while a second call
  allocates lets the collection free it — and the second allocation often
  lands in the recycled memory, silently aliasing the two (#1414 made every
  bignum/bignum division return 1 this way). Root the first result (e.g.
  `gc.rootedSlot`) before computing the second.

- **Root Function* before vm.execute()**: `execute()` allocates a closure
  wrapper internally.

- **`popRoot()` is LIFO, not per-variable**: it always removes whatever is
  currently on top of the shared root stack, not "your" root specifically.
  Pairing one `pushRoot`/`popRoot` around a value doesn't make it safe if
  *other* code pushes an unrelated root in between your push and your pop —
  a `defer gc.popRoot()` is only safe when nothing else can push to the
  same stack before the deferred call fires. Inside a loop body, or before
  any call that itself might push a root (e.g. rooting a second value
  right after), pop *immediately and explicitly* right after the specific
  allocating call you're protecting — never `defer` across a stretch of
  code that itself calls `pushRoot`. A real instance: `compiler_define_syntax.zig`
  (compiler_macro.zig at the time)
  rooted a resolved macro transformer-spec (SRFI 147) via
  `pushRoot`+`defer popRoot()` inside `compileLetSyntax`'s per-binding
  loop; the same loop iteration then pushed a second, unrelated root for
  its own result array entry *before* the deferred call fired, so the
  deferred pop silently removed the wrong (most recent) root instead,
  leaving the actual transformer object unrooted — surfaced only much
  later, in an unrelated library's macro expansion, as a baffling "invalid
  syntax" error with no apparent connection to the root cause.

Dangerous pattern:

```zig
var a = try gc.allocSomething(...);
gc.pushRoot(&a);
defer gc.popRoot();          // fires at the END of this block/iteration
const b = try gc.allocOther(...);
gc.pushRoot(&b);             // <-- pushed BEFORE the defer above fires
// ... falls through or returns here ...
// the defer now pops `b`'s root, not `a`'s
```

Safe (pop immediately, before anything else can push):

```zig
var a = try gc.allocSomething(...);
gc.pushRoot(&a);
const result = try gc.allocOther(a, ...);
gc.popRoot();                // pops `a`'s root right away, strictly nested
```

- **`vm_instance` must point at the live VM before anything allocates**: the
  GC root marker finds the globals/macros/libraries through the
  `vm_instance` threadlocal. Call `vm_mod.setVMInstance(vm)` right after
  `VM.init` — before `registerAll` — and never let a VM struct move after
  that (heap-allocate it or keep it in a stable stack frame). A stale or
  null `vm_instance` means collections sweep everything the globals
  reference (#1401).

Dangerous pattern:

```zig
const a = try gc.allocPair(x, y);
const b = try gc.allocPair(a, z);  // GC may invalidate a
```

Safe:

```zig
var a = try gc.allocPair(x, y);
gc.pushRoot(&a);
const b = try gc.allocPair(a, z);
gc.popRoot();
```

- **The pattern above still leaks its root when the protected call is the one
  that fails** — the `try` unwinds past `popRoot`, and nothing else ever
  lowers `root_count`. You do **not** need an `errdefer` for that: the
  pipeline boundaries snapshot `gc.root_count` on entry and call
  `gc.truncateRoots(depth)` when an error escapes them (#1855). The
  boundaries are the four `compileExpression*` entry points in
  `compiler.zig`, `vm_eval.eval`, and `vm_calls.execute` — between them every
  caller that keeps running after a pipeline error (REPL, `main`'s file loop,
  `kaappi check`, the LSP, `pipeline`'s stage dumps, `native_compiler`, the
  `eval`/`load` primitives, library-body compilation) is covered. Adding an
  `errdefer gc.popRoot()` per site would be ~340 edits of exactly the LIFO
  footgun above, which is why this is done once at the boundary instead.

  Two consequences worth knowing. **Never `pushRoot` expecting a caller to
  pop it across one of those boundaries** — roots do not outlive the boundary
  that saw them pushed. And truncation only ever *shrinks*: a `root_count`
  below the snapshot means an over-pop, which re-rooting cannot repair (the
  slots would point into frames that have since returned), so the boundary
  leaves it alone.

  Recovery *within* a still-running form is not covered at primitive
  granularity: a leak from a primitive whose error a Scheme `guard` catches
  stays on the stack until the enclosing `execute` returns. No primitive with
  that shape is known — the `oom_countdown` sweeps in
  `src/tests_gc_root_boundary.zig` find leaks only in the expander — but a
  new one would be a real hazard, so keep primitive error paths balanced.

- **Tag a `gc_instance`/`vm_instance` guard by what the function was going to
  return anyway** (#1874). A guard in an allocating function returns
  `OutOfMemory` — no GC means the allocation cannot happen, so that *is* its
  error. A guard in an error-message helper returns that helper's own tag
  (`typeError` → `TypeError`, `indexError` → `IndexOutOfBounds`,
  `argError` → `InvalidArgument`): losing the VM costs the detail, not the
  diagnosis. Everything else — most `vm_instance` guards — returns
  `PrimitiveError.InvalidBytecode` (→ KP9001 "internal error", i.e. "report
  this"), never `OutOfMemory` (not an allocation failure) and never a bare
  `TypeError`, which `mapNativeError` dresses up as `type error in '<proc>':
  got <args[0]>` and so blames a real argument. Full rationale in
  `docs/dev/gc-safety-and-error-handling.md`.

- **To test an OOM deep in the pipeline, use `gc.oom_countdown`**, not
  `FailingAllocator` (documented deep-pipeline limitation) and not
  `gc.memory_limit` (an absolute watermark that only trips once a form
  *retains* more than the headroom, so it fails within the first few
  allocations and never reaches the expander). Setting it to `n` lets the
  next `n` heap allocations through and fails the one after. Sweeping `n`
  over a range drives a failure at every *GC* allocation a form performs. It
  is compiled out entirely outside test binaries (`builtin.is_test`).

- **`oom_countdown` reaches only GC (`allocXxx`) allocations** — it fires
  from `maybeCollect`. Raw-allocator allocations are invisible to it: the
  VM's growable register/frame/handler/wind stacks, the fiber snapshot
  buffers, the reactor timer heap, the scheduler's `driving_waits` list,
  bignum limb scratch, and the bytecode/IR/constant pools all go straight
  through `memory.allocSliceNoFill` or an `ArrayList` over `gc.allocator`.
  For those — the fiber-scheduler OOM paths (#2429, #2433) among them — use
  `memory.OomAllocator`, a test-only wrapper with its own independent
  countdown: wrap the backing allocator, hand `allocator()` to `GC.init`, and
  arm `countdown` after construction (#2435). Also compiled out of non-test
  builds.

Stress-test with `-Dgc-stress=true` to force collection on every allocation.
In Debug builds, freed objects are poisoned with `0xAA` to catch use-after-free.
Debug and gc-stress builds additionally stamp freed headers with the
`memory.FREED_OWNER` sentinel, and gc-stress builds quarantine freed slots
across a collection — so marking a dangling value panics deterministically
with `GC: marking freed object (use-after-free)` instead of segfaulting by
luck or silently aliasing a recycled object (#1687).

Rationale and full patterns: `docs/dev/gc-safety-and-error-handling.md`.
