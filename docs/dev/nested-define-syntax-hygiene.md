# Nested `define-syntax` Hygiene Edge Case

## Status

**Not yet fixed.** One R7RS test failure in section 4.3 Macros.

## Failing test

```scheme
(let ()
 (define-syntax foo
   (syntax-rules ()
     ((foo bar y)
      (define-syntax bar
        (syntax-rules ()
          ((bar x) 'y))))))
 (foo bar x)
 (test 'x (bar 1)))     ;=> expected: x, actual: 1
```

**Expected:** `(bar 1)` returns the symbol `x` — the value of `y` captured
when `(foo bar x)` was expanded (since `y` matched `x`).

**Actual:** `(bar 1)` returns `1` — the pattern variable `x` in `bar`'s
rule captures the argument instead of the outer `y` being substituted.

## Root cause

When `foo` expands `(foo bar x)`:
1. Pattern matching: `bar` matches the keyword, `y` matches `x`
2. Template instantiation produces: `(define-syntax bar (syntax-rules () ((bar x) 'y)))`
3. The `y` in `'y` should be substituted with the matched value (symbol `x`)
4. But the `x` in `(bar x)` is inside a nested `syntax-rules` pattern — it's
   a pattern variable for `bar`, not for `foo`

The issue: during template instantiation of `foo`, the expander walks the
entire template including the nested `syntax-rules` form. It substitutes
`y` → `x` in `'y`, which is correct. But it also sees `x` in `(bar x)` and
treats it as a regular symbol (not a pattern variable of the inner macro),
which may interfere with the inner macro's pattern.

In a correct implementation, the nested `syntax-rules` form's patterns and
templates should be treated opaquely — `foo`'s expander should only
substitute its own pattern variables (`y`) and not touch `x` which belongs
to the inner macro's pattern space.

## Analysis

This is a known hard problem in `syntax-rules` implementations. The R7RS
spec (§4.3.2) says pattern variables are scoped to their `syntax-rules`
form. A macro-generating macro requires the outer expander to understand
that the inner `syntax-rules`'s patterns introduce their own bindings.

The current expander (`src/expander.zig`) treats `syntax-rules` forms in
templates as ordinary lists — it recursively walks them substituting pattern
variables and renaming identifiers. It doesn't recognize that inner
`syntax-rules` patterns introduce a new binding scope for pattern variables.

## Possible fix

In `instantiateTemplate` (`src/expander.zig:393`), when encountering a
`syntax-rules` form in the template:

1. Detect `(syntax-rules (...) ...)` as a special template form
2. Collect the inner pattern variable names from the inner rules
3. When recursing into the inner templates, exclude the inner pattern
   variables from the outer substitution bindings
4. Only substitute outer bindings that don't conflict with inner patterns

This requires ~20-30 lines in `instantiateTemplate` to handle the
`syntax-rules` case specially.

## Impact

Low. Macro-generating macros are rare in practice. This is a conformance
edge case — all common macro patterns work correctly. The test exercises a
specific interaction between nested `syntax-rules` scoping that most Scheme
programs never use.

## Verification

After fixing:
```scheme
(let ()
 (define-syntax foo
   (syntax-rules ()
     ((foo bar y)
      (define-syntax bar
        (syntax-rules ()
          ((bar x) 'y))))))
 (foo bar x)
 (bar 1))            ;=> x (the symbol, not 1)
```

## Key files

| Component | Location |
|-----------|----------|
| Template instantiation | `src/expander.zig:393` (`instantiateTemplate`) |
| Pattern matching | `src/expander.zig:194` (`matchPattern`) |
| Compiler macro dispatch | `src/compiler.zig:482` |
