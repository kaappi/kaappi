;; Audit v2, Phase 1A -- `#e`/`#i` exactness across the i64 boundary, and
;; reader vs `string->number` parity.
;;
;; Oracles (quoted, not remembered):
;;
;;   R7RS 6.2.5, p.34 -- "A numerical constant can be specified to be either
;;   exact or inexact by a prefix.  The prefixes are #e for exact, and #i for
;;   inexact.  An exactness prefix can appear before or after any radix prefix
;;   that is used."
;;
;;   R7RS 6.2.7, p.40 -- "The rules used by a particular implementation for
;;   string->number must also be applied to read and to the routine that reads
;;   programs, in order to maintain consistency between internal numeric
;;   processing, I/O, and the processing of programs."
;;
;;   R7RS 7.1.1, p.62 -- "There are no rules for <decimal 2>, <decimal 8>, and
;;   <decimal 16>, which means that numbers containing decimal points or
;;   exponents are always in decimal radix."
;;
;;   R7RS 6.2.3, p.33 -- an implementation that cannot represent an exact
;;   constant "may either report a violation of an implementation restriction
;;   or it may silently represent the constant by an inexact number".  Kaappi
;;   has bignums and exact rationals, so the constants below ARE representable
;;   and this escape hatch does not apply.
;;
;; Every disabled assertion below was reproduced against a fresh ReleaseSafe
;; build with an isolated KAAPPI_HOME.  Each disabled group carries a
;; discriminating control that stays ENABLED, so the file keeps proving that
;; the neighbouring path still works.
;;
;; NOTE: numbers whose reading crashes the process are exercised only through
;; `(read (open-input-string ...))`, never as source literals, so that
;; re-enabling a test cannot abort the whole suite at read time.

