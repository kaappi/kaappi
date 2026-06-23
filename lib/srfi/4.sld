;;; SRFI 4 — Homogeneous numeric vector datatypes
;;; Built on R7RS bytevectors with multi-byte access
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

    ;; u8vector = bytevector (direct alias)
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

    ;; s8vector (signed bytes, stored as u8, converted on access)
    (define s8vector? bytevector?)
    (define make-s8vector make-bytevector)
    (define (s8vector . vals)
      (let ((bv (make-bytevector (length vals) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs) bv
              (begin (s8vector-set! bv i (car vs))
                     (loop (+ i 1) (cdr vs)))))))
    (define s8vector-length bytevector-length)
    (define (s8vector-ref bv i)
      (let ((v (bytevector-u8-ref bv i)))
        (if (> v 127) (- v 256) v)))
    (define (s8vector-set! bv i val)
      (bytevector-u8-set! bv i (if (< val 0) (+ val 256) val)))
    (define (s8vector->list bv)
      (let loop ((i 0) (acc '()))
        (if (= i (bytevector-length bv)) (reverse acc)
            (loop (+ i 1) (cons (s8vector-ref bv i) acc)))))
    (define (list->s8vector lst) (apply s8vector lst))

    ;; Multi-byte helpers (little-endian)
    (define (bv-u16-ref bv i)
      (+ (bytevector-u8-ref bv (* i 2))
         (* (bytevector-u8-ref bv (+ (* i 2) 1)) 256)))
    (define (bv-u16-set! bv i val)
      (bytevector-u8-set! bv (* i 2) (modulo val 256))
      (bytevector-u8-set! bv (+ (* i 2) 1) (quotient val 256)))
    (define (bv-s16-ref bv i)
      (let ((v (bv-u16-ref bv i)))
        (if (> v 32767) (- v 65536) v)))
    (define (bv-s16-set! bv i val)
      (bv-u16-set! bv i (if (< val 0) (+ val 65536) val)))
    (define (bv-u32-ref bv i)
      (+ (bv-u16-ref bv (* i 2))
         (* (bv-u16-ref bv (+ (* i 2) 1)) 65536)))
    (define (bv-u32-set! bv i val)
      (bv-u16-set! bv (* i 2) (modulo val 65536))
      (bv-u16-set! bv (+ (* i 2) 1) (quotient val 65536)))
    (define (bv-s32-ref bv i)
      (let ((v (bv-u32-ref bv i)))
        (if (> v 2147483647) (- v 4294967296) v)))
    (define (bv-s32-set! bv i val)
      (bv-u32-set! bv i (if (< val 0) (+ val 4294967296) val)))

    ;; u16vector
    (define u16vector? bytevector?)
    (define (make-u16vector n . fill)
      (let ((bv (make-bytevector (* n 2) 0)))
        (when (pair? fill)
          (let loop ((i 0))
            (when (< i n) (bv-u16-set! bv i (car fill)) (loop (+ i 1)))))
        bv))
    (define (u16vector . vals)
      (let ((bv (make-bytevector (* (length vals) 2) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs) bv
              (begin (bv-u16-set! bv i (car vs)) (loop (+ i 1) (cdr vs)))))))
    (define (u16vector-length bv) (quotient (bytevector-length bv) 2))
    (define u16vector-ref bv-u16-ref)
    (define u16vector-set! bv-u16-set!)
    (define (u16vector->list bv)
      (let loop ((i 0) (acc '()))
        (if (= i (u16vector-length bv)) (reverse acc)
            (loop (+ i 1) (cons (bv-u16-ref bv i) acc)))))
    (define (list->u16vector lst) (apply u16vector lst))

    ;; s16vector
    (define s16vector? bytevector?)
    (define (make-s16vector n . fill)
      (let ((bv (make-bytevector (* n 2) 0)))
        (when (pair? fill)
          (let loop ((i 0))
            (when (< i n) (bv-s16-set! bv i (car fill)) (loop (+ i 1)))))
        bv))
    (define (s16vector . vals)
      (let ((bv (make-bytevector (* (length vals) 2) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs) bv
              (begin (bv-s16-set! bv i (car vs)) (loop (+ i 1) (cdr vs)))))))
    (define (s16vector-length bv) (quotient (bytevector-length bv) 2))
    (define s16vector-ref bv-s16-ref)
    (define s16vector-set! bv-s16-set!)
    (define (s16vector->list bv)
      (let loop ((i 0) (acc '()))
        (if (= i (s16vector-length bv)) (reverse acc)
            (loop (+ i 1) (cons (bv-s16-ref bv i) acc)))))
    (define (list->s16vector lst) (apply s16vector lst))

    ;; u32vector
    (define u32vector? bytevector?)
    (define (make-u32vector n . fill)
      (let ((bv (make-bytevector (* n 4) 0)))
        (when (pair? fill)
          (let loop ((i 0))
            (when (< i n) (bv-u32-set! bv i (car fill)) (loop (+ i 1)))))
        bv))
    (define (u32vector . vals)
      (let ((bv (make-bytevector (* (length vals) 4) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs) bv
              (begin (bv-u32-set! bv i (car vs)) (loop (+ i 1) (cdr vs)))))))
    (define (u32vector-length bv) (quotient (bytevector-length bv) 4))
    (define u32vector-ref bv-u32-ref)
    (define u32vector-set! bv-u32-set!)
    (define (u32vector->list bv)
      (let loop ((i 0) (acc '()))
        (if (= i (u32vector-length bv)) (reverse acc)
            (loop (+ i 1) (cons (bv-u32-ref bv i) acc)))))
    (define (list->u32vector lst) (apply u32vector lst))

    ;; s32vector
    (define s32vector? bytevector?)
    (define (make-s32vector n . fill)
      (let ((bv (make-bytevector (* n 4) 0)))
        (when (pair? fill)
          (let loop ((i 0))
            (when (< i n) (bv-s32-set! bv i (car fill)) (loop (+ i 1)))))
        bv))
    (define (s32vector . vals)
      (let ((bv (make-bytevector (* (length vals) 4) 0)))
        (let loop ((i 0) (vs vals))
          (if (null? vs) bv
              (begin (bv-s32-set! bv i (car vs)) (loop (+ i 1) (cdr vs)))))))
    (define (s32vector-length bv) (quotient (bytevector-length bv) 4))
    (define s32vector-ref bv-s32-ref)
    (define s32vector-set! bv-s32-set!)
    (define (s32vector->list bv)
      (let loop ((i 0) (acc '()))
        (if (= i (s32vector-length bv)) (reverse acc)
            (loop (+ i 1) (cons (bv-s32-ref bv i) acc)))))
    (define (list->s32vector lst) (apply s32vector lst))

    ;; f32vector / f64vector — store as inexact, indexed by element
    ;; Simplified: use vectors of inexact numbers (not bytevector-backed)
    (define f32vector? vector?)
    (define (make-f32vector n . fill)
      (make-vector n (if (pair? fill) (inexact (car fill)) 0.0)))
    (define (f32vector . vals) (list->vector (map inexact vals)))
    (define f32vector-length vector-length)
    (define f32vector-ref vector-ref)
    (define (f32vector-set! v i x) (vector-set! v i (inexact x)))
    (define (f32vector->list v) (vector->list v))
    (define (list->f32vector lst) (list->vector (map inexact lst)))

    (define f64vector? vector?)
    (define (make-f64vector n . fill)
      (make-vector n (if (pair? fill) (inexact (car fill)) 0.0)))
    (define (f64vector . vals) (list->vector (map inexact vals)))
    (define f64vector-length vector-length)
    (define f64vector-ref vector-ref)
    (define (f64vector-set! v i x) (vector-set! v i (inexact x)))
    (define (f64vector->list v) (vector->list v))
    (define (list->f64vector lst) (list->vector (map inexact lst)))))
