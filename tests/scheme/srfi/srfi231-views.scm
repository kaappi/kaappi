;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 3: views,
;; sharing, and reshaping. Bulk combinators/conversions and multi-array
;; assembly are later phases of this multi-slice SRFI, tracked under
;; issue #1694; (srfi 231) itself is not yet an importable bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-views.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 231 intervals) (srfi 231 storage-classes) (srfi 231 arrays) (srfi 231 views))

(test-begin "srfi-231-views")

;;; --- specialized-array-share: the spec's own "shearing" example,
;;; verbatim (cannot be achieved by any of the other sharing procedures) ---
(let* ((a (array-copy (make-array (make-interval (vector 5 10)) list)))
       (b (specialized-array-share a (make-interval (vector 5 5))
                                    (lambda (i j) (values i (+ i j))))))
  (test-equal #t (specialized-array? b))
  (test-equal '(0 0) (array-ref b 0 0))
  (test-equal '(1 2) (array-ref b 1 1))  ;; b(1,1) = a(1, 1+1) = a(1,2)
  (test-equal '(4 8) (array-ref b 4 4))  ;; b(4,4) = a(4, 4+4) = a(4,8)
  ;; write-through: shares the same body as a
  (array-set! b 'sheared 2 2)
  (test-equal 'sheared (array-ref a 2 4)))

(test-equal #t (guard (e (#t #t))
                  (specialized-array-share (make-array (make-interval (vector 5)) (lambda (i) i))
                                            (make-interval (vector 5)) (lambda (i) (values i)))
                  #f))  ;; source must be specialized

;;; --- array-extract: preserves the SOURCE's absolute coordinate system
;;; (does not reset a sub-array to 0-based), matching the spec's own
;;; worked example verbatim ---
(let* ((a (make-array (make-interval (vector 3 3)) list))
       (b (array-extract a (make-interval (vector 1 0) (vector 3 2)))))
  (test-equal '(1 0) (array-ref b 1 0))
  (test-equal '(1 1) (array-ref b 1 1))
  (test-equal '(2 0) (array-ref b 2 0))
  (test-equal '(2 1) (array-ref b 2 1)))
(test-equal #t (guard (e (#t #t))
                  (array-extract (make-array (make-interval (vector 3 3)) list) (make-interval (vector 0 0) (vector 5 5)))
                  #f))  ;; not a subset

;; array-extract mirrors the source's own mode exactly
(let ((sa (make-specialized-array (make-interval (vector 3 3)) s8-storage-class)))
  (test-equal #t (specialized-array? (array-extract sa (make-interval (vector 1 1) (vector 3 3))))))

;;; --- array-translate ---
(let* ((a (make-array (make-interval (vector 2 3)) list))
       (b (array-translate a (vector 1 -3))))
  (test-equal #t (interval= (array-domain b) (make-interval (vector 1 -3) (vector 3 0))))
  (test-equal '(0 0) (array-ref b 1 -3)))
(test-equal #t (guard (e (#t #t)) (array-translate (make-array (make-interval (vector 2)) list) (vector 1 2)) #f))

;;; --- array-permute: the spec's own two worked examples, verbatim ---
(let* ((a (make-array (make-interval (vector 10 20 21 16)) list))
       (b (array-permute a (vector 3 0 1 2))))
  (test-equal #t (interval= (array-domain b) (make-interval (vector 16 10 20 21))))
  (test-equal (array-ref a 2 5 7 9) (array-ref b 9 2 5 7)))
(let* ((a (make-array (make-interval (vector 1 3 2)) list))
       (b (array-permute a (vector 2 1 0))))
  (test-equal #t (interval= (array-domain b) (make-interval (vector 2 3 1))))
  (test-equal '(0 1 1) (array-ref b 1 1 0)))
(test-equal #t (guard (e (#t #t)) (array-permute (make-array (make-interval (vector 2 3)) list) (vector 0 0)) #f))

;;; --- array-reverse: default (every axis) and explicit flip? ---
(let* ((a (make-array (make-interval (vector 4)) (lambda (i) i)))
       (ra (array-reverse a)))
  (test-equal #t (interval= (array-domain ra) (array-domain a)))  ;; domain unchanged
  (test-equal 3 (array-ref ra 0))
  (test-equal 2 (array-ref ra 1))
  (test-equal 1 (array-ref ra 2))
  (test-equal 0 (array-ref ra 3)))
;; explicit flip? = #f on every axis is a no-op
(let* ((a (make-array (make-interval (vector 3)) (lambda (i) i)))
       (ra (array-reverse a (vector #f))))
  (test-equal 0 (array-ref ra 0))
  (test-equal 2 (array-ref ra 2)))
;; the spec's own palindrome-checker shape (array-every isn't implemented
;; until a later phase, so this checks element-by-element instead)
(let* ((s "abba") (n (string-length s))
       (a (make-array (make-interval (vector n)) (lambda (i) (string-ref s i))))
       (ra (array-reverse a)))
  (test-equal #t (char=? (array-ref a 0) (array-ref ra 3)))
  (test-equal #t (char=? (array-ref a 1) (array-ref ra 2))))

;;; --- array-curry: basic identity, and the outer array is ALWAYS
;;; immutable/non-specialized regardless of the input's own mode ---
(let* ((a (make-array (make-interval (vector 10 10)) list))
       (b (array-curry a 1)))
  (test-equal (array-ref a 3 4) (array-ref (array-ref b 3) 4))
  (test-equal #t (array? b))
  (test-equal #f (mutable-array? b))
  (test-equal #f (specialized-array? b)))

(let* ((sa (make-specialized-array (make-interval (vector 3 3)) s8-storage-class))
       (curried (array-curry sa 1)))
  (array-set! sa 42 1 2)
  (test-equal #f (mutable-array? curried))
  (test-equal #f (specialized-array? curried))
  ;; but the INNER arrays mirror the source's own mode
  (test-equal #t (specialized-array? (array-ref curried 1)))
  (test-equal 42 (array-ref (array-ref curried 1) 2)))

(test-equal #t (guard (e (#t #t)) (array-curry (make-array (make-interval (vector 2)) list) 5) #f))

;;; --- array-sample: the spec's own worked example ---
(let* ((a (make-array (make-interval (vector 3 2)) list))
       (b (array-sample a (vector 2 1))))
  (test-equal #t (interval= (array-domain b) (make-interval (vector 2 2))))
  (test-equal '(2 0) (array-ref b 1 0))
  (test-equal '(2 1) (array-ref b 1 1)))
(test-equal #t (guard (e (#t #t))
                  (array-sample (make-array (make-interval (vector 1) (vector 5)) list) (vector 1)) #f))

;;; --- array-tile: the spec's own 6x6 non-uniform worked example,
;;; verbatim, plus truncation on an unevenly-dividing uniform width ---
(let* ((rows (list (vector 1 2 3 4 5 6) (vector 7 8 9 10 11 12) (vector 13 14 15 16 17 18)
                    (vector 19 20 21 22 23 24) (vector 25 26 27 28 29 30) (vector 31 32 33 34 35 36)))
       (rowvec (list->vector rows))
       (T (make-array (make-interval (vector 6 6)) (lambda (i j) (vector-ref (vector-ref rowvec i) j))))
       (tiled (array-tile T (vector (vector 3 1 2) 3))))
  (test-equal #t (interval= (array-domain tiled) (make-interval (vector 3 2))))
  (let ((t00 (array-ref tiled 0 0)))
    (test-equal 1 (array-ref t00 0 0)) (test-equal 3 (array-ref t00 0 2)) (test-equal 15 (array-ref t00 2 2)))
  (let ((t10 (array-ref tiled 1 0)))
    (test-equal #t (interval= (array-domain t10) (make-interval (vector 3 0) (vector 4 3))))
    (test-equal 19 (array-ref t10 3 0)) (test-equal 21 (array-ref t10 3 2)))
  (let ((t20 (array-ref tiled 2 0)))
    (test-equal #t (interval= (array-domain t20) (make-interval (vector 4 0) (vector 6 3))))
    (test-equal 25 (array-ref t20 4 0)) (test-equal 31 (array-ref t20 5 0))))

;; truncation: 5-element axis tiled with uniform width 2 -> ceil(5/2)=3
;; slices, last one truncated to width 1, not zero-padded or an error
(let* ((a (make-array (make-interval (vector 5)) (lambda (i) i)))
       (tiled (array-tile a (vector 2))))
  (test-equal '(3) (interval-upper-bounds->list (array-domain tiled)))
  (test-equal '(4) (interval-lower-bounds->list (array-domain (array-ref tiled 2))))
  (test-equal '(5) (interval-upper-bounds->list (array-domain (array-ref tiled 2)))))

;; array-tile's outer array is always immutable/non-specialized
(test-equal #f (specialized-array? (array-tile (make-specialized-array (make-interval (vector 4)) s8-storage-class) (vector 2))))

;;; --- array-copy / array-copy!: default-inheritance rule ---
(let* ((plain (make-array (make-interval (vector 2 2)) list))
       (copied (array-copy plain)))
  (test-equal #t (specialized-array? copied))
  (test-equal '(0 0) (array-ref copied 0 0))
  (test-equal '(1 1) (array-ref copied 1 1)))

(let* ((sa (make-specialized-array (make-interval (vector 2 2)) s8-storage-class 5 #t))
       (copy-of-sa (array-copy sa)))
  ;; omitted options are taken from the SOURCE when it's already
  ;; specialized -- by default, array-copy makes a TRUE copy
  (test-equal #t (eq? (array-storage-class copy-of-sa) s8-storage-class))
  (test-equal #t (array-safe? copy-of-sa))
  (test-equal #t (not (eq? (array-body copy-of-sa) (array-body sa)))))

;; array-copy! behaves identically for an ordinary (non-continuation-abusing) call
(let* ((sa (make-specialized-array (make-interval (vector 3)) s8-storage-class)))
  (array-set! sa 7 1)
  (let ((c (array-copy! sa)))
    (test-equal 7 (array-ref c 1))
    (test-equal #t (not (eq? (array-body c) (array-body sa))))))

;;; --- specialized-array-reshape: both of the spec's own worked examples ---
(let* ((a (array-copy (make-array (make-interval (vector 3 4)) list)))
       (reshaped (specialized-array-reshape a (make-interval (vector 4 3)))))
  (test-equal #t (interval= (array-domain reshaped) (make-interval (vector 4 3))))
  ;; row-major flatten: a's 12 elements read out in the new 4x3 shape
  (test-equal '(0 0) (array-ref reshaped 0 0))
  (test-equal '(0 1) (array-ref reshaped 0 1))
  (test-equal '(0 2) (array-ref reshaped 0 2))
  (test-equal '(0 3) (array-ref reshaped 1 0))
  (test-equal '(1 0) (array-ref reshaped 1 1))
  (test-equal '(2 3) (array-ref reshaped 3 2)))

(let* ((a (array-copy (make-array (make-interval (vector 3 4)) list)))
       (b (array-sample a (vector 2 1))))
  ;; b's rows are non-adjacent in a's body -- no affine flatten exists
  (test-equal #t (guard (e (#t #t)) (specialized-array-reshape b (make-interval (vector 8))) #f))
  ;; but copy-on-failure? #t always succeeds via a forced copy first
  (let ((forced (specialized-array-reshape b (make-interval (vector 8)) #t)))
    (test-equal #t (interval= (array-domain forced) (make-interval (vector 8))))))

(test-equal #t (guard (e (#t #t))
                  (specialized-array-reshape (make-array (make-interval (vector 3)) (lambda (i) i)) (make-interval (vector 3)))
                  #f))  ;; not specialized

(test-equal #t (guard (e (#t #t))
                  (specialized-array-reshape (array-copy (make-array (make-interval (vector 4)) (lambda (i) i)))
                                              (make-interval (vector 5)))
                  #f))  ;; volume mismatch

(let ((runner (test-runner-current)))
  (test-end "srfi-231-views")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
