;; Regression test for #688: member/memq/memv/assoc/assq/assv/list-copy
;; must terminate (not hang) on circular lists.
;; Each call should raise an error rather than looping forever.

(import (scheme base) (scheme write))

(define (test-error thunk name)
  (guard (exn (#t #t))
    (thunk)
    (display "FAIL: ")
    (display name)
    (display " did not error on circular list")
    (newline)
    (exit 1)))

(define lst (list 1 2 3))
(set-cdr! (cddr lst) lst)

(test-error (lambda () (member 99 lst)) "member")
(test-error (lambda () (memq 99 lst)) "memq")
(test-error (lambda () (memv 99 lst)) "memv")
(test-error (lambda () (list-copy lst)) "list-copy")

;; Circular alist
(define alst (list (cons 'a 1) (cons 'b 2) (cons 'c 3)))
(set-cdr! (cddr alst) alst)

(test-error (lambda () (assoc 'z alst)) "assoc")
(test-error (lambda () (assq 'z alst)) "assq")
(test-error (lambda () (assv 'z alst)) "assv")

;; Non-circular lists still work
(unless (equal? (member 2 '(1 2 3)) '(2 3))
  (display "FAIL: member on proper list") (newline) (exit 1))
(unless (equal? (memq 'b '(a b c)) '(b c))
  (display "FAIL: memq on proper list") (newline) (exit 1))
(unless (equal? (assoc 'b '((a . 1) (b . 2))) '(b . 2))
  (display "FAIL: assoc on proper list") (newline) (exit 1))
(unless (equal? (list-copy '(1 2 3)) '(1 2 3))
  (display "FAIL: list-copy on proper list") (newline) (exit 1))

(display "PASS")
(newline)
