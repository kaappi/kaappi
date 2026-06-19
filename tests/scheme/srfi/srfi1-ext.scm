(import (scheme base) (scheme write) (srfi 1))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; Constructors
(check "xcons" (xcons 1 2) '(2 . 1))
(check "cons*" (cons* 1 2 3 '(4 5)) '(1 2 3 4 5))
(check "cons* single" (cons* 1) 1)
(check "list-tabulate" (list-tabulate 5 (lambda (i) (* i i))) '(0 1 4 9 16))
(check "list-tabulate 0" (list-tabulate 0 values) '())

;; circular-list
(let ((cl (circular-list 1 2 3)))
  (check "circular-list car" (car cl) 1)
  (check "circular-list cadr" (cadr cl) 2)
  (check "circular-list cadddr" (car (cdddr cl)) 1))

;;; Predicates
(check-true "not-pair? 42" (not-pair? 42))
(check-false "not-pair? pair" (not-pair? '(1)))
(check-true "null-list? '()" (null-list? '()))
(check-false "null-list? pair" (null-list? '(1)))
(check-true "list= equal" (list= = '(1 2 3) '(1 2 3)))
(check-false "list= diff" (list= = '(1 2 3) '(1 2 4)))
(check-false "list= diff len" (list= = '(1 2) '(1 2 3)))
(check-true "list= empty" (list= = '() '()))

;;; Selectors
(check "first" (first '(10 20 30 40 50)) 10)
(check "second" (second '(10 20 30 40 50)) 20)
(check "third" (third '(10 20 30 40 50)) 30)
(check "fourth" (fourth '(10 20 30 40 50)) 40)
(check "fifth" (fifth '(10 20 30 40 50)) 50)

(let-values (((a d) (car+cdr '(1 . 2))))
  (check "car+cdr car" a 1)
  (check "car+cdr cdr" d 2))

(check "take-right" (take-right '(1 2 3 4 5) 3) '(3 4 5))
(check "take-right 0" (take-right '(1 2 3) 0) '())
(check "drop-right" (drop-right '(1 2 3 4 5) 2) '(1 2 3))
(check "drop-right 0" (drop-right '(1 2 3) 0) '(1 2 3))

(let-values (((a b) (split-at '(1 2 3 4 5) 3)))
  (check "split-at left" a '(1 2 3))
  (check "split-at right" b '(4 5)))

;;; Searching
(check "list-index" (list-index even? '(1 3 4 5)) 2)
(check-false "list-index miss" (list-index even? '(1 3 5 7)))
(check "list-index 2-list" (list-index = '(1 2 3) '(3 2 1)) 1)

(let-values (((a b) (span even? '(2 4 5 6))))
  (check "span prefix" a '(2 4))
  (check "span suffix" b '(5 6)))

(let-values (((a b) (span even? '(1 2 3))))
  (check "span no prefix" a '())
  (check "span all suffix" b '(1 2 3)))

(let-values (((a b) (break even? '(1 3 4 5))))
  (check "break prefix" a '(1 3))
  (check "break suffix" b '(4 5)))

;;; Deletion
(check "delete" (delete 3 '(1 2 3 4 3 5)) '(1 2 4 5))
(check "delete with pred" (delete 3 '(1 2 3 4 5) =) '(1 2 4 5))
(check "delete miss" (delete 9 '(1 2 3)) '(1 2 3))
(check "delete-duplicates" (delete-duplicates '(1 2 1 3 2 4)) '(1 2 3 4))
(check "delete-duplicates pred" (delete-duplicates '(1 2 1 3) =) '(1 2 3))
(check "delete-duplicates empty" (delete-duplicates '()) '())

;;; Association lists
(check "alist-cons" (alist-cons 'a 1 '((b . 2))) '((a . 1) (b . 2)))
(check "alist-copy" (alist-copy '((a . 1) (b . 2))) '((a . 1) (b . 2)))
(check "alist-delete" (alist-delete 'b '((a . 1) (b . 2) (c . 3))) '((a . 1) (c . 3)))
(check "alist-delete miss" (alist-delete 'z '((a . 1))) '((a . 1)))
(check "alist-delete pred" (alist-delete 2 '((1 . a) (2 . b) (3 . c)) =) '((1 . a) (3 . c)))

;;; Unfold
(check "unfold" (unfold (lambda (x) (> x 5)) (lambda (x) (* x x)) (lambda (x) (+ x 1)) 1)
       '(1 4 9 16 25))
(check "unfold-right" (unfold-right zero? (lambda (x) (* x x)) (lambda (x) (- x 1)) 5)
       '(1 4 9 16 25))
(check "unfold empty" (unfold (lambda (x) #t) values values 0) '())

;;; Set operations
(check "lset-adjoin" (lset-adjoin = '(1 2 3) 2 4) '(4 1 2 3))
(check "lset-union" (lset-union = '(1 2 3) '(2 3 4)) '(4 1 2 3))
(check "lset-union empty" (lset-union =) '())
(check "lset-xor" (lset-xor = '(1 2 3) '(2 3 4)) '(1 4))
(check "lset-xor same" (lset-xor = '(1 2) '(1 2)) '())

;;; Misc
(check "append-reverse" (append-reverse '(3 2 1) '(4 5)) '(1 2 3 4 5))
(check "append-reverse empty" (append-reverse '() '(1 2)) '(1 2))
(check "length+" (length+ '(1 2 3)) 3)
(check-false "length+ circular" (length+ (circular-list 1 2)))

(let-values (((a) (unzip1 '((1 2) (3 4) (5 6)))))
  (check "unzip1" a '(1 3 5)))

(let-values (((a b) (unzip2 '((1 2) (3 4) (5 6)))))
  (check "unzip2 firsts" a '(1 3 5))
  (check "unzip2 seconds" b '(2 4 6)))

;;; Pair-fold / pair-for-each
(check "pair-fold" (pair-fold (lambda (p acc) (+ acc (car p))) 0 '(1 2 3)) 6)

(let ((result '()))
  (pair-for-each (lambda (p) (set! result (cons (car p) result))) '(1 2 3))
  (check "pair-for-each" result '(3 2 1)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 1 extended tests failed" fail))
