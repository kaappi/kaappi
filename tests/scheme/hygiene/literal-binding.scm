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

;; --- Body-defined macro must not corrupt sibling defines ---
(test-equal "body macro reads body define local correctly"
  10
  (let ()
    (define x 10)
    (define-syntax getx (syntax-rules () ((_) x)))
    (getx)))

(test-equal "body macro with plain pattern var resolves use-site binding"
  10
  (let ()
    (define-syntax m (syntax-rules () ((_ v) v)))
    (let ((y 10)) (m y))))

;; --- Literal bound by sibling body define ---
(test-equal "sibling body define makes literal def-site bound"
  'is-literal
  (let ()
    (define lit 1)
    (define-syntax m
      (syntax-rules (lit)
        ((_ lit) 'is-literal)
        ((_ x)   'not-literal)))
    (m lit)))

;; --- Global literal through nested macro expansion ---
(define lit-g 5)
(define-syntax has-lit-g
  (syntax-rules (lit-g)
    ((_ lit-g) 'is-literal)
    ((_ x)     'not-literal)))
(define-syntax outer-g (syntax-rules () ((_) (has-lit-g lit-g))))
(test-equal "global literal through nested expansion" 'is-literal (outer-g))

;; --- Forward-referenced body define (letrec* region) ---
(test-equal "forward-referenced body define makes literal def-site bound"
  'is-literal
  (let ()
    (define-syntax m
      (syntax-rules (lit)
        ((_ lit) 'is-literal)
        ((_ x)   'not-literal)))
    (define lit 42)
    (m lit)))

;; --- Different bindings with same name must NOT match ---
(test-equal "inner let rebinds literal — different binding identity"
  'not-literal
  (let ((lit 1))
    (define-syntax m
      (syntax-rules (lit)
        ((_ lit) 'is-literal)
        ((_ x)   'not-literal)))
    (let ((lit 2)) (m lit))))

;; --- Forward-reference in lambda body ---
(test-equal "lambda body forward-referenced define makes literal def-site bound"
  'is-literal
  ((lambda ()
     (define-syntax m
       (syntax-rules (lit)
         ((_ lit) 'is-literal)
         ((_ x)   'not-literal)))
     (define lit 42)
     (m lit))))

(let ((runner (test-runner-current)))
  (test-end "literal-binding")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
