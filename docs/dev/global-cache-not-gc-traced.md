# `Function.global_cache` Is Not Traced by the GC

## Status

**Fixed.** global_cache traced in markValue. global_version bumped in all globals.put sites. Noticed during
the GC reachability investigation (2026-06-17).

## The observation

`markValue` traces a `Function`'s constant pool but **not** its `global_cache`:

```zig
// src/memory.zig — markValue
.function => {
    const func = obj.as(Function);
    for (func.constants.items) |c| {
        self.markValue(c);
    }
    // func.global_cache is NOT visited
},
```

`global_cache` is a lazily-allocated `[]Value` (sized to `constants.items.len`)
that memoizes global-variable lookups for the `get_global`, `call_global`, and
`tail_call_global` opcodes. It stores resolved **closures and native functions**
(only those — the opcodes cache a value only when `isClosure` or `isNativeFn`).
It is freed in `freeObject` for `.function`, but never marked.

## Why it is safe today

A cached entry is only *used* when the per-function `cache_version` matches the
VM's `global_version`:

```zig
if (func.cache_version == self.global_version and
    sym_idx < cache.len and cache[sym_idx] != types.VOID) { … use cache … }
```

`set_global` bumps `global_version` on every store (`src/vm.zig:607`). So a cache
*hit* implies no `set_global` has happened since the entry was cached, which
implies the global still holds that value — and the live globals table **is**
traced (`markVMRoots` iterates `vm.globals`). Therefore, on any path where the
cache is actually read, the cached object is independently reachable through
`vm.globals` and gets marked. A *stale* pointer can sit in the cache array after
a value changes, but it is never dereferenced (the version check fails first and
the entry is cleared with `@memset`). Hence: not traced, but not a dangling read.

## Why it is fragile

The argument above depends entirely on **every global mutation bumping
`global_version`**. That is not the case. Only `set_global` bumps it; these
other `globals.put` sites do **not**:

- `VM.defineGlobal` (`src/vm.zig:200`)
- `define-values` execution (`src/vm_eval.zig:72`, `:80`)
- `define-record-type` internals (`src/vm_records.zig:101`, `:148`)
- library import binding (`src/vm_library.zig:19`)

Today these are effectively initial-definition paths that run before a binding is
read and cached, so the window is not hit in practice. But the invariant is
implicit and unguarded. If any of these (or future code) ever **replaces** a
binding that has already been cached, without bumping `global_version`, then:

1. A subsequent `get_global`/`call_global` would see a version match and return
   the **old** cached value (a stale-value correctness bug), and
2. if the old value is no longer reachable through `vm.globals` (it was
   replaced) and nothing else references it, the GC would **free it** (the cache
   is not traced), leaving the cache holding a dangling pointer → use-after-free
   on the next cache hit.

So this is one missing-`+%= 1` away from a real UAF, and the GC tracing is the
only thing that would make it robust independent of that discipline.

## Recommended fix

Cheapest and most robust: **trace `global_cache` in `markValue`**:

```zig
.function => {
    const func = obj.as(Function);
    for (func.constants.items) |c| self.markValue(c);
    if (func.global_cache) |cache| {
        for (cache) |c| self.markValue(c);
    }
},
```

Cached entries are always either `VOID` (ignored by `markValue` — it is an
immediate) or a closure/native fn, so this is safe and O(constants). It removes
the GC-safety dependency on the version-bump discipline entirely.

Separately (and optionally), the stale-*value* concern is its own bug: every code
path that reassigns an existing global should bump `global_version`, or those
`globals.put` sites should route through a single helper that does. That is a
correctness fix orthogonal to GC tracing.

## Cross-references

- Found during the GC reachability work — see
  [gc-reachability-bug.md](gc-reachability-bug.md).
