;; Regression tests for kaappi#2075: a `begin`-wrapped internal definition in
;; a let-family body escaped to the global environment unless an enclosing
;; procedure existed.
;;
;; R7RS 4.2.3 (p. 17): a definition-context `begin` "causes the contained
;; expressions and definitions to be evaluated exactly as if the enclosing
;; begin construct were not present". So `(let ((g 'outer)) (begin (define g
;; 'inner)) g)` must answer `inner` and must not touch a global `g` — at top
;; level exactly as inside a procedure. Before the fix, the top-level form
;; answered `outer` and silently overwrote the global.
;;
;; NOTE the SRFI-64 caveat (learned the hard way in tests/scheme/srfi/
;; srfi188.scm): test-equal evaluates its expression inside a lambda, which
;; supplies exactly the enclosing procedure scope whose absence was the bug.
;; Every probe below that pins the shadowing answer is therefore evaluated at
;; TRUE top level into a `define` and asserted on the variable.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "begin-spliced-define-2075")

;; --- the issue's reproducer, evaluated at true top level ---

(define g2075 'global)
(define probe2075-let
  (let ((g2075 'outer)) (begin (define g2075 'inner)) g2075))
(define probe2075-global-after g2075)

(test-equal "begin-wrapped internal define shadows at top level"
  'inner probe2075-let)
(test-equal "the definition does not escape the let"
  'global probe2075-global-after)

;; --- blast radius: every body-bearing binding form ---

(define x2075-letstar 'global)
(define probe2075-letstar
  (let* ((x2075-letstar 'outer)) (begin (define x2075-letstar 'inner)) x2075-letstar))
(define probe2075-letstar-global x2075-letstar)

(test-equal "let* body behaves the same as let"
  'inner probe2075-letstar)
(test-equal "let*: the definition does not escape"
  'global probe2075-letstar-global)

(define x2075-letrec 'global)
(define probe2075-letrec
  (letrec ((x2075-letrec 'outer)) (begin (define x2075-letrec 'inner)) x2075-letrec))
(define probe2075-letrec-global x2075-letrec)

(test-equal "letrec body behaves the same as let"
  'inner probe2075-letrec)
(test-equal "letrec: the definition does not escape"
  'global probe2075-letrec-global)

(define x2075-nested 'global)
(define probe2075-nested
  (let ((z 1)) (let ((x2075-nested 'outer)) (begin (define x2075-nested 'inner)) x2075-nested)))
(define probe2075-nested-global x2075-nested)

(test-equal "same, one let deeper — still no enclosing procedure"
  'inner probe2075-nested)
(test-equal "nested: the definition does not escape"
  'global probe2075-nested-global)

(define x2075-double 'global)
(define probe2075-double
  (let ((x2075-double 'outer)) (begin (begin (define x2075-double 'inner))) x2075-double))
(define probe2075-double-global x2075-double)

(test-equal "a doubly-nested begin splices the same way"
  'inner probe2075-double)
(test-equal "doubly-nested: the definition does not escape"
  'global probe2075-double-global)

;; --- a fresh (non-shadowing) name is also a local, not a leaked global ---

(define probe2075-fresh
  (let ((y 1)) (begin (define fresh2075 99) #f) (+ y fresh2075)))
(test-equal "a fresh name defined in a spliced begin is a body local"
  100 probe2075-fresh)

;; --- the letrec* region: definitions inside a begin are pre-declared, so
;; they can be mutually recursive exactly like unwrapped ones ---

(test-equal "mutually recursive defines through a begin"
  #t
  (let ()
    (begin
      (define (even2075? n) (if (= n 0) #t (odd2075? (- n 1))))
      (define (odd2075? n) (if (= n 0) #f (even2075? (- n 1)))))
    (even2075? 10)))

;; --- other definition forms inside a spliced begin ---

(test-equal "define-record-type inside a spliced begin"
  '(#t 3 4)
  (let ()
    (begin
      (define-record-type <pt2075> (make-pt2075 x y) pt2075?
        (x pt2075-x) (y pt2075-y)))
    (let ((p (make-pt2075 3 4))) (list (pt2075? p) (pt2075-x p) (pt2075-y p)))))

(test-equal "define-values inside a spliced begin"
  3
  (let ()
    (begin (define-values (a2075 b2075) (values 1 2)))
    (+ a2075 b2075)))

(test-equal "define-syntax inside a spliced begin"
  42
  (let ()
    (begin (define-syntax twice2075 (syntax-rules () ((_ e) (* 2 e)))))
    (twice2075 21)))

;; --- a begin that follows a leading define still joins the definition
;; region (a ⟨later definition⟩ per the grammar) ---

(test-equal "begin after a leading define"
  3
  (let () (define a2075 1) (begin (define b2075 2)) (+ a2075 b2075)))

;; --- the compile-time half: a definition a macro produces inside a let
;; body must bind a local too, never the global (#2075's second half) ---

(define-syntax define-inner2075 (syntax-rules () ((_ v) (define v 42))))

(define z2075 'global)
(define probe2075-macro-let
  (let ((z2075 'outer)) (define-inner2075 z2075) z2075))
(define probe2075-macro-global z2075)

(test-equal "a macro-produced define binds a local in a let body"
  42 probe2075-macro-let)
(test-equal "a macro-produced define does not touch the global"
  'global probe2075-macro-global)

;; --- controls that never had the bug ---

(test-equal "control: unwrapped define shadows at top level"
  'inner
  (let ((c2075 'outer)) (define c2075 'inner) c2075))

(test-equal "control: begin-wrapped define shadows inside a lambda"
  'inner
  ((lambda () (let ((c2075 'outer)) (begin (define c2075 'inner)) c2075))))

;; --- a lexical binding of `begin` makes the form a call, not a splice
;; (mirrors the IR lowerer); the body still must not clobber a global ---

(test-error "a shadowed begin is a call, not a splice"
  (let ((begin 5)) (begin (define h2075 2)) h2075))

;; --- likewise a body-local macro named `begin` shadows the special form
;; for the whole body (IR precedence: macro over special form); the splice
;; must not pre-empt it ---

(test-equal "a body-local macro named begin shadows the special form"
  '(macro 1 2)
  (let ()
    (define-syntax begin (syntax-rules () ((_ . rest) (list 'macro . rest))))
    (begin 1 2)))

(let ((runner (test-runner-current)))
  (test-end "begin-spliced-define-2075")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
