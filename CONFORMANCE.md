# R7RS Conformance

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 419 built-in procedures, 32 syntax forms, and all 14 standard libraries.

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

The REPL evaluates each expression independently: read, compile, execute, print, then discard the compiled function. When a continuation is invoked, it restores the VM state from the capture point, but subsequent REPL expressions weren't part of that captured state — they didn't exist yet.

Within a single expression (or a file), continuations work fully:

```scheme
;; Works — all in one expression:
(begin
  (define k #f)
  (display (+ 1 (call/cc (lambda (c) (set! k c) 10))))
  (newline)
  (k 20))

;; Doesn't work — separate REPL expressions:
kaappi> (define k #f)
kaappi> (+ 1 (call/cc (lambda (c) (set! k c) 10)))
11
kaappi> (k 20)  ;; continuation can't re-enter the previous expression
```

Racket addresses this with delimited continuations (`call-with-continuation-prompt`), but that is a Racket extension, not part of R7RS-small.

### No `syntax-case`

Only `syntax-rules` is supported for macro definitions. R7RS-small deliberately standardizes `syntax-rules` and not `syntax-case` — the latter is part of R6RS and some implementations (Chez, Racket) but was intentionally excluded from R7RS-small to keep the macro system simpler and more portable.

`syntax-rules` covers the vast majority of macro use cases: pattern matching, ellipsis, literal keywords, hygienic renaming. For the rare cases where `syntax-case` would be needed (procedural macros with computed output), workarounds exist using `define-syntax` with explicit template construction.

---

## Remaining gaps

4 edge cases remain — all with low practical impact and workarounds.

### Local-variable referential transparency in macros

**What the spec requires:** R7RS §4.3 says macros defined with `syntax-rules` are hygienic and referentially transparent — free identifiers in a template refer to bindings where the macro was *defined*, not where it is *used*.

**What works:**

Global references are fully transparent:

```scheme
(define helper-val 42)
(define-syntax get-helper
  (syntax-rules ()
    ((get-helper) helper-val)))

(let ((helper-val 99))
  (get-helper))
;=> 42  ✓  macro sees definition-site global, not use-site shadow
```

All standard hygiene works — template-introduced bindings don't capture user variables:

```scheme
(define-syntax my-or
  (syntax-rules ()
    ((my-or) #f)
    ((my-or e) e)
    ((my-or e1 e2 ...)
     (let ((temp e1))
       (if temp temp (my-or e2 ...))))))

(let ((temp 42))
  (my-or #f temp))
;=> 42  ✓  macro's temp doesn't capture user's temp
```

**What fails:**

Local-variable referential transparency in `let-syntax`:

```scheme
(let ((x 1))
  (let-syntax ((m (syntax-rules () ((m) x))))
    (let ((x 2))
      (m))))
;=> Expected: 1  (macro should see x=1 from definition site)
;=> Actual: UndefinedVariable
```

**Why:** The hygiene system renames `x` in the template to a gensym to prevent capture. But `x` is a local variable (compiled to a register slot), not a global — so the gensym doesn't resolve. Fixing this requires the macro to capture its lexical environment at definition time, which needs tight expander-compiler integration (syntax objects or explicit renaming with full environment threading).

**Practical impact:** Low. Requires all of: a macro defined with `let-syntax` (not `define-syntax`), the template references a local (not a global), and the same name is rebound between definition and use. Most real macros reference globals or pattern variables.

**Workaround:** Use a global variable, or pass the value explicitly via a pattern variable:

```scheme
(define x 1)
(define-syntax m (syntax-rules () ((m) x)))
(let ((x 2)) (m))  ;=> 1  ✓
```

### `letrec` init restriction

**What the spec requires:** R7RS §4.2.2 says it is an error to evaluate a `letrec` init expression that references another binding being defined.

**What Kaappi does:** Detects bare variable references to sibling bindings:

```scheme
(letrec ((x y) (y 1)) x)
;=> Compile error  ✓
```

Does not detect indirect references:

