(import (scheme base) (scheme write) (srfi 64))

(test-begin "ffi-callbacks")

;; --- Predicates and lifecycle ---

(define lib (ffi-open #f))

(define cb (ffi-callback (lambda (a b) 0) '(pointer pointer) 'int))
(test-assert "ffi-callback? on callback" (ffi-callback? cb))
(test-assert "ffi-callback? on non-callback" (not (ffi-callback? 42)))
(test-assert "ffi-callback? on string" (not (ffi-callback? "hello")))

(ffi-callback-release cb)
(test-assert "released callback still satisfies predicate" (ffi-callback? cb))

;; --- qsort with Scheme comparator ---

(define bv (make-bytevector 20 0))
;; Write 5 int32 values (little-endian, single-byte values for simplicity)
(bytevector-u8-set! bv 0 5)
(bytevector-u8-set! bv 4 3)
(bytevector-u8-set! bv 8 1)
(bytevector-u8-set! bv 12 4)
(bytevector-u8-set! bv 16 2)

(define base-ptr (ffi-bytevector-ptr bv))

(define int-cmp
  (ffi-callback
    (lambda (a b)
      (let ((va (bytevector-u8-ref bv (- a base-ptr)))
            (vb (bytevector-u8-ref bv (- b base-ptr))))
        (- va vb)))
    '(pointer pointer) 'int))

;; qsort's true signature: void qsort(void *, size_t, size_t, cmp).
;; size_t (not long) matters on Windows, where long is only 32 bits.
(define c-qsort (ffi-fn lib "qsort" '(pointer size_t size_t pointer) 'void))
(c-qsort base-ptr 5 4 int-cmp)

;; Verify sorted order
(test-equal "qsort result[0]" 1 (bytevector-u8-ref bv 0))
(test-equal "qsort result[1]" 2 (bytevector-u8-ref bv 4))
(test-equal "qsort result[2]" 3 (bytevector-u8-ref bv 8))
(test-equal "qsort result[3]" 4 (bytevector-u8-ref bv 12))
(test-equal "qsort result[4]" 5 (bytevector-u8-ref bv 16))

;; --- Reverse sort ---

(define rev-cmp
  (ffi-callback
    (lambda (a b)
      (let ((va (bytevector-u8-ref bv (- a base-ptr)))
            (vb (bytevector-u8-ref bv (- b base-ptr))))
        (- vb va)))
    '(pointer pointer) 'int))

(c-qsort base-ptr 5 4 rev-cmp)

(test-equal "reverse sort[0]" 5 (bytevector-u8-ref bv 0))
(test-equal "reverse sort[4]" 1 (bytevector-u8-ref bv 16))

;; --- Cleanup ---

(ffi-callback-release int-cmp)
(ffi-callback-release rev-cmp)
(ffi-close lib)

(test-end "ffi-callbacks")
