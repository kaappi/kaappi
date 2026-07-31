---
description: Audit a Kaappi primitives source file for R7RS correctness — reads the implementation, writes targeted tests, runs them, and fixes bugs found
---

# Audit Primitives for R7RS Correctness

Systematically audit one `src/primitives_*.zig` file at a time. The argument is the filename (e.g., `primitives_arithmetic.zig`).

## Workflow

### Step 1: Extract procedures

Read `src/<file>` and list every entry in its `specs` table (the single
registration point — `registerAll` walks `all_specs`, and `library.zig` derives
every export set from the same tags, so there is no second list):

```zig
.{ .name = "my-proc", .func = &myProc, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
```

Record for each: Scheme name, Zig function, arity (`.exact = N` / `.variadic = N`),
and `libs`. Note which procedures call back into the VM (`callWithArgs`, `callVM`).

**Do not skip the `%`-prefixed entries.** `.libs = primitives.INTERNAL` means
registered in `vm.globals` and exported by nothing — but still callable from a
plain top-level script with no import, and therefore still a reachable surface
that must reject bad input catchably. `INTERNAL_PUBLIC` additionally exports from
`(kaappi primitives)`. Across the tree these are the least-tested procedures
there are.

### Step 2: Identify what to test

For each procedure, check these categories against the R7RS spec:

**Correct behavior** — does it return the right value for valid inputs? Cross-reference R7RS sections 6.1–6.14.

**Type errors** — what happens when given the wrong type? Every primitive should raise a catchable error, not crash. Test with: fixnum where string expected, string where pair expected, `#f` where procedure expected, etc.

**Boundary conditions:**

- Empty inputs: `'()`, `""`, `#()`, `#u8()`, `0`
- Single-element: `'(x)`, `"a"`, `#(1)`
- Large values: bignums `(expt 2 100)`, long strings, deep lists
- Special floats: `+inf.0`, `-inf.0`, `+nan.0`, `-0.0`
- Negative indices, out-of-bounds indices
- Mixed exact/inexact, fixnum/bignum/rational/complex combinations

**Higher-order functions** — if the procedure takes a callback:

- Does error propagation work? `(guard (e (#t 'caught)) (proc (lambda (x) (error "e")) ...))`
- Are continuations handled? What if the callback invokes `call/cc`?

**Optional arguments** — if variadic, does each optional arg actually work?

**Error taxonomy** — is the *right kind* of error raised? The three helpers are
not interchangeable, and each carries a distinct code:

- `primitives.typeError(proc, expected, got)` → `TypeError`, KP3002 — wrong type
- `primitives.indexError(proc, index, len)` → `IndexOutOfBounds`, KP3006 — carries
  the offending index and the length
- `primitives.argError(proc, fmt, args)` → `InvalidArgument`, KP3007 — a value of
  acceptable type the procedure rejects anyway (e.g. a sealed parent rtd)

A bare `return PrimitiveError.TypeError` is a bug, not a shortcut: `mapNativeError`
synthesizes `type error in '<proc>': got <args[0]>`, so the message *looks*
deliberate while omitting the expected type and — when the offending value is not
the first argument — naming the wrong one. CI's `format` job rejects unannotated
bare returns. A raw `return PrimitiveError.IndexOutOfBounds` has the same defect
one level down: KP3006 with no index and no length.

**Registration-table invariants** — a pure table-vs-body check needing no runtime:
does the declared `arity` match the highest `args[N]` the body actually indexes?
Do the `libs` tags match the SRFI's own export list?

**Re-entrancy and parking** — if the procedure takes a callback, may that callback
block (channel receive, port I/O, `thread-sleep!`)? If it must not, is the
rejection catchable rather than a native-stack overflow?

**Cross-thread deep copy** — if the file introduces or returns a heap type, does it
round-trip both SRFI-18 thread boundaries, or fail cleanly with a clear error?

**Sandbox and WASM degradation** — under `--sandbox`, is the procedure gated
consistently with its siblings? Per-name gates drift.

**GC safety** — does the procedure root values before allocating? Look for patterns like:

```zig
const a = try gc.allocPair(...);
// BUG: a may be invalidated by the next allocation
const b = try gc.allocPair(a, ...);
```

### Step 3: Write the test file

Create `tests/scheme/audit/<basename>-audit.scm`:

```scheme
(import (scheme base) (scheme write) (scheme read) ...)
(import (scheme process-context) (srfi 64))

(test-begin "<basename> audit")

;;; --- procedure-name ---
(test-equal expected (procedure-name args ...))
;; Type error
(test-equal #t (guard (e (#t (error-object? e))) (procedure-name wrong-type)))
;; Boundary
(test-equal expected (procedure-name boundary-input))

(let ((runner (test-runner-current)))
  (test-end "<basename> audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
```

