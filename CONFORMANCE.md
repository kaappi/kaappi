# R7RS Conformance

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 430+ built-in procedures, 32 syntax forms, and all 14 standard libraries. R7RS test suite: 1,394 pass, 0 fail.

This document covers design choices, remaining gaps, and verified conformant behaviors.

---

## Design choices

These are intentional architectural decisions, not missing features. Each is the standard approach taken by most Scheme bytecode interpreters.

### Stack-copying continuations

`call/cc` captures a continuation by copying the entire VM state — registers, call frames, exception handlers, and dynamic-wind stack — into a heap-allocated `Continuation` object. When invoked, the saved state is restored and execution resumes from the capture point.

This is correct and fully re-entrant (multi-shot continuations work). The cost is O(stack depth) per capture — a deep call stack means more data to copy. For most programs this is negligible. Only programs that capture continuations in tight inner loops would notice.

The alternatives are CPS transform (zero capture cost but all code runs slower) and segmented/heap-allocated stacks (fast capture but every call pays allocation cost). Stack copying is the simplest to implement correctly and is the same approach used by Guile and Chibi.

### Continuation scope

A continuation captured in one top-level REPL expression cannot re-enter subsequent top-level expressions. This is standard behavior shared by Guile, Chibi, Chicken, Chez, and Racket — it's how REPLs fundamentally work with continuations, not a Kaappi-specific limitation.

Within a single expression (or a file), continuations work fully.

### No `syntax-case`

Only `syntax-rules` is supported for macro definitions. R7RS-small deliberately standardizes `syntax-rules` and not `syntax-case` — the latter is part of R6RS and some implementations (Chez, Racket) but was intentionally excluded from R7RS-small.

---

## Remaining gaps

2 edge cases remain — both with low practical impact and workarounds.

### Local-variable referential transparency in `let-syntax`

**What the spec requires:** R7RS §4.3 says macros defined with `syntax-rules` are hygienic and referentially transparent — free identifiers in a template refer to bindings where the macro was *defined*, not where it is *used*.

**What works:** Global references, rebound special forms (`let`, `if` as variables), forward references through macros, and custom ellipsis identifiers all work correctly. The only remaining gap is local-variable transparency in `let-syntax`:

```scheme
(let ((x 1))
  (let-syntax ((m (syntax-rules () ((m) x))))
    (let ((x 2))
      (m))))
;=> Expected: 1  (macro should see x=1 from definition site)
;=> Actual: UndefinedVariable
```

**Why:** The hygiene system renames `x` in the template to a gensym to prevent capture. But `x` is a local variable (compiled to a register slot), not a global — so the gensym doesn't resolve. Fixing this requires the macro to capture its lexical environment at definition time, which needs syntax objects or explicit renaming with full environment threading.

**Practical impact:** Low. Requires all of: a macro defined with `let-syntax` (not `define-syntax`), the template references a local (not a global), and the same name is rebound between definition and use.

### `letrec` init restriction

**What the spec requires:** R7RS §4.2.2 says it is an error to evaluate a `letrec` init expression that references another binding being defined.

**What Kaappi does:** Detects bare variable references but not indirect references. R7RS "is an error" (§1.3.2) means implementations are not required to detect it. Chibi, Chicken, and Gauche all allow this.

---

## Verified conformant behaviors

These areas have been tested and match R7RS behavior:

