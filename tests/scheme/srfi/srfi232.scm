;; SRFI-232 (flexible curried procedures) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi232.scm

(import (scheme base) (srfi 232) (chibi test))

(test-begin "srfi-232")

;;; --- one-argument-at-a-time application ---
(define-curried (inc x) (+ x 1))
(test 6 (inc 5))

(define-curried (add2 a b) (+ a b))
(test 3 ((add2 1) 2))

(define-curried (mul3 a b c) (* a b c))
(test 24 (((mul3 2) 3) 4))

(define-curried (cat4 a b c d) (list a b c d))
(test '(1 2 3 4) ((((cat4 1) 2) 3) 4))

;; partial applications are reusable closures
(define add10 (add2 10))
(test 11 (add10 1))
(test 30 (add10 20))

;; each partial application captures independently
(define t2 (mul3 2))
(define t3 (mul3 3))
(test 24 ((t2 3) 4))
(test 36 ((t3 3) 4))

;;; --- SRFI-232: curried procedures accept args one at a time OR in groups ---
;; "applied to their arguments one at a time or all at once"
;; FAIL: #1238 (define-curried produces strictly unary chains — multi-arg
;;   application raises an arity error)
;; (test 3 (add2 1 2))
;; FAIL: #1238
;; (test 24 (mul3 2 3 4))
;; FAIL: #1238
;; (test 24 ((mul3 2 3) 4))

;;; --- missing export: the curried lambda form ---
;; FAIL: #1238 (curried is not exported)
;; (test 7 (((curried (a b) (+ a b)) 3) 4))

;;; --- unsupported shapes are syntax errors at expansion time ---
;; FAIL: #1238 (zero-argument and >4-argument forms do not match any
;;   define-curried pattern and fail to compile)
;; (define-curried (thunk) 'ok)
;; (define-curried (five a b c d e) (list a b c d e))

(test-end "srfi-232")