Grab the runner **before** `test-end` — the outermost `test-end` resets the
current runner. The `(exit 1)` epilogue is what makes `run-all.sh` notice
failures.

### Step 4: Run and diagnose

```bash
zig build run -- tests/scheme/audit/<basename>-audit.scm
```

For each failure:

1. Read the Zig source for the failing procedure
2. Identify the bug (wrong logic, missing branch, type coercion error)
3. Fix the source
4. Re-run the audit test
5. Run `bash tests/scheme/run-all.sh` to verify no regressions

### Step 5: Report

Summarize: how many procedures audited, tests written, bugs found, bugs fixed.

## Common Bug Patterns

These patterns were found during coverage testing and are likely to recur:

### 1. Thunk not called

Functions accepting an optional callback that return the procedure object instead of calling it:

```zig
// BUG: returns the thunk instead of calling it
if (args.len > 2) return args[2];
// FIX: call it
if (types.isProcedure(args[2])) return vm.callWithArgs(args[2], &[_]Value{});
```

### 2. Missing overwrite semantics

Merge/update operations that skip existing entries instead of overwriting:

```zig
// BUG: skips existing keys
if (findKey(ht, key) == null) { ... }
// FIX: overwrite if found
if (findKey(ht, key)) |idx| { entries[idx].value = new_val; } else { ... }
```

### 3. Truncation instead of exact conversion

Numeric operations that truncate floats where exact conversion is needed:

```zig
// BUG: #e1.5 becomes 1
.fixnum = @intFromFloat(f)
// FIX: convert to rational via continued fraction
```

### 4. Ignored optional arguments

Variadic functions that accept but never inspect extra arguments:

```zig
// BUG: trim ignores predicate
while (isWhitespace(data[start])) ...
// FIX: call predicate if provided
if (args.len > 1) { ... call pred ... } else { isWhitespace(...) }
```

### 5. Resource leaks

Heap allocations in primitives or VM without corresponding cleanup:

```zig
// BUG: allocated but never freed
const sched = allocator.create(Scheduler);
vm.scheduler = sched;
// FIX: free in VM.deinit()
if (self.scheduler) |s| { allocator.destroy(s); }
```

### 6. Missing type dispatch

Arithmetic/comparison functions that handle fixnum and flonum but miss bignum, rational, or complex:

```zig
// BUG: (even? (expt 2 100)) → TypeError
if (types.isFixnum(args[0])) { ... }
if (types.isFlonum(args[0])) { ... }
return PrimitiveError.TypeError; // misses bignum!
```

## File Reference

31 files. The table in `CLAUDE.md § Primitives (split into 31 files)` is the
authoritative list of what each one covers; don't duplicate it here, it drifts.
What matters for auditing is which files have an audit test:

**Has an audit test** (`tests/scheme/audit/<basename>-audit.scm`) — 21 files:
arithmetic, bytevector, char, control, core (`primitives.zig`), cxr, ffi, fiber,
filesystem, hashtable, io, lazy, list, numeric, r7rs, random, srfi1, srfi18,
string, string_ext, vector.

**No audit test** — 10 files, all of which postdate the v1 campaign:
`primitives_srfi160.zig`, `srfi181.zig`, `srfi211.zig`, `srfi237.zig`,
`srfi254.zig`, `srfi258.zig`, `srfi260.zig`, `parallel.zig`,
`random_port.zig`, `sysinfo.zig`.

Having an audit test is not the same as being covered: several date from
2026-07-05 and have not grown with their file. `primitives_io.zig` gained ~1,100
lines against a 112-line audit test; `primitives_fiber.zig` gained ~1,240 against
135 lines.

## Audit Priority

Two orderings, depending on why you're here.

**Filling gaps** — the 10 files with no audit test, hardest first:
`srfi237` (inheritance, sealed/opaque), `srfi160` (11-way element-kind dispatch
over raw bytes), `srfi181` (custom-port callback re-entrancy), `srfi254`
(GC-integrated weak refs), then the small batch (`parallel`, `sysinfo`,
`random_port`, `srfi258`, `srfi260`, `srfi211`).

**Re-auditing** — files whose growth has outrun their test, by churn:
`io`, `fiber`, `srfi18`, `vector`, `hashtable`, `filesystem`.

Cross-cutting and higher-yield per minute than any single file: the
`%`-prefixed internal-primitive surface (Step 1), which spans every file and has
close to zero test mention.

## During an audit campaign

`docs/audit-strategy.md` may be running a campaign that **overrides Step 4**:
file GitHub issues instead of fixing in place, so discovery stays separate from
fixing. Check that document's status line before you start fixing anything.
