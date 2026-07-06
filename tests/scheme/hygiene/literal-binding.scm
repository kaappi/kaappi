;; Regression test for #1139: syntax-rules literal matching must respect
;; lexical bindings (R7RS 4.3.2).
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "literal-binding")

;; --- Both unbound: literal matches by name ---
(define-syntax has-lit
  (syntax-rules (lit)
    ((_ lit) 'is-literal)
    ((_ x)   'not-literal)))

(test-equal "both unbound — literal matches" 'is-literal (has-lit lit))

;; --- Use-site bound, def-site unbound: must NOT match ---
(test-equal "let-rebound literal must not match"
  'not-literal (let ((lit 42)) (has-lit lit)))

(test-equal "nested let-rebound literal must not match"
  'not-literal (let ((lit 1)) (let ((lit 2)) (has-lit lit))))

;; --- Same-scope define-syntax: literal IS def-site bound ---
(test-equal "same-let literal matches"
  'is-literal
  (let ((lit 42))
    (define-syntax has-lit2
      (syntax-rules (lit)
        ((_ lit) 'is-literal)
        ((_ x)   'not-literal)))
    (has-lit2 lit)))

;; --- Lambda parameter as literal ---
(test-equal "lambda-parameter literal matches in same scope"
  'is-literal
  ((lambda (lit)
     (define-syntax has-lit3
       (syntax-rules (lit)
         ((_ lit) 'is-literal)
         ((_ x)   'not-literal)))
     (has-lit3 lit)) 99))

;; --- Non-literal pattern var in a different macro ---
(define-syntax get-val
  (syntax-rules (lit)
    ((_ lit) 'is-literal)
    ((_ x)   x)))

(test-equal "non-literal pattern var carries the input form"
  42 (let ((lit 42)) (get-val lit)))

(let ((runner (test-runner-current)))
  (test-end "literal-binding")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
