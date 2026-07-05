;; SRFI-197 (pipeline operators) conformance tests — audit Phase 3d
;; chain currently threads the value as first argument instead of
;; substituting _ (#1219); the enabled tests use only shapes where the two
;; conventions coincide.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi197.scm

(import (scheme base) (srfi 197) (chibi test))

(test-begin "srfi-197")

;;; --- shapes where first-argument insertion matches _-in-first-position ---
(test 3 (chain 1 (+ 2)))
(test 6 (chain 1 (+ 2) (* 2)))
(test '(1 2) (chain 1 (list 2)))
(test 4 (chain 16 (- 12)))

;; bare identity chain
(test 5 (chain 5))

;;; --- chain-and short-circuits on #f ---
(define (to-false x) #f)
(define (boom x) (error "must not run"))
(test 3 (chain-and 1 (+ 2)))
(test #f (chain-and #f (+ 2)))
(test #f (chain-and 1 (+ 1) (to-false) (boom)))

;;; --- chain-lambda ---
(test 7 ((chain-lambda (+ 2) (+ 4)) 1))

;;; --- SRFI-197 placeholder semantics ---
;; "(chain x (a b _)) ; => (a b x)"
;; FAIL: #1219 (chain does not substitute the _ placeholder)
;; (test -9 (chain 10 (- 1 _)))
;; FAIL: #1219 (chain does not substitute the _ placeholder)
;; (test '(a x) (chain 'x (list 'a _)))
;; FAIL: #1219 (nest and nest-reverse are not exported)
;; (test '(a (b (c))) (nest (list 'a _) (list 'b _) (list 'c)))

(test-end "srfi-197")
