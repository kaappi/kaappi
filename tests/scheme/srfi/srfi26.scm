;; SRFI-26 (cut / cute) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi26.scm

(import (scheme base) (scheme write) (srfi 26) (srfi 64))

(test-begin "srfi-26")

;;; --- cut: basic slots ---
(test-equal "cut: one fixed arg" 6 ((cut + 1 <>) 5))
(test-equal "cut: car with quoted list" 9 ((cut car '(9 8))))
(test-equal "cut: map with slot" '(2 4 6) (map (cut * 2 <>) '(1 2 3)))
(test-equal "cut: cdr with slot" '(b) ((cut cdr <>) '(a b)))

;; multiple slots (was broken: later slots swallowed by earlier patterns)
(test-equal "cut: two slots" '(1 a 2) ((cut list <> 'a <>) 1 2))
(test-equal "cut: three slots" '(1 2 3) ((cut list <> <> <>) 1 2 3))
(test-equal "cut: slot-expr-slot" '(1 a 2) ((cut list <> 'a <>) 1 2))
(test-equal "cut: expr-slot-expr-slot" '(a 1 b 2) ((cut list 'a <> 'b <>) 1 2))

;; zero-slot cut defers evaluation to call time
(define calls 0)
(define (probe) (set! calls (+ calls 1)) calls)
(define th (cut probe))
(test-equal "cut: zero-slot not called yet" 0 calls)
(test-equal "cut: zero-slot first call" 1 (th))
(test-equal "cut: zero-slot second call" 2 (th))

;;; --- cut: rest-slot <...> ---
(test-equal "cut: <...> only" '(1 2 3) ((cut list <...>) 1 2 3))
(test-equal "cut: <...> empty" '() ((cut list <...>)))
(test-equal "cut: slot + <...>" '(1 2 3) ((cut list <> <...>) 1 2 3))
(test-equal "cut: fixed + <...>" '(1 2 3) ((cut list 1 <...>) 2 3))
(test-equal "cut: fixed + slot + <...>" '(1 2 3 4) ((cut list 1 <> <...>) 2 3 4))

;;; --- cut: operator-position slot ---
(test-equal "cut: operator slot" 3 ((cut <> 1 2) +))
(test-equal "cut: operator slot + <...>" 6 ((cut <> <...>) + 1 2 3))
(test-equal "cut: operator slot + fixed" '(42) ((cut <> 42) list))

;;; --- cut: arity beyond hardcoded patterns ---
(test-equal "cut: 5 args with 2 slots" '(1 2 3 4 5)
  ((cut list 1 <> 3 <> 5) 2 4))
(test-equal "cut: 6 fixed args" '(a b c d e f)
  ((cut list 'a 'b 'c 'd 'e 'f)))
(test-equal "cut: 4 slots" '(1 2 3 4)
  ((cut list <> <> <> <>) 1 2 3 4))

;;; --- cute: non-slot expressions evaluate once at construction ---
(define n 0)
(define (tick) (set! n (+ n 1)) 10)
(define f (cute + (tick) <>))
(test-equal "cute: first call" 11 (f 1))
(test-equal "cute: second call" 12 (f 2))
(test-equal "cute: tick called once" 1 n)

;; cute with multiple non-slot expressions
(define m 0)
(define (tick2) (set! m (+ m 1)) m)
(define g (cute list (tick2) <> (tick2)))
(test-equal "cute: multiple non-slots evaluated once" '(1 x 2) (g 'x))
(test-equal "cute: stable across calls" '(1 y 2) (g 'y))
(test-equal "cute: tick2 called exactly twice" 2 m)

;; cute with <...>
(define p 0)
(define (tick3) (set! p (+ p 1)) p)
(define h (cute list (tick3) <...>))
(test-equal "cute: rest-slot" '(1 2 3) (h 2 3))
(test-equal "cute: tick3 called once" 1 p)

;; cute with operator slot (like cut, no binding needed)
(test-equal "cute: operator slot" 3 ((cute <> 1 2) +))

;; cute with non-slot operator expression
(define op-count 0)
(define (get-adder) (set! op-count (+ op-count 1)) +)
(define k (cute (get-adder) 1 <>))
(test-equal "cute: operator expr result" 11 (k 10))
(test-equal "cute: operator expr once" 1 op-count)

;; cute zero-slot evaluates at construction
(define q 0)
(define (tick4) (set! q (+ q 1)) q)
(define j (cute list (tick4)))
(test-equal "cute: zero-slot construction eval" 1 q)
(test-equal "cute: zero-slot result stable" '(1) (j))
(test-equal "cute: zero-slot no re-eval" 1 q)

;;; --- hygiene: top-level x/y/t/rest-slot must not interfere ---
(define x 5)
(define y 99)
(define t 77)
(define rest-slot 0)
(test-equal "cut: hygiene with top-level x" 10 ((cut + <>) 10))
(test-equal "cut: hygiene two slots" '(1 2) ((cut list <> <>) 1 2))
(test-equal "cut: hygiene rest-slot" '(1 2 3) ((cut list <> <...>) 1 2 3))
(test-equal "cute: hygiene with top-level y" 10 ((cute + <>) 10))
(test-equal "cute: hygiene non-slot eval" '(1 a 2)
  (let ((r (cute list (+ 0 1) <> (+ 0 2)))) (r 'a)))
(test-equal "cute: hygiene rest-slot" '(a 1 2) ((cute list 'a <...>) 1 2))

(let ((runner (test-runner-current)))
  (test-end "srfi-26")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
