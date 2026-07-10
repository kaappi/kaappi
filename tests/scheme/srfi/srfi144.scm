;; SRFI-144 (flonums) conformance tests — audit Phase 3c
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi144.scm

(import (scheme base) (srfi 144) (scheme process-context) (srfi 64))

(test-begin "srfi-144")

;;; --- constants ---
(test-equal #t (< 2.718281 fl-e 2.718282))
(test-equal #t (< 3.141592 fl-pi 3.141593))
(test-equal #t (< 0.318309 fl-1/pi 0.318310))
(test-equal #t (flonum? fl-greatest))
(test-equal #t (> fl-greatest 1e308))
(test-equal #t (> fl-least 0.0))
(test-equal #t (< fl-least 1e-300))
(test-equal #t (< 0.0 fl-epsilon 1e-10))

;;; --- predicates ---
(test-equal #t (flonum? 1.5))
(test-equal #f (flonum? 1))
(test-equal #f (flonum? 1/2))
(test-equal #t (flzero? 0.0))
(test-equal #t (flpositive? 1.0))
(test-equal #t (flnegative? -1.0))
(test-equal #t (flinteger? 2.0))
(test-equal #f (flinteger? 2.5))
(test-equal #t (flfinite? 1.0))
(test-equal #f (flfinite? +inf.0))
(test-equal #t (flinfinite? +inf.0))
(test-equal #f (flinfinite? 1.0))
(test-equal #t (flnan? +nan.0))
(test-equal #f (flnan? 1.0))
(test-equal #t (flodd? 3.0))
(test-equal #t (fleven? 4.0))

;;; --- arithmetic and comparisons ---
(test-equal 5.0 (fl+ 2.0 3.0))
(test-equal -1.0 (fl- 2.0 3.0))
(test-equal 6.0 (fl* 2.0 3.0))
(test-equal 2.5 (fl/ 5.0 2.0))
(test-equal #t (fl= 1.0 1.0))
(test-equal #t (fl< 1.0 2.0))
(test-equal #t (fl> 2.0 1.0))
(test-equal #t (fl<= 1.0 1.0))
(test-equal #t (fl>= 1.0 1.0))
(test-equal 5.0 (flabs -5.0))
(test-equal 3.0 (flmax 1.0 3.0))
(test-equal 1.0 (flmin 2.0 1.0))
(test-equal 3.0 (flmax 1.0 3.0 2.0))
(test-equal 1.0 (flmin 2.0 1.0 3.0))
(test-equal -inf.0 (flmax))
(test-equal +inf.0 (flmin))
(test-equal 5.0 (flmax 5.0))
(test-equal 5.0 (flmin 5.0))
;; NaN treated as missing per C99 fmax/fmin
(test-equal 1.0 (flmax +nan.0 1.0))
(test-equal 1.0 (flmax 1.0 +nan.0))
(test-equal 1.0 (flmin +nan.0 1.0))
(test-equal 1.0 (flmin 1.0 +nan.0))
(test-equal #t (nan? (flmax +nan.0)))
(test-equal #t (nan? (flmin +nan.0)))

;;; --- rounding ---
(test-equal 1.0 (flfloor 1.7))
(test-equal 2.0 (flceiling 1.2))
(test-equal 1.0 (fltruncate 1.7))
(test-equal -1.0 (fltruncate -1.7))
(test-equal 2.0 (flround 1.5))

;;; --- transcendental ---
(test-equal 3.0 (flsqrt 9.0))
(test-equal 1.0 (flexp 0.0))
(test-equal 0.0 (fllog 1.0))
(test-equal 0.0 (flsin 0.0))
(test-equal 1.0 (flcos 0.0))
(test-equal 0.0 (fltan 0.0))
(test-equal 0.0 (flasin 0.0))
(test-equal 0.0 (flatan 0.0))
(test-equal 8.0 (flexpt 2.0 3.0))

;;; --- conversions ---
(test-equal 2 (fl->exact 2.0))
(test-equal 2.0 (exact->fl 2))
(test-equal 3.0 (fixnum->flonum 3))

(let ((runner (test-runner-current)))
  (test-end "srfi-144")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