```scheme
(letrec ((x (+ y 1)) (y 2)) x)
;=> unspecified — not detected
```

**Why it's acceptable:** R7RS "is an error" (§1.3.2) means implementations are not required to detect it. Chibi, Chicken, and Gauche all allow this.

**Workaround:** Use `letrec*` for sequential initialization:

```scheme
(letrec* ((y 2) (x (+ y 1))) x)  ;=> 3  ✓
```

### Unicode case mapping

**What the spec requires:** R7RS §6.6 says `char-upcase`/`char-downcase` should perform Unicode case mapping.

**What Kaappi covers:**

| Script | Example |
|--------|---------|
| ASCII | `(char-upcase #\a)` → `#\A` |
| Latin-1 Supplement | `(char-upcase #\é)` → `#\É` |
| Latin Extended-A | `(char-downcase #\Ā)` → `#\ā` |
| Greek | `(char-upcase #\α)` → `#\Α` |
| Cyrillic | `(char-upcase #\а)` → `#\А` |
| Armenian | `(char-downcase #\x531;)` → lowercase |
| Georgian (Mtavruli) | `(char-upcase #\x10D0;)` → Mtavruli |
| Cherokee | `(char-downcase #\x13A0;)` → lowercase |

Other scripts (Coptic, Glagolitic, Deseret, etc.) pass through unchanged.

**Why:** Full Unicode case mapping requires ~1,400 codepoint entries. The
scripts above cover the most commonly needed case conversions. Some mappings
are one-to-many (e.g., `ß` → `SS`), requiring string-level handling (supported).

### Self-redefinition during self-tail-recursion

**What the spec requires:** A reference to a top-level variable observes its
current value, even if the variable was just mutated with `set!`.

**What Kaappi does:** A procedure that tail-calls *itself* by name compiles to a
dedicated `self_tail_call` instruction that loops in place (copy args, reset the
instruction pointer) instead of re-reading the global binding. If such a
procedure reassigns its own name mid-recursion and then tail-calls itself, the
optimized loop keeps running the *original* body rather than the new one:

```scheme
(define (f n)
  (if (= n 0)
      'original
      (begin
        (if (= n 1) (set! f (lambda (x) 'redefined)))
        (f (- n 1)))))   ; self-tail-call: loops in place
(f 3)
;=> 'original   (a strict reading would give 'redefined)
```

**Why:** Skipping the global lookup on every self-tail-call is the core of the
optimization (it is what makes deep self-recursion like `tak` fast). Re-reading
and re-validating the binding on each iteration would defeat the purpose. Note
this only affects *self* calls — a tail call to a *different* global (mutual
recursion) still goes through the standard path and observes redefinition:

```scheme
(define (a n)
  (if (= n 0) 'original
      (begin (if (= n 1) (set! a (lambda (x) 'redefined))) (helper n))))
(define (helper n) (a (- n 1)))
(a 3)
;=> 'redefined   ✓  non-self tail call re-reads the global
```

**Practical impact:** Negligible. It requires a procedure to reassign its own
name to a *different* procedure while recursing on itself — a pattern with no
real use. Most production Schemes (Chez, Gauche, Chibi) make the same trade-off.

**Workaround:** To force redefinition to take effect, make the recursive call go
through a different binding (e.g., an indirection) so it is not a self-call.

---

## Verified conformant behaviors

These areas have been tested and match R7RS behavior:

