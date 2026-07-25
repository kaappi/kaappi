;; SRFI 164 (enhanced multi-dimensional arrays) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi164.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 164))

(test-begin "srfi-164")

;;; --- the 10 procedures inherited from SRFI 25 (spot checks) ---
(test-equal 2 (array-rank (make-array (shape 0 2 0 3) 'x)))
(let ((a (make-array (shape 0 2 0 2) 'x)))
  (test-equal 'x (array-ref a 0 0))
  (array-set! a 1 1 'hello)
  (test-equal 'hello (array-ref a 1 1)))
(test-equal #t (array? (make-array (shape 0 1))))
(test-equal #f (array? (vector 1 2 3)))
(let ((b (array (shape 0 2 0 3) 1 2 3 4 5 6)))
  (test-equal 1 (array-ref b 0 0))
  (test-equal 6 (array-ref b 1 2)))
;;; --- packed index arguments: vector and 0-based rank-1 array, plus
;;; their rejection cases (not 1-D, not 0-based, not an index at all) ---
(let ((pa (array (shape 0 2 0 2) 1 2 3 4)))
  (test-equal 4 (array-ref pa (vector 1 1)))
  (array-set! pa (vector 0 1) 'packed)
  (test-equal 'packed (array-ref pa 0 1))
  (test-equal 3 (array-ref pa (array (shape 0 2) 1 0)))
  (test-equal #t (guard (e (#t #t)) (array-ref pa (array (shape 0 2 0 2) 0 0 0 0)) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref pa (array (shape 1 3) 0 1)) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref pa 'nope 0) #f)))

(let ((c (make-array (shape -2 2 -2 2) 0)))
  (array-set! c -2 -2 'corner)
  (test-equal 'corner (array-ref c -2 -2)))
(let* ((i (make-array (shape 0 4 0 4) 0))
       (d (share-array i (shape 0 4) (lambda (k) (values k k)))))
  (do ((k 0 (+ k 1))) ((= k 4)) (array-set! d k 1))
  (test-equal 1 (array-ref i 2 2))
  (test-equal 0 (array-ref i 0 1)))

;;; --- make-array's new cycling-multiple-fill-values behavior ---
(test-equal #(1 2 3 1 2) (array->vector (make-array (shape 0 5) 1 2 3)))
(test-equal #(7 7 7) (array->vector (make-array (shape 0 3) 7)))

;;; --- ->shape: integer, (lower upper) list, and passthrough-pair forms, mixed ---
(let ((a (make-array (->shape (vector 3 4)) 0)))
  (test-equal '(0 3 0 4) (list (array-start a 0) (array-end a 0) (array-start a 1) (array-end a 1))))
(let ((a (make-array (->shape (vector (list -1 2) (list 0 3))) 0)))
  (test-equal '(-1 2 0 3) (list (array-start a 0) (array-end a 0) (array-start a 1) (array-end a 1))))
(let ((a (make-array (->shape (vector (cons 0 2) 3)) 0)))
  (test-equal '(0 2 0 3) (list (array-start a 0) (array-end a 0) (array-start a 1) (array-end a 1))))

;;; ->shape rejects the same lo > hi violation `shape` rejects
(test-equal #t (guard (e (#t #t)) (->shape (vector (cons 5 2))) #f))

;;; --- per spec, "the procedures in this specification that require a
;;; shape can accept a shape-specifier, as if converted by ->shape" -- every
;;; shape-taking procedure below must accept a raw specifier directly, not
;;; just an already-canonical shape. ---
(test-equal '(0 2 0 4) (let ((a (make-array (vector 2 4) 0)))
                          (list (array-start a 0) (array-end a 0) (array-start a 1) (array-end a 1))))
(test-equal 4 (array-ref (array (vector 2 2) 1 2 3 4) 1 1))
(let* ((base164s (array (shape 0 4) 10 20 30 40))
       (viewed (share-array base164s (vector 4) (lambda (k) (values k)))))
  (test-equal 40 (array-ref viewed 3)))
(test-equal 2 (array-ref (build-array (vector 2 3) (lambda (idx) (* (vector-ref idx 0) (vector-ref idx 1)))) 1 2))
(test-equal 6 (array-size (index-array (vector 2 3))))
(test-equal 30 (array-ref (array-reshape (array (shape 0 2 0 3) 10 20 30 40 50 60) (vector 6)) 2))

;;; --- array-shape round-trips back into make-array ---
(let* ((original (make-array (shape -1 2 0 4) 0))
       (recovered (array-shape original))
       (a2 (make-array recovered 0)))
  (test-equal -1 (array-start a2 0))
  (test-equal 2 (array-end a2 0))
  (test-equal 0 (array-start a2 1))
  (test-equal 4 (array-end a2 1)))

;;; --- array-size ---
(test-equal 12 (array-size (make-array (shape 0 3 0 4) 0)))

;;; --- build-array: with and without a setter. Per spec, getter takes a
;;; single index-vector argument and setter takes (index-vector, value). ---
(let ((virt (build-array (shape 0 3 0 3) (lambda (idx) (* (vector-ref idx 0) (vector-ref idx 1))))))
  (test-equal 2 (array-ref virt 1 2))
  (test-equal 4 (array-ref virt 2 2))
  (test-equal #t (guard (e (#t #t)) (array-set! virt 0 0 99) #f)))
(let ((cell 0))
  (let ((mutvirt (build-array (shape 0 1) (lambda (idx) cell) (lambda (idx value) (set! cell value)))))
    (array-set! mutvirt 0 42)
    (test-equal 42 (array-ref mutvirt 0))))

;;; --- index-array ---
(let ((ia (index-array (shape 0 2 0 3))))
  (test-equal 0 (array-ref ia 0 0))
  (test-equal 2 (array-ref ia 0 2))
  (test-equal 3 (array-ref ia 1 0))
  (test-equal 5 (array-ref ia 1 2)))

;;; --- array-index-ref: all-integer (scalar) case ---
(define m164 (array (shape 0 3 0 3) 1 2 3 4 5 6 7 8 9))
(test-equal 5 (array-index-ref m164 1 1))

;;; --- array-index-ref: generalized (array-index) case, an outer-product-
;;; style row/column selection (not a diagonal -- picking row-set x
;;; column-set forms every combination) ---
(let* ((rows02 (array (shape 0 2) 0 2))
       (cols (array (shape 0 3) 0 1 2))
       (picked (array-index-ref m164 rows02 cols)))
  (test-equal 6 (array-size picked))
  (test-equal 1 (array-ref picked 0 0))
  (test-equal 3 (array-ref picked 0 2))
  (test-equal 7 (array-ref picked 1 0))
  (test-equal 9 (array-ref picked 1 2)))

;;; --- array-copy! / array-fill! ---
(let ((dst (make-array (shape 0 2 0 2) 0))
      (src (array (shape 0 2 0 2) 1 2 3 4)))
  (array-copy! dst src)
  (test-equal #(1 2 3 4) (array->vector dst))
  (array-fill! dst 'z)
  (test-equal #(z z z z) (array->vector dst)))
(test-equal #t
  (guard (e (#t #t))
    (array-copy! (make-array (shape 0 2) 0) (make-array (shape 0 3) 0))
    #f))

;;; --- array-transform: a genuinely non-affine transform (absolute-value
;;; fold) proves the shared/view mode doesn't require affineness ---
(let* ((src2 (array (shape -2 3) 10 20 30 40 50))
       (folded (array-transform src2 (shape 0 3)
                                 (lambda (idx) (vector (abs (- (vector-ref idx 0) 2)))))))
  (test-equal 50 (array-ref folded 0))
  (test-equal 30 (array-ref folded 2)))

;;; --- array-index-share: mutable view (array index + integer index ->
;;; reduced-rank view), write-through, and the rank-0 scalar-view case ---
(let* ((base164 (array (shape 0 3 0 3) 1 2 3 4 5 6 7 8 9))
       (rows02 (array (shape 0 2) 0 2))
       (col1-view (array-index-share base164 rows02 1)))
  (test-equal 2 (array-size col1-view))
  (test-equal 2 (array-ref col1-view 0))
  (test-equal 8 (array-ref col1-view 1))
  (array-set! col1-view 0 999)
  (test-equal 999 (array-ref base164 0 1))
  (let ((scalar-view (array-index-share base164 0 0)))
    (test-equal 1 (array-ref scalar-view))
    (array-set! scalar-view 'zz)
    (test-equal 'zz (array-ref base164 0 0))))

;;; --- array-reshape: aliases the backing vector for a simple source ---
(let* ((simple164 (array (shape 0 2 0 3) 1 2 3 4 5 6))
       (reshaped (array-reshape simple164 (shape 0 6))))
  (array-set! reshaped 0 'changed)
  (test-equal 'changed (array-ref simple164 0 0)))

;;; --- array-reshape: for a non-simple source, there's no vector to alias,
;;; so the result is a live view over the source (recomputed per access via
;;; row-major rank), not a snapshot -- confirmed by the write-through below ---
(let* ((simple164 (array (shape 0 2 0 3) 1 2 3 4 5 6))
       (shared164 (share-array simple164 (shape 0 6)
                                (lambda (k) (values (quotient k 3) (remainder k 3)))))
       (reshaped2 (array-reshape shared164 (shape 0 2 0 3))))
  (test-equal 1 (array-ref reshaped2 0 0))
  (array-set! simple164 0 0 'changed-again)
  (test-equal 'changed-again (array-ref reshaped2 0 0)))
(test-equal #t
  (guard (e (#t #t)) (array-reshape (make-array (shape 0 4) 0) (shape 0 3)) #f))

;;; --- array-flatten: always a fresh copy, never a view ---
(let* ((simple164 (array (shape 0 2 0 3) 1 2 3 4 5 6))
       (flat (array-flatten simple164)))
  (test-equal 1 (array-rank flat))
  (test-equal 6 (array-size flat))
  (array-set! simple164 0 0 'mutated-after-flatten)
  (test-equal 1 (array-ref flat 0)))

;;; --- array->vector: live identity for a simple array, snapshot otherwise ---
(let* ((simple2 (array (shape 0 3) 'a 'b 'c))
       (v (array->vector simple2)))
  (vector-set! v 0 'aliased!)
  (test-equal 'aliased! (array-ref simple2 0)))
(let* ((base164 (array (shape 0 2 0 2) 1 2 3 4))
       (view (share-array base164 (shape 0 4) (lambda (k) (values (quotient k 2) (remainder k 2)))))
       (snap (array->vector view)))
  (test-equal #(1 2 3 4) snap)
  (vector-set! snap 0 'not-live)
  (test-equal 1 (array-ref view 0)))

(let ((runner (test-runner-current)))
  (test-end "srfi-164")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
