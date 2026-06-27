;; Regression test for issue #78:
;; Mismatched-length ellipsis template variables must produce a clean error,
;; not read uninitialized memory.

(import (scheme base) (scheme write))

;; Equal-length ellipsis — must work correctly
(define-syntax zip-equal
  (syntax-rules ()
    ((zip-equal (a ...) (b ...)) (quote ((a b) ...)))))

(let ((result (zip-equal (1 2 3) (4 5 6))))
  (unless (equal? result '((1 4) (2 5) (3 6)))
    (display "FAIL: equal-length ellipsis zip")
    (newline)
    (exit 1)))

;; Mismatched-length ellipsis — must raise an error, not produce garbage
(define-syntax zip-mismatched
  (syntax-rules ()
    ((zip-mismatched (a ...) (b ...)) (quote ((a b) ...)))))

(guard (exn (#t 'caught))
  (zip-mismatched (1 2 3) (4 5))
  (display "FAIL: mismatched ellipsis should have raised an error")
  (newline)
  (exit 1))

(display "OK")
(newline)
