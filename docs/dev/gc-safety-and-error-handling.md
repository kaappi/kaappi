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
try gc.pushRoot(&val1);
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

2. **Always pair `pushRoot` with `defer popRoot()`.** This ensures
   balanced rooting even on error returns.

3. **Root the accumulator in loops.** When building a list or vector
   via repeated `allocPair`/`allocVector`, root the accumulating result:
   ```zig
   var result: Value = types.NIL;
   try gc.pushRoot(&result);
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
