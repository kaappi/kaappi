;; Regression test for #841: quotient/remainder/modulo/gcd panic on
;; mixed bignum + flonum arguments; non-numbers yield garbage.

(import (scheme base) (scheme write))

(define big (expt 2 100))
(define pass #t)

(define (fail . args)
  (display "FAIL ")
  (for-each display args)
  (newline)
  (set! pass #f))

;; Mixed bignum + flonum must not panic and must return inexact values.
;; Use (expt 2 48) = 281474976710656 which is a bignum (>2^47 fixnum range)
;; but fits exactly in f64.
(define b48 (expt 2 48))

(let ((r (quotient b48 4.0)))
  (unless (and (inexact? r) (= r 70368744177664.0))
    (fail "quotient b48/4.0: " r)))

(let ((r (quotient 1.0e15 b48)))
  (unless (and (inexact? r) (= r 3.0))
    (fail "quotient 1e15/b48: " r)))

(let ((r (remainder b48 5.0)))
  (unless (and (inexact? r) (= r 1.0))
    (fail "remainder b48/5.0: " r)))

(let ((r (modulo b48 5.0)))
  (unless (and (inexact? r) (= r 1.0))
    (fail "modulo b48/5.0: " r)))

(let ((r (gcd b48 6.0)))
  (unless (and (inexact? r) (= r 2.0))
    (fail "gcd b48 6.0: " r)))

;; Large bignum + flonum (tests the 2^100 case from the issue)
(let ((r (quotient big 3.0)))
  (unless (inexact? r)
    (fail "quotient big/3.0 not inexact: " r)))

(let ((r (remainder big 3.0)))
  (unless (inexact? r)
    (fail "remainder big/3.0 not inexact: " r)))

(let ((r (modulo big 3.0)))
  (unless (inexact? r)
    (fail "modulo big/3.0 not inexact: " r)))

(let ((r (gcd big 6.0)))
  (unless (inexact? r)
    (fail "gcd big 6.0 not inexact: " r)))

;; Non-number arguments should raise an error, not produce garbage
(define (expect-error name thunk)
  (guard (e (#t #t))
    (thunk)
    (fail name " should have raised an error")))

(expect-error "quotient string" (lambda () (quotient "a" 2)))
(expect-error "remainder string" (lambda () (remainder 2 "b")))
(expect-error "modulo string" (lambda () (modulo "a" "b")))
(expect-error "gcd string" (lambda () (gcd "a" 2)))
(expect-error "quotient bignum+string" (lambda () (quotient big "a")))
(expect-error "remainder bignum+string" (lambda () (remainder "a" big)))
(expect-error "modulo bignum+string" (lambda () (modulo big "a")))
(expect-error "gcd bignum+string" (lambda () (gcd big "a")))

(if pass
    (display "All tests passed\n")
    (begin (display "SOME TESTS FAILED\n") (exit 1)))
