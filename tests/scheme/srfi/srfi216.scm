;; SRFI-216 (SICP Prerequisites) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi216.scm
;;
;; See lib/srfi/216.sld's header for scope notes this file is designed
;; around: (runtime)'s unit, parallel-execute's blocking semantics, and
;; the global-vs-local shared-state limitation of Kaappi's SRFI-18 threads
;; (only global top-level variables are actually shared between the
;; threads a single parallel-execute call starts).

(import (scheme base) (scheme lazy) (scheme process-context)
        (srfi 216) (srfi 64))

(test-begin "srfi-216")

;;; --- booleans and nil ---

(test-assert "true triggers if's consequent" (if true #t #f))
(test-assert "false triggers if's alternate" (if false #f #t))
(test-equal "true is #t" #t true)
(test-equal "false is #f" #f false)
(test-equal "nil is the empty list" '() nil)
(test-assert "nil satisfies null?" (null? nil))

;;; --- runtime ---

(test-assert "runtime returns an exact integer"
  (and (integer? (runtime)) (exact? (runtime))))

(test-assert "runtime does not go backwards across intervening work"
  (let ((t0 (runtime)))
    (let loop ((i 0)) (when (< i 100000) (loop (+ i 1))))
    (>= (runtime) t0)))

;;; --- random ---

(test-assert "random of an exact integer is an exact integer"
  (let ((r (random 100)))
    (and (exact? r) (integer? r))))

(test-assert "random of an exact integer stays in [0, n)"
  (let loop ((i 0))
    (or (>= i 500)
        (let ((r (random 100)))
          (and (>= r 0) (< r 100) (loop (+ i 1)))))))

(test-assert "random of an inexact number is inexact"
  (inexact? (random 100.0)))

(test-assert "random of an inexact number stays in [0, x)"
  (let loop ((i 0))
    (or (>= i 500)
        (let ((r (random 100.0)))
          (and (>= r 0.0) (< r 100.0) (loop (+ i 1)))))))

;;; --- parallel-execute ---

(test-assert "parallel-execute: zero thunks is a no-op"
  (begin (parallel-execute) #t))

;; Global flags -- see file header: only global top-level state is shared
;; between the OS threads parallel-execute starts.
(define pe-a #f)
(define pe-b #f)
(define pe-c #f)

(test-assert "parallel-execute: every thunk has run by the time it returns"
  (begin
    (parallel-execute (lambda () (set! pe-a #t))
                       (lambda () (set! pe-b #t))
                       (lambda () (set! pe-c #t)))
    (and pe-a pe-b pe-c)))

;; A genuine race on shared global state (SICP 3.4.1's point: two
;; concurrent processes touching the same variable with no synchronization
;; between them): two threads each overwrite the same global with a
;; different constant. Whichever runs last wins, so the only two legal
;; final values are 'first and 'second -- unlike a read-modify-write race
;; (e.g. (set! x (* x x)) vs. (set! x (+ x 1))), a plain overwrite's legal
;; outcome set doesn't depend on how many times the VM happens to re-read
;; a global per source occurrence, so this assertion is robust regardless
;; of Kaappi's bytecode-level granularity.
(define pe-race 'neither)

(test-assert "parallel-execute: shared-global race lands on one of the two racing values"
  (begin
    (parallel-execute (lambda () (set! pe-race 'first))
                       (lambda () (set! pe-race 'second)))
    (memq pe-race '(first second))))

;;; --- test-and-set! ---

(test-assert "test-and-set! on an unset cell returns #f and sets it"
  (let ((cell (list #f)))
    (let ((prior (test-and-set! cell)))
      (and (not prior) (car cell)))))

(test-assert "test-and-set! on an already-set cell returns #t and leaves it set"
  (let ((cell (list #t)))
    (let ((prior (test-and-set! cell)))
      (and prior (car cell)))))

;; A real cross-thread critical section: 30 threads each spin-acquire a
;; shared (global) lock, bump a shared (global) counter, then release.
;; If test-and-set! were not atomic, some increments would be lost.
(define pe-lock (list #f))
(define pe-counter 0)

(define (pe-bump-safely!)
  (let acquire () (when (test-and-set! pe-lock) (acquire)))
  (set! pe-counter (+ pe-counter 1))
  (set-car! pe-lock #f))

(test-equal "test-and-set! critical section: no lost updates across 30 parallel threads"
  30
  (begin
    (apply parallel-execute (make-list 30 pe-bump-safely!))
    pe-counter))

;;; --- streams ---

(test-assert "the-empty-stream satisfies stream-null?" (stream-null? the-empty-stream))
(test-assert "a cons-stream is not stream-null?" (not (stream-null? (cons-stream 1 2))))

(define (stream-car s) (car s))
(define (stream-cdr s) (force (cdr s)))

(test-assert "cons-stream's tail is a promise" (promise? (cdr (cons-stream 1 2))))
(test-equal "force on a cons-stream's tail evaluates it" 2 (force (cdr (cons-stream 1 2))))
(test-equal "stream-car/stream-cdr over cons-stream" 1 (stream-car (cons-stream 1 2)))

;; The classic self-referential "ones" stream from SICP 3.5.1.
(define ones (cons-stream 1 ones))

(test-equal "self-referential stream: second element" 1 (stream-car (stream-cdr ones)))
(test-equal "self-referential stream: third element"
  1 (stream-car (stream-cdr (stream-cdr ones))))

(define (integers-from n) (cons-stream n (integers-from (+ n 1))))

(define (stream-first-n n s)
  (if (= n 0)
      '()
      (cons (stream-car s) (stream-first-n (- n 1) (stream-cdr s)))))

(test-equal "stream built from cons-stream: first 5 integers from 1"
  '(1 2 3 4 5)
  (stream-first-n 5 (integers-from 1)))

(let ((runner (test-runner-current)))
  (test-end "srfi-216")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
