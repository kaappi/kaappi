;;; SRFI 66 — Octet Vectors.
;;; u8vector = bytevector; the 8 SRFI-4-shaped core procedures plus
;;; u8vector-copy are re-exported unchanged from (srfi 160 u8). Only
;;; u8vector-copy! (different argument order than R7RS bytevector-copy!),
;;; u8vector=?, and u8vector-compare (SRFI 67-style 3-way ordering) are
;;; new logic.
(define-library (srfi 66)
  (import (scheme base) (srfi 160 u8))
  (export u8vector? make-u8vector u8vector u8vector-length
          u8vector-ref u8vector-set! u8vector->list list->u8vector
          u8vector-copy u8vector-copy! u8vector=? u8vector-compare)
  (begin

    ;; SRFI 66: (u8vector-copy! source source-start target target-start n)
    ;; vs. R7RS's (bytevector-copy! to at from [start [end]]) -- adapt.
    (define (u8vector-copy! source source-start target target-start n)
      (bytevector-copy! target target-start source source-start (+ source-start n)))

    (define (u8vector=? a b) (equal? a b))

    (define (u8vector-compare a b)
      (let ((la (u8vector-length a)) (lb (u8vector-length b)))
        (cond
         ((< la lb) -1)
         ((> la lb) 1)
         (else
          (let loop ((i 0))
            (cond ((= i la) 0)
                  ((< (u8vector-ref a i) (u8vector-ref b i)) -1)
                  ((> (u8vector-ref a i) (u8vector-ref b i)) 1)
                  (else (loop (+ i 1)))))))))))
