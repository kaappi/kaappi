;; SRFI-26 (cut / cute) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi26.scm

(import (scheme base) (srfi 26) (chibi test))

(test-begin "srfi-26")

;;; --- basic slots ---
(test 6 ((cut + 1 <>) 5))
;; FAIL: #1208 (cut: later slots swallowed by earlier fixed-arg patterns)
;; (test '(1 a 2) ((cut list <> 'a <>) 1 2))
(test 9 ((cut car '(9 8))))
(test '(2 4 6) (map (cut * 2 <>) '(1 2 3)))
(test '(b) ((cut cdr <>) '(a b)))

;; zero-slot cut defers evaluation to call time
(define calls 0)
(define (probe) (set! calls (+ calls 1)) calls)
(define th (cut probe))
(test 0 calls)
(test 1 (th))
(test 2 (th))

;;; --- rest-slot <...> ---
(test '(1 2 3) ((cut list <...>) 1 2 3))
;; FAIL: #1208 (cut: (cut f <> <...>) shadowed by the (cut f <> b) pattern)
;; (test '(1 2 3) ((cut list <> <...>) 1 2 3))
(test '() ((cut list <...>)))

;; <...> after a fixed argument:
;; FAIL: #1208 (cut: <...> only supported in 3 hardcoded positions)
;; (test '(1 2 3) ((cut list 1 <...>) 2 3))

;;; --- operator-position slot: (cut <> a b) => (lambda (f) (f a b)) ---
;; FAIL: #1208 (cut: operator-position slots unsupported)
;; (test 3 ((cut <> 1 2) +))

;;; --- arity beyond the hardcoded patterns ---
;; SRFI-26 example: (cut list 1 <> 3 <> 5) => (lambda (x2 x4) (list 1 x2 3 x4 5))
;; FAIL: #1208 (cut: arity capped by hardcoded pattern set — expand-time error)
;; (test '(1 2 3 4 5) ((cut list 1 <> 3 <> 5) 2 4))

;;; --- cute: non-slot expressions evaluate once, at construction ---
;; SRFI-26: "cute evaluates the non-slot expressions at the time the
;; procedure is constructed"
(define n 0)
(define (tick) (set! n (+ n 1)) 10)
(define f (cute + (tick) <>))
(test 11 (f 1))
(test 12 (f 2))
;; FAIL: #1208 (cute is an alias of cut — re-evaluates per call; n is 2 here)
;; (test 1 n)

(test-end "srfi-26")
