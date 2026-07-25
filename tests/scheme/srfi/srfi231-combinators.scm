;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 4: bulk
;; combinators and conversions. Multi-array assembly is the last phase
;; of this multi-slice SRFI, tracked under issue #1694; (srfi 231)
;; itself is not yet an importable bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-combinators.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 231 intervals) (srfi 231 storage-classes) (srfi 231 arrays)
        (srfi 231 views) (srfi 231 combinators))

(test-begin "srfi-231-combinators")

;;; --- array-map / array-for-each ---
(let* ((a (make-array (make-interval (vector 3)) (lambda (i) i)))
       (b (make-array (make-interval (vector 3)) (lambda (i) (* i 10))))
       (m (array-map + a b)))
  (test-equal 0 (array-ref m 0))
  (test-equal 11 (array-ref m 1))
  (test-equal 22 (array-ref m 2))
  ;; lazy, immutable, non-specialized
  (test-equal #f (mutable-array? m))
  (test-equal #f (specialized-array? m)))

(test-equal #t (guard (e (#t #t))
                  (array-map + (make-array (make-interval (vector 3)) (lambda (i) i))
                               (make-array (make-interval (vector 5)) (lambda (i) i)))
                  #f))  ;; domain mismatch

(let ((sum 0))
  (array-for-each (lambda (x) (set! sum (+ sum x))) (make-array (make-interval (vector 4)) (lambda (i) i)))
  (test-equal 6 sum))

;;; --- array-fold-left / array-fold-right: the spec's own exact worked
;;; examples, verbatim -- these demonstrate the divergence is real, not
;;; just a notational difference ---
(let ((a (make-array (make-interval (vector 10)) (lambda (i) i))))
  (test-equal '((((((((((() . 0) . 1) . 2) . 3) . 4) . 5) . 6) . 7) . 8) . 9)
    (array-fold-left cons '() a))
  (test-equal '(0 1 2 3 4 5 6 7 8 9) (array-fold-right cons '() a))
  (test-equal -45 (array-fold-left - 0 a))
  (test-equal -5 (array-fold-right - 0 a)))

;; multi-array fold: operator receives separate positional arguments
(let ((a (make-array (make-interval (vector 3)) (lambda (i) i)))
      (b (make-array (make-interval (vector 3)) (lambda (i) (* i 10)))))
  (test-equal 33 (array-fold-left (lambda (acc x y) (+ acc x y)) 0 a b)))

;;; --- array-reduce ---
(test-equal 15 (array-reduce + (make-array (make-interval (vector 5)) (lambda (i) (+ i 1)))))
(test-equal #t (guard (e (#t #t))
                  (array-reduce + (make-array (make-interval (vector 0)) (lambda (i) i))) #f))

;;; --- array-any / array-every: return the actual result, not just #t,
;;; and short-circuit correctly ---
(let ((a (make-array (make-interval (vector 5)) (lambda (i) i))))
  (test-equal 'found (array-any (lambda (x) (and (= x 3) 'found)) a))
  (test-equal #f (array-any (lambda (x) (> x 100)) a))
  (test-equal #t (array-every (lambda (x) (>= x 0)) a))
  (test-equal #f (array-every (lambda (x) (< x 3)) a))
  ;; array-every returns the LAST nonfalse result when all pass
  (test-equal 'ok (array-every (lambda (x) 'ok) a)))

;;; --- array-outer-product ---
(let* ((a1 (make-array (make-interval (vector 2)) (lambda (i) i)))
       (a2 (make-array (make-interval (vector 3)) (lambda (j) (* j 100))))
       (op (array-outer-product + a1 a2)))
  (test-equal '(2 3) (interval-upper-bounds->list (array-domain op)))
  (test-equal 201 (array-ref op 1 2)))

;;; --- array-inner-product: the spec's own exact dot-product example ---
(let* ((X (list*->array 1 (list 1 3 5 7)))
       (Y (list*->array 1 (list 2 3 6 7)))
       (result (array-inner-product X + (lambda (x y) (if (= x y) 1 0)) Y)))
  (test-equal 2 (array->list* result)))

(test-equal #t (guard (e (#t #t))
                  (array-inner-product (make-array (make-interval (vector 3)) (lambda (i) i))
                                        + * (make-array (make-interval (vector 5)) (lambda (i) i)))
                  #f))  ;; bounds mismatch
;; a shared axis that matches bounds-wise but is itself zero-width (both
;; A's last axis and B's first axis are the empty interval [0,0))
(test-equal #t (guard (e (#t #t))
                  (array-inner-product (make-array (make-interval (vector 0)) (lambda (i) i))
                                        + * (make-array (make-interval (vector 0)) (lambda (i) i)))
                  #f))

;;; --- flat conversions: array->list / array->vector / list->array / vector->array ---
(let ((a (make-array (make-interval (vector 2 3)) list)))
  (test-equal '((0 0) (0 1) (0 2) (1 0) (1 1) (1 2)) (array->list a))
  (test-equal (vector '(0 0) '(0 1) '(0 2) '(1 0) '(1 1) '(1 2)) (array->vector a)))

(let* ((iv (make-interval (vector 2 3)))
       (a (list->array iv (list 'a 'b 'c 'd 'e 'f))))
  (test-equal 'a (array-ref a 0 0))
  (test-equal 'c (array-ref a 0 2))
  (test-equal 'd (array-ref a 1 0))
  (test-equal #t (specialized-array? a)))
(test-equal #t (guard (e (#t #t)) (list->array (make-interval (vector 2 3)) (list 1 2 3)) #f))

(let* ((iv (make-interval (vector 2 2)))
       (a (vector->array iv (vector 1 2 3 4))))
  (test-equal 1 (array-ref a 0 0))
  (test-equal 4 (array-ref a 1 1)))
(test-equal #t (guard (e (#t #t)) (vector->array (make-interval (vector 2 2)) (vector 1 2 3)) #f))

;;; --- nested conversions: basic round trip ---
(let ((a (list*->array 2 (list (list 1 2) (list 3 4)))))
  (test-equal '(2 2) (interval-upper-bounds->list (array-domain a)))
  (test-equal 1 (array-ref a 0 0))
  (test-equal 2 (array-ref a 0 1))
  (test-equal 3 (array-ref a 1 0))
  (test-equal 4 (array-ref a 1 1))
  (test-equal '((1 2) (3 4)) (array->list* a)))

;; ragged nested list is rejected
(test-equal #t (guard (e (#t #t)) (list*->array 2 (list (list 1 2) (list 3))) #f))

;; 0-dimensional array->list* returns the bare element, not wrapped
(test-equal 'the-scalar (array->list* (make-array (make-interval (vector)) (lambda () 'the-scalar))))

;;; --- the spec's own 4 exact empty-collection edge cases for
;;; list*->array, verbatim -- these look superficially similar but
;;; produce entirely different shapes ---
(let ((a0 (list*->array 0 '())))
  ;; a RANK-0, volume-1 array whose single element IS the empty list
  (test-equal '() (interval-upper-bounds->list (array-domain a0)))
  (test-equal 1 (interval-volume (array-domain a0)))
  (test-equal '() (array->list* a0)))

(let ((a1 (list*->array 1 '())))
  ;; a genuinely EMPTY rank-1 array
  (test-equal '(0) (interval-upper-bounds->list (array-domain a1)))
  (test-equal #t (array-empty? a1)))

(let ((a2 (list*->array 2 '())))
  (test-equal '(0 0) (interval-upper-bounds->list (array-domain a2)))
  (test-equal #t (array-empty? a2)))

(let ((a3 (list*->array 2 (list '() '()))))
  (test-equal '(2 0) (interval-upper-bounds->list (array-domain a3)))
  (test-equal #t (array-empty? a3)))

;;; --- vector*->array / array->vector*: the vector analogues ---
(let ((a (vector*->array 2 (vector (vector 1 2) (vector 3 4)))))
  (test-equal '(2 2) (interval-upper-bounds->list (array-domain a)))
  (test-equal 1 (array-ref a 0 0))
  (test-equal 4 (array-ref a 1 1))
  (test-equal (vector (vector 1 2) (vector 3 4)) (array->vector* a)))

;; a malformed nested vector (wrong depth -- inner elements aren't
;; vectors) gets a clean, domain-specific error, matching the list path's
;; own %check-nested-list validation, rather than a raw vector->list crash
(test-equal #t (guard (e (#t #t)) (vector*->array 2 (vector 1 2)) #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-combinators")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