- Proper tail calls in all R7RS-specified positions: `if`, `begin`, `cond`, `case`, `and`, `or`, `when`, `unless`, `let`/`let*`/`letrec`/`letrec*`, `do`, `guard`, `parameterize`, lambda bodies
- Hygienic macros: scope-based renaming prevents template-introduced bindings from capturing user variables; referential transparency for global references
- String literal immutability enforced; `symbol->string` returns immutable strings
- `file-error?` / `read-error?` return `#t` for file and reader errors respectively
- Division by zero raises a catchable error: `(guard (e (#t 'caught)) (/ 1 0))` → `caught`
- `case` with `=>` arrow syntax: `(case 6 ((6) => (lambda (x) (+ x 1))))` → `7`
- Radix prefixes: `#b1010` → `10`, `#o17` → `15`, `#xff` → `255`
- Exactness prefixes: `#e1.5` → `1`, `#i3` → `3.0`
- Multiple values in single-value context: first value extracted automatically
- `letrec` bare forward references detected at compile time
- `#!fold-case` / `#!no-fold-case` directives
- Datum labels: `#0=(a b . #0#)` reads circular structures
- `write-shared` detects shared/circular structure with two-pass labeling
- `equal?` terminates on circular structures via visited-set cycle detection
- Nested quasiquote: `` `(a `(b ,(+ 1 2))) `` correctly preserves inner structure
- Hex escapes in `|quoted identifiers|`: `|H\x65;llo|` → symbol `Hello`
- NaN handling: `(eqv? +nan.0 +nan.0)` → `#t`, `(= +nan.0 +nan.0)` → `#f`
- Negative zero: `(eqv? 0.0 -0.0)` → `#f`, `(= 0.0 -0.0)` → `#t`
- Library single-load guarantee
- `dynamic-wind` correctness across continuation jumps
- `delay`/`force` with memoization
- `define-record-type`, `syntax-rules` with ellipsis, `cond-expand`
- Arbitrary-precision integers (bignums): `(expt 2 100)` → exact result, automatic fixnum↔bignum promotion on overflow
- Exact rationals: `(/ 1 3)` → `1/3`, `(+ 1/3 1/6)` → `1/2`, `(inexact->exact 1.5)` → `3/2`; reader parses `1/2` syntax
- All 14 standard libraries registered and importable

---

## Fixed bugs

These were compiler/VM bugs discovered during SRFI library development and fixed.

### Conditional jump table overflow (fixed)

**What was broken:** `cond`, `case`, `and`, and `or` forms stored jump offsets in a fixed `[32]usize` stack array. A `cond` with 15+ branches (common in dispatch-heavy library functions) overflowed the array, silently corrupting adjacent stack memory — including the `CallFrame.saved_wind_count` field. The corrupted wind count caused the VM to access invalid `wind_stack` entries on function return, producing `panic: incorrect alignment`.

**Fix:** Replaced all fixed-size jump arrays with dynamically-sized `ArrayList(usize)` in `compiler_conditionals.zig` (`compileCond`, `compileAnd`, `compileOr`) and `compiler_advanced.zig` (`compileCase`).

### Closure variable boxing across branches (fixed)

**What was broken:** When a lambda captured a local variable (triggering `box_local` for shared mutation), the `box_local` instruction was emitted at the closure creation point — inside whatever `cond`/`if` branch contained the lambda. But the compiler marked the variable as boxed globally, so ALL branches used `get_box_local`/`set_box_local` to access it. If a different branch was entered first (without the closure), the variable was still unboxed, and `get_box_local` misinterpreted the raw value.

Example that triggered the bug:

```scheme
(define (f sre gc)
  (cond
    ((eq? (car sre) 'seq)
     ;; This branch creates a closure capturing gc → emits box_local
     (map (lambda (s) (f s gc)) (cdr sre)))
    ((eq? (car sre) 'grp)
     ;; This branch uses get_box_local for gc — but gc was never boxed!
     (set-car! gc (+ 1 (car gc)))
     (f (cadr sre) gc))))
```

**Fix:** Two changes to `vm.zig`:
1. Changed the box sentinel from `NIL` to `VOID` — boxes are now `(value . #void)` instead of `(value . ())`, so they're distinguishable from regular one-element lists.
2. Made `get_box_local`, `set_box_local`, and the `closure` capture instruction auto-box on first access. If a register hasn't been boxed yet (because `box_local` was in an untaken branch), the instruction boxes it on the spot before proceeding.

---

## SRFI conformance

46 SRFIs supported. 8 built-in (native Zig), 38 portable (.sld files). Coverage details for the built-in SRFIs follow.

