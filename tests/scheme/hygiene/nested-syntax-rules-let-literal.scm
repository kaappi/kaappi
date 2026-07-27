;; Regression test for #1720: a literal `let` inside a macro-generated
;; (nested) syntax-rules failed to match a `let` token at the eventual use
;; site, unlike every other special-form literal (lambda, define,
;; case-lambda, let*-values). `let` and `if` are deliberately excluded from
;; expander.zig's well_known_forms (unlike lambda/define/etc.) so a macro's
;; own executable use of them stays hygienic under use-site shadowing --
;; but that same exclusion meant a NESTED syntax-rules's `let`/`if` LITERAL
;; got hygiene-renamed by the generating macro's own expansion, and
;; matchPattern's literal-comparison only stripped a hygiene rename off the
;; USE-SITE input side (for the opposite, already-handled case: a bare
;; literal matching a renamed input, e.g. SRFI 257's cm-match), never off
;; the PATTERN/literal side -- so a renamed literal could never match a
;; real, unrenamed token typed at the generated macro's use site. Fixed by
;; stripping both sides before comparing.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "nested-syntax-rules-let-literal")

;; --- The exact repro from #1720 ---

(define-syntax %dm-lambda
  (syntax-rules ()
    ((_ name)
     (define-syntax name
       (syntax-rules (lambda)
         ((_ lambda fmls body ...) (list 'ok-lambda (quote fmls))))))))
(%dm-lambda $lam)

(test-equal "lambda literal in nested syntax-rules (baseline)"
  '(ok-lambda (c))
  ($lam lambda (c) 1))

(define-syntax %dm-let
  (syntax-rules ()
    ((_ name)
     (define-syntax name
       (syntax-rules (let)
         ((_ let loop-name clauses body ...) (list 'ok-let (quote loop-name))))))))
(%dm-let $F)

(test-equal "let literal in nested syntax-rules matches (#1720)"
  '(ok-let loop)
  ($F let loop (c 3) 1))

;; --- `if` shares the same well_known_forms exclusion as `let` ---

(define-syntax %dm-if
  (syntax-rules ()
    ((_ name)
     (define-syntax name
       (syntax-rules (if)
         ((_ if a) (list 'ok-if a)))))))
(%dm-if $I)

(test-equal "if literal in nested syntax-rules matches"
  '(ok-if 7)
  ($I if 7))

;; --- Several special-form literals together (mirrors SRFI 247's
;;     define-syntactic-monad dispatch shape, which motivated #1720) ---

(define-syntax %dm-multi
  (syntax-rules ()
    ((_ name)
     (define-syntax name
       (syntax-rules (let lambda define case-lambda let*-values)
         ((_ let a) (list 'is-let a))
         ((_ lambda a) (list 'is-lambda a))
         ((_ define a) (list 'is-define a))
         ((_ case-lambda a) (list 'is-case-lambda a))
         ((_ let*-values a) (list 'is-let*-values a)))))))
(%dm-multi $M)

(test-equal "multiple special-form literals: let" '(is-let 1) ($M let 1))
(test-equal "multiple special-form literals: lambda" '(is-lambda 2) ($M lambda 2))
(test-equal "multiple special-form literals: define" '(is-define 3) ($M define 3))
(test-equal "multiple special-form literals: case-lambda" '(is-case-lambda 4) ($M case-lambda 4))
(test-equal "multiple special-form literals: let*-values" '(is-let*-values 5) ($M let*-values 5))

;; --- Two independent levels of nesting, each declaring its own `let`
;;     literal, must not interfere with each other ---

(define-syntax %dm-let-two-levels
  (syntax-rules ()
    ((_ name1 name2)
     (begin
       (define-syntax name1
         (syntax-rules (let)
           ((_ let x) (list 'level1 x))))
       (define-syntax name2
         (syntax-rules ()
           ((_ inner)
            (define-syntax inner
              (syntax-rules (let)
                ((_ let y) (list 'level2 y)))))))))))
(%dm-let-two-levels $A $Bgen)
($Bgen $B)

(test-equal "first of two independent nested let literals" '(level1 42) ($A let 42))
(test-equal "second of two independent nested let literals" '(level2 99) ($B let 99))

;; --- The non-nested case (direct, not template-generated) already worked
;;     before #1720's fix; keep it under test as a contrast/baseline ---

(define-syntax direct-let
  (syntax-rules (let)
    ((_ let loop-name clauses body ...) (list 'direct-ok (quote loop-name)))))

(test-equal "non-nested let literal (baseline, always worked)"
  '(direct-ok loop)
  (direct-let let loop (c 3) 1))

;; --- Fixing the literal-matching bug must not weaken hygiene: a macro's
;;     own internal, executable `let` usage must still be protected from
;;     capture by a use-site variable literally named "let" ---

(define-syntax my-add1
  (syntax-rules ()
    ((_ x) (let ((tmp x)) (+ tmp 1)))))

(test-equal "shadowing let as a variable does not capture a macro's own let"
  101
  (let ((let 100)) (my-add1 let)))

;; --- Named-let and anonymous let, unaffected by the nested-literal fix ---

(test-equal "named let still works"
  10
  (let loop ((i 0) (acc 0)) (if (= i 5) acc (loop (+ i 1) (+ acc i)))))

(test-equal "anonymous let still works" 3 (let ((x 1) (y 2)) (+ x y)))

(let ((runner (test-runner-current)))
  (test-end "nested-syntax-rules-let-literal")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
