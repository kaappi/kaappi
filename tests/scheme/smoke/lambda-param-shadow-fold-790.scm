;; Regression test for #790: IR constant folding and simplifyBooleans must not
;; fold a call to a primitive name that is shadowed by a lambda parameter (or an
;; enclosing local). Lambda bodies are lowered through the IR by
;; compileLambdaWithIR, where the folds previously fired with no scope check.
;;
;; The shadowing expressions are passed as arguments to the plain procedure
;; `check` (NOT wrapped in a macro like SRFI-64's test-eqv), so the operator
;; lambda is compiled via the IR path rather than the legacy passthrough
;; compiler. Wrapping in test-eqv would exercise the already-correct legacy
;; path and pass even against the bug.
(import (scheme base) (scheme write))

(define failures 0)
(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (begin (set! failures (+ failures 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write actual) (newline))))

;; tryFoldFromAST / foldConstants: binary arithmetic
(check "param-shadowed + folds as -" -1 ((lambda (+) (+ 1 2)) -))
(check "param-shadowed * folds as -" -1 ((lambda (*) (* 3 4)) -))

;; comparison operators
(check "param-shadowed < returns +" 3 ((lambda (<) (< 1 2)) +))
(check "param-shadowed = returns +" 3 ((lambda (=) (= 1 2)) +))

;; unary predicates
(check "param-shadowed zero? returns list" '(0) ((lambda (zero?) (zero? 0)) list))
(check "param-shadowed not returns odd?" #t ((lambda (not) (not 5)) odd?))

;; simplifyBooleans: (if (not X) A B) must not rewrite when not is a parameter
(check "param-shadowed not in if" 'a ((lambda (not) (if (not 5) 'a 'b)) odd?))

;; foldConstants pass: inner (- 5 4) folds (- not shadowed), outer + is shadowed
;; by *, so the IR fold pass must leave (+ 1 2) alone -> (* 1 2) = 2.
(check "shadowed op with pre-folded args" 2 ((lambda (+) (+ (- 5 4) 2)) *))

;; enclosing lambda parameter shadows via the upvalue chain
(check "upvalue-shadowed + in nested lambda"
  -1 ((lambda (+) ((lambda (y) (+ 3 4)) 10)) -))

;; unshadowed operators must still fold normally inside a lambda body
(check "unshadowed + still folds" 3 ((lambda (y) (+ 1 2)) 99))
(check "unshadowed not still folds in if" 'then ((lambda (y) (if (not #f) 'then 'else)) 99))

(if (= failures 0)
    (begin (display "PASS") (newline))
    (begin (display failures) (display " failures") (newline) (exit 1)))
