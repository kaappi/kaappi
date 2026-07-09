;; SRFI-144 (flonums) conformance tests — audit Phase 3c
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi144.scm

(import (scheme base) (srfi 144) (chibi test))

(test-begin "srfi-144")

;;; --- constants ---
(test #t (< 2.718281 fl-e 2.718282))
(test #t (< 3.141592 fl-pi 3.141593))
(test #t (< 0.318309 fl-1/pi 0.318310))
(test #t (flonum? fl-greatest))
(test #t (> fl-greatest 1e308))
(test #t (> fl-least 0.0))
(test #t (< fl-least 1e-300))
(test #t (< 0.0 fl-epsilon 1e-10))

;;; --- predicates ---
(test #t (flonum? 1.5))
(test #f (flonum? 1))
(test #f (flonum? 1/2))
(test #t (flzero? 0.0))
(test #t (flpositive? 1.0))
(test #t (flnegative? -1.0))
(test #t (flinteger? 2.0))
(test #f (flinteger? 2.5))
(test #t (flfinite? 1.0))
(test #f (flfinite? +inf.0))
(test #t (flinfinite? +inf.0))
(test #f (flinfinite? 1.0))
(test #t (flnan? +nan.0))
(test #f (flnan? 1.0))
(test #t (flodd? 3.0))
(test #t (fleven? 4.0))

;;; --- arithmetic and comparisons ---
(test 5.0 (fl+ 2.0 3.0))
(test -1.0 (fl- 2.0 3.0))
(test 6.0 (fl* 2.0 3.0))
(test 2.5 (fl/ 5.0 2.0))
(test #t (fl= 1.0 1.0))
(test #t (fl< 1.0 2.0))
(test #t (fl> 2.0 1.0))
(test #t (fl<= 1.0 1.0))
(test #t (fl>= 1.0 1.0))
(test 5.0 (flabs -5.0))
(test 3.0 (flmax 1.0 3.0))
(test 1.0 (flmin 2.0 1.0))
(test 3.0 (flmax 1.0 3.0 2.0))
(test 1.0 (flmin 2.0 1.0 3.0))
(test -inf.0 (flmax))
(test +inf.0 (flmin))
(test 5.0 (flmax 5.0))
(test 5.0 (flmin 5.0))
;; NaN treated as missing per C99 fmax/fmin
(test 1.0 (flmax +nan.0 1.0))
(test 1.0 (flmax 1.0 +nan.0))
(test 1.0 (flmin +nan.0 1.0))
(test 1.0 (flmin 1.0 +nan.0))
(test #t (nan? (flmax +nan.0)))
(test #t (nan? (flmin +nan.0)))

;;; --- rounding ---
(test 1.0 (flfloor 1.7))
(test 2.0 (flceiling 1.2))
(test 1.0 (fltruncate 1.7))
(test -1.0 (fltruncate -1.7))
(test 2.0 (flround 1.5))

;;; --- transcendental ---
(test 3.0 (flsqrt 9.0))
(test 1.0 (flexp 0.0))
(test 0.0 (fllog 1.0))
(test 0.0 (flsin 0.0))
(test 1.0 (flcos 0.0))
(test 0.0 (fltan 0.0))
(test 0.0 (flasin 0.0))
(test 0.0 (flatan 0.0))
(test 8.0 (flexpt 2.0 3.0))

;;; --- conversions ---
(test 2 (fl->exact 2.0))
(test 2.0 (exact->fl 2))
(test 3.0 (fixnum->flonum 3))

(test-end "srfi-144")
