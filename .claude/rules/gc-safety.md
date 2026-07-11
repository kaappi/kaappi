---
globs: ["src/primitives_*.zig", "src/memory.zig", "src/vm*.zig"]
description: GC safety requirements for heap-mutating code
---

# GC Safety Rules

When mutating heap objects (set-car!, set-cdr!, vector-set!, hash-table-set!,
string-set!, record field mutation):

- **Write barrier required**: call `gc.writeBarrier(container, new_val)` after
  storing a Value into a heap object field. Omitting this corrupts the
  generational GC during minor collections.

- **Root before allocating**: if you hold a pointer to a heap object and then
  allocate (which may trigger GC), root the value first with
  `gc.pushRoot(&val)` / `gc.popRoot()`. `pushRoot` is infallible (panics on
  overflow at 1024 slots) — no `try` or `catch` needed.

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

Stress-test with `-Dgc-stress=true` to force collection on every allocation.
In Debug builds, freed objects are poisoned with `0xAA` to catch use-after-free.

Rationale and full patterns: `docs/dev/gc-safety-and-error-handling.md`.
