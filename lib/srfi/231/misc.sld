;;; SRFI 231 -- Miscellaneous procedures (permutation/translation vectors).
;;;
;;; Phase 1a of #1694's SRFI 231 slice (see lib/srfi/231/intervals.sld for
;;; the overall roadmap note). These 6 procedures are pure vector utilities
;;; with zero dependency on intervals -- kept as their own tiny library
;;; since later array-transform phases (array-inner-product, array-block)
;;; need index-rotate/index-first/index-last directly without pulling in
;;; the whole interval layer, matching the spec's own "Miscellaneous
;;; procedures" section which precedes "Intervals" in its own document
;;; structure.
;;;
;;; translation?/permutation? per spec: a translation is "a vector of exact
;;; integers" (any length, any sign); a permutation of dimension n is "a
;;; vector whose entries are the exact integers 0,1,...,n-1, each occurring
;;; once, in any order" -- confirmed via direct primary-source fetch since
;;; neither is spelled out as executable pseudocode in the spec text itself.
(define-library (srfi 231 misc)
  (import (scheme base))
  (export translation? permutation? index-rotate index-first index-last index-swap)
  (begin

    (define (%vector-every pred v)
      (let loop ((i 0))
        (or (= i (vector-length v))
            (and (pred (vector-ref v i)) (loop (+ i 1))))))

    (define (translation? object)
      (and (vector? object) (%vector-every (lambda (x) (and (integer? x) (exact? x))) object)))

    (define (permutation? object)
      (and (vector? object)
           (let* ((n (vector-length object)) (seen (make-vector n #f)))
             (let loop ((i 0))
               (or (= i n)
                   (let ((x (vector-ref object i)))
                     (and (integer? x) (exact? x) (<= 0 x) (< x n)
                          (not (vector-ref seen x))
                          (begin (vector-set! seen x #t) (loop (+ i 1))))))))))

    ;; (index-rotate 5 3) => #(3 4 0 1 2)
    (define (index-rotate n k)
      (let ((v (make-vector n 0)))
        (let loop ((i 0))
          (when (< i n)
            (vector-set! v i (modulo (+ i k) n))
            (loop (+ i 1))))
        v))

    ;; (index-first 5 3) => #(3 0 1 2 4)
    (define (index-first n k)
      (let ((v (make-vector n 0)) (pos 1))
        (vector-set! v 0 k)
        (let loop ((i 0))
          (when (< i n)
            (unless (= i k)
              (vector-set! v pos i)
              (set! pos (+ pos 1)))
            (loop (+ i 1))))
        v))

    ;; (index-last 5 3) => #(0 1 2 4 3)
    (define (index-last n k)
      (let ((v (make-vector n 0)) (pos 0))
        (let loop ((i 0))
          (when (< i n)
            (unless (= i k)
              (vector-set! v pos i)
              (set! pos (+ pos 1)))
            (loop (+ i 1))))
        (vector-set! v (- n 1) k)
        v))

    ;; (index-swap 5 3 0) => #(3 1 2 0 4)
    (define (index-swap n i j)
      (let ((v (make-vector n 0)))
        (let loop ((k 0))
          (when (< k n)
            (vector-set! v k k)
            (loop (+ k 1))))
        (let ((vi (vector-ref v i)))
          (vector-set! v i (vector-ref v j))
          (vector-set! v j vi))
        v))))
