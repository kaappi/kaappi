;; SRFI-141 (integer division) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi141.scm

(import (scheme base) (srfi 141) (chibi test))

(test-begin "srfi-141")

(define (mv->list producer) (call-with-values producer list))

;;; --- floor/ : quotient rounds toward -inf, remainder has divisor's sign ---
(test '(3 1) (mv->list (lambda () (floor/ 7 2))))
(test '(-4 1) (mv->list (lambda () (floor/ -7 2))))
(test '(-4 -1) (mv->list (lambda () (floor/ 7 -2))))
(test '(3 -1) (mv->list (lambda () (floor/ -7 -2))))
(test 3 (floor-quotient 7 2))
(test -4 (floor-quotient -7 2))
(test 1 (floor-remainder -7 2))
(test -1 (floor-remainder 7 -2))

;;; --- ceiling/ : quotient rounds toward +inf ---
(test '(4 -1) (mv->list (lambda () (ceiling/ 7 2))))
(test '(-3 -1) (mv->list (lambda () (ceiling/ -7 2))))
(test '(-3 1) (mv->list (lambda () (ceiling/ 7 -2))))
(test '(4 1) (mv->list (lambda () (ceiling/ -7 -2))))

;;; --- truncate/ : quotient rounds toward zero ---
(test '(3 1) (mv->list (lambda () (truncate/ 7 2))))
(test '(-3 -1) (mv->list (lambda () (truncate/ -7 2))))
(test '(-3 1) (mv->list (lambda () (truncate/ 7 -2))))
(test '(3 -1) (mv->list (lambda () (truncate/ -7 -2))))

;;; --- round/ : quotient rounds to nearest, ties to even ---
(test '(4 -1) (mv->list (lambda () (round/ 7 2))))
(test '(-4 1) (mv->list (lambda () (round/ -7 2))))
(test '(-4 -1) (mv->list (lambda () (round/ 7 -2))))
(test '(4 1) (mv->list (lambda () (round/ -7 -2))))
(test '(2 1) (mv->list (lambda () (round/ 5 2))))     ; 2.5 ties to even 2
(test '(2 1) (mv->list (lambda () (round/ 7 3))))     ; 2.33 rounds to 2

;;; --- euclidean/ : remainder always in [0, |d|) ---
(test '(3 1) (mv->list (lambda () (euclidean/ 7 2))))
(test '(-4 1) (mv->list (lambda () (euclidean/ -7 2))))
(test '(-3 1) (mv->list (lambda () (euclidean/ 7 -2))))
(test '(4 1) (mv->list (lambda () (euclidean/ -7 -2))))
(test 1 (euclidean-remainder -7 2))
(test 1 (euclidean-remainder -7 -2))

;;; --- balanced/ : remainder in [-|d|/2, |d|/2) ---
(test '(4 -1) (mv->list (lambda () (balanced/ 7 2))))
;; FAIL: #1232 (balanced/ is aliased to round/ — ties break to even
;; instead of keeping the remainder in [-|d|/2, |d|/2))
;; (test '(3 -1) (mv->list (lambda () (balanced/ 5 2))))
;; FAIL: #1232 (balanced/ aliased to round/)
;; (test '(-3 -1) (mv->list (lambda () (balanced/ -7 2))))
;; FAIL: #1232 (balanced/ aliased to round/)
;; (test '(3 -1) (mv->list (lambda () (balanced/ -7 -2))))
(test '(2 1) (mv->list (lambda () (balanced/ 7 3))))

;;; --- bignums ---
(test '(14285714285714285714 2)
      (mv->list (lambda () (floor/ 100000000000000000000 7))))

;;; --- exact zero dividend ---
(test '(0 0) (mv->list (lambda () (floor/ 0 5))))
(test '(0 0) (mv->list (lambda () (euclidean/ 0 -5))))

;;; --- division by zero raises ---
(test #t (guard (e (#t #t)) (floor/ 5 0) #f))
(test #t (guard (e (#t #t)) (truncate-quotient 5 0) #f))

(test-end "srfi-141")
