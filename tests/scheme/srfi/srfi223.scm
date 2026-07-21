;; SRFI-223 (Generalized binary search) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi223.scm

(import (scheme base) (srfi 223) (srfi 64))

(test-begin "srfi-223")

;;; --- bisect-left / bisect-right on vectors ---
(test-equal "vector-bisect-left: find insertion point"
  1 (vector-bisect-left #(1 2 2 3 5) 2 <))
(test-equal "vector-bisect-right: find insertion point"
  3 (vector-bisect-right #(1 2 2 3 5) 2 <))
(test-equal "vector-bisect-left: not present"
  3 (vector-bisect-left #(1 2 3 5) 4 <))
(test-equal "vector-bisect-right: not present"
  3 (vector-bisect-right #(1 2 3 5) 4 <))
(test-equal "vector-bisect-left: empty"
  0 (vector-bisect-left #() 1 <))
(test-equal "vector-bisect-right: empty"
  0 (vector-bisect-right #() 1 <))
(test-equal "vector-bisect-left: at beginning"
  0 (vector-bisect-left #(1 2 3) 0 <))
(test-equal "vector-bisect-right: at end"
  3 (vector-bisect-right #(1 2 3) 4 <))
(test-equal "vector-bisect-left: all same"
  0 (vector-bisect-left #(5 5 5 5) 5 <))
(test-equal "vector-bisect-right: all same"
  4 (vector-bisect-right #(5 5 5 5) 5 <))

;;; --- raw bisect-left / bisect-right ---
(test-equal "bisect-left: raw"
  2 (bisect-left #(10 20 30 40 50) 30 vector-ref < 0 5))
(test-equal "bisect-right: raw"
  3 (bisect-right #(10 20 30 40 50) 30 vector-ref < 0 5))
(test-equal "bisect-left: subrange"
  2 (bisect-left #(10 20 30 40 50) 25 vector-ref < 1 4))

;;; --- bisection constructor ---
(define-values (string-bisect-left string-bisect-right)
  (bisection string-ref (lambda (s) (values 0 (string-length s)))))

(test-equal "string-bisect-left"
  2 (string-bisect-left "abcde" #\c char<?))
(test-equal "string-bisect-right"
  3 (string-bisect-right "abcde" #\c char<?))

;;; --- with explicit lo/hi ---
(test-equal "vector-bisect-left: explicit bounds"
  2 (vector-bisect-left #(1 2 3 4 5) 3 < 1 4))

(let ((runner (test-runner-current)))
  (test-end "srfi-223")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
