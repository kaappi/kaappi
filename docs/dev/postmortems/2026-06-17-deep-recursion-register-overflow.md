# Deep-Recursion Register-File Overflow

## Status

**Fixed** (two phases). Phase 1 (2026-06-17): bounds checks added at all three
re-entrant call sites; adaptive stride (locals_count+2, min 16) replaces flat
+200, allowing ~60 re-entrant levels. Phase 2 (#593, 2026-06-30): frame and
register arrays made growable (heap-allocated slices, double-on-overflow), fully
eliminating the fixed-capacity limit. The VM now supports thousands of nested
non-tail-recursive frames, bounded only by available memory (hard caps: 32768
frames, 65536 registers).

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

The VM uses a single **flat register file** shared by all call frames (now
heap-allocated and growable; originally fixed-size):

```zig
// src/vm.zig (original constants, now replaced by growable slices)
pub const INITIAL_FRAME_CAPACITY    = 480;   // grows to MAX_FRAME_LIMIT (32768)
pub const INITIAL_REGISTER_CAPACITY = 2048;  // grows to MAX_REGISTER_LIMIT (65536)
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
   const base: u32 = if (self.frame_count > 0)
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

## Fixes applied

1. **Bounds-check the register window.** Before writing args / pushing a frame in
   `callWithArgs`, `callClosure`, and `callValue`, the register window is
   validated. This converts overflows into clean, catchable `StackOverflow` errors.
2. **Adaptive stride.** The flat `+200` was replaced with the caller's actual
   high-water register use (`locals_count + 2`, min 16) so re-entrant frames pack
   tighter.
3. **Growable register file (#593).** Both `frames` and `registers` are now
   heap-allocated slices that double on overflow (initial 480/2048, caps at
   32768/65536). `ensureFrameCapacity` and `ensureRegisterCapacity` on the VM
   handle growth at all frame push sites.
4. **Widened `CallFrame.base` from u16 to u32 (#593).** The u16 field overflowed
   at ~20,000 non-tail frames, causing a Zig panic instead of a clean
   `StackOverflow`. The u32 field supports up to 4 billion register indices.
   `dst` stays u16 (per-frame offset, bounded by `locals_count`).

## Cross-references

- Surfaced alongside the GC reachability fix — see
  [2026-06-17-gc-reachability-bug.md](2026-06-17-gc-reachability-bug.md) ("Unrelated pre-existing
  crashes").
- The other suite crash found at the same time was the unrelated `string-copy!`
  `@memcpy` aliasing panic (since fixed).