### SRFI 1 — List Library

**Coverage: ~90%** (55 of ~60 spec procedures)

Implemented: `cons*`, `xcons`, `list-tabulate`, `circular-list`, `iota`, `proper-list?`, `dotted-list?`, `circular-list?`, `not-pair?`, `null-list?`, `list=`, `first`–`fifth`, `car+cdr`, `take`, `drop`, `take-right`, `drop-right`, `take-while`, `drop-while`, `split-at`, `last`, `last-pair`, `zip`, `unzip1`, `unzip2`, `count`, `fold`, `fold-right`, `pair-fold`, `reduce`, `reduce-right`, `unfold`, `unfold-right`, `map` (via scheme base), `for-each` (via scheme base), `append-map`, `filter-map`, `pair-for-each`, `filter`, `partition`, `remove`, `find`, `find-tail`, `any`, `every`, `list-index`, `span`, `break`, `delete`, `delete-duplicates`, `alist-cons`, `alist-copy`, `alist-delete`, `lset<=` (via `lset=`), `lset=`, `lset-adjoin`, `lset-union`, `lset-intersection`, `lset-difference`, `lset-xor`, `append-reverse`, `length+`, `concatenate`.

R7RS base procedures (`cons`, `list`, `pair?`, `null?`, `car`, `cdr`, `caar`–`cddddr`, `length`, `append`, `reverse`, `list-ref`, `list-tail`, `list-copy`, `make-list`, `map`, `for-each`, `assoc`, `assq`, `assv`, `member`, `memq`, `memv`) are available via `(scheme base)` but not re-exported from `(srfi 1)`.

**Not implemented:**
- `sixth`–`tenth` — trivial but rarely used; `list-ref` works
- `pair-fold-right` — uncommon fold variant
- `unzip3`–`unzip5` — rarely used
- `map-in-order` — identical to `map` in left-to-right implementations
- Linear-update (`!`) variants — SRFI 1 permits non-mutating implementations; use the functional versions
- `lset-diff+intersection`, `lset-diff+intersection!` — composite operation; use `lset-difference` + `lset-intersection`

### SRFI 9 — Records

**Coverage: 100%.** `define-record-type` is implemented as R7RS compiler syntax.

### SRFI 13 — String Library

**Coverage: ~75%** (38 of ~50 spec procedures)

Implemented: `string-contains`, `string-prefix?`, `string-suffix?`, `string-trim`, `string-trim-right`, `string-trim-both`, `string-index`, `string-count`, `string-split`, `string-join`, `string-concatenate`, `string-take`, `string-drop`, `string-take-right`, `string-drop-right`, `string-pad`, `string-pad-right`, `string-reverse`, `string-filter`, `string-delete`, `string-replace`, `string-titlecase`, `string-every`, `string-any`, `string-tabulate`. Plus standard string operations re-exported from R7RS: `string-length`, `string-append`, `substring`, `string-copy`, `string-ref`, `string-set!`, `string<?`, `string<=?`, `string=?`, `string>=?`, `string>?`, `string-upcase`, `string-downcase`, `string-foldcase`.

**Not implemented:**
- SRFI 14 char-set overloads — `string-trim`, `string-index`, etc. accept a predicate but not a char-set object directly. Use `(lambda (c) (char-set-contains? cs c))` as a workaround.
- `string-unfold`, `string-unfold-right` — uncommon constructors
- `string-xcopy!` — mutation variant
- `string-map`, `string-for-each` with start/end indices — base versions available without index range
- `string-hash`, `string-ci-hash` — available via `(srfi 69)` instead

### SRFI 27 — Random Numbers

**Coverage: ~20%** (2 of ~10 spec procedures)

Implemented: `random-integer`, `random-real`.

**Not implemented:** `default-random-source`, `random-source?`, `random-source-make-integers`, `random-source-make-reals`, `random-source-randomize!`, `random-source-pseudo-randomize!`, `random-source-state-ref`, `random-source-state-set!`. These require a random source heap object type. The basic interface (`random-integer`, `random-real`) covers the most common use cases.

