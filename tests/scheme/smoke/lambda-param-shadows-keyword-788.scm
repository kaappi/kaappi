;; Regression test for #788: IR lowering treated locally-shadowed syntactic
;; keywords (if, and, begin, quote, when, ...) as special forms inside lambda
;; bodies. R7RS has no reserved words, so a lambda parameter binding the name
;; of a keyword must shadow the syntax and the body must compile as a call to
;; the parameter. Manual pass/fail because SRFI-64 relies on the very keywords
;; this test shadows.
(import (scheme base) (scheme write))

(define failures 0)
(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (begin (set! failures (+ failures 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write actual) (newline))))

;; Parameter shadows a special form; the body is an ordinary call to it.
(check "if shadowed"     99      ((lambda (if)     (if 1 2 3))  (lambda (a b c) 99)))
(check "and shadowed"    '(1 2)  ((lambda (and)    (and 1 2))   list))
(check "or shadowed"     '(1 2)  ((lambda (or)     (or 1 2))    list))
(check "begin shadowed"  '(1 2)  ((lambda (begin)  (begin 1 2)) list))
(check "when shadowed"   '(1 2)  ((lambda (when)   (when 1 2))  list))
(check "unless shadowed" '(1 2)  ((lambda (unless) (unless 1 2)) list))
(check "quote shadowed"  -5      ((lambda (quote)  (quote 5))   -))

;; The shadow holds inside nested forms lowered by the same IR pass.
(check "shadow inside begin" 99
       ((lambda (if) (begin (if 1 2 3))) (lambda (a b c) 99)))

;; And across a lambda boundary, where the keyword resolves as an upvalue
;; captured from the outer parameter.
(check "shadow via upvalue" 99
       (((lambda (if) (lambda () (if 1 2 3))) (lambda (a b c) 99))))

;; A shadowed primitive must not be constant-folded as the builtin.
(check "primitive + shadowed" 2 ((lambda (+) (+ 1 2)) *))

;; Control: an unshadowed keyword still compiles as the special form.
(check "if not shadowed" 2 ((lambda (x) (if 1 2 3)) 0))

(if (= failures 0)
    (display "all passed")
    (begin (display failures) (display " failures")))
(newline)
(if (> failures 0) (exit 1))
