;; SRFI-244 (Multiple-value Definitions) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi244.scm
;;
;; define-values is already a Kaappi core special form; this suite covers
;; the (srfi 244) re-export path plus the semantics SRFI 244 states for it.
;;
;; Grown in audit v2 Phase 3.8 from 6 assertions. Two things the smoke test
;; did not reach: every <formals> shape crossed with every definition
;; context (top level, let body, lambda body, nested), and the arity-matching
;; rule -- "the <formals> are matched to the return values in the same way
;; that the <formals> in a lambda expression are matched to the arguments in
;; a procedure call".  #550 was that top level did not enforce that rule when
;; the expression yielded exactly one value, while the identical definition
;; one scope in did; it now does (see the #550 note further down).

(import (scheme base) (scheme process-context) (srfi 244) (srfi 64))

(test-begin "srfi-244")

;;; --- the spec's own examples ---

(define-values (x y) (values 1 2))
(test-equal "spec example: (define-values (x y) (values 1 2)), (+ x y)" 3 (+ x y))

(define-values (a . b) (values 1 2))
(test-equal "spec example: (define-values (a . b) (values 1 2)), (cons a b)"
  '(1 2) (cons a b))

;;; --- every <formals> shape at top level ---

(define-values (dv-single) (values 42))
(test-equal "formals (x): single fixed variable" 42 dv-single)

(define-values dv-all (values 1 2 3))
(test-equal "formals x: a bare identifier collects every value as a list"
  '(1 2 3) dv-all)

(define-values dv-all-one (values 7))
(test-equal "formals x: a bare identifier still makes a list of one" '(7) dv-all-one)

(define-values dv-all-none (values))
(test-equal "formals x: a bare identifier over zero values is the empty list"
  '() dv-all-none)

(define-values (dv-h . dv-t) (values 1 2 3))
(test-equal "formals (x . y): head" 1 dv-h)
(test-equal "formals (x . y): dotted tail collects the rest" '(2 3) dv-t)

(define-values (dv-h2 . dv-t2) (values 9))
(test-equal "formals (x . y): head when the tail collects nothing" 9 dv-h2)
(test-equal "formals (x . y): dotted tail may collect nothing" '() dv-t2)

(define-values (dv-p dv-q dv-r) (values 'p 'q 'r))
(test-equal "formals (x y z): three fixed variables" '(p q r)
  (list dv-p dv-q dv-r))

(define-values () (values))
(test-assert "formals (): zero variables over zero values is accepted" #t)

;;; a non-`values` expression counts as exactly one value
(define-values (dv-plain) (+ 20 22))
(test-equal "a non-values expression supplies exactly one value" 42 dv-plain)

;;; --- definition contexts.  SRFI 244: "define-values ... is a <definition>
;;; and may appear anywhere other definitions may appear." ---

(test-equal "definition context: a let body"
  30 (let () (define-values (p q) (values 10 20)) (+ p q)))

(test-equal "definition context: a lambda body"
  30 ((lambda () (define-values (p q) (values 10 20)) (+ p q))))

(define (dv-in-define)
  (define-values (p q) (values 10 20))
  (+ p q))
(test-equal "definition context: a named define's body" 30 (dv-in-define))

(test-equal "definition context: nested lets each get their own bindings"
  '(1 2 3 4)
  (let () (define-values (p q) (values 1 2))
    (let () (define-values (r s) (values 3 4))
      (list p q r s))))

(test-equal "definition context: dotted formals inside a body"
  '(1 (2 3))
  (let () (define-values (h . t) (values 1 2 3)) (list h t)))

(test-equal "definition context: a bare identifier inside a body"
  '(1 2)
  (let () (define-values everything (values 1 2)) everything))

;;; letrec* region: a definition earlier in the same body may refer forward
;;; to names a later define-values binds (#1719).
(test-equal "letrec* region: an earlier define sees a later define-values"
  '(1 2)
  (let ()
    (define (fetch) (list fwd-p fwd-q))
    (define-values (fwd-p fwd-q) (values 1 2))
    (fetch)))

;;; the bindings are ordinary locations, so set! works on them
(define-values (dv-m dv-n) (values 1 2))
(set! dv-m 99)
(test-equal "define-values binds ordinary mutable locations" '(99 2)
  (list dv-m dv-n))

;;; a local define-values must not disturb a same-named top-level binding
(define dv-shadowed 'top)
(test-equal "a body define-values shadows rather than assigns"
  'body (let () (define-values (dv-shadowed) (values 'body)) dv-shadowed))
(test-equal "the top-level binding survives the shadowing body" 'top dv-shadowed)

;;; --- arity matching.  SRFI 244: "the <formals> are matched to the return
;;; values in the same way that the <formals> in a lambda expression are
;;; matched to the arguments in a procedure call".  The spec adds "The
;;; effect of the <formals> not matching is undefined", so what follows is
;;; not a conformance assertion -- but the implementation already raises for
;;; the internal case, and the top-level case of the same text does not.
;;;
;;; Enabled assertions pin both sides so a fix flips only the top-level set.

(test-error "internal definition: too few values raises"
  (eval '(let () (define-values (p q) (values 1)) p)
        (environment '(scheme base) '(srfi 244))))
(test-error "internal definition: too many values raises"
  (eval '(let () (define-values (p q) (values 1 2 3)) p)
        (environment '(scheme base) '(srfi 244))))
(test-error "lambda body: too few values raises"
  (eval '((lambda () (define-values (p q) (values 1)) p))
        (environment '(scheme base) '(srfi 244))))

;;; #550 (fixed): a *top-level* define-values whose producer yields a
;;; single value now enforces the same lambda-style arity as the internal
;;; cases above -- `(define-values (a b) (values 1))`, `(define-values () 42)`
;;; and `(define-values (a b) 1)` each raise KP3003 instead of binding a
;;; prefix and continuing.
;;;
;;; That path (handleDefineValues in vm_eval.zig) cannot be asserted from
;;; here: it fires only for a *bare* top-level form, not for one wrapped in a
;;; `let`/`lambda` body (compiler path) or handed to `eval` with an explicit
;;; immutable `(environment ...)` (which raises KP3007 before arity is even
;;; reached). And a bare top-level raise flips the whole file's exit code,
;;; which run-all.sh reads as failure. So the top-level regression lives
;;; out-of-process in tests/scheme/errors/define-values-toplevel-arity-550.sh,
;;; which runs each snippet as its own program and checks the exit code and
;;; the KP3003 message.

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-244" 'yes (cond-expand (srfi-244 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-244")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
