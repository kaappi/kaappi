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
  via `arg_roots` before `maybeCollect()`. Callers do NOT need to root Values
  that are passed directly as allocator arguments. However, Values held in
  local variables across multiple allocation calls still need manual rooting.

- **Root Function* before vm.execute()**: `execute()` allocates a closure
  wrapper internally.

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
