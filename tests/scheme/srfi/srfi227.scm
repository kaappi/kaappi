;; SRFI-227 (optional arguments) conformance tests — audit Phase 3d
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi227.scm

(import (scheme base) (srfi 227) (chibi test))

(test-begin "srfi-227")

;;; --- all-optional forms ---
(define f1 (opt-lambda ((a 1)) a))
(test 1 (f1))
(test 9 (f1 9))

(define f2 (opt-lambda ((a 1) (b 2)) (list a b)))
(test '(1 2) (f2))
(test '(9 2) (f2 9))
(test '(9 8) (f2 9 8))

;;; --- required + optional ---
(define g1 (opt-lambda (r (a 10)) (list r a)))
(test '(5 10) (g1 5))
(test '(5 6) (g1 5 6))

(define g2 (opt-lambda (r (a 10) (b 20)) (list r a b)))
(test '(5 10 20) (g2 5))
(test '(5 6 20) (g2 5 6))
(test '(5 6 7) (g2 5 6 7))

(define g3 (opt-lambda (r s (a 10)) (list r s a)))
(test '(1 2 10) (g3 1 2))
(test '(1 2 3) (g3 1 2 3))

;;; --- plain formals fall back to lambda ---
(define plain (opt-lambda (a b) (+ a b)))
(test 3 (plain 1 2))

;;; --- opt*-lambda: defaults see earlier parameters (let*-like) ---
(define s1 (opt*-lambda ((a 2) (b (* a 3))) (list a b)))
(test '(5 15) (s1 5))
(test '(5 9) (s1 5 9))
;; with zero arguments the default of b must see a's default:
;; FAIL: #1222 (opt*-lambda is an alias of opt-lambda; zero-arg case uses
;;              parallel let, so (* a 3) cannot see a)
;; (test '(2 6) (s1))

;;; --- let-optionals ---
(test '(1 2) (let-optionals '(1) ((a 0) (b 2)) (list a b)))
(test '(0 2) (let-optionals '() ((a 0) (b 2)) (list a b)))
(test '(1 9) (let-optionals '(1 9) ((a 0) (b 2)) (list a b)))

(test-end "srfi-227")
