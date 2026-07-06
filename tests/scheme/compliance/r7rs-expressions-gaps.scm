;; R7RS sections 4.1-4.3 conformance gap tests — audit Phase 1A.
;; Covers spec requirements not exercised by tests/scheme/r7rs/r7rs-tests.scm.
;; Spec references cite docs/errata-corrected-r7rs.pdf.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "r7rs-expressions-gaps")

;; --- 4.1.2 Literal expressions ---
;; "Numerical constants, string constants, character constants, vector
;; constants, bytevector constants, and boolean constants evaluate to
;; themselves; they need not be quoted." (p. 12)
(test-equal "unquoted vector self-evaluates" '#(1 2 3) #(1 2 3))
(test-equal "unquoted bytevector self-evaluates" '#u8(64 65) #u8(64 65))

;; --- 4.1.4 Procedures ---
;; Rest parameter is bound to a newly allocated list of leftover args —
;; the empty list when the fixed formals consume everything. (p. 13)
(test-equal "rest arg is () when exactly matched" '() ((lambda (x y . z) z) 3 4))

;; --- 4.1.7 Inclusion ---
;; include reads files with case preserved; paths resolve relative to the
;; including file. (p. 14)
(include "fixtures/include-plain.scm")
(test-equal "include splices definitions" 7 included-value)

;; include-ci "reads each file as if it began with the #!fold-case
;; directive, while include does not." (p. 14)
(include-ci "fixtures/include-ci-upper.scm")
(test-equal "include-ci folds case" 42 folded-value)

;; --- 4.2.1 Conditionals: cond ---
;; "If the selected <clause> contains only the <test> and no <expression>s,
;; then the value of the <test> is returned as the result." (p. 14)
(test-equal "cond test-only clause returns test value" 'hello (cond (#f) ('hello)))
(test-equal "cond test-only first clause" 42 (cond (42) (else #f)))

;; --- 4.2.1 Conditionals: and / or ---
;; and: "If all the expressions evaluate to true values, the values of the
;; last expression are returned." (p. 15) — plural: multiple values pass through.
(test-equal "and passes through multiple values"
  '(1 2) (call-with-values (lambda () (and #t (values 1 2))) list))
;; or: "the value of the first expression that evaluates to a true value is
;; returned" — values (plural) per errata; first true expression's values.
(test-equal "or passes through multiple values"
  '(1 2) (call-with-values (lambda () (or (values 1 2) #f)) list))

;; --- 4.2.1 cond-expand (expression form) ---
;; Feature requirements: feature identifier, (library ...), and/or/not. (p. 15)
(test-equal "cond-expand (library ...) requirement"
  'has-base (cond-expand ((library (scheme base)) 'has-base) (else 'no)))
(test-equal "cond-expand and/not requirements"
  'ok (cond-expand ((and r7rs (not this-feature-does-not-exist)) 'ok) (else 'no)))
(test-equal "cond-expand or requirement"
  'yes (cond-expand ((or this-feature-does-not-exist r7rs) 'yes) (else 'no)))
(test-equal "cond-expand else clause"
  'fallback (cond-expand (this-feature-does-not-exist 'no) (else 'fallback)))

;; --- 4.2.2 Binding constructs ---
;; let*: "The <variable>s need not be distinct." (p. 16)
(test-equal "let* allows duplicate variables" 2 (let* ((x 1) (x (+ x 1))) x))

;; let-values: a single-identifier <formals> captures all values as a list,
;; and dotted <formals> capture leftovers, as in lambda. (p. 17)
(test-equal "let-values single-identifier formals"
  '(1 2 3) (let-values ((x (values 1 2 3))) x))
(test-equal "let-values dotted formals"
  '(1 (2 3)) (let-values (((a . r) (values 1 2 3))) (list a r)))

;; let-values: "The <init>s are evaluated in the current environment" —
;; not in the environment extended by earlier formals (unlike let*-values). (p. 17)
(test-equal "let-values inits see outer environment"
  'outer
  (let ((a 'outer))
    (let-values (((a) (values 'inner))
                 ((b) (values a)))
      b)))

;; --- 4.2.4 Iteration: do ---
;; "A <step> can be omitted, in which case the effect is the same as if
;; (<variable> <init> <variable>) had been written." (p. 18)
(test-equal "do with omitted step keeps binding"
  'k (do ((i 0 (+ i 1)) (c 'k)) ((= i 3) c)))

;; --- 4.2.6 Dynamic bindings ---
;; "Initially, this value is the value of (converter init)." (p. 20)
(test-equal "make-parameter applies converter to init"
  10 (let ((p (make-parameter 5 (lambda (x) (* x 2))))) (p)))
;; parameterize passes new values through the converter; a converter that
;; raises propagates the error (spec example: (parameterize ((radix 0)) ...)
;; => error, p. 20).
(test-equal "parameterize converter error propagates"
  'err
  (let ((radix (make-parameter
                10
                (lambda (x) (if (and (exact-integer? x) (<= 2 x 16))
                                x
                                (error "invalid radix"))))))
    (guard (e (#t 'err))
      (parameterize ((radix 0)) (radix)))))
;; "Then the previous values of the parameters are restored" after the body. (p. 20)
(test-equal "nested parameterize restores values"
  '(3 2 1)
  (let ((p (make-parameter 1)) (acc '()))
    (parameterize ((p 2))
      (parameterize ((p 3))
        (set! acc (cons (p) acc)))
      (set! acc (cons (p) acc)))
    (set! acc (cons (p) acc))
    (reverse acc)))

;; --- 4.2.8 Quasiquotation ---
;; Improper-list templates: `((foo ,(- 10 3)) ,@(cdr '(c)) . ,(car '(cons)))
;; => ((foo 7) . cons) (spec example, p. 21)
(test-equal "quasiquote improper-list template"
  '((foo 7) . cons)
  `((foo ,(- 10 3)) ,@(cdr '(c)) . ,(car '(cons))))
(test-equal "quasiquote unquote in cdr position"
  '(1 . 2) `(1 . ,(+ 1 1)))

;; --- 4.3.2 Pattern language: constants ---
;; "P is a constant and E is equal to P in the sense of the equal?
;; procedure" (p. 24) — string and numeric constants in patterns.
(let ()
  (define-syntax const-pat
    (syntax-rules ()
      ((_ "hello") 'str)
      ((_ 42) 'num)
      ((_ x) 'other)))
  (test-equal "string constant pattern matches" 'str (const-pat "hello"))
  (test-equal "numeric constant pattern matches" 'num (const-pat 42))
  (test-equal "non-constant falls through" 'other (const-pat z)))

;; --- 4.3.2 Pattern language: literal identifier matching ---
;; "An input identifier matches a literal if and only if it is an identifier
;; and either both its occurrence in the macro expression and its occurrence
;; in the macro definition have the same lexical binding, or the two
;; identifiers are the same and both have no lexical binding." (p. 23)
(define-syntax has-lit
  (syntax-rules (lit)
    ((_ lit) 'is-literal)
    ((_ x) 'not-literal)))
(test-equal "unbound literal matches unbound use" 'is-literal (has-lit lit))
(test-equal "locally rebound literal must not match"
  'not-literal (let ((lit 42)) (has-lit lit)))

;; --- 4.3.1 Binding constructs for syntactic keywords ---
;; let-syntax: "The <body> is expanded in the syntactic environment obtained
;; by extending the syntactic environment of the let-syntax expression" —
;; the transformer specs themselves are resolved in the OUTER environment,
;; so a transformer in the same let-syntax sees the outer m. (p. 22)
(define-syntax m-outer (syntax-rules () ((_) 'outer)))
(test-equal "let-syntax transformer sees outer keyword"
  'outer
  (let-syntax ((m-outer (syntax-rules () ((_) 'inner)))
               (call-m (syntax-rules () ((_) (m-outer)))))
    (call-m)))
;; letrec-syntax: "Each binding of a <keyword> has the <transformer spec>s
;; as well as the <body> within its region" — sibling transformers see the
;; NEW binding. (p. 22)
(test-equal "letrec-syntax transformer sees sibling keyword"
  'inner
  (letrec-syntax ((m-rec (syntax-rules () ((_) 'inner)))
                  (call-m-rec (syntax-rules () ((_) (m-rec)))))
    (call-m-rec)))

(let ((runner (test-runner-current)))
  (test-end "r7rs-expressions-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
