;; SRFI-4 (homogeneous numeric vector datatypes) tests — audit Phase 3e
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi4.scm

(import (scheme base) (srfi 4) (scheme process-context) (srfi 64))

(test-begin "srfi-4")

;;; --- u8 ---
(let ((v (make-u8vector 3 7)))
  (test-equal #t (u8vector? v))
  (test-equal 3 (u8vector-length v))
  (test-equal 7 (u8vector-ref v 0))
  (u8vector-set! v 1 255)
  (test-equal 255 (u8vector-ref v 1))
  (test-equal '(7 255 7) (u8vector->list v)))
(test-equal #t (u8vector? (u8vector 1 2)))
(test-equal '(1 2) (u8vector->list (list->u8vector '(1 2))))
(test-equal #f (u8vector? "not"))

;;; --- s8 signed range ---
(let ((v (s8vector -128 0 127)))
  (test-equal #t (s8vector? v))
  (test-equal -128 (s8vector-ref v 0))
  (test-equal 127 (s8vector-ref v 2))
  (s8vector-set! v 1 -1)
  (test-equal -1 (s8vector-ref v 1)))
(test-equal '(-5 5) (s8vector->list (list->s8vector '(-5 5))))
(test-equal 3 (s8vector-length (make-s8vector 3)))
(test-equal '(42 42) (s8vector->list (make-s8vector 2 42)))

;;; --- u16 / s16 ---
(let ((v (u16vector 0 65535)))
  (test-equal 65535 (u16vector-ref v 1))
  (test-equal 2 (u16vector-length v)))
(let ((v (s16vector -32768 32767)))
  (test-equal -32768 (s16vector-ref v 0))
  (test-equal 32767 (s16vector-ref v 1)))
(test-equal '(1 2) (u16vector->list (list->u16vector '(1 2))))
(test-equal 3 (u16vector-length (make-u16vector 3)))
(test-equal '(100 100) (u16vector->list (make-u16vector 2 100)))
(test-equal '(-1 1) (s16vector->list (list->s16vector '(-1 1))))
(test-equal '(-5 -5) (s16vector->list (make-s16vector 2 -5)))

;;; --- u32 / s32 ---
(let ((v (u32vector 4294967295)))
  (test-equal 4294967295 (u32vector-ref v 0)))
(let ((v (s32vector -2147483648 2147483647)))
  (test-equal -2147483648 (s32vector-ref v 0))
  (test-equal 2147483647 (s32vector-ref v 1)))
(test-equal 4 (u32vector-length (make-u32vector 4 0)))
(test-equal '(999 999) (u32vector->list (make-u32vector 2 999)))
(test-equal '(-100 100) (s32vector->list (list->s32vector '(-100 100))))
(test-equal '(-7 -7) (s32vector->list (make-s32vector 2 -7)))

;;; --- f32 / f64 ---
(let ((v (f64vector 1.5 -2.5)))
  (test-equal #t (f64vector? v))
  (test-equal 1.5 (f64vector-ref v 0))
  (f64vector-set! v 1 3.25)
  (test-equal 3.25 (f64vector-ref v 1)))
(let ((v (f32vector 0.5)))
  (test-equal #t (f32vector? v))
  (test-equal 0.5 (f32vector-ref v 0)))
(test-equal '(1.0 2.0) (f64vector->list (list->f64vector '(1.0 2.0))))
(test-equal '(3.0 3.0) (f64vector->list (make-f64vector 2 3.0)))
(test-equal '(0.5 0.5) (f32vector->list (make-f32vector 2 0.5)))

;;; --- type disjointness among the vector kinds ---
(test-equal #f (s8vector? (u8vector 1)))
(test-equal #f (u16vector? (u8vector 1)))
(test-equal #f (u8vector? (s8vector 1)))
(test-equal #f (u32vector? (s32vector 1)))
(test-equal #f (s32vector? (u32vector 1)))
(test-equal #f (u16vector? (s16vector 1)))
(test-equal #f (s16vector? (u16vector 1)))
(test-equal #f (f32vector? (f64vector 1.0)))
(test-equal #f (f64vector? (f32vector 1.0)))
(test-equal #f (f64vector? (u32vector 1)))
(test-equal #f (u8vector? (vector 1)))
(test-equal #f (f64vector? (vector 1)))
(test-equal #f (f32vector? (vector 1)))
(test-equal #f (u8vector? (f64vector 1.0)))
(test-equal #f (s8vector? (u16vector 1)))

;;; --- out-of-range / bad-index errors are catchable ---
;; u8 range errors (from bytevector-u8-set!)
(test-equal #t (guard (e (#t #t)) (u8vector-set! (u8vector 1) 0 256) #f))
(test-equal #t (guard (e (#t #t)) (u8vector-set! (u8vector 1) 0 -1) #f))
(test-equal #t (guard (e (#t #t)) (u8vector-ref (u8vector 1) 5) #f))
;; s8 range errors
(test-equal #t (guard (e (#t #t)) (s8vector-set! (s8vector 1) 0 128) #f))
(test-equal #t (guard (e (#t #t)) (s8vector-set! (s8vector 1) 0 -129) #f))
(test-equal #t (guard (e (#t #t)) (s8vector 200) #f))
;; u16 range errors
(test-equal #t (guard (e (#t #t)) (u16vector-set! (u16vector 1) 0 65536) #f))
(test-equal #t (guard (e (#t #t)) (u16vector-set! (u16vector 1) 0 -1) #f))
(test-equal #t (guard (e (#t #t)) (u16vector 70000) #f))
;; s16 range errors
(test-equal #t (guard (e (#t #t)) (s16vector-set! (s16vector 1) 0 32768) #f))
(test-equal #t (guard (e (#t #t)) (s16vector-set! (s16vector 1) 0 -32769) #f))
;; u32 range errors
(test-equal #t (guard (e (#t #t)) (u32vector-set! (u32vector 1) 0 4294967296) #f))
(test-equal #t (guard (e (#t #t)) (u32vector-set! (u32vector 1) 0 -1) #f))
;; s32 range errors
(test-equal #t (guard (e (#t #t)) (s32vector-set! (s32vector 1) 0 2147483648) #f))
(test-equal #t (guard (e (#t #t)) (s32vector-set! (s32vector 1) 0 -2147483649) #f))

;;; --- mutation through set! ---
(let ((v (u16vector 10 20)))
  (u16vector-set! v 0 30000)
  (test-equal 30000 (u16vector-ref v 0)))
(let ((v (s32vector 0)))
  (s32vector-set! v 0 -1000000)
  (test-equal -1000000 (s32vector-ref v 0)))

(let ((runner (test-runner-current)))
  (test-end "srfi-4")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