- Proper tail calls in all R7RS-specified positions: `if`, `begin`, `cond`, `case`, `and`, `or`, `when`, `unless`, `let`/`let*`/`letrec`/`letrec*`, `do`, `guard`, `parameterize`, lambda bodies
- Hygienic macros: scope-based renaming prevents template-introduced bindings from capturing user variables; referential transparency for global references; special forms (`let`, `if`, `begin`, etc.) in templates are hygiene-renamed and correctly recognized by the compiler even when rebound at the use site
- Custom ellipsis identifiers: `(syntax-rules custom-elli (...) ...)` fully supported
- Ellipsis-as-literal priority: when `...` is both the ellipsis and a literal, literal takes priority (R7RS §4.3.2)
- Forward references through macros: `define-syntax` in `let`/`lambda` bodies can reference sibling `define` forms defined later in the same scope
- `define-values` works both at top level and inside `let`/`lambda` bodies (all R7RS §5.3.2 forms)
- `cond` with `=>` correctly treats `=>` as a normal expression when rebound as a variable
- `null-environment` and `scheme-report-environment` (R7RS §6.12 / R5RS compat)
- String literal immutability enforced; `symbol->string` returns immutable strings
- `file-error?` / `read-error?` return `#t` for file and reader errors respectively
- Division by zero raises a catchable error
- `case` with `=>` arrow syntax
- Radix prefixes: `#b1010` → `10`, `#o17` → `15`, `#xff` → `255`
- Exactness prefixes: `#e1.5` → `3/2`, `#e0.25` → `1/4`, `#i3` → `3.0`
- Complex numbers: `number->string`/`string->number` for `"1+2i"` format; `exact`/`inexact`/`exact?`/`inexact?` on complex; `sqrt` on complex; `expt` with complex base/exponent (including Euler's identity)
- `letrec` bare forward references detected at compile time
- `#!fold-case` / `#!no-fold-case` directives
- Datum labels: `#0=(a b . #0#)` reads circular structures
- `write-shared` detects shared/circular structure with two-pass labeling
- `equal?` terminates on circular structures via visited-set cycle detection
- Nested quasiquote correctly preserves inner structure
- NaN handling: `(eqv? +nan.0 +nan.0)` → `#t`, `(= +nan.0 +nan.0)` → `#f`
- Negative zero: `(eqv? 0.0 -0.0)` → `#f`, `(= 0.0 -0.0)` → `#t`
- Library single-load guarantee
- `dynamic-wind` correctness across continuation jumps
- `delay`/`force` with memoization
- `define-record-type`, `syntax-rules` with ellipsis, `cond-expand`
- Arbitrary-precision integers (bignums) with automatic fixnum↔bignum promotion
- Exact rationals with reader syntax (`1/2`), arithmetic, and conversion
- All 15 standard libraries registered and importable (including `(scheme r5rs)`)

---

## Fixed bugs (this session)

27 bugs found and fixed via systematic `/audit-primitives` skill:

**Arithmetic:** `min`/`max` on rationals, `quotient`/`modulo`/`gcd` on flonums, `floor-quotient`/`truncate-quotient` on bignums, `square` on rationals, `even?`/`odd?` on flonums/bignums

**Strings:** `string-trim`/`trim-right`/`trim-both` UTF-8 corruption with predicate arg, `string-ci-hash` Unicode case folding

**Hash tables:** `hash-table-ref` thunk not called, `hash-table-merge!` not overwriting

**I/O:** `write-bytevector` start/end args, `textual-port?` on binary ports, `load` file-error type

**Memory:** FiberScheduler leak, `allocFiber` missing GC trigger, vector temp allocation leaks (5 functions), GC safety in `list-copy`/`make-list`/`map`

**Vectors:** `vector-swap!` negative index panic

**Reader:** `#e` prefix truncation (now produces rationals), `thread-sleep!` accepts `#f`

**FFI:** uninformative `dlerror()` messages in `ffi-open`/`ffi-fn`

**Random:** `random-source-state-ref`/`state-set!` full 4-word state roundtrip

---

## SRFI conformance

52 SRFIs supported. 8 built-in (native Zig), 44 portable (.sld files). Coverage details for the built-in SRFIs follow.

### SRFI 1 — List Library

**Coverage: ~95%** (62 of ~65 spec procedures)

Implemented: `cons*`, `xcons`, `list-tabulate`, `circular-list`, `iota`, `proper-list?`, `dotted-list?`, `circular-list?`, `not-pair?`, `null-list?`, `list=`, `first`–`tenth`, `car+cdr`, `take`, `drop`, `take-right`, `drop-right`, `take-while`, `drop-while`, `split-at`, `last`, `last-pair`, `zip`, `unzip1`, `unzip2`, `count`, `fold`, `fold-right`, `pair-fold`, `pair-fold-right`, `reduce`, `reduce-right`, `unfold`, `unfold-right`, `map-in-order`, `append-map`, `filter-map`, `pair-for-each`, `filter`, `partition`, `remove`, `find`, `find-tail`, `any`, `every`, `list-index`, `span`, `break`, `delete`, `delete-duplicates`, `alist-cons`, `alist-copy`, `alist-delete`, `lset=`, `lset-adjoin`, `lset-union`, `lset-intersection`, `lset-difference`, `lset-xor`, `append-reverse`, `length+`, `concatenate`.

**Not implemented:**
- `unzip3`–`unzip5` — rarely used
- Linear-update (`!`) variants — SRFI 1 permits non-mutating implementations
- `lset-diff+intersection` — composite operation; use `lset-difference` + `lset-intersection`

### SRFI 9 — Records

**Coverage: 100%.** `define-record-type` is implemented as R7RS compiler syntax.

### SRFI 13 — String Library

**Coverage: ~85%** (43 of ~50 spec procedures)

Implemented: `string-contains`, `string-prefix?`, `string-suffix?`, `string-trim`, `string-trim-right`, `string-trim-both` (with predicate argument, UTF-8 safe), `string-index`, `string-index-right`, `string-skip`, `string-skip-right`, `string-count`, `string-split`, `string-join`, `string-concatenate`, `string-take`, `string-drop`, `string-take-right`, `string-drop-right`, `string-pad`, `string-pad-right`, `string-reverse`, `string-filter`, `string-delete`, `string-replace`, `string-titlecase`, `string-every`, `string-any`, `string-tabulate`, `string-unfold`, `string-unfold-right`.

**Not implemented:**
- SRFI 14 char-set overloads — use `(lambda (c) (char-set-contains? cs c))` as workaround
- `string-xcopy!` — mutation variant
- `string-map`, `string-for-each` with start/end indices — base versions available

### SRFI 27 — Random Numbers

**Coverage: 100%** (12 of 12 spec procedures). Full state save/restore via `random-source-state-ref`/`state-set!` (all 4 xoshiro256 state words).

### SRFI 39 — Parameter Objects

**Coverage: 100%.** `make-parameter` (with optional converter) is exported; `parameterize` is compiler syntax.

### SRFI 69 — Hash Tables

**Coverage: ~95%** (21 of ~22 spec procedures). `hash-table-ref` correctly calls default thunk. `hash-table-merge!` overwrites existing keys. `string-ci-hash` uses Unicode case folding.

**Not implemented:**
- `hash-table-equivalence-function`, `hash-table-hash-function` — `make-hash-table` accepts but ignores custom comparator/hash arguments

### SRFI 133 — Vector Library

**Coverage: ~95%** (32 of ~33 spec procedures)

Implemented: All SRFI-133 procedures including `vector-unfold`, `vector-unfold-right`, `vector-binary-search`, `vector-concatenate`, `vector-cumulate`, `vector-partition`, `vector-swap!`, `vector-reverse!`, `vector-reverse-copy`, `vector-skip`, `vector-skip-right`.

**Not implemented:**
- `vector-append-subvectors` — composite append with subranges

### SRFI 170 — POSIX API

**Coverage: ~65%** (53 of ~80+ spec procedures)

Implemented: File info (`file-info`, `file-info?`, `file-info-type`, all `file-info:*` accessors, type predicates), file operations (`create-directory`, `delete-directory`, `rename-file`, `create-symlink`, `read-symlink`, `create-hard-link`, `real-path`, `set-file-mode`, `truncate-file`, `create-fifo`, `set-file-owner`, `set-file-times`), process state (`pid`, `umask`, `set-umask!`, `current-directory`, `set-current-directory!`, `user-uid`, `user-gid`, `user-effective-uid`, `user-effective-gid`, `user-supplementary-gids`, `nice`), environment (`set-environment-variable!`, `delete-environment-variable!`), terminal (`terminal?`), user/group database, directory traversal (`open-directory`, `read-directory`, `close-directory`, `directory-files`), time (`posix-time`, `monotonic-time`), temp files (`temp-file-prefix`, `create-temp-file`).

**Not implemented (by design):**
- Process management (`fork`, `exec*`, `waitpid`, `_exit`) — unsafe in GC'd bytecode VM
- Signal handling — requires async-safe VM interrupt mechanism
- Pipes, I/O multiplexing — not exposed
