;; SRFI 231 (Intervals and Generalized Arrays) tests -- phase 5: multi-array
;; assembly, the final content phase of this multi-slice SRFI, tracked
;; under issue #1694. (srfi 231) itself is not yet an importable bare
;; library -- only the merge-into-public-library step remains after this.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi231-assembly.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 231 intervals) (srfi 231 arrays) (srfi 231 views) (srfi 231 assembly))

(test-begin "srfi-231-assembly")

(define (const-array h w v) (make-array (make-interval (vector h w)) (lambda (i j) v)))

;;; --- array-assign!: no non-! counterpart; always mutates in place,
;;; requires EXACT domain equality, returns an unspecified value ---
(let* ((a (make-specialized-array (make-interval (vector 3 3))))
       (src (make-array (make-interval (vector 3 3)) (lambda (i j) (+ (* i 3) j)))))
  (array-assign! a src)
  (test-equal 0 (array-ref a 0 0))
  (test-equal 4 (array-ref a 1 1))
  (test-equal 8 (array-ref a 2 2))
  ;; partial overwrite through a shared sub-view (write-through to a)
  (let ((view (array-extract a (make-interval (vector 1 1) (vector 3 3))))
        (patch (make-array (make-interval (vector 1 1) (vector 3 3)) (lambda (i j) 99))))
    (array-assign! view patch)
    (test-equal 0 (array-ref a 0 0))   ;; untouched
    (test-equal 99 (array-ref a 1 1))
    (test-equal 99 (array-ref a 1 2))
    (test-equal 99 (array-ref a 2 2))))
