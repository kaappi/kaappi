# GC Reachability Bug: Immutable String Literals Freed During Execution

## Status

**Resolved.** Root cause found and fixed; the immutable-string sweep workaround
has been removed. The strings were never the problem with marking — they were
being freed by the GC *before* they reached a constant pool, because the
**reader and compiler held the source datum in unrooted locals across
allocations that can trigger a collection**.

## Symptoms

String literals displayed as `0xAA 0xAA` (DebugAllocator's freed-memory poison)
instead of their actual content. Occurred under heavy allocation pressure (e.g.
35+ file reads in `scripts/large-files.scm`). Deterministic for a given build,
but sensitive to exact allocation counts (a "heisenbug": adding/removing a few
lines anywhere shifts GC timing and makes it appear/disappear).

## Reproduction

```bash
zig build run -- scripts/large-files.scm
```

Output before the fix:
```
   1243██src/vm.zig    ##############################
```
The `██` are bytes `0xAA 0xAA` — the literal `"  "` (two spaces) freed by GC and
its data buffer overwritten by the poison pattern.

## How it was diagnosed

1. **Amplified the bug deterministically.** The original symptom depended on
   exact allocation counts. Temporarily forcing a full collection on *every*
   allocation (`maybeCollect` → always `collect()`) made the corruption fire
   reliably regardless of workload — the technique suggested as item #4 in the
   original investigation.

2. **Instrumented the sweep.** After marking but before sweeping, the diagnostic
   walked the heap for unmarked `immutable` strings and reported what held them.
   The decisive finding contradicted the original hypothesis: the freed `"  "`
   strings were **not in any function constant pool** — they were held by an
   **unmarked pair**, i.e. they were still part of the in-flight source datum,
   not yet compiled.

3. **Followed the datum upstream.** That pointed at two unrooted windows:
   - **Reader.** In `readList`/`readListTail`/`readAbbreviation`, the list *tail*
     (`rest`) was passed to `allocPair(car, rest)` while unrooted. `allocPair`
     runs `maybeCollect()` *before* allocating, so a collection there could free
     the tail (its pairs **and** their string elements). `readVector` had the
     same flaw: elements already read sat in an unrooted `ArrayList` while later
     elements were read.
   - **Compiler.** `Compiler.compile(expr)` walked `expr` without rooting it. The
     compiler roots its in-progress `Function` (via `extra_roots`), so a literal
     was safe *once `addConstant` stored it* — but the expander and derived-form
     compilers allocate while walking earlier parts of the form, and any
     collection then freed the not-yet-compiled tail of `expr`, leaving the
     compiler to store a dangling string pointer in the constant pool. The
     macro-expansion path (`compileExpr(expanded, …)`) had the same gap for the
     freshly allocated expanded form.

This is why only **reader-created (immutable) strings** were affected, why they
were always in list **tails**, and why it only happened under allocation
pressure (a GC had to fire *during* a read or compile).

## Fix

Root the in-flight data across the allocations that can collect:

- `reader_datum.zig`: root `rest` before each terminal `allocPair` in
  `readList`, `readListTail`, and `readAbbreviation`; mirror `readVector`
  elements into the GC's by-value `extra_roots` while accumulating (rooting
  `&elems.items[i]` would be unsafe — the `ArrayList` can realloc).
- `compiler.zig`: root the source `expr` for the duration of `compile()`, root
  the expanded form across the macro-expansion `compileExpr` call, and root all
  `exprs` across `compileMultiple()`.
- `memory.zig`: removed the immutable-string sweep workaround.

## Related bug found and fixed (same class)

`runFile` collects every top-level `*Function` into a plain `ArrayList`
(`compiled_funcs`) to write the `.sbc` bytecode cache at the end. That list is
not a GC root, and each function is removed from `extra_roots` after its own
compile and `popRoot`'d after its own `execute` — so a collection triggered
while executing a *later* top-level form could free an earlier function. The
cache writer (`bytecode_file.collectNestedFunctions`) then walked freed memory
and segfaulted (`0xaaaaaaaaaaaaaaaa`). This affected import-free scripts (the
cache is skipped when imports are present), e.g. `tests/scheme/compliance/lists.scm`.
Fixed by rooting each collected function in `extra_roots` for the rest of the run.

## Verification

- `zig build test` passes.
- `scripts/large-files.scm` renders correctly with the workaround removed.
- With GC forced on every allocation, the freed-string diagnostic reports zero
  live strings freed; with an aggressive fixed threshold the entire
  `tests/scheme` suite (41 files) runs crash-free.

## Unrelated pre-existing crashes (not GC; out of scope)

Surfaced while sweeping the test suite; confirmed identical on the pre-fix
commit, so not introduced here:

- `string-copy!` calls `@memcpy` with overlapping source/destination
  (`primitives_string.zig` `stringCopyBangFn`) — panics on aliasing input
  (`tests/scheme/r7rs-tests.scm`).
- Deep `force`/promise recursion overflows the fixed 1024-entry frame/register
  arrays (`index out of bounds: index 1201, len 1024`) in
  `tests/scheme/r7rs/{combined-tests,r7rs-tests}.scm`.
