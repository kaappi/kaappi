;; SRFI-4 (homogeneous numeric vector datatypes) tests — audit Phase 3e
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi4.scm

(import (scheme base) (srfi 4) (chibi test))

(test-begin "srfi-4")

;;; --- u8 ---
(let ((v (make-u8vector 3 7)))
  (test #t (u8vector? v))
  (test 3 (u8vector-length v))
  (test 7 (u8vector-ref v 0))
  (u8vector-set! v 1 255)
  (test 255 (u8vector-ref v 1))
  (test '(7 255 7) (u8vector->list v)))
(test #t (u8vector? (u8vector 1 2)))
(test '(1 2) (u8vector->list (list->u8vector '(1 2))))
(test #f (u8vector? "not"))

;;; --- s8 signed range ---
(let ((v (s8vector -128 0 127)))
  (test #t (s8vector? v))
  (test -128 (s8vector-ref v 0))
  (test 127 (s8vector-ref v 2))
  (s8vector-set! v 1 -1)
  (test -1 (s8vector-ref v 1)))
(test '(-5 5) (s8vector->list (list->s8vector '(-5 5))))
(test 3 (s8vector-length (make-s8vector 3)))
(test '(42 42) (s8vector->list (make-s8vector 2 42)))

;;; --- u16 / s16 ---
(let ((v (u16vector 0 65535)))
  (test 65535 (u16vector-ref v 1))
  (test 2 (u16vector-length v)))
(let ((v (s16vector -32768 32767)))
  (test -32768 (s16vector-ref v 0))
  (test 32767 (s16vector-ref v 1)))
(test '(1 2) (u16vector->list (list->u16vector '(1 2))))
(test 3 (u16vector-length (make-u16vector 3)))
(test '(100 100) (u16vector->list (make-u16vector 2 100)))
(test '(-1 1) (s16vector->list (list->s16vector '(-1 1))))
(test '(-5 -5) (s16vector->list (make-s16vector 2 -5)))

;;; --- u32 / s32 ---
(let ((v (u32vector 4294967295)))
  (test 4294967295 (u32vector-ref v 0)))
(let ((v (s32vector -2147483648 2147483647)))
  (test -2147483648 (s32vector-ref v 0))
  (test 2147483647 (s32vector-ref v 1)))
(test 4 (u32vector-length (make-u32vector 4 0)))
(test '(999 999) (u32vector->list (make-u32vector 2 999)))
(test '(-100 100) (s32vector->list (list->s32vector '(-100 100))))
(test '(-7 -7) (s32vector->list (make-s32vector 2 -7)))

;;; --- f32 / f64 ---
(let ((v (f64vector 1.5 -2.5)))
  (test #t (f64vector? v))
  (test 1.5 (f64vector-ref v 0))
  (f64vector-set! v 1 3.25)
  (test 3.25 (f64vector-ref v 1)))
(let ((v (f32vector 0.5)))
  (test #t (f32vector? v))
  (test 0.5 (f32vector-ref v 0)))
(test '(1.0 2.0) (f64vector->list (list->f64vector '(1.0 2.0))))
(test '(3.0 3.0) (f64vector->list (make-f64vector 2 3.0)))
(test '(0.5 0.5) (f32vector->list (make-f32vector 2 0.5)))

;;; --- type disjointness among the vector kinds ---
(test #f (s8vector? (u8vector 1)))
(test #f (u16vector? (u8vector 1)))
(test #f (u8vector? (s8vector 1)))
(test #f (u32vector? (s32vector 1)))
(test #f (s32vector? (u32vector 1)))
(test #f (u16vector? (s16vector 1)))
(test #f (s16vector? (u16vector 1)))
(test #f (f32vector? (f64vector 1.0)))
(test #f (f64vector? (f32vector 1.0)))
(test #f (f64vector? (u32vector 1)))
(test #f (u8vector? (vector 1)))
(test #f (f64vector? (vector 1)))
(test #f (f32vector? (vector 1)))
(test #f (u8vector? (f64vector 1.0)))
(test #f (s8vector? (u16vector 1)))

;;; --- out-of-range / bad-index errors are catchable ---
;; u8 range errors (from bytevector-u8-set!)
(test #t (guard (e (#t #t)) (u8vector-set! (u8vector 1) 0 256) #f))
(test #t (guard (e (#t #t)) (u8vector-set! (u8vector 1) 0 -1) #f))
(test #t (guard (e (#t #t)) (u8vector-ref (u8vector 1) 5) #f))
;; s8 range errors
(test #t (guard (e (#t #t)) (s8vector-set! (s8vector 1) 0 128) #f))
(test #t (guard (e (#t #t)) (s8vector-set! (s8vector 1) 0 -129) #f))
(test #t (guard (e (#t #t)) (s8vector 200) #f))
;; u16 range errors
(test #t (guard (e (#t #t)) (u16vector-set! (u16vector 1) 0 65536) #f))
(test #t (guard (e (#t #t)) (u16vector-set! (u16vector 1) 0 -1) #f))
(test #t (guard (e (#t #t)) (u16vector 70000) #f))
;; s16 range errors
(test #t (guard (e (#t #t)) (s16vector-set! (s16vector 1) 0 32768) #f))
(test #t (guard (e (#t #t)) (s16vector-set! (s16vector 1) 0 -32769) #f))
;; u32 range errors
(test #t (guard (e (#t #t)) (u32vector-set! (u32vector 1) 0 4294967296) #f))
(test #t (guard (e (#t #t)) (u32vector-set! (u32vector 1) 0 -1) #f))
;; s32 range errors
(test #t (guard (e (#t #t)) (s32vector-set! (s32vector 1) 0 2147483648) #f))
(test #t (guard (e (#t #t)) (s32vector-set! (s32vector 1) 0 -2147483649) #f))

;;; --- mutation through set! ---
(let ((v (u16vector 10 20)))
  (u16vector-set! v 0 30000)
  (test 30000 (u16vector-ref v 0)))
(let ((v (s32vector 0)))
  (s32vector-set! v 0 -1000000)
  (test -1000000 (s32vector-ref v 0)))

(test-end "srfi-4")
