# Future ideas

Roughly ordered by impact. None are committed — this is a brainstorm list.

---

## 1. Run the chibi r7rs-tests.scm conformance suite

The de facto R7RS test suite (~1,225 assertions) from [chibi-scheme](https://github.com/ashinn/chibi-scheme/blob/master/tests/r7rs-tests.scm). Running it would validate the implementation against real-world expectations and surface bugs we haven't caught with our own tests.

**Steps:**
- Download `r7rs-tests.scm` and adapt the `(chibi test)` import to our test framework (or implement a minimal SRFI-64 compatible `test` library)
- Run, triage failures, fix
- Also try [ecraven/r7rs-coverage](https://github.com/ecraven/r7rs-coverage) for a comparative matrix against 14 other implementations

---

## 2. Zig FFI — call Zig from Scheme

Let Scheme programs call Zig functions directly, enabling things like:

```scheme
(import (kaappi ffi))
(define sqlite-open (ffi-load "sqlite3" "sqlite3_open"))
```

**Approach:**
- Define a `(kaappi ffi)` library with `ffi-load`, `ffi-call`, type marshaling
- Leverage Zig's `@cImport` and dynamic linking
- Start with a simple C FFI (dlopen/dlsym) and add Zig-native bindings later
- This is what makes the implementation practically useful beyond toy programs

---

## 3. Bytecode serialization (.sbc files)

Save compiled bytecode to disk so libraries don't recompile on every load.

**Design:**
- Serialize `Function` objects (code bytes, constant pool, arity, upvalue descriptors) to a binary format
- Cache in `~/.cache/kaappi/` keyed by source file hash
- Load cached bytecode on `import` if the cache is fresh
- Similar to Guile's `.go` files or Python's `.pyc`

---

## 4. Performance benchmarks

Run the [ecraven/r7rs-benchmarks](https://github.com/ecraven/r7rs-benchmarks) suite (~50 benchmarks) to measure performance against Chibi, Chicken, Gauche, Chez, etc.

**Optimization opportunities to investigate:**
- NaN-boxing (pack flonums directly in the u64 value without heap allocation)
- Inline caching for global variable lookups
- Generational or copying GC (current mark-and-sweep is simple but stop-the-world)
- Superinstruction fusion (common opcode sequences compiled to single dispatch)
- Register allocation improvements in the compiler

---

## 5. Better error messages

Add source location tracking (file, line, column) through the pipeline so errors report where they occurred.

**Current:** `Runtime error: error.UndefinedVariable`
**Goal:** `test.scm:12:5: error: undefined variable 'foo'`

**Approach:**
- Reader: annotate tokens/datums with source position
- Compiler: propagate positions into bytecode (debug info table mapping IP → source location)
- VM: look up source position when reporting errors
- Printer: format errors with file:line:col prefix

---

## 6. CI (GitHub Actions)

Automated testing on push to prevent regressions.

```yaml
# .github/workflows/test.yml
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with: { version: '0.16.0' }
      - run: zig build test
      - run: zig build run -- tests/scheme/phase1/basic.scm
```

---

## 7. R7RS-large SRFIs

Implement popular Scheme Requests for Implementation to make Kaappi useful for real programs:

| SRFI | Name | Impact |
|------|------|--------|
| SRFI-1 | List library | High — `fold`, `filter`, `partition`, `zip`, etc. |
| SRFI-9 | Record types | Already have `define-record-type` |
| SRFI-69 | Hash tables | High — missing data structure |
| SRFI-125 | Intermediate hash tables | Successor to SRFI-69 |
| SRFI-133 | Vector library | `vector-fold`, `vector-map`, etc. |
| SRFI-14 | Character sets | Useful for parsing |
| SRFI-13 | String library | `string-trim`, `string-contains`, etc. |
| SRFI-39 | Parameter objects | Already have `make-parameter` |
| SRFI-41 | Streams | Lazy list library |
| SRFI-115 | Regular expressions | Would make text processing practical |

---

## 8. Standard library in Scheme

Rewrite some built-in procedures in Scheme itself (loaded from `.sld` files at startup). This:
- Reduces the Zig primitive count
- Makes the implementation easier to extend
- Demonstrates that the library system works for real code
- Good candidates: `map`, `for-each`, `assoc`, `member`, `append`, `reverse`, CxR compositions

---

## 9. Debugger

Step-through debugging in the REPL:

```
kaappi> (debug (fib 5))
[1] (fib 5)
  n = 5
debug> step
[2] (if (< n 2) n ...)
debug> locals
  n = 5
debug> continue
=> 5
```

**Approach:**
- Add `debug` opcode or a breakpoint table
- REPL enters debug mode when a breakpoint is hit
- Commands: `step`, `next`, `continue`, `locals`, `backtrace`

---

## 10. Module cache and precompilation

```
kaappi --compile mylib.sld        # precompile to mylib.sbc
kaappi --lib-path ./lib program.scm  # use precompiled libraries
```

Combined with bytecode serialization (#3), this enables fast startup for large programs.

---

## 11. Tail call optimization for `let`

Currently, `(let ((x (f))) x)` doesn't optimize the call to `f` as a tail call because the `let` binding creates a scope. Detecting that the body is just a variable reference to the binding could enable this.

---

## 12. Bignum support

Add arbitrary-precision integers for programs that need them. Options:
- Use Zig's `std.math.big.int` if available
- Implement from scratch (array of u64 limbs)
- Automatic promotion: when fixnum overflows, promote to bignum

This would also enable exact rationals (`1/2`, `22/7`) since numerator/denominator wouldn't overflow.
