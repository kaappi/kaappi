---
description: Audit a Kaappi primitives source file for R7RS correctness — reads the implementation, writes targeted tests, runs them, and fixes bugs found
---

# Audit Primitives for R7RS Correctness

Systematically audit one `src/primitives_*.zig` file at a time. The argument is the filename (e.g., `primitives_arithmetic.zig`).

## Workflow

### Step 1: Extract procedures

Read `src/<file>` and list every procedure registered with `try reg(vm, ...)`:
- Scheme name, Zig function name, arity (exact N or variadic N)
- Note which procedures call back into the VM (use `callWithArgs`, `callVM`)

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
(import (chibi test))

(test-begin "<basename> audit")

;;; --- procedure-name ---
(test expected (procedure-name args ...))
;; Type error
(test #t (guard (e (#t (error-object? e))) (procedure-name wrong-type)))
;; Boundary
(test expected (procedure-name boundary-input))

(test-end "<basename> audit")
```

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

| File | Procedures | Domain |
|------|-----------|--------|
| `primitives_arithmetic.zig` | +, -, *, /, comparisons, trig, complex | Arithmetic |
| `primitives_numeric.zig` | rounding, exactness, conversion | Numeric |
| `primitives_string.zig` | string ops, mutation, higher-order | Strings |
| `primitives_io.zig` | ports, file I/O, read/write | I/O |
| `primitives_control.zig` | raise, guard, call/cc, dynamic-wind | Control |
| `primitives_hashtable.zig` | SRFI-69 hash tables | Hash tables |
| `primitives_string_ext.zig` | SRFI-13 string library | Strings ext |
| `primitives_vector.zig` | vectors, SRFI-133 | Vectors |
| `primitives_bytevector.zig` | bytevectors, binary I/O | Bytevectors |
| `primitives_list.zig` | list operations | Lists |
| `primitives_char.zig` | char classification, case | Characters |
| `primitives_r7rs.zig` | eval, load, parameters, time | R7RS misc |
| `primitives_srfi1.zig` | SRFI-1 list library | Lists ext |
| `primitives_srfi18.zig` | SRFI-18 threads | Threads |
| `primitives_random.zig` | SRFI-27 random | Random |
| `primitives_filesystem.zig` | SRFI-170 filesystem | Filesystem |
| `primitives_lazy.zig` | delay, force, promises | Lazy |
| `primitives_ffi.zig` | C FFI | FFI |

## Audit Priority

Start with files that have the highest bug density risk (complex type dispatch, many optional args):
1. `primitives_arithmetic.zig` — most complex type dispatch
2. `primitives_numeric.zig` — exact/inexact conversion edge cases
3. `primitives_string.zig` — UTF-8 + mutation
4. `primitives_io.zig` — error propagation in callbacks
5. Then proceed through the rest in any order
