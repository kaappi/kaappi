;; SRFI 74 (octet-addressed binary blocks) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi74.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 74))

(test-begin "srfi-74")

(test-equal #t (eq? (endianness big) (endianness big)))
(test-equal #f (eq? (endianness big) (endianness little)))
(test-assert (or (eq? (endianness native) (endianness big))
                  (eq? (endianness native) (endianness little))))

(test-equal #t (blob? (make-blob 4)))
(test-equal #t (bytevector? (make-blob 4)))
(test-equal 4 (blob-length (make-blob 4)))
(test-equal '(0 0 0 0) (blob->u8-list (make-blob 4)))
(test-equal '(9 8 7) (blob->u8-list (u8-list->blob '(9 8 7))))
(test-equal #t (blob=? (make-blob 2) (u8-list->blob '(0 0))))
(test-equal #f (blob=? (u8-list->blob '(1 2)) (u8-list->blob '(1 3))))
(test-equal '(1 2 3) (blob->u8-list (blob-copy (u8-list->blob '(1 2 3)))))

(let ((a (u8-list->blob '(1 2 3))) (b (make-blob 3)))
  (blob-copy! a 1 b 0 2)
  (test-equal '(2 3 0) (blob->u8-list b)))

;; single-byte accessors
(let ((b (make-blob 2)))
  (blob-u8-set! b 0 200)
  (test-equal 200 (blob-u8-ref b 0))
  (blob-s8-set! b 1 -1)
  (test-equal -1 (blob-s8-ref b 1))
  (test-equal 255 (blob-u8-ref b 1)))

;; fixed-width big/little round trips
(let ((b (make-blob 8)))
  (blob-u16-set! (endianness big) b 0 #x0102)
  (test-equal '(1 2) (list (blob-u8-ref b 0) (blob-u8-ref b 1)))
  (test-equal 258 (blob-u16-ref (endianness big) b 0))
  (blob-u16-set! (endianness little) b 2 #x0102)
  (test-equal '(2 1) (list (blob-u8-ref b 2) (blob-u8-ref b 3)))
  (test-equal 258 (blob-u16-ref (endianness little) b 2))
  (blob-s16-set! (endianness big) b 4 -1)
  (test-equal -1 (blob-s16-ref (endianness big) b 4))
  (test-equal 65535 (blob-u16-ref (endianness big) b 4)))

(let ((b (make-blob 4)))
  (blob-u32-set! (endianness big) b 0 #xDEADBEEF)
  (test-equal #xDEADBEEF (blob-u32-ref (endianness big) b 0))
  (test-equal (list #xDE #xAD #xBE #xEF)
    (list (blob-u8-ref b 0) (blob-u8-ref b 1) (blob-u8-ref b 2) (blob-u8-ref b 3))))

(let ((b (make-blob 8)))
  (blob-s64-set! (endianness little) b 0 -123456789012345)
  (test-equal -123456789012345 (blob-s64-ref (endianness little) b 0)))

;; native accessors agree with explicit-endianness accessors
(let ((b1 (make-blob 4)) (b2 (make-blob 4)))
  (blob-u32-native-set! b1 0 42)
  (blob-u32-set! (endianness native) b2 0 42)
  (test-equal (blob->u8-list b1) (blob->u8-list b2))
  (test-equal 42 (blob-u32-native-ref b1 0)))

;; generic uint/sint at arbitrary sizes
(let ((b (make-blob 5)))
  (blob-uint-set! 5 (endianness big) b 0 1099511627775) ; 2^40 - 1
  (test-equal 1099511627775 (blob-uint-ref 5 (endianness big) b 0)))
(let ((b (make-blob 3)))
  (blob-sint-set! 3 (endianness little) b 0 -8388608) ; -(2^23)
  (test-equal -8388608 (blob-sint-ref 3 (endianness little) b 0)))

;; list conversions
(test-equal '(1 2 3) (blob->uint-list 2 (endianness big) (uint-list->blob 2 (endianness big) '(1 2 3))))
(test-equal '(-1 -2 3) (blob->sint-list 2 (endianness little) (sint-list->blob 2 (endianness little) '(-1 -2 3))))

(let ((runner (test-runner-current)))
  (test-end "srfi-74")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
