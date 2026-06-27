;; Regression test for issue #72:
;; Malformed binding forms must produce clean syntax errors, not abort.

(import (scheme base) (scheme write))

(define (compile-errors? thunk)
  (guard (exn (#t #t))
    (thunk)
    #f))

;; (let ((x)) x) — missing init
(unless (compile-errors? (lambda () (eval '(let ((x)) x))))
  (display "FAIL: let missing init") (newline) (exit 1))

;; (let* ((x)) x) — missing init
(unless (compile-errors? (lambda () (eval '(let* ((x)) x))))
  (display "FAIL: let* missing init") (newline) (exit 1))

;; (letrec ((x)) x) — missing init
(unless (compile-errors? (lambda () (eval '(letrec ((x)) x))))
  (display "FAIL: letrec missing init") (newline) (exit 1))

;; (do ((x)) (#t 0)) — missing init
(unless (compile-errors? (lambda () (eval '(do ((x)) (#t 0)))))
  (display "FAIL: do missing init") (newline) (exit 1))

;; (let ((x . 5)) x) — improper binding
(unless (compile-errors? (lambda () (eval '(let ((x . 5)) x))))
  (display "FAIL: let improper binding") (newline) (exit 1))

;; Valid uses still work
(unless (= (let ((x 1) (y 2)) (+ x y)) 3)
  (display "FAIL: valid let") (newline) (exit 1))
(unless (= (let* ((x 1) (y (+ x 1))) y) 2)
  (display "FAIL: valid let*") (newline) (exit 1))
(unless (= (letrec ((x 42)) x) 42)
  (display "FAIL: valid letrec") (newline) (exit 1))
(unless (= (do ((i 0 (+ i 1))) ((= i 5) i)) 5)
  (display "FAIL: valid do") (newline) (exit 1))

(display "OK")
(newline)
