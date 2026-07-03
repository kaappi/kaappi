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

;; The mismatched-length negative case (must produce a clean error, not
;; garbage) is rejected at macro-expansion (compile) time, which guard
;; cannot catch and which flips the process exit code. It lives in
;; tests/scheme/errors/error-format.sh instead.

(display "OK")
(newline)
