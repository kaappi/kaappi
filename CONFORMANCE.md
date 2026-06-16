# R7RS Conformance

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 313 built-in procedures, 32 syntax forms, and all 14 standard libraries.

This document covers design choices, remaining gaps, and verified conformant behaviors.

---

## Design choices

These are intentional deviations from the full R7RS numeric/continuation/macro tower, with rationale.

| Area | Behavior | Rationale |
|------|----------|-----------|
| **Stack-copying continuations** | `call/cc` snapshots full VM state (registers, frames, handlers, wind stack) — O(depth) per capture. | Correct and fully re-entrant. Simpler than CPS transform or segmented stacks. |
| **Continuation scope** | A multi-shot continuation captured in one top-level form cannot re-enter subsequent top-level forms. | The REPL evaluates forms one at a time. Wrap in `(begin ...)` to span them. |
| **No `syntax-case`** | Only `syntax-rules` is supported. | R7RS-small specifies `syntax-rules` only. |

---

## Remaining gaps

3 edge cases remain — all with low practical impact and workarounds.

| Gap | Severity | Summary |
|-----|----------|---------|
| [Local-variable macro transparency](#local-variable-referential-transparency-in-macros) | Low | `let-syntax` macros can't reference locals from definition site |
| [`letrec` init restriction](#letrec-init-restriction) | Very low | Indirect forward references not detected — spec says "is an error" |
| [Unicode case mapping](#unicode-case-mapping) | Low | Latin/Greek/Cyrillic covered; other cased scripts pass through unchanged |

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

## Gap details

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

---

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

---

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

Other scripts (Armenian, Georgian, Cherokee, etc.) pass through unchanged.

**Why:** Full Unicode case mapping requires ~1,400 codepoint entries. Some mappings are one-to-many (e.g., `ß` → `SS`), requiring string-level handling.

**Practical impact:** Low. Latin, Greek, and Cyrillic cover the vast majority of case-sensitive text processing.

**Workaround:** Use explicit codepoint arithmetic for uncovered scripts:

```scheme
(define (armenian-upcase ch)
  (let ((cp (char->integer ch)))
    (if (and (>= cp #x561) (<= cp #x586))
        (integer->char (- cp 48))
        ch)))
```
