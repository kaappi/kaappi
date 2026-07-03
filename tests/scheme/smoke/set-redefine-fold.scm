;; Regression test: constant folding must not fold a call to a primitive that
;; is a `set!` target within the enclosing form. The `set!` runs before the
;; call, so the value folded in at compile time is stale.
;;
;;   (define f (lambda () (set! + -) (+ 5 2)))
;;   (f)  ; must be 3, not the folded 7
;;
;; Uses the manual-check / procedure-argument style (NOT SRFI-64 test-eqv) so
;; the folded expressions travel the IR fold path (tryFoldFromAST /
;; foldConstants). test-eqv would route through the legacy passthrough path
;; and mask an IR-path regression. See also global-redefine-fold.scm.
(import (scheme base) (scheme write) (scheme process-context))

;; Adder captured from the original + so a test that clobbers the global +
;; cannot corrupt failure counting.
(define real+ +)
(define failures 0)
(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (begin (set! failures (real+ failures 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write actual) (newline))))

;; Originals, restored between tests so each starts from the primitive.
(define orig+ +)
(define orig- -)
(define orig* *)
(define orig= =)

;; IR path: set! of + inside a lambda body.
(define f (lambda () (set! + -) (+ 5 2)))
(define r-f (f))              ; running f rebinds global + to -
(set! + orig+)               ; restore before check (which uses +)
(check "set! + -> - in lambda body folds as -" 3 r-f)

;; Legacy passthrough path control: the let wrapper forces that path.
(define g (lambda () (let ((x 1)) (set! + -) (+ 5 2))))
(define r-g (g))
(set! + orig+)
(check "set! + -> - in let body folds as -" 3 r-g)

;; A + call textually before the set! must also be suppressed (conservative
;; whole-body scan); it evaluates before the rebind so it is still correct.
(define h (lambda () (+ 100 1) (set! + -) (+ 5 2)))
(define r-h (h))
(set! + orig+)
(check "set! + -> - suppresses every fold in the body" 3 r-h)

;; The set! sits in the outer body; the folded call lives in a nested lambda
;; that captures the same global +. Suppression must reach the nested scope.
(define k (lambda () (set! + -) (lambda () (+ 5 2))))
(define inner (k))           ; global + is now -
(define r-k (inner))         ; (+ 5 2) with + = - -> 3, not folded 7
(set! + orig+)
(check "set! in outer body suppresses fold in nested lambda" 3 r-k)

;; Other foldable primitives.
(define fm (lambda () (set! * -) (* 10 3)))
(define r-fm (fm))
(set! * orig*)
(check "set! * -> - folds as -" 7 r-fm)

;; (= 2 1): folded as = would be #f; run as > it is #t.
(define fe (lambda () (set! = >) (= 2 1)))
(define r-fe (fe))
(set! = orig=)
(check "set! = -> > folds as >" #t r-fe)

;; A primitive that is never a set! target must still fold correctly.
(check "unshadowed + still folds" 3 ((lambda () (+ 1 2))))

;; A set! that appears only inside quoted data must not suppress folding.
(define p (lambda () (quote (set! + -)) (+ 5 2)))
(check "quoted set! does not suppress folding" 7 (p))

(if (= failures 0)
    (begin (display "all passed") (newline))
    (begin (display failures) (display " failures") (newline) (exit 1)))
