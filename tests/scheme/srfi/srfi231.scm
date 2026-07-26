;; SRFI 231 (Intervals and Generalized Arrays) -- hub test. Confirms the
;; public re-export library (lib/srfi/231.sld, merging misc, intervals,
;; storage-classes, arrays, views, combinators, and assembly) actually
;; exposes its full surface via a single `(import (srfi 231))`, distinct
;; from the per-phase suites (srfi231-intervals.scm, srfi231-arrays.scm,
;; etc.) which each import only their own phase file directly. Issue
;; #1694 (the numeric-vector and array family) is fully closed as of
;; this file landing.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 231))

(test-begin "srfi-231-hub")

;;; --- misc ---
(test-equal #t (permutation? (vector 2 0 1)))
(test-equal #f (permutation? (vector 0 0 1)))
(test-equal #(2 3 0 1) (index-rotate 4 2))

;;; --- intervals ---
(let ((i (make-interval (vector -2 -2) (vector 3 3))))
  (test-equal 2 (interval-dimension i))
  (test-equal 25 (interval-volume i))
  (test-equal #f (interval-empty? i)))

;;; --- storage-classes ---
(test-equal #t (storage-class? s32-storage-class))
(test-equal 0 (storage-class-default s32-storage-class))

;;; --- arrays ---
(let ((a (make-specialized-array (make-interval (vector 3 3)) s32-storage-class)))
  (test-equal #t (specialized-array? a))
  (array-set! a 42 1 1)
  (test-equal 42 (array-ref a 1 1)))

;;; --- views ---
(let* ((a (make-array (make-interval (vector 2 2)) (lambda (i j) (+ (* i 2) j))))
       (c (array-curry a 1)))
  (test-equal 1 (array-dimension c))
  (test-equal 3 (array-ref (array-ref c 1) 1)))

;;; --- combinators ---
(let ((a (make-array (make-interval (vector 3)) (lambda (i) (* i i)))))
  (test-equal '(0 1 4) (array->list a))
  (test-equal 5 (array-fold-left + 0 a)))

;;; --- assembly ---
(let* ((a1 (make-array (make-interval (vector 2)) (lambda (i) i)))
       (a2 (make-array (make-interval (vector 2)) (lambda (i) (+ 10 i))))
       (stacked (array-stack 0 (list a1 a2))))
  (test-equal 0 (array-ref stacked 0 0))
  (test-equal 11 (array-ref stacked 1 1)))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-hub")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
