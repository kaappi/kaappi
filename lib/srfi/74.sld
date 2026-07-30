;;; SRFI 74 — Octet-Addressed Binary Blocks.
;;; A blob is a bytevector -- no reason for a second, incompatible
;;; byte-buffer type. Floating point is explicitly out of this SRFI's own
;;; scope (per its Rationale), so only integer accessors are needed here.
;;; `(endianness native)` resolves via `%host-big-endian?`, a tiny internal
;;; primitive exposing the real hardware byte order (src/primitives_r7rs.zig)
;;; -- this SRFI's own semantics require native-tagged accesses to observe
;;; actual hardware order (e.g. for interop with externally-produced binary
;;; data), which a portable implementation has no other way to learn on a
;;; genuinely big-endian host (kaappi supports s390x/ppc64le as first-class
;;; targets, so this can't be assumed little-endian).
(define-library (srfi 74)
  ;; (kaappi primitives): the internal %-prefixed helpers this file calls
  ;; below. They used to arrive with (scheme base), which reserved their
  ;; names against every user library (kaappi#1856).
  (import (scheme base) (srfi 160 u8) (kaappi primitives))
  (export endianness
          blob? make-blob blob-length blob-copy blob-copy!
          blob->u8-list u8-list->blob blob=?
          blob-u8-ref blob-s8-ref blob-u8-set! blob-s8-set!
          blob-uint-ref blob-sint-ref blob-uint-set! blob-sint-set!
          blob-u16-ref blob-s16-ref blob-u16-set! blob-s16-set!
          blob-u16-native-ref blob-s16-native-ref
          blob-u16-native-set! blob-s16-native-set!
          blob-u32-ref blob-s32-ref blob-u32-set! blob-s32-set!
          blob-u32-native-ref blob-s32-native-ref
          blob-u32-native-set! blob-s32-native-set!
          blob-u64-ref blob-s64-ref blob-u64-set! blob-s64-set!
          blob-u64-native-ref blob-s64-native-ref
          blob-u64-native-set! blob-s64-native-set!
          blob->uint-list blob->sint-list uint-list->blob sint-list->blob)
  (begin

    (define-syntax endianness
      (syntax-rules (big little native)
        ((_ big) 'big)
        ((_ little) 'little)
        ((_ native) (if (%host-big-endian?) 'big 'little))))

    (define blob? bytevector?)
    (define (make-blob k) (make-bytevector k 0))
    (define blob-length bytevector-length)
    (define blob-copy bytevector-copy)
    (define (blob-copy! source source-start target target-start n)
      (bytevector-copy! target target-start source source-start (+ source-start n)))
    (define blob->u8-list u8vector->list)
    (define u8-list->blob list->u8vector)
    (define (blob=? a b) (equal? a b))

    (define (blob-u8-ref b k) (bytevector-u8-ref b k))
    (define (blob-u8-set! b k v) (bytevector-u8-set! b k v))
    (define (blob-s8-ref b k)
      (let ((v (bytevector-u8-ref b k))) (if (> v 127) (- v 256) v)))
    (define (blob-s8-set! b k v)
      (bytevector-u8-set! b k (if (< v 0) (+ v 256) v)))

    ;; Horner assembly/disassembly, byte by byte -- there's no raw
    ;; word-level memory access at the Scheme level to make "native" mode
    ;; any faster than "big"/"little" here, and the spec's alignment
    ;; requirement for *-native-* accessors is a documented precondition
    ;; on the caller, not something this implementation needs to enforce.
    (define (blob-uint-ref size e blob k)
      (case e
        ((big)
         (let loop ((i 0) (acc 0))
           (if (= i size) acc (loop (+ i 1) (+ (* acc 256) (bytevector-u8-ref blob (+ k i)))))))
        ((little)
         (let loop ((i (- size 1)) (acc 0))
           (if (< i 0) acc (loop (- i 1) (+ (* acc 256) (bytevector-u8-ref blob (+ k i)))))))
        (else (error "blob-uint-ref: invalid endianness" e))))

    (define (blob-sint-ref size e blob k)
      (let* ((u (blob-uint-ref size e blob k))
             (bound (expt 2 (- (* 8 size) 1))))
        (if (>= u bound) (- u (* bound 2)) u)))

    (define (blob-uint-set! size e blob k n)
      (case e
        ((big)
         (let loop ((i (- size 1)) (v n))
           (when (>= i 0)
             (bytevector-u8-set! blob (+ k i) (modulo v 256))
             (loop (- i 1) (quotient v 256)))))
        ((little)
         (let loop ((i 0) (v n))
           (when (< i size)
             (bytevector-u8-set! blob (+ k i) (modulo v 256))
             (loop (+ i 1) (quotient v 256)))))
        (else (error "blob-uint-set!: invalid endianness" e))))

    (define (blob-sint-set! size e blob k n)
      (blob-uint-set! size e blob k (if (< n 0) (+ n (expt 2 (* 8 size))) n)))

    (define (blob-u16-ref e b k) (blob-uint-ref 2 e b k))
    (define (blob-s16-ref e b k) (blob-sint-ref 2 e b k))
    (define (blob-u16-set! e b k n) (blob-uint-set! 2 e b k n))
    (define (blob-s16-set! e b k n) (blob-sint-set! 2 e b k n))
    (define (blob-u16-native-ref b k) (blob-u16-ref (endianness native) b k))
    (define (blob-s16-native-ref b k) (blob-s16-ref (endianness native) b k))
    (define (blob-u16-native-set! b k n) (blob-u16-set! (endianness native) b k n))
    (define (blob-s16-native-set! b k n) (blob-s16-set! (endianness native) b k n))

    (define (blob-u32-ref e b k) (blob-uint-ref 4 e b k))
    (define (blob-s32-ref e b k) (blob-sint-ref 4 e b k))
    (define (blob-u32-set! e b k n) (blob-uint-set! 4 e b k n))
    (define (blob-s32-set! e b k n) (blob-sint-set! 4 e b k n))
    (define (blob-u32-native-ref b k) (blob-u32-ref (endianness native) b k))
    (define (blob-s32-native-ref b k) (blob-s32-ref (endianness native) b k))
    (define (blob-u32-native-set! b k n) (blob-u32-set! (endianness native) b k n))
    (define (blob-s32-native-set! b k n) (blob-s32-set! (endianness native) b k n))

    (define (blob-u64-ref e b k) (blob-uint-ref 8 e b k))
    (define (blob-s64-ref e b k) (blob-sint-ref 8 e b k))
    (define (blob-u64-set! e b k n) (blob-uint-set! 8 e b k n))
    (define (blob-s64-set! e b k n) (blob-sint-set! 8 e b k n))
    (define (blob-u64-native-ref b k) (blob-u64-ref (endianness native) b k))
    (define (blob-s64-native-ref b k) (blob-s64-ref (endianness native) b k))
    (define (blob-u64-native-set! b k n) (blob-u64-set! (endianness native) b k n))
    (define (blob-s64-native-set! b k n) (blob-s64-set! (endianness native) b k n))

    (define (blob->uint-list size e blob)
      (let ((n (quotient (blob-length blob) size)))
        (let loop ((i 0) (acc '()))
          (if (= i n) (reverse acc) (loop (+ i 1) (cons (blob-uint-ref size e blob (* i size)) acc))))))

    (define (blob->sint-list size e blob)
      (let ((n (quotient (blob-length blob) size)))
        (let loop ((i 0) (acc '()))
          (if (= i n) (reverse acc) (loop (+ i 1) (cons (blob-sint-ref size e blob (* i size)) acc))))))

    (define (uint-list->blob size e lst)
      (let* ((n (length lst)) (b (make-blob (* n size))))
        (let loop ((i 0) (lst lst))
          (if (null? lst) b
              (begin (blob-uint-set! size e b (* i size) (car lst)) (loop (+ i 1) (cdr lst)))))))

    (define (sint-list->blob size e lst)
      (let* ((n (length lst)) (b (make-blob (* n size))))
        (let loop ((i 0) (lst lst))
          (if (null? lst) b
              (begin (blob-sint-set! size e b (* i size) (car lst)) (loop (+ i 1) (cdr lst)))))))))
