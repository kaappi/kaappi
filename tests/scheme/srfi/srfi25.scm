;; SRFI 25 (multi-dimensional array primitives) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi25.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 25))

(test-begin "srfi-25")

;;; --- construction ---
(test-equal 2 (array-rank (make-array (shape 0 3 0 4))))
(test-equal 0 (array-start (make-array (shape 0 3 0 4)) 0))
(test-equal 4 (array-end (make-array (shape 0 3 0 4)) 1))

(let ((a (make-array (shape 0 2 0 2) 'x)))
  (test-equal 'x (array-ref a 0 0))
  (array-set! a 1 1 'hello)
  (test-equal 'hello (array-ref a 1 1)))

;;; --- array?  disjointness ---
(test-equal #t (array? (make-array (shape 0 1))))
(test-equal #f (array? (vector 1 2 3)))
(test-equal #f (array? "not"))
(test-equal #f (array? '(1 2 3)))

;;; --- array literal constructor, row-major fill ---
(let ((b (array (shape 0 2 0 3) 1 2 3 4 5 6)))
  (test-equal 1 (array-ref b 0 0))
  (test-equal 3 (array-ref b 0 2))
  (test-equal 4 (array-ref b 1 0))
  (test-equal 6 (array-ref b 1 2)))

;;; --- arbitrary non-zero lower bounds (SRFI 25's defining difference vs. SRFI 47/63) ---
(let ((c (make-array (shape -2 2 -2 2) 0)))
  (test-equal -2 (array-start c 0))
  (test-equal 2 (array-end c 0))
  (array-set! c -2 -2 'corner)
  (test-equal 'corner (array-ref c -2 -2))
  (array-set! c 1 1 'other-corner)
  (test-equal 'other-corner (array-ref c 1 1)))

;;; --- packed index forms (vector or 1-D array) ---
(let ((b (array (shape 0 2 0 3) 1 2 3 4 5 6)))
  (test-equal 2 (array-ref b (vector 0 1)))
  (test-equal 6 (array-ref b (array (shape 0 2) 1 2)))
  (array-set! b (vector 1 1) 'packed)
  (test-equal 'packed (array-ref b 1 1)))

;;; --- array-set!'s value-LAST calling convention (opposite of SRFI 47/63) ---
(let ((a (make-array (shape 0 1 0 1) 0)))
  (array-set! a 0 0 'last-arg-is-value)
  (test-equal 'last-arg-is-value (array-ref a 0 0)))

;;; --- share-array: the spec's own i_4 diagonal-view example, verbatim ---
(define i_4
  (let* ((i (make-array (shape 0 4 0 4) 0))
         (d (share-array i (shape 0 4) (lambda (k) (values k k)))))
    (do ((k 0 (+ k 1))) ((= k 4)) (array-set! d k 1))
    i))
(test-equal 1 (array-ref i_4 0 0))
(test-equal 1 (array-ref i_4 1 1))
(test-equal 1 (array-ref i_4 2 2))
(test-equal 1 (array-ref i_4 3 3))
(test-equal 0 (array-ref i_4 0 1))
(test-equal 0 (array-ref i_4 1 0))

;;; --- nested share-array (view of a view), both read and write-through ---
(define base
  (array (shape 0 4 0 4)
         0 1 2 3
         4 5 6 7
         8 9 10 11
         12 13 14 15))
(define (row-view r) (share-array base (shape 0 4) (lambda (j) (values r j))))
(define row1 (row-view 1))
(test-equal 4 (array-ref row1 0))
(test-equal 7 (array-ref row1 3))
(define row1-rev (share-array row1 (shape 0 4) (lambda (j) (values (- 3 j)))))
(test-equal 7 (array-ref row1-rev 0))
(test-equal 4 (array-ref row1-rev 3))
(array-set! row1-rev 0 'mutated)
(test-equal 'mutated (array-ref base 1 3))
(test-equal 'mutated (array-ref row1 3))

;;; --- errors are catchable ---
(let ((a (make-array (shape 0 3 0 3) 0)))
  (test-equal #t (guard (e (#t #t)) (array-ref a 5 5) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref a -1 0) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref a 0) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref a 0 0 0) #f)))
(test-equal #t (guard (e (#t #t)) (shape 0 1 2) #f))
(test-equal #t (guard (e (#t #t)) (shape 5 2) #f))
(test-equal #t (guard (e (#t #t)) (array (shape 0 2) 1) #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-25")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