(test-equal #t (guard (e (#t #t))  ;; domain mismatch
                  (array-assign! (make-specialized-array (make-interval (vector 3 3)))
                                  (make-array (make-interval (vector 2 2)) (lambda (i j) 0)))
                  #f))
(test-equal #t (guard (e (#t #t))  ;; destination must be mutable
                  (array-assign! (make-array (make-interval (vector 2 2)) (lambda (i j) 0))
                                  (make-array (make-interval (vector 2 2)) (lambda (i j) 0)))
                  #f))

;;; --- array-stack / array-stack!: k is INCLUSIVE [0,d] -- a new axis of
;;; width (length arrays) is inserted at position k ---
(let ((a1 (make-array (make-interval (vector 2 2)) (lambda (i j) (+ (* i 2) j))))
      (a2 (make-array (make-interval (vector 2 2)) (lambda (i j) (+ 100 (* i 2) j)))))
  ;; k=0: new axis at the front
  (let ((s0 (array-stack 0 (list a1 a2))))
    (test-equal #t (interval= (array-domain s0) (make-interval (vector 2 2 2))))
    (test-equal 0 (array-ref s0 0 0 0))
    (test-equal 3 (array-ref s0 0 1 1))
    (test-equal 100 (array-ref s0 1 0 0))
    (test-equal 103 (array-ref s0 1 1 1)))
  ;; k=1: new axis in the middle
  (let ((s1 (array-stack 1 (list a1 a2))))
    (test-equal 0 (array-ref s1 0 0 0))
    (test-equal 100 (array-ref s1 0 1 0))
    (test-equal 3 (array-ref s1 1 0 1))
    (test-equal 103 (array-ref s1 1 1 1)))
  ;; k=2 (== dimension): new axis appended at the end
  (let ((s2 (array-stack 2 (list a1 a2))))
    (test-equal 0 (array-ref s2 0 0 0))
    (test-equal 100 (array-ref s2 0 0 1))
    (test-equal 3 (array-ref s2 1 1 0))
    (test-equal 103 (array-ref s2 1 1 1)))
  ;; array-stack! is a plain alias
  (test-equal (array-ref (array-stack 0 (list a1 a2)) 1 0 1)
              (array-ref (array-stack! 0 (list a1 a2)) 1 0 1))
  (test-equal #t (guard (e (#t #t)) (array-stack 0 (list a1 (const-array 3 3 0))) #f))  ;; domain mismatch
  (test-equal #t (guard (e (#t #t)) (array-stack 3 (list a1 a2)) #f))  ;; k out of range
  (test-equal #t (guard (e (#t #t)) (array-stack 0 '()) #f)))  ;; empty list

;;; --- array-decurry / array-decurry!: exact inverse of array-curry ---
(let* ((e (make-array (make-interval (vector 2 2 2)) (lambda (i j k) (+ (* i 100) (* j 10) k))))
       (c (array-curry e 1))
       (d (array-decurry c)))
  (test-equal #t (interval= (array-domain d) (array-domain e)))
  (test-equal (array-ref e 0 0 0) (array-ref d 0 0 0))
  (test-equal (array-ref e 0 1 1) (array-ref d 0 1 1))
  (test-equal (array-ref e 1 0 1) (array-ref d 1 0 1))
  (test-equal (array-ref e 1 1 1) (array-ref d 1 1 1))
  (test-equal (array-ref d 1 1 1) (array-ref (array-decurry! c) 1 1 1)))  ;; ! is a plain alias
(test-equal #t (guard (e (#t #t))  ;; inconsistent inner domains
                  (array-decurry (make-array (make-interval (vector 2))
                                              (lambda (i) (if (= i 0) (const-array 2 2 0) (const-array 3 3 0)))))
                  #f))

;;; --- array-append / array-append!: k is EXCLUSIVE [0,d) -- concatenates
;;; along an EXISTING axis, resetting that axis's lower bound to 0 ---
(let ((a1 (make-array (make-interval (vector 2 3)) (lambda (i j) (+ (* i 3) j))))
      (a2 (make-array (make-interval (vector 2 3)) (lambda (i j) (+ 100 (* i 3) j)))))
  (let ((ap0 (array-append 0 (list a1 a2))))
    (test-equal #t (interval= (array-domain ap0) (make-interval (vector 4 3))))
    (test-equal 0 (array-ref ap0 0 0))
    (test-equal 5 (array-ref ap0 1 2))
    (test-equal 100 (array-ref ap0 2 0))
    (test-equal 105 (array-ref ap0 3 2)))
  (let ((ap1 (array-append 1 (list a1 a2))))
    (test-equal #t (interval= (array-domain ap1) (make-interval (vector 2 6))))
    (test-equal 0 (array-ref ap1 0 0))
    (test-equal 2 (array-ref ap1 0 2))
    (test-equal 100 (array-ref ap1 0 3))
    (test-equal 105 (array-ref ap1 1 5)))
  (test-equal (array-ref (array-append 0 (list a1 a2)) 2 1)
              (array-ref (array-append! 0 (list a1 a2)) 2 1))  ;; ! is a plain alias
  ;; off-axis dimension mismatch
  (test-equal #t (guard (e (#t #t)) (array-append 0 (list a1 (make-array (make-interval (vector 2 4)) (lambda (i j) 0)))) #f))
  (test-equal #t (guard (e (#t #t)) (array-append 2 (list a1 a2)) #f))  ;; k out of range (exclusive)
  (test-equal #t (guard (e (#t #t)) (array-append 0 '()) #f)))  ;; empty list

;;; --- array-block / array-block!: assembles a d-dim array of d-dim
;;; blocks; the spec's own "block matrix" shape -- blocks sharing a row
;;; must share height, blocks sharing a column must share width. Each
;;; block below has a DELIBERATELY NONZERO lower bound and a
;;; position-dependent (not constant) value: a block that already sits
;;; at zero with a uniform value can't distinguish a correct
;;; local-index/block-lower-bound remap (assembly.sld's
;;; `(vector-map + local-idx block-lowers)`) from one that is missing,
;;; sign-flipped, or otherwise wrong -- every probed index would return
;;; the same value either way.
(define (pos-array h w tag lower-i lower-j)
  (array-translate (make-array (make-interval (vector h w)) (lambda (i j) (list tag i j)))
                    (vector lower-i lower-j)))
(let* ((b00 (pos-array 2 2 'a 5 7)) (b01 (pos-array 2 3 'b 3 2))
       (b10 (pos-array 3 2 'c 1 9)) (b11 (pos-array 3 3 'd 4 4))
       (blocks (vector (vector b00 b01) (vector b10 b11)))
       (a-of-a (make-array (make-interval (vector 2 2))
                            (lambda (i j) (vector-ref (vector-ref blocks i) j))))
       (r (array-block a-of-a)))
  (test-equal #t (interval= (array-domain r) (make-interval (vector 5 5))))
  (test-equal (array-ref b00 5 7) (array-ref r 0 0))
  (test-equal (array-ref b00 6 8) (array-ref r 1 1))
  (test-equal (array-ref b01 3 2) (array-ref r 0 2))
  (test-equal (array-ref b01 4 4) (array-ref r 1 4))
  (test-equal (array-ref b10 1 9) (array-ref r 2 0))
  (test-equal (array-ref b10 3 10) (array-ref r 4 1))
  (test-equal (array-ref b11 4 4) (array-ref r 2 2))
  (test-equal (array-ref b11 6 6) (array-ref r 4 4))
  (test-equal (array-ref r 3 3) (array-ref (array-block! a-of-a) 3 3))  ;; ! is a plain alias
  ;; round trip: array-tile(array-block(A)) reproduces the original blocks.
  ;; array-tile's sub-arrays come from array-extract, which preserves
  ;; ABSOLUTE source coordinates (never reset to 0-based) -- each tile is
  ;; probed at its own absolute corner within r, not at (0,0).
  (let* ((tiled (array-tile r (vector (vector 2 3) (vector 2 3))))
         (t00 (array-ref tiled 0 0)) (t01 (array-ref tiled 0 1))
         (t10 (array-ref tiled 1 0)) (t11 (array-ref tiled 1 1)))
    (test-equal (array-ref b00 5 7) (array-ref t00 0 0))
    (test-equal (array-ref b01 3 2) (array-ref t01 0 2))
    (test-equal (array-ref b10 1 9) (array-ref t10 2 0))
    (test-equal (array-ref b11 4 4) (array-ref t11 2 2)))
  ;; inconsistent widths across a shared column must error
  (let* ((bad-blocks (vector (vector b00 b01) (vector b10 (const-array 3 4 3))))
         (bad-a-of-a (make-array (make-interval (vector 2 2))
                                  (lambda (i j) (vector-ref (vector-ref bad-blocks i) j)))))
    (test-equal #t (guard (e (#t #t)) (array-block bad-a-of-a) #f))))
(test-equal #t (guard (e (#t #t))  ;; block dimension (1) must match outer array's dimension (2)
                  (array-block (make-array (make-interval (vector 2 2))
                                            (lambda (i j) (make-array (make-interval (vector 2)) (lambda (x) 0)))))
                  #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-231-assembly")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
