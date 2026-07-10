;; SRFI-195 (multiple-value boxes) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi195.scm

(import (scheme base) (srfi 195) (scheme process-context) (srfi 64))

(test-begin "srfi-195")

;;; --- single-value boxes (SRFI-111 subset) ---
(define b1 (box 42))
(test-equal #t (box? b1))
(test-equal #f (box? 42))
(test-equal #f (box? (list 42)))
(test-equal 42 (unbox b1))
(test-equal 1 (box-arity b1))
(set-box! b1 43)
(test-equal 43 (unbox b1))

;;; --- multiple-value boxes ---
(define b3 (box 1 2 3))
(test-equal #t (box? b3))
(test-equal 3 (box-arity b3))
(test-equal '(1 2 3) (call-with-values (lambda () (unbox b3)) list))
(test-equal 1 (unbox-value b3 0))
(test-equal 2 (unbox-value b3 1))
(test-equal 3 (unbox-value b3 2))

(set-box-value! b3 1 20)
(test-equal '(1 20 3) (call-with-values (lambda () (unbox b3)) list))

(set-box! b3 7 8 9)
(test-equal '(7 8 9) (call-with-values (lambda () (unbox b3)) list))

;;; --- zero-value boxes ---
(define b0 (box))
(test-equal #t (box? b0))
(test-equal 0 (box-arity b0))
(test-equal '() (call-with-values (lambda () (unbox b0)) list))

;;; --- errors ---
;; set-box! with wrong arity is an error (raising is conforming)
(test-equal #t (guard (e (#t #t)) (set-box! b1 1 2) #f))
;; unbox-value out of range
(test-equal #t (guard (e (#t #t)) (unbox-value b1 5) #f))

;;; --- boxes hold arbitrary values ---
(define bm (box '(a b) #(1)))
(test-equal '(a b) (unbox-value bm 0))
(test-equal #(1) (unbox-value bm 1))

(let ((runner (test-runner-current)))
  (test-end "srfi-195")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
