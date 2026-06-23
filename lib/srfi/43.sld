;;; SRFI 43 — Vector Library (predecessor to SRFI 133)
;;; Re-exports from SRFI 133 with SRFI 43 names
(define-library (srfi 43)
  (import (scheme base) (srfi 133))
  (export make-vector vector vector? vector-ref vector-set! vector-length
          vector-fold vector-fold-right
          vector-map vector-map!
          vector-for-each
          vector-count
          vector-index vector-index-right
          vector-skip vector-skip-right
          vector-any vector-every
          vector-copy vector-copy!
          vector-reverse-copy
          vector->list list->vector
          vector-fill!
          vector-swap!
          vector-append vector-concatenate
          vector-empty?)
  (begin
    (define (vector-fold kons knil vec)
      (let ((len (vector-length vec)))
        (let loop ((i 0) (acc knil))
          (if (= i len) acc
              (loop (+ i 1) (kons acc (vector-ref vec i)))))))

    (define (vector-fold-right kons knil vec)
      (let loop ((i (- (vector-length vec) 1)) (acc knil))
        (if (< i 0) acc
            (loop (- i 1) (kons acc (vector-ref vec i))))))

    (define (vector-map! f vec)
      (let ((len (vector-length vec)))
        (let loop ((i 0))
          (when (< i len)
            (vector-set! vec i (f (vector-ref vec i)))
            (loop (+ i 1))))))))
