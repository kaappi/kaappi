;; SRFI-270 (Hexadecimal Floating-Point Constants) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi270.scm
;;
;; The reader syntax and string->number extension are implemented directly
;; in the engine (src/reader_tokens.zig, src/bignum.zig); write-hexadecimal-
;; float is the one portable procedure the spec adds. See lib/srfi/270.sld's
;; header for the split.

(import (scheme base) (scheme process-context) (srfi 270) (srfi 64))

(test-begin "srfi-270")

;;; --- reader syntax: the spec's own worked examples ---

(test-equal "reader: #x9p9 = 9*2^9" 4608.0 #x9p9)
(test-equal "reader: #x1.2p3 = 9" 9.0 #x1.2p3)
(test-equal "reader: #x-0.Ap-2 = -5/32" -0.15625 #x-0.Ap-2)
(test-equal "reader: #xFE.FF, no p (exponent defaults to 0)" 254.99609375 #xFE.FF)
(test-equal "reader: pi example from the spec" 3.141592653589793 #x1.921fb54442d18p1)
(test-equal "reader: integer part only, no fraction" 8.0 #x1p3)
(test-equal "reader: fraction only, no integer part" 0.625 #x.ap0)
(test-assert "reader: hex float is inexact by default" (inexact? #x1.2p3))
(test-equal "reader: #e forces exact" 9 #e#x1.2p3)
(test-equal "reader: #i on an ordinary hex integer forces inexact" 26.0 #i#x1a)

;;; --- string->number must also understand hex floats ---

(test-equal "string->number: #x-prefixed hex float" 9.0 (string->number "#x1.2p3"))
(test-equal "string->number: radix-16 argument, hex float" 9.0 (string->number "1.2p3" 16))
(test-equal "string->number: radix-16, negative, exponent" -0.15625 (string->number "-0.Ap-2" 16))
(test-equal "string->number: radix-16, no fraction, has exponent" 4608.0 (string->number "9p9" 16))
(test-equal "string->number: still #f for garbage" #f (string->number "not-a-number" 16))
(test-equal "string->number: ordinary hex integers still work" 26 (string->number "1a" 16))

;; Regression: a hex float whose mantissa overflows i64 as a plain integer
;; used to fall into the bignum-overflow fallback, which doesn't
;; understand '.'/'p' and returned #f for an otherwise-valid hex float.
(test-equal "string->number: hex float with an i64-overflowing mantissa"
  (expt 16.0 17)
  (string->number "#x100000000000000000.0p0"))
(test-assert "string->number: hex float with an overflowing mantissa matches the reader"
  (= (string->number "#x123456789abcdef01234.5p3") #x123456789abcdef01234.5p3))
(test-equal "string->number: radix-16 argument, overflowing mantissa"
  (expt 16.0 17)
  (string->number "100000000000000000.0p0" 16))

;; Regression: a pathologically long exponent digit run used to overflow
;; the i32 accumulator and panic (a real crash, not just a wrong answer)
;; in the default ReleaseSafe build. A digit run this long is always
;; semantically equivalent to +inf.0/0.0 anyway (any exponent magnitude
;; past ~1075 already saturates), so capping the accumulator changes no
;; correct answer, only prevents the crash.
(test-equal "reader: pathologically large positive exponent saturates instead of crashing"
  +inf.0 #x1p99999999999999)
(test-equal "reader: pathologically large negative exponent saturates instead of crashing"
  0.0 #x1p-99999999999999)
(test-equal "string->number: pathologically large positive exponent"
  +inf.0 (string->number "1p99999999999999" 16))
(test-equal "string->number: pathologically large negative exponent"
  0.0 (string->number "1p-99999999999999" 16))
;; A large but non-pathological exponent, comfortably below the cap,
;; must still be computed exactly rather than also saturating.
(test-equal "reader: a large but sane exponent is still exact" 1.0715086071862673e+301 #x1p1000)
(test-equal "reader: a large but sane negative exponent is still exact" 9.332636185032189e-302 #x1p-1000)

;;; --- write-hexadecimal-float: round-trips through the reader ---

(define (hex-float->string x)
  (let ((port (open-output-string)))
    (write-hexadecimal-float x port)
    (get-output-string port)))

(define (roundtrips? x) (eqv? x (string->number (hex-float->string x) 16)))

(test-assert "round-trip: 9.0" (roundtrips? 9.0))
(test-assert "round-trip: pi" (roundtrips? 3.141592653589793))
(test-assert "round-trip: a negative value" (roundtrips? -0.15625))
(test-assert "round-trip: an exact power of two" (roundtrips? 8.0))
(test-assert "round-trip: a value needing a full mantissa" (roundtrips? 100.5))
(test-assert "round-trip: the smallest positive subnormal double" (roundtrips? (expt 2.0 -1074)))
(test-assert "round-trip: a negative subnormal" (roundtrips? (- (expt 2.0 -1030))))
(test-assert "round-trip: zero" (roundtrips? 0.0))

;; Zero and negative zero must format distinguishably, with the correct
;; spec-mandated zero exponent.
(test-equal "write: 0.0" "0.0p0" (hex-float->string 0.0))
(test-equal "write: -0.0" "-0.0p0" (hex-float->string -0.0))

;; Normal numbers normalize to integer part 1; subnormals to integer part 0.
(test-equal "write: normal number has integer part 1" "1.2p3" (hex-float->string 9.0))
(test-assert "write: subnormal has integer part 0"
  (let ((s (hex-float->string (expt 2.0 -1074))))
    (char=? (string-ref s 0) #\0)))

;; NaN/infinity print as ordinary Scheme syntax, per spec.
(test-equal "write: +nan.0" "+nan.0" (hex-float->string +nan.0))
(test-equal "write: +inf.0" "+inf.0" (hex-float->string +inf.0))
(test-equal "write: -inf.0" "-inf.0" (hex-float->string -inf.0))

;; Complex numbers: each component follows the same rules.
(test-equal "write: a complex number" "1.8p1+1p2i" (hex-float->string 3.0+4.0i))

(let ((runner (test-runner-current)))
  (test-end "srfi-270")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
