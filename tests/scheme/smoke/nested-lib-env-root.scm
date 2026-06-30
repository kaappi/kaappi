;; Regression test for issue #516: pending_lib_envs conditional push
;; but unconditional pop over-decrements the counter, un-rooting
;; in-flight library environments during deeply nested imports.
;;
;; Creates a chain of 12 nested libraries (beyond the 8-slot stack)
;; to verify push/pop symmetry.

(import (scheme base) (scheme process-context))

(define-library (nest-1)
  (import (scheme base))
  (export nest-1-val)
  (begin (define nest-1-val 1)))

(define-library (nest-2)
  (import (scheme base) (nest-1))
  (export nest-2-val)
  (begin (define nest-2-val (+ nest-1-val 1))))

(define-library (nest-3)
  (import (scheme base) (nest-2))
  (export nest-3-val)
  (begin (define nest-3-val (+ nest-2-val 1))))

(define-library (nest-4)
  (import (scheme base) (nest-3))
  (export nest-4-val)
  (begin (define nest-4-val (+ nest-3-val 1))))

(define-library (nest-5)
  (import (scheme base) (nest-4))
  (export nest-5-val)
  (begin (define nest-5-val (+ nest-4-val 1))))

(define-library (nest-6)
  (import (scheme base) (nest-5))
  (export nest-6-val)
  (begin (define nest-6-val (+ nest-5-val 1))))

(define-library (nest-7)
  (import (scheme base) (nest-6))
  (export nest-7-val)
  (begin (define nest-7-val (+ nest-6-val 1))))

(define-library (nest-8)
  (import (scheme base) (nest-7))
  (export nest-8-val)
  (begin (define nest-8-val (+ nest-7-val 1))))

(define-library (nest-9)
  (import (scheme base) (nest-8))
  (export nest-9-val)
  (begin (define nest-9-val (+ nest-8-val 1))))

(define-library (nest-10)
  (import (scheme base) (nest-9))
  (export nest-10-val)
  (begin (define nest-10-val (+ nest-9-val 1))))

(define-library (nest-11)
  (import (scheme base) (nest-10))
  (export nest-11-val)
  (begin (define nest-11-val (+ nest-10-val 1))))

(define-library (nest-12)
  (import (scheme base) (nest-11))
  (export nest-12-val)
  (begin (define nest-12-val (+ nest-11-val 1))))

(import (nest-12))

(unless (= nest-12-val 12)
  (display "FAIL: expected 12, got ")
  (display nest-12-val)
  (newline)
  (exit 1))

(display "PASS: nested-lib-env-root")
(newline)
