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
  `gc.pushRoot(&val)` / `gc.popRoot()`.

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

Stress-test with `-Dgc-threshold=1` to force collection on every allocation.
