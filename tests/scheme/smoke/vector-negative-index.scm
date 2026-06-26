;; Regression test for #50: negative index args must error, not panic

(import (scheme base) (scheme write))

(define (expect-error thunk name)
  (guard (exn (#t (begin (display "PASS: ") (display name) (newline))))
    (thunk)
    (display "FAIL: ") (display name) (display " did not error") (newline)))

(expect-error (lambda () (vector-reverse! (vector 1 2 3) -1))
              "vector-reverse! negative start")
(expect-error (lambda () (vector-reverse! (vector 1 2 3) 0 -1))
              "vector-reverse! negative end")
(expect-error (lambda () (vector-reverse-copy (vector 1 2 3) -1))
              "vector-reverse-copy negative start")
(expect-error (lambda () (vector-reverse-copy (vector 1 2 3) 0 -1))
              "vector-reverse-copy negative end")
(expect-error (lambda () (vector-unfold (lambda (i) i) -5))
              "vector-unfold negative length")
