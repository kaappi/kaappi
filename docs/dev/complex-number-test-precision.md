# Complex Number Test Precision Mismatch

## Status

**Not yet fixed.** One R7RS test failure in section 6.2 Numbers.

## Failing test

```scheme
(test 0.54030230586814+0.841470984807897i (make-polar 1 1))
```

**Expected:** `0.54030230586814+0.841470984807897i`
**Actual:** `0.5403023058681398+0.8414709848078965i`

The values differ only in the last 2-3 digits of both real and imaginary
parts. Both are correct IEEE 754 `cos(1)` and `sin(1)` — the expected value
in the test has fewer significant digits.

## Root cause

The test framework's approximate comparison (`test-approx=?` in
`lib/chibi/test.sld`) only handles real numbers:

```scheme
(define (test-approx=? a b)
  (or (equal? a b)
      (and (real? a) (real? b)          ; ← only reals!
           (let ((diff (abs (- a b))))
             (<= diff (* 1e-6 (max 1.0 (abs a) (abs b))))))))
```

Complex numbers fail the `(real? a)` check, so the comparison falls through
to `(equal? a b)` which does exact bitwise comparison. The last few digits
differ, so `equal?` returns `#f`.

The `test-equal?` wrapper correctly identifies both values as inexact numbers
and calls `test-approx=?`, but `test-approx=?` doesn't handle the complex
case.

## Fix

Extend `test-approx=?` in `lib/chibi/test.sld` to compare complex numbers
component-wise:

```scheme
(define (test-approx=? a b)
  (or (equal? a b)
      (and (real? a) (real? b)
           (let ((diff (abs (- a b))))
             (<= diff (* 1e-6 (max 1.0 (abs a) (abs b))))))
      (and (complex? a) (complex? b)
           (not (real? a)) (not (real? b))
           (test-approx=? (real-part a) (real-part b))
           (test-approx=? (imag-part a) (imag-part b)))))
```

This recurses into the real and imaginary parts, applying the same 1e-6
relative tolerance to each component separately.

## Impact

Cosmetic. The `make-polar` implementation is correct — `cos(1)` and `sin(1)`
are computed to full IEEE 754 f64 precision. The expected value in the test
was simply written with fewer significant digits.

## Verification

After fixing:
```scheme
(test 0.54030230586814+0.841470984807897i (make-polar 1 1))  ;=> PASS
```

## Key files

| Component | Location |
|-----------|----------|
| test-approx=? | `lib/chibi/test.sld:49-53` |
| test-equal? | `lib/chibi/test.sld:55-59` |
| make-polar | `src/primitives_arithmetic.zig` |
