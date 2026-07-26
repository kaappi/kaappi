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

;;; --- public-export completeness audit ---
;;; The tests above only exercise 14 representative bindings; that alone
;;; can't catch the hub silently dropping some OTHER name from its
;;; claimed 118-binding surface (a typo or missed addition in
;;; lib/srfi/231.sld's own export clause, independent of whether the
;;; underlying phase file still exports it correctly). Referencing every
;;; single exported identifier by name forces each one to resolve --
;;; simply evaluating this expression fails with an unbound-variable
;;; error if the hub's export list is ever missing one, without needing
;;; a call or a return-value check on any of them. Kept in the same
;;; order as lib/srfi/231.sld's own export clause.
(test-assert
 (= 118
    (length
     (list translation? permutation? index-rotate index-first index-last
           index-swap interval? make-interval interval-dimension
           interval-lower-bound interval-upper-bound interval-width
           interval-lower-bounds->list interval-upper-bounds->list
           interval-lower-bounds->vector interval-upper-bounds->vector
           interval-widths interval-volume interval-empty? interval=
           interval-subset? interval-contains-multi-index? interval-for-each
           interval-fold-left interval-fold-right interval-dilate
           interval-translate interval-permute interval-scale interval-intersect
           interval-cartesian-product interval-projections make-storage-class
           storage-class? storage-class-getter storage-class-setter
           storage-class-checker storage-class-maker storage-class-copier
           storage-class-length storage-class-default storage-class-data?
           storage-class-data->body generic-storage-class char-storage-class
           s8-storage-class s16-storage-class s32-storage-class
           s64-storage-class u1-storage-class u8-storage-class u16-storage-class
           u32-storage-class u64-storage-class f8-storage-class
           f16-storage-class f32-storage-class f64-storage-class
           c64-storage-class c128-storage-class array? mutable-array?
           specialized-array? make-array make-specialized-array
           make-specialized-array-from-data array-domain array-getter
           array-setter array-dimension array-ref array-set! array-freeze!
           array-empty? array-body array-indexer array-storage-class array-safe?
           array-packed? specialized-array-default-safe?
           specialized-array-default-mutable? specialized-array-share
           array-extract array-translate array-permute array-reverse array-curry
           array-tile array-sample array-copy array-copy!
           specialized-array-reshape array-map array-for-each array-fold-left
           array-fold-right array-reduce array-any array-every
           array-outer-product array-inner-product array->list list->array
           array->list* list*->array array->vector vector->array array->vector*
           vector*->array array-assign! array-stack array-stack! array-decurry
           array-decurry! array-append array-append! array-block array-block!))))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-hub")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
