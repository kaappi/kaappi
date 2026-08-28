;; SRFI-241 (Match) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi241.scm
;;
;; Kaappi's reader has no [...]  bracket syntax, so clauses and cata patterns
;; are written with plain parens throughout (see lib/srfi/241.sld header for
;; the remaining scope notes relative to the SRFI text).

(import (scheme base) (scheme process-context) (srfi 241) (srfi 64)
        (srfi 211 explicit-renaming))

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

;;; ==================================================================
;;; Lifted limitation 1 (kaappi#2391): arbitrary ellipsis sub-patterns
;;; ==================================================================

(test-equal "compound subpattern under ellipsis"
  '((1 3) (2 4))
  (match '((1 2) (3 4)) (((,a ,b) ...) (list a b))))

(test-equal "nested ellipsis"
  '((1 2 3) (4 5))
  (match '((1 2 3) (4 5)) (((,x ...) ...) x)))

(test-equal "literal inside ellipsis subpattern"
  '(1 2)
  (match '((k 1) (k 2)) (((k ,v) ...) v)))

(test-equal "literal mismatch under ellipsis falls to next clause"
  'no
  (match '((k 1) (j 2)) (((k ,v) ...) v) (,_ 'no)))

(test-equal "dotted subpattern under ellipsis"
  '((a c) (b d))
  (match '((a . b) (c . d)) (((,x . ,y) ...) (list x y))))

(test-equal "vector subpattern under ellipsis"
  '((1 3) (2 4))
  (match '(#(1 2) #(3 4)) ((#(,a ,b) ...) (list a b))))

(test-equal "named cata under ellipsis with multiple values"
  '((1 2 3) (2 4 6))
  (let ((dup (lambda (x) (values x (* 2 x)))))
    (match '(1 2 3) ((,(dup -> a b) ...) (list a b)))))

(test-equal "named cata inside compound subpattern under ellipsis"
  '((1 3) (20 60))
  (let ((tenfold (lambda (v) (* v 10))))
    (match '((1 2) (3 6))
      (((,a ,(tenfold -> b)) ...) (list a b)))))

(test-equal "named cata at ellipsis depth 2 transposes"
  '((10 20) (30))
  (let ((tenfold (lambda (v) (* v 10))))
    (match '((1 2) (3))
      (((,(tenfold -> x) ...) ...) x))))

;;; ==================================================================
;;; Lifted limitation 2 (kaappi#2391): mandatory patterns after the
;;; ellipsis, in lists and vectors
;;; ==================================================================

(test-equal "ellipsis followed by one mandatory pattern"
  '((1 2 3) 4)
  (match '(1 2 3 4) ((,x ... ,y) (list x y))))

(test-equal "ellipsis followed by two mandatory patterns"
  '((1 2) 3 4)
  (match '(1 2 3 4) ((,x ... ,y ,z) (list x y z))))

(test-equal "ellipsis, mandatory pattern, then dotted tail"
  '((1 2) 3 4)
  (match '(1 2 3 . 4) ((,x ... ,y . ,r) (list x y r))))

(test-equal "minimum length: too few elements falls to next clause"
  'no
  (match '(1) ((,x ... ,y ,z) 'yes) (,_ 'no)))

(test-equal "empty ellipsis prefix before mandatory suffix"
  '(() 9)
  (match '(9) ((,x ... ,y) (list x y))))

(test-equal "vector: prefix + ellipsis + suffix"
  '(1 (2 3) 4)
  (match #(1 2 3 4) (#(,a ,m ... ,z) (list a m z))))

(test-equal "vector: empty ellipsis segment between prefix and suffix"
  '(1 () 2)
  (match #(1 2) (#(,a ,m ... ,z) (list a m z))))

(test-equal "vector: too short for prefix+suffix falls to next clause"
  'no
  (match #(1) (#(,a ,m ... ,z) 'yes) (,_ 'no)))

;;; ==================================================================
;;; Lifted limitation 3 (kaappi#2391): the SRFI's ellipsis-aware
;;; quasiquote inside match clause bodies
;;; ==================================================================

(test-equal "qq: splice an ellipsis-bound variable"
  '(got 1 2 3)
  (match '(1 2 3) ((,x ...) `(got ,x ...))))

(test-equal "qq: splice with a following literal"
  '(a 1 2 3 b)
  (match '(1 2 3) ((,x ...) `(a ,x ... b))))

(test-equal "qq: compound template iterates variables in parallel"
  '((1 . 2) (3 . 4))
  (match '((1 2) (3 4)) (((,a ,b) ...) `((,a . ,b) ...))))

(test-equal "qq: nested ellipsis template"
  '((1 2) (3))
  (match '((1 2) (3)) (((,x ...) ...) `((,x ...) ...))))

(test-equal "qq: double ellipsis flattens one level"
  '(1 2 3)
  (match '((1 2) (3)) (((,x ...) ...) `(,x ... ...))))

(test-equal "qq: arbitrary expression under ellipsis (spec example)"
  '(a 3 4 5 6 b)
  (match '() (() `(a ,(+ 1 2) ,(map abs '(4 -5 6)) ... b))))

(test-equal "qq: ordinary template unchanged"
  '(a 3 (b))
  (match 3 (,x `(a ,x (b)))))

(test-equal "qq: unquote-splicing still available"
  '(a 1 2 b)
  (match '(1 2) ((,x ...) `(a ,@x b))))

(test-equal "qq: (... tpl) escapes the ellipsis"
  '(a ...)
  (match '() (() `(... (a ...)))))

(test-equal "qq: nested quasiquote stays literal"
  '(quasiquote (a (unquote (+ 1 2))))
  (match '() (() ``(a ,(+ 1 2)))))

(test-equal "qq: vector template with splice"
  #(1 2 3)
  (match '(1 2 3) ((,x ...) `#(,x ...))))

(test-equal "qq: quasiquote outside match bodies is untouched"
  '(plain (1 2 3) ...)
  `(plain ,(list 1 2 3) ...))

;;; ==================================================================
;;; Lifted limitation 4 (kaappi#2391): cata operators run only after
;;; the clause's guard passes (the spec's evaluation order)
;;; ==================================================================

(define cata-calls 0)
(define (traced-cata v) (set! cata-calls (+ cata-calls 1)) v)

(test-equal "cata not evaluated when the guard rejects"
  'fallback
  (match '(5)
    ((,(traced-cata -> x)) (guard #f) 'no)
    (,_ 'fallback)))
(test-equal "no cata side effect after a rejected guard" 0 cata-calls)

(test-equal "cata evaluated when the guard passes"
  5
  (match '(5)
    ((,(traced-cata -> x)) (guard #t) x)
    (,_ 'fallback)))
(test-equal "exactly one cata call after a passing guard" 1 cata-calls)

(test-equal "guard still sees structurally bound variables"
  'big
  (match '(10) ((,x) (guard (> x 5)) 'big) (,_ 'small)))

;;; --- multiple values from a clause body ---
(test-equal "clause body may return multiple values"
  '(1 2)
  (call-with-values
    (lambda () (match '(1 2) ((,a ,b) (values a b))))
    list))

;;; --- pattern keywords survive an er-macro rename (evidence for #2388:
;;; compare is hygiene-stripped name equality, so a renamed ... / unquote
;;; emitted by another macro is still recognized) ---
(define-syntax collect-all
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'match) (cadr form)
           (list (list (list (rename 'unquote) (rename 'x)) (rename '...))
                 (rename 'x))))))

(test-equal "match emitted by an er-macro with renamed keywords"
  '(1 2 3)
  (collect-all '(1 2 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-241")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
