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

;;; --- u16 / s16 ---
(let ((v (u16vector 0 65535)))
  (test 65535 (u16vector-ref v 1))
  (test 2 (u16vector-length v)))
(let ((v (s16vector -32768 32767)))
  (test -32768 (s16vector-ref v 0))
  (test 32767 (s16vector-ref v 1)))
(test '(1 2) (u16vector->list (list->u16vector '(1 2))))

;;; --- u32 / s32 ---
(let ((v (u32vector 4294967295)))
  (test 4294967295 (u32vector-ref v 0)))
(let ((v (s32vector -2147483648 2147483647)))
  (test -2147483648 (s32vector-ref v 0))
  (test 2147483647 (s32vector-ref v 1)))
(test 4 (u32vector-length (make-u32vector 4 0)))

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

;;; --- type disjointness among the vector kinds ---
;; FAIL: #1225 (integer vector kinds are indistinguishable bytevector aliases)
;; (test #f (s8vector? (u8vector 1)))
;; FAIL: #1225 (integer vector kinds are indistinguishable bytevector aliases)
;; (test #f (u16vector? (u8vector 1)))
(test #f (f64vector? (u32vector 1)))
(test #f (u8vector? (vector 1)))

;;; --- out-of-range / bad-index errors are catchable ---
(test #t (guard (e (#t #t)) (u8vector-set! (u8vector 1) 0 256) #f))
(test #t (guard (e (#t #t)) (u8vector-set! (u8vector 1) 0 -1) #f))
(test #t (guard (e (#t #t)) (u8vector-ref (u8vector 1) 5) #f))
;; FAIL: #1225 (signed setters accept out-of-range values; 128 wraps to -128)
;; (test #t (guard (e (#t #t)) (s8vector-set! (s8vector 1) 0 128) #f))

(test-end "srfi-4")
