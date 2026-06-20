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

;;; ---- Folds ----
(check "fold +" (fold + 0 '(1 2 3 4 5)) 15)
(check "fold cons" (fold cons '() '(a b c)) '(c b a))
(check "fold empty" (fold + 0 '()) 0)
(check "fold 2-list" (fold (lambda (a b acc) (+ a b acc)) 0 '(1 2 3) '(10 20 30)) 66)

(check "fold-right cons" (fold-right cons '() '(a b c)) '(a b c))
(check "fold-right +" (fold-right + 0 '(1 2 3)) 6)
(check "fold-right empty" (fold-right + 0 '()) 0)
(check "fold-right 2-list" (fold-right (lambda (a b acc) (cons (list a b) acc)) '() '(1 2 3) '(a b c))
       '((1 a) (2 b) (3 c)))

(check "reduce +" (reduce + 0 '(1 2 3 4 5)) 15)
(check "reduce empty" (reduce + 0 '()) 0)
(check "reduce single" (reduce + 0 '(42)) 42)

(check "reduce-right +" (reduce-right + 0 '(1 2 3)) 6)
(check "reduce-right empty" (reduce-right + 0 '()) 0)
(check "reduce-right cons" (reduce-right cons '() '(a b c)) '(a b . c))

;;; ---- Filtering ----
(check "filter even?" (filter even? '(1 2 3 4 5 6)) '(2 4 6))
(check "filter none" (filter even? '(1 3 5)) '())
(check "filter all" (filter even? '(2 4 6)) '(2 4 6))
(check "filter empty" (filter even? '()) '())

(check "remove even?" (remove even? '(1 2 3 4 5)) '(1 3 5))
(check "remove none" (remove even? '(1 3 5)) '(1 3 5))
(check "remove all" (remove even? '(2 4 6)) '())
(check "remove empty" (remove even? '()) '())

(let-values (((yes no) (partition even? '(1 2 3 4 5))))
  (check "partition yes" yes '(2 4))
  (check "partition no" no '(1 3 5)))
(let-values (((yes no) (partition even? '())))
  (check "partition empty yes" yes '())
  (check "partition empty no" no '()))

;;; ---- Searching ----
(check "find even?" (find even? '(1 3 4 5)) 4)
(check-false "find none" (find even? '(1 3 5)))
(check-false "find empty" (find even? '()))

(let ((result (find-tail even? '(1 3 4 5))))
  (check "find-tail" (car result) 4)
  (check "find-tail rest" (cdr result) '(5)))
(check-false "find-tail none" (find-tail even? '(1 3 5)))
(check-false "find-tail empty" (find-tail even? '()))

(check-true "any even? found" (any even? '(1 3 4 5)))
(check-false "any even? none" (any even? '(1 3 5)))
(check-false "any empty" (any even? '()))
(check-true "any 2-list" (any = '(1 2 3) '(3 2 1)))

(check-true "every even? all" (every even? '(2 4 6)))
(check-false "every even? mixed" (every even? '(2 3 4)))
(check-true "every empty" (every even? '()))
(check-true "every 2-list" (every < '(1 2 3) '(4 5 6)))
(check-false "every 2-list fail" (every < '(1 2 3) '(0 5 6)))

(check "count even?" (count even? '(1 2 3 4 5 6)) 3)
(check "count none" (count even? '(1 3 5)) 0)
(check "count empty" (count even? '()) 0)
(check "count 2-list" (count = '(1 2 3) '(1 0 3)) 2)

;;; ---- Construction ----
(check "iota 5" (iota 5) '(0 1 2 3 4))
(check "iota 0" (iota 0) '())
(check "iota start" (iota 5 1) '(1 2 3 4 5))
(check "iota step" (iota 5 0 2) '(0 2 4 6 8))
(check "iota float start" (iota 3 1.0) '(1.0 2.0 3.0))
(check "iota float step" (iota 3 0 0.5) '(0.0 0.5 1.0))

(check "zip" (zip '(a b c) '(1 2 3)) '((a 1) (b 2) (c 3)))
(check "zip unequal" (zip '(a b) '(1 2 3)) '((a 1) (b 2)))
(check "zip single" (zip '(a b c)) '((a) (b) (c)))
(check "zip empty" (zip '()) '())

(check "concatenate" (concatenate '((a b) (c d) (e))) '(a b c d e))
(check "concatenate empty lists" (concatenate '(() () ())) '())
(check "concatenate empty" (concatenate '()) '())
(check "concatenate single" (concatenate '((1 2 3))) '(1 2 3))

;;; ---- Extraction ----
(check "take" (take '(a b c d) 2) '(a b))
(check "take 0" (take '(a b c) 0) '())
(check "drop" (drop '(a b c d) 2) '(c d))
(check "drop 0" (drop '(a b c) 0) '(a b c))

(check "take-while" (take-while even? '(2 4 5 6)) '(2 4))
(check "take-while none" (take-while even? '(1 2 3)) '())
(check "take-while all" (take-while even? '(2 4 6)) '(2 4 6))
(check "take-while empty" (take-while even? '()) '())

(check "drop-while" (drop-while even? '(2 4 5 6)) '(5 6))
(check "drop-while none" (drop-while even? '(1 2 3)) '(1 2 3))
(check "drop-while all" (drop-while even? '(2 4 6)) '())
(check "drop-while empty" (drop-while even? '()) '())

;;; ---- Mapping ----
(check "filter-map" (filter-map (lambda (x) (if (even? x) (* x 2) #f)) '(1 2 3 4 5))
       '(4 8))
(check "filter-map all false" (filter-map (lambda (x) #f) '(1 2 3)) '())
(check "filter-map empty" (filter-map values '()) '())
(check "filter-map 2-list" (filter-map (lambda (a b) (if (= a b) a #f)) '(1 2 3) '(1 0 3))
       '(1 3))

(check "append-map" (append-map (lambda (x) (list x (* x 10))) '(1 2 3))
       '(1 10 2 20 3 30))
(check "append-map empty results" (append-map (lambda (x) '()) '(1 2 3)) '())
(check "append-map empty" (append-map values '()) '())

;;; ---- Misc ----
(check "last" (last '(1 2 3)) 3)
(check "last single" (last '(42)) 42)

(let ((lp (last-pair '(1 2 3))))
  (check "last-pair car" (car lp) 3)
  (check "last-pair cdr" (cdr lp) '()))

(check-true "proper-list?" (proper-list? '(1 2 3)))
(check-true "proper-list? empty" (proper-list? '()))
(check-false "proper-list? dotted" (proper-list? '(1 . 2)))
(check-false "proper-list? atom" (proper-list? 42))

(check-false "dotted-list? proper" (dotted-list? '(1 2 3)))
(check-false "dotted-list? empty" (dotted-list? '()))
(check-true "dotted-list? dotted" (dotted-list? '(1 . 2)))
(check-true "dotted-list? atom" (dotted-list? 42))

(let ((cl (circular-list 1 2 3)))
  (check-true "circular-list?" (circular-list? cl))
  (check-false "circular-list? proper" (circular-list? '(1 2 3)))
  (check-false "circular-list? empty" (circular-list? '()))
  (check-false "circular-list? atom" (circular-list? 42))
  (check-false "proper-list? circular" (proper-list? cl))
  (check-false "dotted-list? circular" (dotted-list? cl)))

;;; ---- Selectors ----
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
(check "take-right all" (take-right '(1 2 3) 3) '(1 2 3))

(check "drop-right" (drop-right '(1 2 3 4 5) 2) '(1 2 3))
(check "drop-right 0" (drop-right '(1 2 3) 0) '(1 2 3))
(check "drop-right all" (drop-right '(1 2 3) 3) '())

(let-values (((a b) (split-at '(1 2 3 4 5) 3)))
  (check "split-at left" a '(1 2 3))
  (check "split-at right" b '(4 5)))
(let-values (((a b) (split-at '(1 2 3) 0)))
  (check "split-at 0 left" a '())
  (check "split-at 0 right" b '(1 2 3)))

;;; ---- Searching (advanced) ----
(check "list-index" (list-index even? '(1 3 4 5)) 2)
(check-false "list-index miss" (list-index even? '(1 3 5 7)))
(check "list-index 2-list" (list-index = '(1 2 3) '(3 2 1)) 1)
(check "list-index empty" (list-index even? '()) #f)

(let-values (((a b) (span even? '(2 4 5 6))))
  (check "span prefix" a '(2 4))
  (check "span suffix" b '(5 6)))
(let-values (((a b) (span even? '(1 2 3))))
  (check "span no prefix" a '())
  (check "span all suffix" b '(1 2 3)))
(let-values (((a b) (span even? '(2 4 6))))
  (check "span all prefix" a '(2 4 6))
  (check "span empty suffix" b '()))
(let-values (((a b) (span even? '())))
  (check "span empty prefix" a '())
  (check "span empty suffix2" b '()))

(let-values (((a b) (break even? '(1 3 4 5))))
  (check "break prefix" a '(1 3))
  (check "break suffix" b '(4 5)))
(let-values (((a b) (break even? '(2 4 6))))
  (check "break immediate" a '())
  (check "break all" b '(2 4 6)))
(let-values (((a b) (break even? '())))
  (check "break empty prefix" a '())
  (check "break empty suffix" b '()))

;;; ---- Deletion ----
(check "delete" (delete 3 '(1 2 3 4 3 5)) '(1 2 4 5))
(check "delete with pred" (delete 3 '(1 2 3 4 5) =) '(1 2 4 5))
(check "delete miss" (delete 9 '(1 2 3)) '(1 2 3))
(check "delete empty" (delete 1 '()) '())
(check "delete all" (delete 1 '(1 1 1)) '())

(check "delete-duplicates" (delete-duplicates '(1 2 1 3 2 4)) '(1 2 3 4))
(check "delete-duplicates pred" (delete-duplicates '(1 2 1 3) =) '(1 2 3))
(check "delete-duplicates empty" (delete-duplicates '()) '())
(check "delete-duplicates no dups" (delete-duplicates '(1 2 3)) '(1 2 3))
(check "delete-duplicates all same" (delete-duplicates '(1 1 1)) '(1))

;;; ---- Association lists ----
(check "alist-cons" (alist-cons 'a 1 '((b . 2))) '((a . 1) (b . 2)))
(check "alist-cons empty" (alist-cons 'a 1 '()) '((a . 1)))
(check "alist-copy" (alist-copy '((a . 1) (b . 2))) '((a . 1) (b . 2)))
(check "alist-copy empty" (alist-copy '()) '())
(check "alist-delete" (alist-delete 'b '((a . 1) (b . 2) (c . 3))) '((a . 1) (c . 3)))
(check "alist-delete miss" (alist-delete 'z '((a . 1))) '((a . 1)))
(check "alist-delete pred" (alist-delete 2 '((1 . a) (2 . b) (3 . c)) =) '((1 . a) (3 . c)))
(check "alist-delete empty" (alist-delete 'a '()) '())

;;; ---- Set operations ----
(check "lset-adjoin" (lset-adjoin = '(1 2 3) 2 4) '(4 1 2 3))
(check "lset-adjoin all new" (lset-adjoin = '() 1 2 3) '(3 2 1))
(check "lset-adjoin no new" (lset-adjoin = '(1 2 3) 1 2 3) '(1 2 3))

(check "lset-union" (lset-union = '(1 2 3) '(2 3 4)) '(4 1 2 3))
(check "lset-union empty" (lset-union =) '())
(check "lset-union single" (lset-union = '(1 2 3)) '(1 2 3))
(check "lset-union 3 lists"
       (lset-union = '(1 2) '(2 3) '(3 4))
       '(4 3 1 2))

(check "lset-xor" (lset-xor = '(1 2 3) '(2 3 4)) '(1 4))
(check "lset-xor same" (lset-xor = '(1 2) '(1 2)) '())
(check "lset-xor single" (lset-xor = '(1 2 3)) '(1 2 3))

(check "lset-intersection" (lset-intersection eq? '(a b c d) '(b c e)) '(b c))
(check "lset-intersection empty" (lset-intersection eq? '(a b c) '(d e f)) '())
(check "lset-intersection 3 lists" (lset-intersection eq? '(a b c) '(b c d) '(c d e)) '(c))

(check "lset-difference" (lset-difference eq? '(a b c d) '(b c e)) '(a d))
(check "lset-difference chained" (lset-difference eq? '(a b c d) '(b) '(d)) '(a c))
(check-true "lset= same" (lset= eq? '(a b c) '(c b a)))
(check-false "lset= different" (lset= eq? '(a b) '(a b c)))
(check-true "lset= empty" (lset= eq? '() '()))

;;; ---- Unfold ----
(check "unfold" (unfold (lambda (x) (> x 5)) (lambda (x) (* x x)) (lambda (x) (+ x 1)) 1)
       '(1 4 9 16 25))
(check "unfold empty" (unfold (lambda (x) #t) values values 0) '())

(check "unfold-right" (unfold-right zero? (lambda (x) (* x x)) (lambda (x) (- x 1)) 5)
       '(1 4 9 16 25))
(check "unfold-right empty" (unfold-right (lambda (x) #t) values values 0) '())
(check "unfold-right with tail" (unfold-right zero? values (lambda (x) (- x 1)) 3 '(99))
       '(1 2 3 99))

;;; ---- Misc ----
(check "append-reverse" (append-reverse '(3 2 1) '(4 5)) '(1 2 3 4 5))
(check "append-reverse empty" (append-reverse '() '(1 2)) '(1 2))
(check "append-reverse empty tail" (append-reverse '(3 2 1) '()) '(1 2 3))

(check "length+" (length+ '(1 2 3)) 3)
(check "length+ empty" (length+ '()) 0)
(check-false "length+ circular" (length+ (circular-list 1 2)))

(let ((u1 (unzip1 '((1 2) (3 4) (5 6)))))
  (check "unzip1" u1 '(1 3 5)))
(let-values (((a b) (unzip2 '((1 2) (3 4) (5 6)))))
  (check "unzip2 firsts" a '(1 3 5))
  (check "unzip2 seconds" b '(2 4 6)))

(check "pair-fold" (pair-fold (lambda (p acc) (+ acc (car p))) 0 '(1 2 3)) 6)

(let ((result '()))
  (pair-for-each (lambda (p) (set! result (cons (car p) result))) '(1 2 3))
  (check "pair-for-each" result '(3 2 1)))

;;; ---- Constructors (additional) ----
(check "xcons" (xcons 1 2) '(2 . 1))
(check "cons*" (cons* 1 2 3 '(4 5)) '(1 2 3 4 5))
(check "cons* single" (cons* 1) 1)
(check "cons* two" (cons* 1 2) '(1 . 2))

(check "list-tabulate" (list-tabulate 5 (lambda (i) (* i i))) '(0 1 4 9 16))
(check "list-tabulate 0" (list-tabulate 0 values) '())
(check "list-tabulate 1" (list-tabulate 1 (lambda (i) 'x)) '(x))

(let ((cl (circular-list 1 2 3)))
  (check "circular-list car" (car cl) 1)
  (check "circular-list cadr" (cadr cl) 2)
  (check "circular-list wrap" (car (cdddr cl)) 1))
(check "circular-list single" (car (circular-list 42)) 42)

;;; ---- Predicates ----
(check-true "not-pair? 42" (not-pair? 42))
(check-false "not-pair? pair" (not-pair? '(1)))
(check-true "not-pair? nil" (not-pair? '()))
(check-true "not-pair? string" (not-pair? "hello"))

(check-true "null-list? '()" (null-list? '()))
(check-false "null-list? pair" (null-list? '(1)))

(check-true "list= equal" (list= = '(1 2 3) '(1 2 3)))
(check-false "list= diff" (list= = '(1 2 3) '(1 2 4)))
(check-false "list= diff len" (list= = '(1 2) '(1 2 3)))
(check-true "list= empty" (list= = '() '()))
(check-true "list= single" (list= =))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI-1 coverage tests failed" fail))
