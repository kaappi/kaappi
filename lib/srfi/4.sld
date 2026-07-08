;;; SRFI 4 — Homogeneous numeric vector datatypes
;;; Each kind is a disjoint record type wrapping a bytevector (integer kinds)
;;; or a vector (float kinds). u8vector is the same as R7RS bytevector.
(define-library (srfi 4)
  (import (scheme base))
  (export u8vector? make-u8vector u8vector u8vector-length
          u8vector-ref u8vector-set! u8vector->list list->u8vector
          s8vector? make-s8vector s8vector s8vector-length
          s8vector-ref s8vector-set! s8vector->list list->s8vector
          u16vector? make-u16vector u16vector u16vector-length
          u16vector-ref u16vector-set! u16vector->list list->u16vector
          s16vector? make-s16vector s16vector s16vector-length
          s16vector-ref s16vector-set! s16vector->list list->s16vector
          u32vector? make-u32vector u32vector u32vector-length
          u32vector-ref u32vector-set! u32vector->list list->u32vector
          s32vector? make-s32vector s32vector s32vector-length
          s32vector-ref s32vector-set! s32vector->list list->s32vector
          f32vector? make-f32vector f32vector f32vector-length
          f32vector-ref f32vector-set! f32vector->list list->f32vector
          f64vector? make-f64vector f64vector f64vector-length
          f64vector-ref f64vector-set! f64vector->list list->f64vector)
  (begin

    ;; u8vector = bytevector (direct alias, per SRFI-4 spec)
    (define u8vector? bytevector?)
    (define make-u8vector make-bytevector)
    (define (u8vector . vals) (apply bytevector vals))
    (define u8vector-length bytevector-length)
    (define u8vector-ref bytevector-u8-ref)
    (define u8vector-set! bytevector-u8-set!)
    (define (u8vector->list bv)
      (let loop ((i 0) (acc '()))
        (if (= i (bytevector-length bv)) (reverse acc)
            (loop (+ i 1) (cons (bytevector-u8-ref bv i) acc)))))
    (define (list->u8vector lst) (apply bytevector lst))

    ;; --- Record types for non-u8 integer kinds ---

    (define-record-type <s8vector>
      (%make-s8vector bv)
      s8vector?
      (bv s8vector-bv))

    (define-record-type <u16vector>
      (%make-u16vector bv)
      u16vector?
      (bv u16vector-bv))

    (define-record-type <s16vector>
      (%make-s16vector bv)
      s16vector?
      (bv s16vector-bv))

    (define-record-type <u32vector>
      (%make-u32vector bv)
      u32vector?
      (bv u32vector-bv))

    (define-record-type <s32vector>
      (%make-s32vector bv)
      s32vector?
      (bv s32vector-bv))

    ;; --- Record types for float kinds ---

    (define-record-type <f32vector>
      (%make-f32vector vec)
      f32vector?
      (vec f32vector-vec))

    (define-record-type <f64vector>
      (%make-f64vector vec)
      f64vector?
      (vec f64vector-vec))

    ;; --- Multi-byte helpers (little-endian, operate on raw bytevectors) ---

    (define (bv-u16-ref bv i)
      (+ (bytevector-u8-ref bv (* i 2))
         (* (bytevector-u8-ref bv (+ (* i 2) 1)) 256)))
    (define (bv-u16-set! bv i val)
      (bytevector-u8-set! bv (* i 2) (modulo val 256))
      (bytevector-u8-set! bv (+ (* i 2) 1) (quotient val 256)))
    (define (bv-u32-ref bv i)
      (+ (bv-u16-ref bv (* i 2))
         (* (bv-u16-ref bv (+ (* i 2) 1)) 65536)))
    (define (bv-u32-set! bv i val)
      (bv-u16-set! bv (* i 2) (modulo val 65536))
      (bv-u16-set! bv (+ (* i 2) 1) (quotient val 65536)))

    ;; --- s8vector ---

    (define (make-s8vector n . fill)
      (let ((bv (make-bytevector n 0)))
        (when (pair? fill)
          (let ((f (car fill)))
            (unless (and (integer? f) (<= -128 f 127))
              (error "make-s8vector: value out of range" f))
            (let ((u (if (< f 0) (+ f 256) f)))
              (let loop ((i 0))
                (when (< i n) (bytevector-u8-set! bv i u) (loop (+ i 1)))))))
        (%make-s8vector bv)))
    (define (s8vector . vals)
      (let ((bv (make-bytevector (length vals) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs)
              (%make-s8vector bv)
              (let ((v (car vs)))
                (unless (and (integer? v) (<= -128 v 127))
                  (error "s8vector: value out of range" v))
                (bytevector-u8-set! bv i (if (< v 0) (+ v 256) v))
                (loop (+ i 1) (cdr vs)))))))
    (define (s8vector-length sv) (bytevector-length (s8vector-bv sv)))
    (define (s8vector-ref sv i)
      (let ((v (bytevector-u8-ref (s8vector-bv sv) i)))
        (if (> v 127) (- v 256) v)))
    (define (s8vector-set! sv i val)
      (unless (and (integer? val) (<= -128 val 127))
        (error "s8vector-set!: value out of range" val))
      (bytevector-u8-set! (s8vector-bv sv) i (if (< val 0) (+ val 256) val)))
    (define (s8vector->list sv)
      (let ((bv (s8vector-bv sv)))
        (let loop ((i 0) (acc '()))
          (if (= i (bytevector-length bv)) (reverse acc)
              (loop (+ i 1)
                    (cons (let ((v (bytevector-u8-ref bv i)))
                            (if (> v 127) (- v 256) v))
                          acc))))))
    (define (list->s8vector lst) (apply s8vector lst))

    ;; --- u16vector ---

    (define (make-u16vector n . fill)
      (let ((bv (make-bytevector (* n 2) 0)))
        (when (pair? fill)
          (let ((f (car fill)))
            (unless (and (integer? f) (<= 0 f 65535))
              (error "make-u16vector: value out of range" f))
            (let loop ((i 0))
              (when (< i n) (bv-u16-set! bv i f) (loop (+ i 1))))))
        (%make-u16vector bv)))
    (define (u16vector . vals)
      (let ((bv (make-bytevector (* (length vals) 2) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs)
              (%make-u16vector bv)
              (let ((v (car vs)))
                (unless (and (integer? v) (<= 0 v 65535))
                  (error "u16vector: value out of range" v))
                (bv-u16-set! bv i v)
                (loop (+ i 1) (cdr vs)))))))
    (define (u16vector-length uv) (quotient (bytevector-length (u16vector-bv uv)) 2))
    (define (u16vector-ref uv i) (bv-u16-ref (u16vector-bv uv) i))
    (define (u16vector-set! uv i val)
      (unless (and (integer? val) (<= 0 val 65535))
        (error "u16vector-set!: value out of range" val))
      (bv-u16-set! (u16vector-bv uv) i val))
    (define (u16vector->list uv)
      (let ((bv (u16vector-bv uv)))
        (let loop ((i 0) (n (u16vector-length uv)) (acc '()))
          (if (= i n) (reverse acc)
              (loop (+ i 1) n (cons (bv-u16-ref bv i) acc))))))
    (define (list->u16vector lst) (apply u16vector lst))

    ;; --- s16vector ---

    (define (make-s16vector n . fill)
      (let ((bv (make-bytevector (* n 2) 0)))
        (when (pair? fill)
          (let ((f (car fill)))
            (unless (and (integer? f) (<= -32768 f 32767))
              (error "make-s16vector: value out of range" f))
            (let ((u (if (< f 0) (+ f 65536) f)))
              (let loop ((i 0))
                (when (< i n) (bv-u16-set! bv i u) (loop (+ i 1)))))))
        (%make-s16vector bv)))
    (define (s16vector . vals)
      (let ((bv (make-bytevector (* (length vals) 2) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs)
              (%make-s16vector bv)
              (let ((v (car vs)))
                (unless (and (integer? v) (<= -32768 v 32767))
                  (error "s16vector: value out of range" v))
                (bv-u16-set! bv i (if (< v 0) (+ v 65536) v))
                (loop (+ i 1) (cdr vs)))))))
    (define (s16vector-length sv) (quotient (bytevector-length (s16vector-bv sv)) 2))
    (define (s16vector-ref sv i)
      (let ((v (bv-u16-ref (s16vector-bv sv) i)))
        (if (> v 32767) (- v 65536) v)))
    (define (s16vector-set! sv i val)
      (unless (and (integer? val) (<= -32768 val 32767))
        (error "s16vector-set!: value out of range" val))
      (bv-u16-set! (s16vector-bv sv) i (if (< val 0) (+ val 65536) val)))
    (define (s16vector->list sv)
      (let ((bv (s16vector-bv sv)))
        (let loop ((i 0) (n (s16vector-length sv)) (acc '()))
          (if (= i n) (reverse acc)
              (loop (+ i 1) n
                    (cons (let ((v (bv-u16-ref bv i)))
                            (if (> v 32767) (- v 65536) v))
                          acc))))))
    (define (list->s16vector lst) (apply s16vector lst))

    ;; --- u32vector ---

    (define (make-u32vector n . fill)
      (let ((bv (make-bytevector (* n 4) 0)))
        (when (pair? fill)
          (let ((f (car fill)))
            (unless (and (integer? f) (<= 0 f 4294967295))
              (error "make-u32vector: value out of range" f))
            (let loop ((i 0))
              (when (< i n) (bv-u32-set! bv i f) (loop (+ i 1))))))
        (%make-u32vector bv)))
    (define (u32vector . vals)
      (let ((bv (make-bytevector (* (length vals) 4) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs)
              (%make-u32vector bv)
              (let ((v (car vs)))
                (unless (and (integer? v) (<= 0 v 4294967295))
                  (error "u32vector: value out of range" v))
                (bv-u32-set! bv i v)
                (loop (+ i 1) (cdr vs)))))))
    (define (u32vector-length uv) (quotient (bytevector-length (u32vector-bv uv)) 4))
    (define (u32vector-ref uv i) (bv-u32-ref (u32vector-bv uv) i))
    (define (u32vector-set! uv i val)
      (unless (and (integer? val) (<= 0 val 4294967295))
        (error "u32vector-set!: value out of range" val))
      (bv-u32-set! (u32vector-bv uv) i val))
    (define (u32vector->list uv)
      (let ((bv (u32vector-bv uv)))
        (let loop ((i 0) (n (u32vector-length uv)) (acc '()))
          (if (= i n) (reverse acc)
              (loop (+ i 1) n (cons (bv-u32-ref bv i) acc))))))
    (define (list->u32vector lst) (apply u32vector lst))

    ;; --- s32vector ---

    (define (make-s32vector n . fill)
      (let ((bv (make-bytevector (* n 4) 0)))
        (when (pair? fill)
          (let ((f (car fill)))
            (unless (and (integer? f) (<= -2147483648 f 2147483647))
              (error "make-s32vector: value out of range" f))
            (let ((u (if (< f 0) (+ f 4294967296) f)))
              (let loop ((i 0))
                (when (< i n) (bv-u32-set! bv i u) (loop (+ i 1)))))))
        (%make-s32vector bv)))
    (define (s32vector . vals)
      (let ((bv (make-bytevector (* (length vals) 4) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs)
              (%make-s32vector bv)
              (let ((v (car vs)))
                (unless (and (integer? v) (<= -2147483648 v 2147483647))
                  (error "s32vector: value out of range" v))
                (bv-u32-set! bv i (if (< v 0) (+ v 4294967296) v))
                (loop (+ i 1) (cdr vs)))))))
    (define (s32vector-length sv) (quotient (bytevector-length (s32vector-bv sv)) 4))
    (define (s32vector-ref sv i)
      (let ((v (bv-u32-ref (s32vector-bv sv) i)))
        (if (> v 2147483647) (- v 4294967296) v)))
    (define (s32vector-set! sv i val)
      (unless (and (integer? val) (<= -2147483648 val 2147483647))
        (error "s32vector-set!: value out of range" val))
      (bv-u32-set! (s32vector-bv sv) i (if (< val 0) (+ val 4294967296) val)))
    (define (s32vector->list sv)
      (let ((bv (s32vector-bv sv)))
        (let loop ((i 0) (n (s32vector-length sv)) (acc '()))
          (if (= i n) (reverse acc)
              (loop (+ i 1) n
                    (cons (let ((v (bv-u32-ref bv i)))
                            (if (> v 2147483647) (- v 4294967296) v))
                          acc))))))
    (define (list->s32vector lst) (apply s32vector lst))

    ;; --- f32vector (stores inexact numbers in a wrapped vector) ---

    (define (make-f32vector n . fill)
      (%make-f32vector
       (make-vector n (if (pair? fill) (inexact (car fill)) 0.0))))
    (define (f32vector . vals)
      (%make-f32vector (list->vector (map inexact vals))))
    (define (f32vector-length fv) (vector-length (f32vector-vec fv)))
    (define (f32vector-ref fv i) (vector-ref (f32vector-vec fv) i))
    (define (f32vector-set! fv i x) (vector-set! (f32vector-vec fv) i (inexact x)))
    (define (f32vector->list fv) (vector->list (f32vector-vec fv)))
    (define (list->f32vector lst)
      (%make-f32vector (list->vector (map inexact lst))))

    ;; --- f64vector (stores inexact numbers in a wrapped vector) ---

    (define (make-f64vector n . fill)
      (%make-f64vector
       (make-vector n (if (pair? fill) (inexact (car fill)) 0.0))))
    (define (f64vector . vals)
      (%make-f64vector (list->vector (map inexact vals))))
    (define (f64vector-length fv) (vector-length (f64vector-vec fv)))
    (define (f64vector-ref fv i) (vector-ref (f64vector-vec fv) i))
    (define (f64vector-set! fv i x) (vector-set! (f64vector-vec fv) i (inexact x)))
    (define (f64vector->list fv) (vector->list (f64vector-vec fv)))
    (define (list->f64vector lst)
      (%make-f64vector (list->vector (map inexact lst))))))
