(define-library (srfi 60)
  (import (scheme base) (scheme case-lambda) (srfi 151))
  (export
    ;; bitwise operations — log* names
    logand logior logxor lognot logtest logbit?
    ;; bitwise operations — SRFI-33/bitwise-* names
    bitwise-and bitwise-ior bitwise-xor bitwise-not
    bitwise-if bitwise-merge
    any-bits-set? bit-set?
    ;; shifting, counting, field ops
    ash arithmetic-shift
    logcount bit-count integer-length
    log2-binary-factors first-set-bit
    copy-bit bit-field copy-bit-field
    rotate-bit-field reverse-bit-field
    ;; boolean/integer conversions
    integer->list list->integer booleans->integer)
  (begin
    (define logand bitwise-and)
    (define logior bitwise-ior)
    (define logxor bitwise-xor)
    (define lognot bitwise-not)
    (define ash arithmetic-shift)
    (define logcount bit-count)
    (define any-bits-set? any-bit-set?)
    (define logtest any-bit-set?)
    (define logbit? bit-set?)
    (define bitwise-merge bitwise-if)
    (define log2-binary-factors first-set-bit)
    (define copy-bit-field bit-field-replace-same)
    (define rotate-bit-field bit-field-rotate)
    (define reverse-bit-field bit-field-reverse)

    (define integer->list
      (case-lambda
        ((k) (integer->list k (integer-length k)))
        ((k len)
         (let loop ((i 0) (result '()))
           (if (= i len) result
               (loop (+ i 1) (cons (bit-set? i k) result)))))))

    (define (list->integer lst)
      (let loop ((l lst) (result 0))
        (if (null? l) result
            (loop (cdr l) (+ (* result 2) (if (car l) 1 0))))))

    (define (booleans->integer . bools)
      (list->integer bools))))
