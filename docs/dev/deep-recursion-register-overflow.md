# Deep-Recursion Register-File Overflow

## Status

**Fixed.** Bounds checks added at all three re-entrant call sites. Adaptive stride (locals_count+2, min 16) replaces flat +200, allowing ~60 re-entrant levels. Found while sweeping the test suite during the GC
reachability investigation (2026-06-17); confirmed identical on the pre-fix
commit, so not introduced by that work.

## Symptom

A hard Zig panic instead of a catchable Scheme error:

```
thread … panic: index out of bounds: index 1201, len 1024
```

Reproducers:
```bash
zig build run -- tests/scheme/r7rs/combined-tests.scm
zig build run -- tests/scheme/r7rs/r7rs-tests.scm
```

Both crash partway through (exit 134). The crashing frame is in `runUntil`,
reached via `callWithArgs` ← `forceFn` (`src/primitives_lazy.zig:55`) — i.e. a
deeply recursive chain of `force` / promise streams.

## Root cause

The VM uses a single **flat, fixed register file** shared by all call frames:

```zig
// src/vm.zig
pub const MAX_FRAMES    = 256;
pub const MAX_REGISTERS = 1024;   // registers: [MAX_REGISTERS]Value
```

Each call frame occupies a slice of that one array starting at its `base`. There
are two ways a frame's `base` is chosen, and they behave very differently:

1. **Normal bytecode calls** (`call` / `tail_call` opcodes → `callValue` →
   `callClosure`, `src/vm.zig:1102`): the new frame's base is `base + 1`, where
   `base = frame.base + base_reg` and `base_reg` is a **compiler-assigned**
   register offset for the call site. The window grows by the caller's actual
   register pressure per non-tail level — usually small, and tail calls reuse the
   window, so this rarely overflows in practice.

2. **Re-entrant native → Scheme calls** (`callWithArgs`, `src/vm.zig:366`, and
   the `callValue`/`callClosure` native path, lines ~245, ~317, ~397): the new
   frame's base is a **flat `prev.base + 200`**:

   ```zig
   const base: u16 = if (self.frame_count > 0)
       self.frames[self.frame_count - 1].base + 200
   else
       0;
   ```

   This stride is used whenever a *native* procedure calls back into Scheme,
   because there is no compiler-arranged argument window to reuse.

With a flat +200 stride and a 1024-slot file, only **~5–6 re-entrant levels** fit
(bases 0, 200, 400, 600, 800, 1000, 1200). At the 6th re-entry `base = 1200`,
already past the array end; the thunk's first register write lands at
`registers[1200 + dst]` → `index 1201, len 1024`.

Crucially, **the only overflow guard is on frame count**:

```zig
if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow; // 256
```

There is **no bounds check on `base + reg` against `MAX_REGISTERS`**. Because the
register file (1024) is exhausted long before the frame count (256) in the
re-entrant path, the clean `StackOverflow` error is never returned — the program
indexes out of bounds instead.

## What triggers it

Any deep recursion that re-enters the VM through a native procedure, e.g.:

- `force` of a deeply nested / self-referential promise or lazy stream
  (`primitives_lazy.zig` `forceFn` → `callWithArgs`) — the observed reproducer.
- Potentially `map` / `for-each` / `apply` / `string-for-each` / sort comparators
  / `dynamic-wind` thunks when they recurse deeply, since each re-enters via the
  +200 path.

Ordinary tail-recursive Scheme loops are unaffected (they reuse one window).
Ordinary non-tail Scheme recursion grows the window only by the compiler-assigned
offset, so it tolerates much greater depth before (also unbounded) overflow.

## Impact

- **ReleaseSafe / Debug:** hard panic + abort (`index out of bounds`). The error
  is *not* catchable by Scheme `guard` / exception handlers — it kills the process.
- **ReleaseFast (safety off):** worse — the out-of-bounds writes land in memory
  adjacent to the `registers` array inside the `VM` struct (`frames`,
  `handler_stack`, counters, …), i.e. silent memory corruption / UB.

## Possible fixes (not yet chosen)

1. **Bounds-check the register window (minimal, highest value).** Before writing
   args / pushing a frame in `callWithArgs`, `callClosure`, and `callValue`,
   verify `base + window <= MAX_REGISTERS` and return `VMError.StackOverflow`
   otherwise. This converts the crash into a clean, catchable Scheme error and
   closes the ReleaseFast corruption hole. `window` can be `func.locals_count`
   (or a safe bound when unknown).
2. **Shrink / make the stride adaptive.** Replace the flat `+200` with the
   caller's actual high-water register use (`locals_count`) so re-entrant frames
   pack tighter and tolerate deeper recursion. Combine with (1).
3. **Grow the budget.** Increase `MAX_REGISTERS`, and/or make the register file a
   growable allocation. Larger ceiling, but still needs (1) to fail gracefully.

Recommended: (1) now for safety, then (2) to raise the practical depth limit.

## Cross-references

- Surfaced alongside the GC reachability fix — see
  [gc-reachability-bug.md](gc-reachability-bug.md) ("Unrelated pre-existing
  crashes").
- The other suite crash found at the same time was the unrelated `string-copy!`
  `@memcpy` aliasing panic (since fixed).
