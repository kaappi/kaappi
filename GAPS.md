# R7RS Conformance Gaps

This document explains the remaining gaps between Kaappi and the R7RS-small specification, why they exist, and workarounds.

For the full conformance summary (including everything that IS conformant), see `README.md`.

---

## 1. Local-variable referential transparency in macros

### What the spec requires

R7RS §4.3 says macros defined with `syntax-rules` are hygienic and referentially transparent. Referential transparency means that free identifiers in a macro template refer to the bindings visible where the macro was **defined**, not where it is **used**.

### What works

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

All standard hygiene also works — template-introduced bindings don't capture user variables:

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

### What fails

Local-variable referential transparency in `let-syntax`:

```scheme
(let ((x 1))
  (let-syntax ((m (syntax-rules () ((m) x))))
    (let ((x 2))
      (m))))
;=> Expected: 1  (macro should see x=1 from definition site)
;=> Actual: UndefinedVariable
```

### Why it fails

The macro template contains a free reference to `x`. During expansion, the hygiene system renames `x` to a gensym (`__hyg_N_x`) to prevent capture. But `x` here is a **local variable** (compiled to a register slot), not a global — so the gensym doesn't resolve to anything.

For this to work, the macro would need to **capture its lexical environment at definition time** — remember that `x` refers to a specific register slot in the enclosing `let` frame. Then during expansion, the template's `x` would resolve against that saved scope, not the current one.

### Why it's hard to fix

This requires the expander and compiler to be tightly integrated:

1. When `let-syntax` creates a macro, store a snapshot of the current compiler scope (which locals exist and at what register slots)
2. When expanding the macro later, resolve the template's free variables against the saved scope
3. The compiler must emit code referencing the correct register/upvalue from the saved scope

This is what Racket achieves with syntax objects and what Chibi achieves with explicit renaming + full environment threading. Both approaches require the expander to produce scope-annotated output that the compiler can interpret — a fundamental architectural change.

### Practical impact

**Low.** This edge case requires all of:
- A macro defined with `let-syntax` (not `define-syntax`)
- The macro's template references a local variable (not a global)
- The same name is rebound between the macro's definition and its use

Most real Scheme macros reference globals (`if`, `let`, `cons`, `+`, etc.) or pattern variables from the use site. The local-variable case almost never arises in practice.

### Workaround

Use a global variable instead of a local:

```scheme
(define x 1)
(define-syntax m (syntax-rules () ((m) x)))
(let ((x 2)) (m))
;=> 1  ✓
```

Or pass the value explicitly via a pattern variable:

```scheme
(let ((x 1))
  (let-syntax ((m (syntax-rules () ((m v) v))))
    (let ((x 2))
      (m x))))  ; passes the outer x explicitly
```

---

## 2. `letrec` init restriction (partial)

### What the spec requires

R7RS §4.2.2 says it is an error to evaluate a `letrec` init expression that references the value of another binding being defined:

```scheme
(letrec ((x y) (y 1)) x)  ; "is an error" per spec
```

### What Kaappi does

Kaappi detects **bare variable references** to sibling bindings at compile time:

```scheme
(letrec ((x y) (y 1)) x)
;=> Compile error  ✓  bare reference to y detected
```

But it does **not** detect indirect references through expressions:

```scheme
(letrec ((x (+ y 1)) (y 2)) x)
;=> void (or other undefined behavior) — not detected
```

### Why it's acceptable

The R7RS phrase "is an error" (§1.3.2) means implementations are **not required** to detect or report the error. Most Scheme implementations don't detect it either — Chibi, Chicken, and Gauche all allow the above code to run with unspecified results.

### Workaround

Use `letrec*` for sequential initialization where earlier bindings are visible to later ones:

```scheme
(letrec* ((y 2) (x (+ y 1))) x)
;=> 3  ✓
```

---

## 3. Unicode case mapping (Latin/Greek/Cyrillic only)

### What the spec requires

R7RS §6.6 says `char-upcase`, `char-downcase`, and `char-foldcase` should perform Unicode case mapping. The `(scheme char)` library's `string-upcase`, `string-downcase`, and `string-foldcase` should do the same for strings.

### What Kaappi covers

Case mapping works correctly for:

| Script | Range | Example |
|--------|-------|---------|
| ASCII | U+0041–U+007A | `(char-upcase #\a)` → `#\A` |
| Latin-1 Supplement | U+00C0–U+00FF | `(char-upcase #\é)` → `#\É` |
| Latin Extended-A | U+0100–U+017F | `(char-downcase #\Ā)` → `#\ā` |
| Latin Extended-B | U+0180–U+024F | partial coverage |
| Latin Extended Additional | U+1E00–U+1EFF | partial coverage |
| Greek | U+0370–U+03FF | `(char-upcase #\α)` → `#\Α` |
| Greek Extended | U+1F00–U+1FFF | partial coverage |
| Cyrillic | U+0400–U+04FF | `(char-upcase #\а)` → `#\А` |
| Cyrillic Supplement | U+0500–U+052F | partial coverage |

### What's missing

Case mapping for other scripts returns the character unchanged:

- Armenian (U+0530–U+058F)
- Georgian (U+10A0–U+10FF)
- Cherokee (U+13A0–U+13FF)
- Deseret (U+10400–U+1044F)
- Full-width Latin (U+FF21–U+FF5A)
- Various other scripts with cased characters

### Why it's hard to fix

Full Unicode case mapping requires large lookup tables — the Unicode Character Database defines case mappings for ~1,400 codepoints across dozens of scripts. Some mappings are one-to-many (e.g., German `ß` uppercases to `SS` — two characters), which requires string-level handling that our character-level `char-upcase` can't express.

### Practical impact

**Low for most users.** Latin, Greek, and Cyrillic cover the vast majority of case-sensitive text processing in practice. Programs working with Armenian, Georgian, or other cased scripts would need to implement their own case mapping.

### Workaround

For scripts not covered, use explicit codepoint arithmetic or a lookup table in Scheme:

```scheme
(define (armenian-upcase ch)
  (let ((cp (char->integer ch)))
    (if (and (>= cp #x561) (<= cp #x586))
        (integer->char (- cp 48))
        ch)))
```

---

## Summary

| Gap | Severity | Fixable? | Why |
|-----|----------|----------|-----|
| Local-variable macro transparency | Low | Hard | Requires expander-compiler integration with environment capture |
| `letrec` init restriction | Very low | N/A | Spec says implementations need not detect it |
| Unicode case mapping scope | Low | Data-heavy | Needs ~1,400 codepoint mapping entries |

All three gaps have workarounds and affect edge cases that rarely arise in practice. The implementation passes all standard R7RS tests for the features it covers.