### SRFI 39 — Parameter Objects

**Coverage: 100%.** `make-parameter` is exported; `parameterize` is compiler syntax.

### SRFI 69 — Hash Tables

**Coverage: ~95%** (21 of ~22 spec procedures)

Implemented: `make-hash-table`, `hash-table?`, `hash-table-ref`, `hash-table-ref/default`, `hash-table-set!`, `hash-table-delete!`, `hash-table-exists?`, `hash-table-size`, `hash-table-keys`, `hash-table-values`, `hash-table-walk`, `hash-table->alist`, `alist->hash-table`, `hash-table-copy`, `hash-table-update!/default`, `hash-table-fold`, `hash-table-merge!`, `hash`, `string-hash`, `string-ci-hash`, `hash-by-identity`.

**Not implemented:**
- `hash-table-equivalence-function`, `hash-table-hash-function` — all hash tables use `equal?`; the equivalence/hash arguments to `make-hash-table` are accepted but ignored
- `hash-table-update!` (without default) — use `hash-table-update!/default` with an explicit default

### SRFI 133 — Vector Library

**Coverage: ~90%** (30 of ~33 spec procedures)

Implemented: `vector`, `make-vector`, `vector?`, `vector-length`, `vector-ref`, `vector-set!`, `vector->list`, `list->vector`, `vector-fill!`, `vector-copy`, `vector-copy!`, `vector-append`, `vector-for-each`, `vector-map`, `vector-empty?`, `vector-count`, `vector-any`, `vector-every`, `vector-index`, `vector-index-right`, `vector-skip`, `vector-skip-right`, `vector-swap!`, `vector-reverse!`, `vector-reverse-copy`, `vector-unfold`, `vector-concatenate`, `vector-cumulate`, `vector-partition`.

**Not implemented:**
- `vector-unfold-right` — right-to-left unfold variant
- `vector-append-subvectors` — composite append with subranges
- `vector-binary-search` — binary search (requires sorted vector)

### SRFI 170 — POSIX API

**Coverage: ~60%** (50 of ~80+ spec procedures)

Implemented: File info (`file-info`, `file-info?`, all `file-info:*` accessors, `file-info-directory?`, `file-info-regular?`, `file-info-symlink?`, `file-info-fifo?`, `file-info-socket?`, `file-info-device?`), file operations (`create-directory`, `delete-directory`, `rename-file`, `create-symlink`, `read-symlink`, `create-hard-link`, `real-path`, `set-file-mode`, `truncate-file`, `create-fifo`, `set-file-owner`, `set-file-times`), process state (`pid`, `umask`, `set-umask!`, `current-directory`, `set-current-directory!`, `user-uid`, `user-gid`, `user-effective-uid`, `user-effective-gid`, `user-supplementary-gids`, `nice`), environment (`set-environment-variable!`, `delete-environment-variable!`), terminal (`terminal?`), user/group database (`user-info`, `user-info?`, `user-info:*`, `group-info`, `group-info?`, `group-info:*`), directory traversal (`open-directory`, `read-directory`, `close-directory`, `directory-files`), time (`posix-time`, `monotonic-time`).

**Not implemented (by design):**
- Process management (`fork`, `exec*`, `waitpid`, `_exit`) — `fork` in a GC'd bytecode VM duplicates the entire heap; safe implementation requires copy-on-write or pre-fork GC, which is architecturally complex
- Signal handling (`signal`, `signal-handler`, `set-signal-handler!`) — requires async-safe VM interrupt mechanism
- Pipes (`pipe`, `dup`, `dup2`, `close`) — file descriptor management is not exposed
- I/O multiplexing (`select`, `poll`) — requires event loop integration
- Time conversion (`time-utc->posix`, `posix->time-utc`, `time-monotonic->...`) — SRFI 170 time objects not implemented; `posix-time` and `monotonic-time` return raw seconds
