;;; SRFI 201 (Syntactic extensions to the core Scheme bindings) tests
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi201.scm
;;;
;;; See lib/srfi/201.sld for the scope of the port relative to the full
;;; spec, and in particular why this suite uses the SRFI's own reference
;;; names (mlambda, cdefine, named-match-let-values, match-let*-values,
;;; or/values) rather than importing them renamed over lambda/define/
;;; let/let*/or: shadowing those names hits a real Kaappi engine bug
;;; (documented in detail in the library header) whenever the shadowing
;;; transformer's expansion isn't a byte-for-byte reproduction of its
;;; input. Using the SRFI's own names sidesteps it entirely while
;;; exercising the exact same matching engine.

(import (scheme base) (srfi 201) (scheme write) (scheme process-context) (srfi 64))

(test-begin "srfi-201")

;;; --- mlambda: plain identifiers behave like ordinary lambda ---

(test-equal "plain identifier mlambda" 7 ((mlambda (a b) (+ a b)) 3 4))
(test-equal "plain variadic mlambda" '(1 2 3) ((mlambda args args) 1 2 3))
(test-equal "plain dotted mlambda" '(1 2 3)
  ((mlambda (a . rest) (cons a rest)) 1 2 3))
(test-equal "mlambda body may contain internal defines"
  30
  ((mlambda (n) (define double (* 2 n)) (+ double n)) 10))

;;; --- mlambda: pattern-matching parameters (SRFI 201's own example) ---

(test-equal "spec example: destructuring mlambda parameter"
  '(3 7 11)
  (map (mlambda (`(,x . ,y)) (+ x y)) '((1 . 2) (3 . 4) (5 . 6))))

(test-equal "nested pair pattern in mlambda parameter"
  6
  ((mlambda (`(,a (,b ,c))) (+ a b c)) '(1 (2 3))))

(test-equal "literal-in-pattern must match"
  'ok
  ((mlambda (`(tag ,x)) (if (= x 5) 'ok 'no)) '(tag 5)))

(test-assert "mismatched literal in pattern signals an error"
  (guard (e (#t #t))
    ((mlambda (`(tag ,x)) x) '(other 5))
    #f))

(test-equal "vector pattern in mlambda parameter"
  5
  ((mlambda (`#(,a ,b)) (+ a b)) #(2 3)))

;;; --- mlambda: body-less is a predicate ---

(test-equal "body-less mlambda, matching pattern" #t
  ((mlambda (`(,x . ,y))) '(1 . 2)))
(test-equal "body-less mlambda, non-matching pattern" #f
  ((mlambda (`(,x . ,y))) 5))
(test-equal "body-less mlambda over plain identifiers always matches" #t
  ((mlambda (a b)) 1 2))

;;; --- mlambda: match failure raises an error ---

(test-assert "non-bodyless mlambda signals an error on pattern mismatch"
  (guard (e (#t #t))
    ((mlambda (`(,x . ,y)) x) 5)
    #f))

;;; --- cdefine: plain and curried (SRFI 219-style currying) ---

(cdefine forty-two 42)
(test-equal "plain cdefine" 42 forty-two)

(cdefine (plain-fn x) (* x 2))
(test-equal "simple function cdefine" 10 (plain-fn 5))

(cdefine ((adder n) m) (+ n m))
(test-equal "one level of currying" 7 ((adder 3) 4))
(cdefine add5 (adder 5))
(test-equal "curried cdefine partial application" 15 (add5 10))

(cdefine (((compose3 f) g) x) (f (g x)))
(test-equal "two levels of currying"
  9
  (((compose3 (mlambda (n) (* n n))) (mlambda (n) (+ n 1))) 2))

(cdefine ((cat . xs) . ys) (append xs ys))
(test-equal "rest arguments at each curry level" '(1 2 3) ((cat 1 2) 3))

;;; --- cdefine: curried with destructuring parameters ---

(cdefine ((pair-adder `(,a . ,b)) `(,c . ,d)) (+ a b c d))
(test-equal "curried cdefine with destructuring patterns"
  10
  ((pair-adder '(1 . 2)) '(3 . 4)))

;;; --- cdefine: body-less curried => nested predicate ---

(cdefine ((both-pairs? `(,a . ,b)) `(,c . ,d)))
(test-equal "body-less curried cdefine matches at every level" #t
  ((both-pairs? '(1 . 2)) '(3 . 4)))
(test-equal "body-less curried cdefine rejects mismatch at outer level" #f
  ((both-pairs? 5) '(3 . 4)))
(test-equal "body-less curried cdefine rejects mismatch at inner level" #f
  ((both-pairs? '(1 . 2)) 5))

;;; --- named-match-let-values / match-let*-values: pattern bindings ---

(test-equal "plain let-shaped binding" 7
  (named-match-let-values ((a 3) (b 4)) (+ a b)))
(test-equal "destructuring let-shaped binding"
  3
  (named-match-let-values ((`(,x . ,y) '(1 . 2))) (+ x y)))
(test-equal "named-match-let-values with plain bindings"
  120
  (named-match-let-values loop ((n 5) (acc 1))
    (if (= n 0) acc (loop (- n 1) (* acc n)))))
(test-equal "named-match-let-values with a destructuring binding"
  6
  (named-match-let-values loop ((`(,a . ,b) '(1 . 2)) (acc 3))
    (+ a b acc)))

(test-equal "plain match-let*-values" 8
  (match-let*-values ((a 3) (b (+ a 1))) (+ a b (- b a))))
(test-equal "destructuring match-let*-values, later binding sees earlier"
  7
  (match-let*-values ((`(,x . ,y) '(3 . 4)) (total (+ x y))) total))

;;; --- or/values: multiple-value propagation ---

(test-equal "or/values with no arguments" #f (or/values))
(test-equal "or/values with a single expression" 5 (or/values 5))
(test-equal "or/values short-circuits on first true value" 1 (or/values 1 2))
(test-equal "or/values skips false values" 2 (or/values #f 2))
(test-equal "or/values with all false" #f (or/values #f #f))

(test-equal "or/values propagates multiple values from a true leading expression"
  '(1 2)
  (call-with-values (lambda () (or/values (values 1 2) #f)) list))

(test-equal "or/values propagates multiple values from a later expression"
  '(1 2)
  (call-with-values (lambda () (or/values #f (values 1 2))) list))

(let ((runner (test-runner-current)))
  (test-end "srfi-201")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
