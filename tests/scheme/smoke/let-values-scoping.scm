;; Regression test for issue #71:
;; let-values producers must see the outer scope, not previous bindings.

(import (scheme base) (scheme write))

(define x 100)

;; let-values: second producer must see outer x=100, not new x=1
(let-values (((x) (values 1)) ((b) (values x)))
  (unless (equal? (list x b) '(1 100))
    (display "FAIL: let-values outer scoping")
    (newline)
    (exit 1)))

;; let*-values: second producer sees new x=1 (sequential)
(let*-values (((x) (values 1)) ((b) (values x)))
  (unless (equal? (list x b) '(1 1))
    (display "FAIL: let*-values sequential scoping")
    (newline)
    (exit 1)))

;; Basic let-values still works
(let-values (((a b) (values 1 2)))
  (unless (= (+ a b) 3)
    (display "FAIL: basic let-values") (newline) (exit 1)))

;; Multiple bindings
(let-values (((a b) (values 1 2)) ((c) (values 3)))
  (unless (= (+ a b c) 6)
    (display "FAIL: multiple bindings") (newline) (exit 1)))

(display "OK")
(newline)
