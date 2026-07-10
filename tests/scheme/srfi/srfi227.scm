;; SRFI-227 (optional arguments) conformance tests — audit Phase 3d
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi227.scm

(import (scheme base) (srfi 227) (scheme process-context) (srfi 64))

(test-begin "srfi-227")

;;; --- opt-lambda: all-optional forms ---
(define f1 (opt-lambda ((a 1)) a))
(test-equal 1 (f1))
(test-equal 9 (f1 9))

(define f2 (opt-lambda ((a 1) (b 2)) (list a b)))
(test-equal '(1 2) (f2))
(test-equal '(9 2) (f2 9))
(test-equal '(9 8) (f2 9 8))

;;; --- opt-lambda: required + optional ---
(define g1 (opt-lambda (r (a 10)) (list r a)))
(test-equal '(5 10) (g1 5))
(test-equal '(5 6) (g1 5 6))

(define g2 (opt-lambda (r (a 10) (b 20)) (list r a b)))
(test-equal '(5 10 20) (g2 5))
(test-equal '(5 6 20) (g2 5 6))
(test-equal '(5 6 7) (g2 5 6 7))

(define g3 (opt-lambda (r s (a 10)) (list r s a)))
(test-equal '(1 2 10) (g3 1 2))
(test-equal '(1 2 3) (g3 1 2 3))

;;; --- opt-lambda: defaults must not see earlier formals (parallel binding) ---
(define outer-a 99)
(test-equal '(1 99)
            ((let ((a outer-a))
               (opt-lambda ((a 1) (b a)) (list a b)))))

;;; --- opt-lambda: plain formals fall back to lambda ---
(define plain (opt-lambda (a b) (+ a b)))
(test-equal 3 (plain 1 2))

;;; --- opt-lambda: 3+ optionals (was capped at 2) ---
(define f3 (opt-lambda ((a 1) (b 2) (c 3)) (list a b c)))
(test-equal '(1 2 3) (f3))
(test-equal '(10 2 3) (f3 10))
(test-equal '(10 20 3) (f3 10 20))
(test-equal '(10 20 30) (f3 10 20 30))

(define f4 (opt-lambda ((a 1) (b 2) (c 3) (d 4)) (list a b c d)))
(test-equal '(1 2 3 4) (f4))
(test-equal '(10 2 3 4) (f4 10))
(test-equal '(10 20 30 4) (f4 10 20 30))
(test-equal '(10 20 30 40) (f4 10 20 30 40))

;;; --- opt-lambda: required + 3 optionals ---
(define g4 (opt-lambda (r (a 10) (b 20) (c 30)) (list r a b c)))
(test-equal '(1 10 20 30) (g4 1))
(test-equal '(1 2 20 30) (g4 1 2))
(test-equal '(1 2 3 30) (g4 1 2 3))
(test-equal '(1 2 3 4) (g4 1 2 3 4))

;;; --- opt*-lambda: defaults see earlier parameters (let*-like) ---
(define s1 (opt*-lambda ((a 2) (b (* a 3))) (list a b)))
(test-equal '(5 15) (s1 5))
(test-equal '(5 9) (s1 5 9))
;; zero-argument case: b's default must see a's default (#1222)
(test-equal '(2 6) (s1))

;;; --- opt*-lambda: 3 sequential defaults ---
(define s2 (opt*-lambda ((a 1) (b (+ a 1)) (c (+ a b))) (list a b c)))
(test-equal '(1 2 3) (s2))
(test-equal '(10 11 21) (s2 10))
(test-equal '(10 20 30) (s2 10 20))
(test-equal '(10 20 30) (s2 10 20 30))

;;; --- opt*-lambda: required + sequential defaults ---
(define s3 (opt*-lambda (r (a (* r 2)) (b (+ r a))) (list r a b)))
(test-equal '(5 10 15) (s3 5))
(test-equal '(5 3 8) (s3 5 3))
(test-equal '(5 3 7) (s3 5 3 7))

;;; --- let-optionals ---
(test-equal '(1 2) (let-optionals '(1) ((a 0) (b 2)) (list a b)))
(test-equal '(0 2) (let-optionals '() ((a 0) (b 2)) (list a b)))
(test-equal '(1 9) (let-optionals '(1 9) ((a 0) (b 2)) (list a b)))

;;; --- let-optionals* (sequential defaults) ---
(test-equal '(2 6) (let-optionals* '() ((a 2) (b (* a 3))) (list a b)))
(test-equal '(5 15) (let-optionals* '(5) ((a 2) (b (* a 3))) (list a b)))
(test-equal '(5 9) (let-optionals* '(5 9) ((a 2) (b (* a 3))) (list a b)))

(let ((runner (test-runner-current)))
  (test-end "srfi-227")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
