# GC Safety and Error Handling

Patterns contributors must follow to keep the runtime correct under
garbage collection pressure and to propagate errors consistently.

The terse checklist version of the GC rules lives in
`.claude/rules/gc-safety.md` (auto-loaded by the Claude Code harness when
editing GC-sensitive files). This document is the rationale behind those
rules — keep the two in sync.

---

## GC Safety

The garbage collector is generational (young and old generations, minor
and full collections) with mark-and-sweep at its core. It scans a root
set (VM registers, the root stack, globals, macros) and frees any heap
object not reachable from a root. GC can trigger during **any** `alloc*`
call in `memory.zig`.

### The dangerous pattern

```zig
// BAD — val1 is unrooted when allocPair triggers GC
const val1 = try gc.allocString("hello");
const pair = try gc.allocPair(val1, types.NIL);  // GC may free val1
```

Between `allocString` returning and `allocPair` storing `val1` as the
car, GC can run. Since `val1` is only on the Zig stack (which GC does
not scan), it looks unreachable and gets freed.

### The safe pattern

```zig
var val1 = try gc.allocString("hello");
gc.pushRoot(&val1);
defer gc.popRoot();
const pair = try gc.allocPair(val1, types.NIL);  // val1 is protected
```

`pushRoot` adds the address of `val1` to the GC's root stack. If GC
runs during `allocPair`, it finds `val1` through the root stack and
keeps it alive.

### Rules

1. **Root any heap Value that must survive another allocation.** If you
   call two `alloc*` functions and the first result is used by or after
   the second, root it.

2. **Pair `pushRoot` with `defer popRoot()` where the whole scope is
   `pushRoot`-free.** `popRoot` removes whatever is on top of the shared
   stack, not "your" entry, so a deferred pop is only correct when nothing
   between the push and the deferred call can push its own root. Inside a
   loop body, or right before rooting a second value, pop explicitly
   immediately after the specific call being protected instead. See the
   `compileLetSyntax` incident in `.claude/rules/gc-safety.md`.

3. **Root the accumulator in loops.** When building a list or vector
   via repeated `allocPair`/`allocVector`, root the accumulating result:

   ```zig
   var result: Value = types.NIL;
   gc.pushRoot(&result);
   defer gc.popRoot();
   for (items) |item| {
       result = try gc.allocPair(item, result);
   }
   ```

4. **Don't store unrooted Values in ArrayLists.** If you collect heap
   Values in an `ArrayList(Value)` across allocations, those Values are
   not in the root set. Either collect non-heap data (indices, offsets)
   and allocate during the rooted build phase, or use `gc.extra_roots`
   (see `readVector` in `reader_datum.zig` for the pattern).

5. **Symbols are safe.** Interned symbols live in `gc.symbols` and are
   always reachable — no rooting needed.

6. **Fixnums, booleans, characters, nil, void are safe.** These are
   immediates (encoded in the NaN-boxed u64), not heap objects.

7. **Root `Function*` before `vm.execute()`.** `execute()` allocates a
   closure wrapper internally, so an unrooted Function can be collected
   out from under the call.

### The write barrier

Because the collector is generational, minor collections scan only the
young generation plus a remembered set of old objects that point into
it. Mutating a field of a heap object (set-car!, set-cdr!, vector-set!,
hash-table-set!, record field mutation) can create an old→young
reference the minor collection would otherwise never see — the young
object would be freed while still reachable.

After storing a Value into a heap object field, call:

```zig
gc.writeBarrier(container, new_val);
```

where `container` is the heap object being mutated. The barrier records
the old→young edge in the remembered set. Omitting it does not fail
immediately — it corrupts the heap only when a minor collection happens
to run before the next full collection, which is why these bugs surface
as rare, allocation-pattern-sensitive crashes.

### Stress testing

Build with `-Dgc-threshold=1` to force a collection on every allocation.
This turns "rare, timing-dependent" rooting and barrier bugs into
deterministic failures. Every new allocation pattern in a loop should
also get a stress test — see `tests/scheme/smoke/gc-rooting-stress.scm`.