;; `(scheme inexact)` is declared for finite?/infinite?/nan?.  They resolve at
;; top level even without it -- a script reaches vm.globals directly -- so
;; omitting it would still run green here while failing inside a library body.
;; Declare it rather than rely on that ambient reachability (see kaappi#1831).
(import (scheme base) (scheme inexact) (scheme write) (scheme complex)
        (scheme process-context) (srfi 64))

(test-begin "reader-exactness-gaps")

(define (rd s) (read (open-input-string s)))
(define (rd/safe s) (guard (e (#t 'read-error)) (read (open-input-string s))))
(define (wr x) (let ((p (open-output-string))) (write x p) (get-output-string p)))
(define (round-trips? x) (let ((y (rd/safe (wr x)))) (and (number? y) (equal? x y))))

;; ---------------------------------------------------------------------------
;; 1. Baseline: the exactness prefixes work at all, in both directions.
;; ---------------------------------------------------------------------------

(test-assert "#e on an integer is exact"        (exact? (rd "#e42")))
(test-assert "#i on an integer is inexact"      (inexact? (rd "#i42")))
(test-assert "#e on a decimal is exact"         (exact? (rd "#e1.5")))
(test-assert "#i on a decimal is inexact"       (inexact? (rd "#i1.5")))
(test-assert "#e on a rational is exact"        (exact? (rd "#e1/3")))
(test-assert "#i on a rational is inexact"      (inexact? (rd "#i1/3")))
(test-equal  "#e3.0 is 3 (R7RS 6.2.6 example)"  3 (rd "#e3.0"))
(test-assert "(exact? #e3.0) (R7RS 6.2.6)"      (exact? (rd "#e3.0")))
(test-assert "(real? #e1e10) (R7RS 6.2.6)"      (real? (rd "#e1e10")))

;; R7RS 6.2.5: "An exactness prefix can appear before or after any radix
;; prefix".  All eight orderings agree between the two parsers.
(test-equal "#e#x10" 16 (rd "#e#x10"))
(test-equal "#x#e10" 16 (rd "#x#e10"))
(test-equal "#i#x10" 16.0 (rd "#i#x10"))
(test-equal "#x#i10" 16.0 (rd "#x#i10"))
(test-assert "#e#x10 exact"   (exact? (rd "#e#x10")))
(test-assert "#x#e10 exact"   (exact? (rd "#x#e10")))
(test-assert "#i#x10 inexact" (inexact? (rd "#i#x10")))
(test-assert "#x#i10 inexact" (inexact? (rd "#x#i10")))
(test-equal "#e#x10 = string->number" (rd "#e#x10") (string->number "#e#x10"))
(test-equal "#x#e10 = string->number" (rd "#x#e10") (string->number "#x#e10"))
(test-equal "#i#x10 = string->number" (rd "#i#x10") (string->number "#i#x10"))
(test-equal "#x#i10 = string->number" (rd "#x#i10") (string->number "#x#i10"))

;; R7RS 7.1.1: exponents/decimal points are decimal-radix only, so the `e` in
;; `#x1e5` is a hex DIGIT, not an exponent marker.
(test-equal "#x1e5 is hex 0x1e5, not 1e5" 485 (rd "#x1e5"))
(test-equal "#x1e5 = string->number"      485 (string->number "#x1e5"))

;; ---------------------------------------------------------------------------
;; 2. `#e` at and beyond the i64 boundary.
;;
;;    Known bug #1891: the flonum->exact conversion in reader_tokens.zig
;;    `applyExactness` bails out to the unconverted flonum once the value
;;    exceeds i64 range, so the `#e` prefix is silently dropped.
;; ---------------------------------------------------------------------------

;; Controls: below the cliff `#e` works, in both signs.
(test-assert "#e1e17 is exact"  (exact? (rd "#e1e17")))
(test-assert "#e1e18 is exact"  (exact? (rd "#e1e18")))
(test-assert "#e-1e18 is exact" (exact? (rd "#e-1e18")))
(test-equal  "#e1e18 value"  1000000000000000000 (rd "#e1e18"))
(test-equal  "#e-1e18 value" -1000000000000000000 (rd "#e-1e18"))
;; Control: a plain bignum literal (no prefix, no exponent) is exact.
(test-assert "bignum literal is exact" (exact? (rd "10000000000000000000")))
(test-assert "#e on a bignum literal stays exact"
             (exact? (rd "#e10000000000000000000")))

;; FAIL: #1891 (#e1e19 reads inexact -- exactness prefix dropped past i64)
;; (test-assert "#e1e19 is exact" (exact? (rd "#e1e19")))
;; FAIL: #1891 (#e1e20 reads inexact)
;; (test-assert "#e1e20 is exact" (exact? (rd "#e1e20")))
;; FAIL: #1891 (#e-1e19 reads inexact -- same cliff, negative side)
;; (test-assert "#e-1e19 is exact" (exact? (rd "#e-1e19")))
;; FAIL: #1891 (#e1e19 value)
;; (test-equal "#e1e19 value" 10000000000000000000 (rd "#e1e19"))
;; FAIL: #1891 (#e1e400 yields +inf.0 -- an exactness prefix producing infinity)
;; (test-assert "#e1e400 is exact" (exact? (rd "#e1e400")))
;; FAIL: #1891 (#e1e400 must not be infinite)
;; (test-assert "#e1e400 is finite" (finite? (rd "#e1e400")))

;; R7RS 6.2.7 parity: string->number gets all of these RIGHT, which is what
;; makes the divergence a 6.2.7 violation rather than a shared limitation.
(test-assert "string->number #e1e19 is exact"  (exact? (string->number "#e1e19")))
(test-assert "string->number #e1e400 is exact" (exact? (string->number "#e1e400")))
(test-equal  "string->number #e1e19 value"
             10000000000000000000 (string->number "#e1e19"))
;; FAIL: #1891 (6.2.7 consistency: read and string->number must agree)
;; (test-equal "read/string->number agree on #e1e19"
;;             (rd "#e1e19") (string->number "#e1e19"))

;; ---------------------------------------------------------------------------
;; 3. NEW: reader panic on `#e<decimal that rounds to exactly 2^63>`.
;;
;;    reader_tokens.zig guards the conversion with `f > max_i64_f`, where
;;    max_i64_f is @floatFromInt(maxInt(i64)) -- which rounds UP to 2^63.  A
;;    value of exactly 2^63 therefore passes the guard and then overflows
;;    @intFromFloat, panicking with "integer part of floating point value out
;;    of bounds" (exit 134).  minInt(i64) = -2^63 is exactly representable, so
;;    the negative side is unaffected -- hence the asymmetry below.
;;
;;    This also aborts `kaappi check` and `kaappi fmt --check`, i.e. tools that
;;    never execute the program.
;; ---------------------------------------------------------------------------

;; Controls: the neighbouring doubles on both sides are fine.
(test-equal "#e just below 2^63 (rounds to 2^63-1024)"
            9223372036854774784 (rd "#e9223372036854774784.0"))
(test-assert "#e just above 2^63 stays finite"
             (finite? (rd "#e9223372036854777856.0")))
(test-equal "#e at -2^63 (negative side is unaffected)"
            -9223372036854775808 (rd "#e-9223372036854775808.0"))
;; Control: the same magnitude without `.0` takes the integer path, not the
;; flonum path, and is correct.
(test-equal "#e2^63 as an integer literal is exact and correct"
            9223372036854775808 (rd "#e9223372036854775808"))
;; Control: `#i` on the same text is fine -- it is the `#e` conversion only.
(test-assert "#i2^63 is fine" (inexact? (rd "#i9223372036854775808.0")))
;; Control: the runtime `exact` procedure handles the identical value.
(test-equal "(exact 2^63) is correct at runtime"
            9223372036854775808 (exact 9223372036854775808.0))
;; Control: string->number does not crash on the text that panics the reader.
;; It currently returns #f, which is itself non-conforming -- don't pin that as
;; correct, or fixing it looks like a regression here.  Assert only the property
;; this control exists to establish: no crash.
(test-assert "string->number does not crash on the same text"
             (let ((v (string->number "#e9223372036854775808.0")))
               (or (not v) (number? v))))

;; FAIL: #1907 (reader panics: #e<double == 2^63> overflows @intFromFloat)
;; (test-equal "#e2^63 as a decimal float" 9223372036854775808
;;             (rd "#e9223372036854775808.0"))
;; FAIL: #1907 (same panic -- lowest decimal that rounds up to 2^63)
;; (test-equal "#e lowest double rounding to 2^63" 9223372036854775808
;;             (rd "#e9223372036854775296.0"))
;; FAIL: #1907 (same panic via exponent notation)
;; (test-equal "#e2^63 via exponent" 9223372036854775808
;;             (rd "#e9.223372036854776e18"))

;; ---------------------------------------------------------------------------
;; 4. NEW: `#i` on a radix-prefixed BIGNUM reinterprets its digits as decimal.
;;
;;    reader_tokens.zig's `.bignum_str` arm of the inexact path calls
;;    parseFloat on the raw digit slice without consulting `bs.radix`.  The
;;    adjacent `.big_rational` arm DOES check the radix, and the comment above
;;    `.bignum_str` even asserts the invariant the code fails to enforce.
;;
;;    Silent wrong answers when the digits happen to be decimal-valid, and a
;;    spurious read error when they are not (hex a-f).
;; ---------------------------------------------------------------------------

;; Controls: without `#i`, every radix reads the bignum correctly.
(test-equal "#x bignum (no #i)" 4722366482869645213696 (rd "#x1000000000000000000"))
(test-equal "#o bignum (no #i)" 590295810358705651712
            (rd "#o100000000000000000000000"))
(test-equal "#b bignum (no #i)" 36893488147419103231
            (rd "#b11111111111111111111111111111111111111111111111111111111111111111"))
(test-equal "#x bignum with letters (no #i)" 4722366482869645213695
            (rd "#xFFFFFFFFFFFFFFFFFF"))
;; Control: below the i64 boundary the fixnum arm is used and `#i` is correct.
(test-equal "#i#xFF (fixnum arm)"  255.0 (rd "#i#xFF"))
(test-equal "#i#b1010 (fixnum arm)" 10.0 (rd "#i#b1010"))
(test-equal "#i#o777 (fixnum arm)" 511.0 (rd "#i#o777"))
;; Control: radix 10 bignums go through parseFloat legitimately.
(test-equal "#i on a decimal bignum" 1e19 (rd "#i10000000000000000000"))
(test-equal "#i#d on a decimal bignum" 1e19 (rd "#i#d10000000000000000000"))
;; Control: string->number gets every one of these right.
(test-equal "string->number #i#x bignum"
            4.722366482869645e21 (string->number "#i#x1000000000000000000"))
(test-equal "string->number #i#x bignum with letters"
            4.722366482869645e21 (string->number "#i#xFFFFFFFFFFFFFFFFFF"))

;; FAIL: #1908 (#i#x<bignum> parses hex digits as decimal: gives 1e18, want ~4.72e21)
;; (test-equal "#i#x bignum" 4.722366482869645e21 (rd "#i#x1000000000000000000"))
;; FAIL: #1908 (#i#b<bignum> parses binary digits as decimal: gives 1.111...e64)
;; (test-equal "#i#b bignum" 3.6893488147419103e19
;;             (rd "#i#b11111111111111111111111111111111111111111111111111111111111111111"))
;; FAIL: #1908 (#i#o<bignum> parses octal digits as decimal: gives 1.0e23)
;; (test-equal "#i#o bignum" 5.902958103587057e20
;;             (rd "#i#o100000000000000000000000"))
;; FAIL: #1908 (#i#x<bignum with a-f> raises a spurious read error)
;; (test-equal "#i#x bignum with letters" 4.722366482869645e21
;;             (rd "#i#xFFFFFFFFFFFFFFFFFF"))
;; FAIL: #1908 (#i on a radix-prefixed bignum RATIONAL raises a spurious read error)
;; (test-assert "#i#x bignum rational"
;;              (inexact? (rd "#i#x1000000000000000000/3")))

;; Control for the rational case: `#e` on the same text is correct.
(test-equal "#e#x bignum rational" 4722366482869645213696/3
            (rd "#e#x1000000000000000000/3"))

;; ---------------------------------------------------------------------------
;; 5. NEW: `#e` on a decimal below 1e-15 collapses to exact ZERO.
;;
;;    The continued-fraction conversion in reader_tokens.zig terminates on
;;    ABSOLUTE tolerances (`< 1e-15`).  For a magnitude below that tolerance
;;    the very first iteration already "converges", yielding 0/1.  The whole
;;    value is lost.  At exactly 1e-15 the same tolerance produces an
;;    off-by-one denominator.
;;
;;    This is the opposite end of the number line from #1891, and a different
;;    mechanism: nothing here overflows anything.
;; ---------------------------------------------------------------------------

;; Controls: down to 1e-14 the conversion is exact and correct.
(test-equal "#e1e-13" 1/10000000000000 (rd "#e1e-13"))
(test-equal "#e1e-14" 1/100000000000000 (rd "#e1e-14"))
(test-equal "#e0.1"   1/10 (rd "#e0.1"))
(test-equal "#e0.5"   1/2 (rd "#e0.5"))
(test-equal "#e3.14159" 314159/100000 (rd "#e3.14159"))
(test-equal "#e-2.25" -9/4 (rd "#e-2.25"))
(test-equal "#e0.0"   0 (rd "#e0.0"))
;; Control: string->number is correct all the way down.
(test-equal "string->number #e1e-16"
            1/10000000000000000 (string->number "#e1e-16"))
(test-equal "string->number #e1e-19"
            1/10000000000000000000 (string->number "#e1e-19"))
;; Control: the runtime `exact` procedure keeps the value (different algorithm).
(test-assert "(exact 1e-19) is not zero" (not (zero? (exact 1e-19))))
(test-assert "(exact 1e-30) is not zero" (not (zero? (exact 1e-30))))

;; FAIL: #1909 (#e1e-16 collapses to exact 0 -- entire value lost)
;; (test-assert "#e1e-16 is not zero" (not (zero? (rd "#e1e-16"))))
;; FAIL: #1909 (#e1e-19 collapses to exact 0)
;; (test-assert "#e1e-19 is not zero" (not (zero? (rd "#e1e-19"))))
;; FAIL: #1909 (#e1e-30 collapses to exact 0)
;; (test-assert "#e1e-30 is not zero" (not (zero? (rd "#e1e-30"))))
;; FAIL: #1909 (#e-1e-20 collapses to exact 0, sign lost too)
;; (test-assert "#e-1e-20 is negative" (negative? (rd "#e-1e-20")))
;; FAIL: #1909 (#e1.5e-18 collapses to exact 0)
;; (test-assert "#e1.5e-18 is not zero" (not (zero? (rd "#e1.5e-18"))))
;; FAIL: #1909 (#e1e-15 off-by-one denominator: gives 1/999999999999999)
;; (test-equal "#e1e-15" 1/1000000000000000 (rd "#e1e-15"))
;; FAIL: #1909 (#e0.000000000000001 off-by-one denominator)
;; (test-equal "#e0.000000000000001" 1/1000000000000000 (rd "#e0.000000000000001"))
;; FAIL: #1909 (6.2.7 consistency for the tiny end)
;; (test-equal "read/string->number agree on #e1e-16"
;;             (rd "#e1e-16") (string->number "#e1e-16"))

;; ---------------------------------------------------------------------------
;; 6. NEW: `#i` on a COMPLEX literal is a no-op in the reader.
;;
;;    reader_tokens.zig's inexact path passes `.complex` tokens through
;;    untouched, so the prefix is silently ignored.
;;
;;    Both copies of `applyExactness` have a Complex hole, in complementary
;;    places -- see the table in section 8.  Closed issue #751 covers the
;;    string->number half; its fix wired the four complex call sites through
;;    applyExactness, but that function has no Complex arm in EITHER direction
;;    (primitives_numeric.zig -- the `.inexact` and `.exact` branches both fall
;;    through to a bare `return val`), so the prefix is still dropped.
;; ---------------------------------------------------------------------------

;; Controls: `#i` works on every non-complex shape, and the runtime `inexact`
;; procedure does convert a complex.
(test-assert "#i1 is inexact"          (inexact? (rd "#i1")))
(test-assert "#i1/2 is inexact"        (inexact? (rd "#i1/2")))
(test-assert "1+2i is exact"           (exact? (rd "1+2i")))
(test-assert "(inexact 1+2i) is inexact" (inexact? (inexact (rd "1+2i"))))
(test-assert "1.5+2.5i is inexact"     (inexact? (rd "1.5+2.5i")))

;; FAIL: #1910 (#i on a complex literal is ignored: (exact? #i1+2i) => #t)
;; (test-assert "#i1+2i is inexact" (inexact? (rd "#i1+2i")))
;; FAIL: #1910 (#i on a complex literal is ignored)
;; (test-assert "#i3+4i is inexact" (inexact? (rd "#i3+4i")))

;; ---------------------------------------------------------------------------
;; 7. NEW: `#e` on a complex whose component exceeds i64 yields an unreadable
;;    `0/0`.
;;
;;    reader_tokens.zig's `.complex` arm of the exact path sets both exactness
;;    flags with NO range check at all, so the printer later renders the
;;    out-of-range component as the rational `0/0`.  That external
;;    representation does not read back: bare `0/0` is a read error, and inside
;;    a complex it comes back as `+nan.0`.
;;
;;    This is the only round-trip failure across the whole matrix (section 9).
;; ---------------------------------------------------------------------------

;; Controls: within i64 the same shapes are correct and DO round-trip.
(test-equal  "#e1.5+2.5i" 3/2+5/2i (rd "#e1.5+2.5i"))
(test-assert "#e1.5+2.5i round-trips" (round-trips? (rd "#e1.5+2.5i")))
(test-assert "#e1e18+1i round-trips"  (round-trips? (rd "#e1e18+1i")))
(test-assert "bare 0/0 is a read error" (eq? 'read-error (rd/safe "0/0")))

;; FAIL: #1910 (#e1e19+1i prints as 0/0+1i and reads back as +nan.0+1i)
;; (test-assert "#e1e19+1i round-trips" (round-trips? (rd "#e1e19+1i")))

;; ---------------------------------------------------------------------------
;; 8. R7RS 6.2.7 parity: `read` and `string->number` are two independent
;;    parsers, and they disagree.
;;
;;    There are two separate `applyExactness` implementations --
;;    `reader_tokens.zig:393` (read / the program reader) and
;;    `primitives_numeric.zig:979` (string->number) -- with different
;;    strategies.  string->number reconstructs the value from the decimal
;;    digits exactly (mantissa x 10^scale, via bignum); the reader parses to
;;    f64 FIRST and then tries to un-round it with a tolerance-based continued
;;    fraction.  That structural difference is why the reader loses at both
;;    ends of the range (sections 2, 3 and 5) while string->number does not.
;;
;;    Historical fixes have landed in one copy at a time:
;;
;;      issue | fixed in           | still live in
;;      ------+--------------------+---------------------------------------
;;      #79   | reader_tokens      | (guard added, but off by one -- sec. 3)
;;      #604  | primitives_numeric | --
;;      #419  | primitives_numeric | reader_tokens (`#e+inf.0` => +inf.0)
;;      #751  | primitives_numeric | fix incomplete -- no Complex arm at all
;;      #1891 | --                 | reader_tokens
;;
;;    Beyond the divergences already covered above, these cells disagree on
;;    their own:
;;      - `#e+inf.0` / `#e-inf.0` / `#e+nan.0`: read yields the inexact
;;        infinity/NaN, string->number yields #f.  #419 settled that #f is the
;;        intended answer, so the reader is the side that is wrong.
;;      - `#e`/`#i` on a complex: string->number ignores the prefix entirely
;;        (closed #751, fix incomplete); the reader honours `#e` but not `#i`.
;; ---------------------------------------------------------------------------

;; Controls: the parsers agree on the ordinary cases.
(test-equal "parity #e42"    (rd "#e42")    (string->number "#e42"))
(test-equal "parity #i42"    (rd "#i42")    (string->number "#i42"))
(test-equal "parity #e1/3"   (rd "#e1/3")   (string->number "#e1/3"))
(test-equal "parity #i1/3"   (rd "#i1/3")   (string->number "#i1/3"))
(test-equal "parity #e0.1"   (rd "#e0.1")   (string->number "#e0.1"))
(test-equal "parity #e1e18"  (rd "#e1e18")  (string->number "#e1e18"))
(test-equal "parity #x1e5"   (rd "#x1e5")   (string->number "#x1e5"))
(test-equal "parity #i#xFF"  (rd "#i#xFF")  (string->number "#i#xFF"))
(test-equal "parity #x bignum"
            (rd "#x1000000000000000000") (string->number "#x1000000000000000000"))
;; Control: `#i+inf.0` DOES agree -- it is `#e` on an infinity that diverges.
(test-equal "parity #i+inf.0" (rd "#i+inf.0") (string->number "#i+inf.0"))

;; Every divergence above has the reader on the wrong side.  This one inverts
;; it: an UNPREFIXED decimal spelling exactly 2^63 reads correctly but makes
;; string->number return #f.  Same boundary as #1907 and the same
;; negative-side-is-fine asymmetry, but no exactness prefix is involved, so it
;; is not an applyExactness defect -- it is the plain decimal parse path.
;; Controls (enabled, they pass): the neighbouring value, the negative side,
;; and larger magnitudes all agree.
(test-equal "parity 2^63-1 as a decimal"
            (rd "9223372036854775807.0") (string->number "9223372036854775807.0"))
(test-equal "parity -2^63 as a decimal"
            (rd "-9223372036854775808.0") (string->number "-9223372036854775808.0"))
(test-equal "parity 1e19" (rd "1e19") (string->number "1e19"))
(test-equal "parity 1e300" (rd "1e300") (string->number "1e300"))
;; FAIL: #1919 (unprefixed 2^63 decimal: reader ok, string->number gives #f)
;; (test-equal "parity 2^63 as a decimal"
;;             (rd "9223372036854775808.0") (string->number "9223372036854775808.0"))

;; FAIL: #1911 (6.2.7: read gives +inf.0, string->number gives #f)
;; (test-equal "parity #e+inf.0" (rd "#e+inf.0") (string->number "#e+inf.0"))
;; FAIL: #1911 (6.2.7: read gives -inf.0, string->number gives #f)
;; (test-equal "parity #e-inf.0" (rd "#e-inf.0") (string->number "#e-inf.0"))
;; FAIL: #1911 (6.2.7: read gives +nan.0, string->number gives #f)
;; (test-assert "parity #e+nan.0"
;;              (eq? (not (rd "#e+nan.0")) (not (string->number "#e+nan.0"))))
;; FAIL: #1910 (string->number ignores #e on a complex: yields 1.0+2.0i inexact)
;; (test-assert "string->number #e1+2i is exact" (exact? (string->number "#e1+2i")))
;; FAIL: #1910 (string->number ignores #i on a complex: yields 1.0+2.0i either way)
;; (test-equal "parity #i1+2i" (rd "#i1+2i") (string->number "#i1+2i"))

;; ---------------------------------------------------------------------------
;; 9. NEW: an exactness/radix prefix disables the trailing-delimiter check on
;;    the DECIMAL path, so one token silently reads as two datums.
;;
;;    Related to #1892, but that issue is scoped to RADIX prefixes and the
;;    `readIntegerWithRadix` path; these cases need no radix prefix at all and
;;    go through `readNumber`.  A fix confined to the radix path would leave
;;    them live.  The unprefixed spelling correctly raises a read error, which
;;    is the discriminating control.
;; ---------------------------------------------------------------------------

;; Controls: without a prefix, trailing junk IS rejected.
(test-assert "1.5abc is a read error"  (eq? 'read-error (rd/safe "1.5abc")))
(test-assert "12abc is a read error"   (eq? 'read-error (rd/safe "12abc")))
(test-assert "1e19/3 is a read error"  (eq? 'read-error (rd/safe "1e19/3")))
;; Control: string->number rejects all of them.
(test-assert "string->number rejects #e1.5abc" (not (string->number "#e1.5abc")))
(test-assert "string->number rejects #e12abc"  (not (string->number "#e12abc")))
(test-assert "string->number rejects #e1e19/3" (not (string->number "#e1e19/3")))

;; FAIL: #1892 (#e1.5abc reads as 3/2, leaving `abc`; cf. #1892 but decimal path)
;; (test-assert "#e1.5abc is a read error" (eq? 'read-error (rd/safe "#e1.5abc")))
;; FAIL: #1892 (#i1.5abc reads as 1.5, leaving `abc`)
;; (test-assert "#i1.5abc is a read error" (eq? 'read-error (rd/safe "#i1.5abc")))
;; FAIL: #1892 (#e12abc reads as 12, leaving `abc`)
;; (test-assert "#e12abc is a read error" (eq? 'read-error (rd/safe "#e12abc")))
;; FAIL: #1892 (#e12/3xyz reads as 4, leaving `xyz`)
;; (test-assert "#e12/3xyz is a read error" (eq? 'read-error (rd/safe "#e12/3xyz")))
;; FAIL: #1892 (#e1e19/3 drops `/3` entirely; '(#e1e19/3) reads as two datums)
;; (test-assert "#e1e19/3 is a read error" (eq? 'read-error (rd/safe "#e1e19/3")))
;; FAIL: #1892 (#d1e19/3 -- a pure radix-10 prefix triggers it too)
;; (test-assert "#d1e19/3 is a read error" (eq? 'read-error (rd/safe "#d1e19/3")))
;; FAIL: #1892 (one token becomes two datums)
;; (test-equal "(#e1.5abc) is one datum" 1 (length (rd "(#e1.5abc)")))

;; ---------------------------------------------------------------------------
;; 10. Round-trip invariant across the matrix.
;;
;;     The campaign's systematic reader check:
;;       (equal? x (read (open-input-string (write-to-string x))))
;;     Holds on every cell reachable without a panic except `#e1e19+1i`
;;     (section 7).
;; ---------------------------------------------------------------------------

(for-each
 (lambda (s)
   (let ((v (rd/safe s)))
     (test-assert (string-append "round-trip " s)
                  (or (eq? v 'read-error) (round-trips? v)))))
 '("#e1e17" "#e1e18" "#e1e19" "#e1e400" "#e-1e19" "#e0.1" "#e1.5"
   "#e1e-16" "#e1e-19" "#i1" "#i1/2" "#i#xFF" "#i#x1000000000000000000"
   "#e#x10" "#x#e10" "#e+inf.0" "#i+inf.0" "#e1+2i" "#i1+2i" "#e1.5+2.5i"
   "#e+i" "#e10000000000000000000" "#i10000000000000000000"
   "#e9223372036854775807" "#x1e5" "#e1/3" "#i22/7"))

;; FAIL: #1910 (see section 7 -- writes 0/0+1i, reads back +nan.0+1i)
;; (test-assert "round-trip #e1e19+1i" (round-trips? (rd "#e1e19+1i")))

;; ---------------------------------------------------------------------------
;; 11. Confirmed-correct areas, pinned so a future change cannot regress them
;;     silently.
;; ---------------------------------------------------------------------------

;; SRFI 270 hex floats -- deliberate extensions, and both parsers agree.
(test-equal "#x1.8 hex float"      1.5  (rd "#x1.8"))
(test-equal "#x1p4 hex float"      16.0 (rd "#x1p4"))
(test-equal "parity #x1.8" (rd "#x1.8") (string->number "#x1.8"))
(test-equal "parity #x1p4" (rd "#x1p4") (string->number "#x1p4"))

;; Exactness prefixes over rationals in every radix, within i64.
(test-equal "#e#x10/2"    8    (rd "#e#x10/2"))
(test-equal "#i#x10/2"    8.0  (rd "#i#x10/2"))
(test-equal "#i#o777/7"   73.0 (rd "#i#o777/7"))
(test-equal "#e10000000000000000000/3" 10000000000000000000/3
            (rd "#e10000000000000000000/3"))

;; `#i` on exact values of every shape.
(test-equal "#i0"  0.0  (rd "#i0"))
(test-equal "#i-1" -1.0 (rd "#i-1"))
(test-equal "#i on a large bignum" 1e41
            (rd "#i100000000000000000000000000000000000000000"))

;; `#i` on infinities and NaN is a no-op, and agrees with string->number.
(test-assert "#i+inf.0" (and (infinite? (rd "#i+inf.0")) (positive? (rd "#i+inf.0"))))
(test-assert "#i+nan.0" (nan? (rd "#i+nan.0")))

(let ((runner (test-runner-current)))
  (test-end "reader-exactness-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
