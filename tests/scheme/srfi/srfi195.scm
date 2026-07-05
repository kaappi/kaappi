;; SRFI-195 (multiple-value boxes) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi195.scm

(import (scheme base) (srfi 195) (chibi test))

(test-begin "srfi-195")

;;; --- single-value boxes (SRFI-111 subset) ---
(define b1 (box 42))
(test #t (box? b1))
(test #f (box? 42))
(test #f (box? (list 42)))
(test 42 (unbox b1))
(test 1 (box-arity b1))
(set-box! b1 43)
(test 43 (unbox b1))

;;; --- multiple-value boxes ---
(define b3 (box 1 2 3))
(test #t (box? b3))
(test 3 (box-arity b3))
(test '(1 2 3) (call-with-values (lambda () (unbox b3)) list))
(test 1 (unbox-value b3 0))
(test 2 (unbox-value b3 1))
(test 3 (unbox-value b3 2))

(set-box-value! b3 1 20)
(test '(1 20 3) (call-with-values (lambda () (unbox b3)) list))

(set-box! b3 7 8 9)
(test '(7 8 9) (call-with-values (lambda () (unbox b3)) list))

;;; --- zero-value boxes ---
(define b0 (box))
(test #t (box? b0))
(test 0 (box-arity b0))
(test '() (call-with-values (lambda () (unbox b0)) list))

;;; --- errors ---
;; set-box! with wrong arity is an error (raising is conforming)
(test #t (guard (e (#t #t)) (set-box! b1 1 2) #f))
;; unbox-value out of range
(test #t (guard (e (#t #t)) (unbox-value b1 5) #f))

;;; --- boxes hold arbitrary values ---
(define bm (box '(a b) #(1)))
(test '(a b) (unbox-value bm 0))
(test #(1) (unbox-value bm 1))

(test-end "srfi-195")
