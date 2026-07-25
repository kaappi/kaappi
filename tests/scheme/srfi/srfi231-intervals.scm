;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 1a: intervals
;; and the (srfi 231 misc) permutation/translation helpers. Arrays and
;; storage classes are later phases of this multi-slice SRFI, tracked under
;; issue #1694; (srfi 231) itself is not yet an importable bare library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-intervals.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 231 misc) (srfi 231 intervals))

(test-begin "srfi-231-intervals")

;;; --- (srfi 231 misc): permutation/translation predicates and index constructors ---
(test-equal #t (permutation? (vector 0 1 2)))
(test-equal #t (permutation? (vector 1 0 2)))
(test-equal #f (permutation? (vector 0 0 2)))
(test-equal #f (permutation? (vector 0 1 3)))
(test-equal #f (permutation? "not a vector"))
(test-equal #t (translation? (vector 1 -2 3)))
(test-equal #t (translation? (vector)))
(test-equal #f (translation? (vector 1.5)))
(test-equal #f (translation? "not a vector"))
;; worked examples straight from the spec
(test-equal (vector 3 4 0 1 2) (index-rotate 5 3))
(test-equal (vector 3 0 1 2 4) (index-first 5 3))
(test-equal (vector 0 1 2 4 3) (index-last 5 3))
(test-equal (vector 3 1 2 0 4) (index-swap 5 3 0))

;;; --- index-* preconditions are validated, including the asymmetric
;;; inclusive/exclusive boundary: index-rotate's k may equal n (identity
;;; permutation), but index-first/-last/-swap's k/i/j must be strictly
;;; less than n ---
(test-equal (vector 0 1 2) (index-rotate 3 3))
(test-equal #t (guard (e (#t #t)) (index-rotate 3 -1) #f))
(test-equal #t (guard (e (#t #t)) (index-rotate 3 4) #f))
(test-equal #t (guard (e (#t #t)) (index-first 3 -1) #f))
(test-equal #t (guard (e (#t #t)) (index-first 3 3) #f))
(test-equal #t (guard (e (#t #t)) (index-last 3 -1) #f))
(test-equal #t (guard (e (#t #t)) (index-last 3 3) #f))
(test-equal #t (guard (e (#t #t)) (index-swap 3 0 5) #f))

;;; --- construction: both 1-arg and 2-arg forms ---
(test-equal 2 (interval-dimension (make-interval (vector 3 4))))
(test-equal '(0 0) (interval-lower-bounds->list (make-interval (vector 3 4))))
(test-equal '(3 4) (interval-upper-bounds->list (make-interval (vector 3 4))))

(let ((b (make-interval (vector -2 -2) (vector 2 2))))
  (test-equal '(-2 -2) (interval-lower-bounds->list b))
  (test-equal '(2 2) (interval-upper-bounds->list b))
  (test-equal -2 (interval-lower-bound b 0))
  (test-equal 2 (interval-upper-bound b 1))
  (test-equal 4 (interval-width b 0)))

;;; --- construction errors are catchable ---
(test-equal #t (guard (e (#t #t)) (make-interval (vector -1 2)) #f))
(test-equal #t (guard (e (#t #t)) (make-interval (vector 5 5) (vector 3 3)) #f))
(test-equal #t (guard (e (#t #t)) (make-interval (vector 1.5)) #f))
(test-equal #t (guard (e (#t #t))
                  (interval-lower-bound (make-interval (vector 3 4)) 5) #f))
;; make-interval takes at most 2 arguments -- a 3rd is rejected, not
;; silently discarded
(test-equal #t (guard (e (#t #t))
                  (make-interval (vector 0) (vector 1) (vector 2)) #f))

;;; --- an interval does not retain a dependence on the caller's vector ---
(let* ((v (vector 5 5)) (c (make-interval v)))
  (vector-set! v 0 999)
  (test-equal '(5 5) (interval-upper-bounds->list c)))

;;; --- zero-dimensional and empty intervals ---
(let ((z (make-interval (vector))))
  (test-equal 0 (interval-dimension z))
  (test-equal 1 (interval-volume z))
  (test-equal #f (interval-empty? z)))

(let ((e (make-interval (vector 3 3) (vector 3 5))))
  (test-equal #t (interval-empty? e))
  (test-equal 0 (interval-volume e)))

;;; --- interval= / interval-subset? ---
(test-equal #t (interval= (make-interval (vector 3 4)) (make-interval (vector 3 4))))
(test-equal #f (interval= (make-interval (vector 3 4)) (make-interval (vector 4 3))))
(let ((outer (make-interval (vector -2 -2) (vector 2 2)))
      (inner (make-interval (vector 1 1) (vector 2 2))))
  (test-equal #t (interval-subset? inner outer))
  (test-equal #f (interval-subset? outer inner)))
;; per spec, mismatched dimensions are an error, not a normal #f result
(test-equal #t (guard (e (#t #t))
                  (interval-subset? (make-interval (vector 2)) (make-interval (vector 2 3))) #f))

;;; --- interval-contains-multi-index? ---
(let ((b (make-interval (vector -2 -2) (vector 2 2))))
  (test-equal #t (interval-contains-multi-index? b -2 -2))
  (test-equal #f (interval-contains-multi-index? b 2 0))
  (test-equal #t (interval-contains-multi-index? b 0 0))
  ;; a multi-index must consist of exact integers
  (test-equal #t (guard (e (#t #t)) (interval-contains-multi-index? b 1.5 0) #f)))

;;; --- interval-for-each: lexicographic order, separate positional args ---
(let ((visits '()))
  (interval-for-each (lambda (i j) (set! visits (cons (list i j) visits))) (make-interval (vector 2 2)))
  (test-equal '((0 0) (0 1) (1 0) (1 1)) (reverse visits)))

;;; --- interval-fold-left / interval-fold-right: order-sensitive (cons)
;;; so a left/right mixup would be caught immediately ---
(let ((d (make-interval (vector 3))))
  (test-equal '(2 1 0) (interval-fold-left (lambda (i) i) (lambda (acc x) (cons x acc)) '() d))
  (test-equal '(0 1 2) (interval-fold-right (lambda (i) i) (lambda (x acc) (cons x acc)) '() d)))

;; 0-dimensional fold cases match the spec's own formulas exactly
(let ((z (make-interval (vector))))
  (test-equal '(id 42) (interval-fold-left (lambda () 42) (lambda (acc x) (list acc x)) 'id z))
  (test-equal '(42 id) (interval-fold-right (lambda () 42) (lambda (x acc) (list x acc)) 'id z)))

;; empty-interval fold cases: f must never be called, identity returned untouched
(let ((e (make-interval (vector 3 3) (vector 3 5))))
  (test-equal 'identity-value
    (interval-fold-left (lambda (i j) (error "should not be called")) (lambda (acc x) x) 'identity-value e))
  (test-equal 'identity-value
    (interval-fold-right (lambda (i j) (error "should not be called")) (lambda (x acc) x) 'identity-value e)))

;;; --- interval-dilate / interval-translate / interval-permute / interval-scale ---
(let* ((b (make-interval (vector -2 -2) (vector 2 2)))
       (dil (interval-dilate b (vector -1 -1) (vector 1 1))))
  (test-equal '(-3 -3) (interval-lower-bounds->list dil))
  (test-equal '(3 3) (interval-upper-bounds->list dil))
  ;; diff vectors of the wrong length are rejected, not silently truncated
  ;; by vector-map's shortest-wins behavior
  (test-equal #t (guard (e (#t #t)) (interval-dilate b (vector -1) (vector 1 1)) #f))
  (test-equal #t (guard (e (#t #t)) (interval-dilate b (vector -1 -1) (vector 1 1 1)) #f)))

(let* ((b (make-interval (vector -2 -2) (vector 2 2)))
       (tr (interval-translate b (vector 10 20))))
  (test-equal '(8 18) (interval-lower-bounds->list tr))
  (test-equal '(12 22) (interval-upper-bounds->list tr))
  (test-equal #t (guard (e (#t #t)) (interval-translate b "not a translation") #f))
  (test-equal #t (guard (e (#t #t)) (interval-translate b (vector 1 2 3)) #f)))

;; matches the spec's own permutation convention: result axis i has bounds
;; of the original's axis permutation[i]
(let ((pm (interval-permute (make-interval (vector 10 20 30)) (vector 2 0 1))))
  (test-equal '(30 10 20) (interval-upper-bounds->list pm)))
(test-equal #t (guard (e (#t #t))
                  (interval-permute (make-interval (vector 1 2)) (vector 5 5)) #f))
(test-equal #t (guard (e (#t #t))
                  (interval-permute (make-interval (vector 1 2 3)) (vector 1 0)) #f))

(test-equal '(4) (interval-upper-bounds->list (interval-scale (make-interval (vector 10)) (vector 3))))
(test-equal #t (guard (e (#t #t))
                  (interval-scale (make-interval (vector -2 -2) (vector 2 2)) (vector 1 1)) #f))
(test-equal #t (guard (e (#t #t))
                  (interval-scale (make-interval (vector 10 10)) (vector 2)) #f))

;;; --- interval-intersect ---
(let ((i1 (make-interval (vector 0 0) (vector 5 5)))
      (i2 (make-interval (vector 3 3) (vector 8 8)))
      (i3 (make-interval (vector 100 100) (vector 200 200))))
  (let ((ix (interval-intersect i1 i2)))
    (test-equal '(3 3) (interval-lower-bounds->list ix))
    (test-equal '(5 5) (interval-upper-bounds->list ix)))
  (test-equal #f (interval-intersect i1 i3))
  ;; mismatched dimensions must be rejected, not silently limited to the
  ;; first interval's own (possibly smaller) axis count
  (test-equal #t (guard (e (#t #t)) (interval-intersect (make-interval (vector 5)) i1) #f)))

;;; --- interval-cartesian-product ---
(let ((cp (interval-cartesian-product (make-interval (vector 2 3)) (make-interval (vector 5)))))
  (test-equal 3 (interval-dimension cp))
  (test-equal '(2 3 5) (interval-upper-bounds->list cp)))

;;; --- interval-projections: the spec's own worked example, verbatim ---
(let-values (((left right) (interval-projections (make-interval (vector 2 3 1 5 4)) 2)))
  (test-equal '(2 3 1) (interval-upper-bounds->list left))
  (test-equal '(5 4) (interval-upper-bounds->list right)))
(test-equal #t (guard (e (#t #t))
                  (interval-projections (make-interval (vector 2 3)) 5) #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-intervals")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