`-Dgc-stress=true` builds go further and make marking-time use-after-free
itself deterministic (#1687). Freeing an object stamps its header with the
reserved `memory.FREED_OWNER` owner id (in Debug builds too, after the
`0xAA` poison), and the freed slot is held in a per-GC quarantine —
released oldest-first, only past `GC.quarantine_max_bytes`, and only
between a later collection's mark and sweep phases. A dangling value that
reaches the mark phase then panics with
`GC: marking freed object (use-after-free)` rather than being skipped as a
foreign-owned object (the poisoned owner byte never matches the marking
GC's id) or silently aliasing a live object recycled into the same slot —
the two escape modes that let the #1682 dangling-local bug survive twelve
nightly stress runs. Release builds compile out both the stamp/check and
the quarantine.

### Unwinding the root stack on error (#1855)

Rooting around a fallible call has a hole the rules above cannot close:

```zig
var a = try gc.allocSomething(...);
gc.pushRoot(&a);
const result = try gc.allocOther(a, ...);  // if THIS fails...
gc.popRoot();                              // ...this never runs
```

When the protected call is the one that fails, the error unwinds past the
`popRoot`. `root_count` is only ever moved by `pushRoot`/`popRoot`, so
nothing put it back: the root stack was left holding the address of a local
in a frame that no longer exists, and the next collection dereferences it.
Under NaN-boxing that usually reads as a garbage flonum (harmless by luck)
and occasionally as a plausible heap pointer (UB). Worse, the extra entry
shifts the whole stack, so every `defer popRoot()` still to fire on the way
out removes the wrong entry.

Switching to `errdefer` at each of the ~340 push sites is not the fix — a
`defer`/`errdefer` near a loop is the LIFO footgun of rule 2, so the cure
reintroduces the disease. Instead the **pipeline boundaries** snapshot
`gc.root_count` on entry and call `gc.truncateRoots(depth)` when an error
escapes:

| Boundary | Covers |
|----------|--------|
| `compileExpression`, `compileExpressionWithMacrosAt`, `compileExpressionInEnv`, `compileProgram` (`compiler.zig`) | Reader, expander, IR and bytecode emission — for every caller: REPL, `main`'s file loop, `kaappi check`, the LSP, `pipeline`'s stage dumps, `native_compiler`, the `eval`/`load` primitives, library-body compilation |
| `vm_eval.eval` | The top-level-only handlers that bypass the compiler (`import`, `define-library`, `define-record-type`, …) and the reader |
| `vm_calls.execute` | The running program. Truncated inside the error branch, *before* it runs pending `dynamic-wind` after-thunks — those allocate, so a leaked root would otherwise still be live when they collect |

Two invariants follow. Roots never outlive the boundary that saw them
pushed, so nothing may `pushRoot` expecting a caller across a boundary to
pop it. And truncation only ever shrinks: a depth *below* the snapshot is an
over-pop, which re-rooting cannot repair — the resurrected slots may already
belong to a returned frame — so the boundary leaves it alone.

What is deliberately not covered: recovery *within* a running form. A root
leaked by a primitive whose error a Scheme `guard` catches survives until
the enclosing `execute` returns, because snapshotting per native call would
put a load on the interpreter's hottest path for a hazard no primitive
currently has. The sweeps in `src/tests_gc_root_boundary.zig` find leaks
only in the expander; keep primitive error paths balanced so that stays
true.

To reproduce a failure this deep, use `gc.oom_countdown` — `n` allocations
succeed, the next fails. Sweeping `n` walks the failure across every
allocation a form performs. `FailingAllocator` cannot reach these sites, and
`gc.memory_limit` is an absolute watermark that only trips once a form
*retains* more than the headroom, so it fails in the first few allocations
and never reaches the expander. `oom_countdown` is compiled out entirely
outside test binaries (`builtin.is_test`).

### Raw-allocator ownership is still local (#1864)

The boundary reset above unwinds the **GC root stack** and nothing else. A
struct taken from `gc.allocator` is owned by whichever field is eventually
assigned it, so every fallible step between the `create` and that assignment
still needs its own local `errdefer`:

```zig
const sched = vm.gc.allocator.create(FiberScheduler) catch return VMError.OutOfMemory;
sched.* = FiberScheduler.init(vm);
errdefer {                       // nothing owns `sched` until vm.scheduler is set
    sched.deinit(vm.gc.allocator);
    vm.gc.allocator.destroy(sched);
}
```

`fiber.ensureScheduler` was missing exactly this: an OOM in the main fiber's
`allocFiber` or in `addFiber` returned with the scheduler neither destroyed
nor stored, leaking both the struct and the managed `waiter_index` map inside
it. This is not the LIFO footgun of rule 2 — an `errdefer` that undoes a
*specific* allocation it names is always safe; only the shared, positional
root stack makes `defer popRoot()` order-dependent.

Note the scoping: an `errdefer` inside a block is discarded when that block
exits normally, so the one above cannot fire for a later failure in the
reactor block that follows it — which matters, because by then `vm.scheduler`
owns the pointer and freeing it would be a double free.

### Where to look

The `reverse` function in `primitives.zig` is a clean reference
implementation. The `readVector` function in `reader_datum.zig` shows
the `extra_roots` pattern for dynamic-length collections.

---

## Error Handling

### Error type hierarchy

Primitives return `PrimitiveError!Value`. The VM translates these to
`VMError` at dispatch boundaries. The mapping:

| PrimitiveError | VMError | When |
|---------------|---------|------|
| `TypeError` | `TypeError` | Wrong argument type |
| `DivisionByZero` | `DivisionByZero` | Division or modulo by zero |
| `IndexOutOfBounds` | `IndexOutOfBounds` | Vector/string index out of range |
| `InvalidArgument` | `InvalidArgument` | Semantically invalid argument value |
| `OutOfMemory` | `OutOfMemory` | Allocation failed |
| `ExceptionRaised` | `ExceptionRaised` | Scheme `raise` was called |
| `ContinuationInvoked` | `ContinuationInvoked` | `call/cc` continuation was invoked |
| `Yielded` | `Yielded` | Fiber yielded |
| `ArityMismatch` | `ArityMismatch` | Wrong argument count (checked before dispatch) |

### Rules

1. **Use the specific error variant.** Don't return `TypeError` for an
   index out of bounds — return `IndexOutOfBounds`. The dispatch layer
   generates better error messages when it knows the actual error type.

2. **Set error detail before returning.** Use
   `vm.setErrorDetail("proc-name: message", .{args})` or the
   `primitives.typeError("proc-name", "expected-type", got)` helper.
   If no detail is set, the dispatch layer generates a generic message.

3. **All dispatch error switches must cover all 8 variants.** When
   catching `PrimitiveError` in `vm_dispatch.zig`, always handle:
   `TypeError`, `DivisionByZero`, `IndexOutOfBounds`,
   `InvalidArgument`, `OutOfMemory`, `ExceptionRaised`,
   `ContinuationInvoked`, `Yielded`. Use `callNative` in
   `vm_calls.zig` as the reference.

4. **Don't use `catch {}` for correctness-relevant operations.** If an
   OOM during `hashmap.put` means a binding is silently lost, propagate
   with `catch return error.OutOfMemory`. Reserve `catch {}` for:
   - Port cleanup (`closePort` in `with-*` patterns)
   - Debug info (source line tracking, line tables)
   - Error-path recovery where the primary error takes precedence

### Sandbox enforcement

Sandbox restrictions operate at two levels:

1. **Registration level** — `primitives.registerSandboxed()` omits
   dangerous procedure registrations (FFI, filesystem, threads). The
   library registry omits `(kaappi ffi)`, `(scheme file)`, etc.

2. **Defense-in-depth** — Individual procedures also check
   `vm.sandbox_mode` as a belt-and-suspenders guard. See
   `checkSandbox` in `primitives_ffi.zig`.

When adding a new procedure that accesses the filesystem, network, or
native code, add it to both layers.

---

## Testing

Every bug fix must include a regression test. Every new allocation
pattern in a loop should have a stress test that exercises GC pressure.
See `tests/scheme/smoke/gc-rooting-stress.scm` for the pattern.
