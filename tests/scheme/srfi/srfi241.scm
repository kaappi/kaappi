;; SRFI-241 (Match) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi241.scm
;;
;; Kaappi's reader has no [...]  bracket syntax, so clauses and cata patterns
;; are written with plain parens throughout (see lib/srfi/241.sld header for
;; the full list of scope limitations relative to the SRFI text).

(import (scheme base) (scheme process-context) (srfi 241) (srfi 64))

(test-begin "srfi-241")

;;; --- literal symbols, variables, clause fallthrough ---
(test-equal "spec example: literal + variable dispatch"
  629
  (match '(a 17 37)
    ((a ,x) (- x))
    ((b ,x ,y) (+ x y))
    ((a ,x ,y) (* x y))))

;;; --- wildcard ---
(test-equal "wildcard: ,_" 'ok (match '(1 2 3) ((1 ,_ 3) 'ok) (,_ 'no)))

;;; --- pairs / dotted tail ---
(test-equal "pair pattern with dotted tail"
  '(1 . (2 3))
  (match '(1 2 3) ((,x . ,y) (cons x y))))

;;; --- default cata (auto-recursion): list length ---
(define (my-length lst)
  (match lst
    (() 0)
    ((,x . ,(y)) (+ 1 y))))

(test-equal "default cata: length via auto-recursion" 4 (my-length '(a b c d)))
(test-equal "default cata: length of empty list" 0 (my-length '()))

;;; --- named cata: split into odds/evens ---
(define (my-split lis)
  (match lis
    (() (values '() '()))
    ((,x) (values (list x) '()))
    ((,x ,y . ,(my-split -> odds evens))
     (values (cons x odds) (cons y evens)))))

(let-values (((odds evens) (my-split '(a b c d e f))))
  (test-equal "named cata: split odds" '(a c e) odds)
  (test-equal "named cata: split evens" '(b d f) evens))

;;; --- guards + repeated default-cata (,(var) ...) ---
(define (simple-eval x)
  (match x
    (,i (guard (integer? i)) i)
    ((+ ,(x*) ...) (apply + x*))
    ((* ,(x*) ...) (apply * x*))
    ((- ,(x) ,(y)) (- x y))
    ((/ ,(x) ,(y)) (/ x y))
    (,_ (error "simple-eval: invalid expression" x))))

(test-equal "guard + repeated cata: spec example"
  4
  (simple-eval '(+ (- 0 1) (+ 2 3))))
(test-equal "guard: bare integer" 5 (simple-eval 5))
(test-equal "repeated cata: multiplication" 24 (simple-eval '(* 2 3 4)))

;;; --- ellipsis: simple variable collector ---
(test-equal "ellipsis: (,x ...) collects whole list"
  '(1 2 3)
  (match '(1 2 3) ((,x ...) x)))

(test-equal "ellipsis: (,x ...) on empty list"
  '()
  (match '() ((,x ...) x)))

(test-equal "ellipsis with fixed prefix: (a ,x ...)"
  '(2 3)
  (match '(a 2 3) ((a ,x ...) x)))

(test-equal "ellipsis with dotted tail: (,x ... . ,y)"
  (cons '(1 2) 3)
  (match (cons 1 (cons 2 3))
    ((,x ... . ,y) (cons x y))))

;;; --- vector patterns ---
(test-equal "vector: fixed length"
  '(1 2 3)
  (match #(1 2 3) (#(,a ,b ,c) (list a b c))))

(test-equal "vector: whole-vector ellipsis"
  '(1 2 3 4)
  (match #(1 2 3 4) (#(,x ...) x)))

(test-assert "vector: wrong length fails to matching clause"
  (match #(1 2)
    (#(,a ,b ,c) #f)
    (,_ #t)))

;;; --- no matching clause raises ---
(test-assert "no matching clause signals an error"
  (guard (e (#t #t))
    (match 42 ((a) 'no))
    #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-241")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
