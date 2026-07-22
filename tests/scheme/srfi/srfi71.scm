;; SRFI-71 (Extended LET-syntax for multiple values) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi71.scm

(import (scheme base) (scheme process-context) (srfi 71) (srfi 64))

(test-begin "srfi-71")

(define (quo-rem x y) (values (quotient x y) (remainder x y)))

;;; --- let: backward compatibility with plain R7RS bindings ---
(test-equal "let: ordinary single binding" 1 (let ((x 1)) x))
(test-equal "let: ordinary parallel bindings" 3 (let ((x 1) (y 2)) (+ x y)))
(test-equal "let: named let is untouched"
  10
  (let loop ((i 0) (acc 0)) (if (= i 5) acc (loop (+ i 1) (+ acc i)))))

;;; --- let: multi-value shorthand and explicit forms ---
(test-equal "let: shorthand multi-value binding" '(3 1) (let ((q r (quo-rem 7 2))) (list q r)))
(test-equal "let: explicit (values ...) binding" '(10 20) (let (((values y1 y2) (values 10 20))) (list y1 y2)))
(test-equal "let: explicit dotted-rest binding" '(1 (2 3)) (let (((values a . rest) (values 1 2 3))) (list a rest)))
(test-equal "let: zero-value binding" 'ok (let (((values) (values))) 'ok))
(test-equal "let: multiple clauses are parallel" '(1 2 3) (let ((a 1) (b c (values 2 3))) (list a b c)))
(test-equal "let: spec's own quo example" 3 (let ((q r (quo-rem 7 2))) q))
(test-equal "let: spec's own uncons example" '(1 . 2) (let ((car-x cdr-x (uncons (cons 1 2)))) (cons car-x cdr-x)))

;;; --- let*: sequential visibility ---
(test-equal "let*: ordinary sequential binding" 3 (let* ((x 1) (y (+ x 1))) (+ x y)))
(test-equal "let*: multi-value binding feeds a later clause" '(1 2 3) (let* ((a b (values 1 2)) (c (+ a b))) (list a b c)))
(test-equal "let*: zero bindings" 5 (let* () 5))

;;; --- letrec: mutual recursion and multi-value clauses ---
(test-equal "letrec: mutual recursion"
  #t
  (letrec ((ev? (lambda (n) (if (= n 0) #t (od? (- n 1)))))
           (od? (lambda (n) (if (= n 0) #f (ev? (- n 1))))))
    (ev? 10)))
(test-equal "letrec: multi-value clause, later clause sees it" '(1 2 3) (letrec ((a b (values 1 2)) (c (+ a b))) (list a b c)))
(test-equal "letrec: explicit dotted-rest clause" '(1 (2 3)) (letrec (((values a . rest) (values 1 2 3))) (list a rest)))

;;; --- un- procedures ---
(test-equal "uncons" '(1 2) (values->list (uncons (cons 1 2))))
(test-equal "uncons-2" '(1 2 (3)) (values->list (uncons-2 '(1 2 3))))
(test-equal "uncons-3" '(1 2 3 (4)) (values->list (uncons-3 '(1 2 3 4))))
(test-equal "uncons-4" '(1 2 3 4 (5)) (values->list (uncons-4 '(1 2 3 4 5))))
(test-equal "uncons-cons" '(1 2 ((3 . 4))) (values->list (uncons-cons '((1 . 2) (3 . 4)))))
(test-equal "unlist" '(1 2 3) (values->list (unlist '(1 2 3))))
(test-equal "unvector" '(1 2 3) (values->list (unvector #(1 2 3))))

;;; --- values->list / values->vector ---
(test-equal "values->list: multiple values" '(1 2 3) (values->list (values 1 2 3)))
(test-equal "values->list: zero values" '() (values->list (values)))
(test-equal "values->list: single value" '(42) (values->list 42))
(test-equal "values->vector: multiple values" #(1 2 3) (values->vector (values 1 2 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-71")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
