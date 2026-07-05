;; SRFI-87 (=> in case clauses) conformance tests — audit Phase 3d
;; The feature is provided by the built-in R7RS case form; (srfi 87) is a
;; marker library.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi87.scm

(import (scheme base) (srfi 87) (chibi test))

(test-begin "srfi-87")

;; => in a matching clause receives the key
(test 20 (case 2 ((1 2 3) => (lambda (x) (* x 10))) (else 0)))
(test 'two (case 2
             ((1) => (lambda (x) 'one))
             ((2) => (lambda (x) 'two))
             (else 'other)))

;; => in the else clause receives the key
(test 9 (case 9 ((1 2) => (lambda (x) 'small)) (else => (lambda (x) x))))
(test 'composite (case 6
                   ((2 3 5 7) 'prime)
                   (else => (lambda (x) 'composite))))

;; mixing plain and => clauses
(test 'plain (case 1 ((1) 'plain) ((2) => (lambda (x) 'arrow)) (else 'no)))
(test 4 (case 2 ((1) 'plain) ((2) => (lambda (x) (* x x))) (else 'no)))

;; the receiver is evaluated only when its clause matches
(define hits 0)
(define (bump! tag) (lambda (x) (set! hits (+ hits 1)) tag))
(test 'b (case 'b
           ((a) => (bump! 'a))
           ((b) => (bump! 'b))
           (else => (bump! 'e))))
(test 1 hits)

(test-end "srfi-87")
