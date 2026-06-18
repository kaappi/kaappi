# Fixnum Overflow Auto-Promotion to Bignum

## Status

**Fixed.** Added `makeFixnumChecked` helper that checks the i63 range and
auto-promotes to bignum via `gc.allocBignumFromI64`. Applied at all
arithmetic result sites (+, -, *, /, quotient, abs).

## Problem

Fixnums are 63-bit signed integers (range: -2^62 to 2^62-1). Values are
stored as `i64` internally via `toFixnum()`, and results are packed back with
`makeFixnum()`. The overflow detection uses Zig's `@addWithOverflow` etc. on
`i64`, which only fires at the `i64` boundary (2^63), not the `i63` boundary
(2^62). Results in the gap [2^62, 2^63-1] silently wrap when encoded.

```scheme
(+ 4611686018427387903 1)   ;=> -4611686018427387904  (WRONG: should be 4611686018427387904)
(* 2305843009213693952 2)   ;=> -4611686018427387904  (WRONG: wraps at i63 boundary)
(/ -4611686018427387904 -1) ;=> -4611686018427387904  (WRONG: negation of minInt(i63) overflows)
(expt 2 62)                 ;=> 4611686018427387904   (CORRECT: uses bignum path)
```

This causes 2 of the 4 remaining R7RS test failures:
```
FAIL [6.2 Numbers]: expected 4611686018427387904 got -4611686018427387904  (division)
FAIL [6.2 Numbers]: expected 4611686018427387904 got -4611686018427387904  (quotient)
```

## Root cause by operation

### Addition (`+`) — `src/primitives_arithmetic.zig:213-289`

Uses `@addWithOverflow(sum, types.toFixnum(a))` on the `i64` accumulator.
Detects i64 overflow and falls back to `bignumAddAll`. But `sum` can exceed
i63 without exceeding i64, so `makeFixnum(sum)` wraps.

### Subtraction (`-`) — `src/primitives_arithmetic.zig:291-381`

Same pattern: `@subWithOverflow` on i64. Negation of `minInt(i63)` produces
`2^62` which fits i64 but overflows i63.

### Multiplication (`*`) — `src/primitives_arithmetic.zig:383-452`

Same pattern: `@mulWithOverflow` on i64. `2^61 * 2 = 2^62` fits i64 but not
i63.

### Division (`/`, `quotient`) — `src/primitives_arithmetic.zig:454-571`

No overflow detection at all for exact integer division. `(-2^62) / (-1) =
2^62` overflows fixnum silently. `@divTrunc` on i64 succeeds, `makeFixnum`
wraps.

### Exponentiation (`expt`) — `src/primitives_numeric.zig:210-225`

Already correct: always uses `bignum_mod.expt()` which operates on bignums
internally and demotes via `makeBignumValue()` only when the result fits i63.

## Recommended fix

### Step 1: Add an i63-range check helper

```zig
// In primitives_arithmetic.zig or a shared location
fn fitsFixnum(n: i64) bool {
    return n >= std.math.minInt(i63) and n <= std.math.maxInt(i63);
}

fn makeFixnumOrBignum(gc: *memory.GC, n: i64) !Value {
    if (fitsFixnum(n)) return types.makeFixnum(n);
    return bignum_mod.fromI64(gc, n);
}
```

### Step 2: Replace `makeFixnum` with `makeFixnumOrBignum` at overflow sites

**Addition** (line ~284): After the i64 accumulator loop, check with
`fitsFixnum(sum)` before calling `makeFixnum`.

**Subtraction** (lines ~369, ~376): Same pattern.

**Multiplication** (line ~447): Same pattern.

**Division/quotient**: Add an explicit check after `@divTrunc`:
```zig
const result = @divTrunc(a, b);
if (!fitsFixnum(result)) return bignum_mod.fromI64(gc, result);
return types.makeFixnum(result);
```

### Step 3: Fix rational arithmetic fallback

Lines 251-265, 336-348, 421-436 in `primitives_arithmetic.zig` fall back to
**float** on intermediate overflow during rational computation. These should
fall back to bignum rational instead, preserving exactness.

### Step 4: Add `bignum.fromI64`

The bignum module needs a helper to create a bignum from an i64 value that
doesn't fit in i63:

```zig
pub fn fromI64(gc: *memory.GC, n: i64) !Value {
    const positive = n >= 0;
    const magnitude: u64 = if (positive) @intCast(n) else @intCast(-n);
    // allocate single-limb bignum with magnitude
    ...
}
```

Note: `bignum_mod.expt` already has working promotion logic. The pattern in
`makeBignumValue` (line 702-714) checks against `maxInt(i63)` — this is
correct. The fix is about ensuring arithmetic operations USE this path instead
of wrapping with `makeFixnum`.

## Affected operations and their current status

| Operation | Overflow check | Fallback | Status |
|-----------|---------------|----------|--------|
| `+` | `@addWithOverflow` (i64) | bignum (i64 only) | Wraps at i63 boundary |
| `-` | `@subWithOverflow` (i64) | bignum (i64 only) | Wraps at i63 boundary |
| `*` | `@mulWithOverflow` (i64) | bignum (i64 only) | Wraps at i63 boundary |
| `/` | None | None | Wraps silently |
| `quotient` | None | None | Wraps silently |
| `remainder` | N/A | N/A | Cannot overflow |
| `modulo` | N/A | N/A | Cannot overflow |
| `expt` | Bignum throughout | bignum | Correct |
| `square` | `@mulWithOverflow` (i64) | bignum (i64 only) | Wraps at i63 boundary |
| `abs` | None | None | Wraps for minInt(i63) |

## Verification

After fixing:
```scheme
(+ 4611686018427387903 1)       ;=> 4611686018427387904 (bignum)
(* 2305843009213693952 2)       ;=> 4611686018427387904 (bignum)
(/ -4611686018427387904 -1)     ;=> 4611686018427387904 (bignum)
(quotient -4611686018427387904 -1) ;=> 4611686018427387904 (bignum)
(- 0 -4611686018427387904)      ;=> 4611686018427387904 (bignum)
(fixnum? (+ 4611686018427387903 1)) ;=> #f (should be bignum)
(integer? (+ 4611686018427387903 1)) ;=> #t
```

Run `zig build test` and then:
```bash
zig build run -- tests/scheme/r7rs/r7rs-tests.scm
```
The two "expected 4611686018427387904" failures should resolve.

## Complexity

Low-medium. The change is mechanical — replace ~8 `makeFixnum(result)` calls
with a checked version. The `bignum.fromI64` helper is straightforward.
Rational arithmetic fallback (step 3) is optional and more involved.
