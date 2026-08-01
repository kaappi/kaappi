;;; SRFI 188 (Splicing binding constructs for syntactic keywords) tests
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi188.scm
;;;
;;; See lib/srfi/188.sld for why this port implements both forms as plain
;;; delegates to non-splicing let-syntax/letrec-syntax rather than attempting
;;; (and subtly failing at) real splicing. This suite tests that the
;;; delegate behaves correctly as let-syntax/letrec-syntax, and separately
;;; documents -- rather than silently getting wrong -- the one behavior the
;;; SRFI's own spec exists for.
;;;
;;; Grown in audit v2 Phase 3.8 from 7 assertions. The additions cover the
;;; transformer-environment half the delegate is supposed to get exactly
;;; right (splicing-let-syntax's transformers see the surrounding scope,
;;; splicing-letrec-syntax's see each other), and pin the underlying
;;; `begin`-splicing mechanism the .sld header's rationale rests on -- which
;;; turns out to be position-dependent and, at top level, to leak the
;;; definition into the global environment (#2075).

(import (scheme base) (scheme process-context) (srfi 188) (srfi 64))

(test-begin "srfi-188")

;;; --- ordinary use: local macro over a sequence of expressions ---

(test-equal "splicing-let-syntax expands and evaluates its body"
  6
  (splicing-let-syntax ((double (syntax-rules () ((_ x) (* 2 x)))))
    (+ (double 1) (double 2))))

(test-equal "splicing-letrec-syntax expands and evaluates its body"
  6
  (splicing-letrec-syntax ((double (syntax-rules () ((_ x) (* 2 x)))))
    (+ (double 1) (double 2))))

;;; --- letrec-syntax semantics: bindings see each other ---
;;;
;;; Mutual recursion between two macros has to reduce structurally (peeling
;;; a list) rather than arithmetically -- syntax-rules templates don't
;;; evaluate `(- n 1)`, they just re-embed it as bigger unevaluated syntax,
;;; so a numeric-countdown version of this test would never terminate.

(test-equal "splicing-letrec-syntax bindings are mutually recursive"
  4
  (splicing-letrec-syntax
      ((count-a (syntax-rules ()
                  ((_ ()) 0)
                  ((_ (x . rest)) (+ 1 (count-b rest)))))
       (count-b (syntax-rules ()
                  ((_ ()) 0)
                  ((_ (x . rest)) (+ 1 (count-a rest))))))
    (count-a (a b c d))))

;;; --- let-syntax semantics: independent, non-recursive bindings ---

(test-equal "splicing-let-syntax supports multiple independent bindings"
  30
  (splicing-let-syntax ((twice (syntax-rules () ((_ x) (* 2 x))))
                         (thrice (syntax-rules () ((_ x) (* 3 x)))))
    (+ (twice 3) (thrice 8))))

;;; --- the transformer environment.  Per SRFI 188 both forms behave like
;;; their non-splicing counterparts for the KEYWORD bindings themselves
;;; (only the body's definition context differs), so R7RS 4.3.1's
;;; distinction must hold: a splicing-let-syntax transformer's own free
;;; references resolve in the SURROUNDING scope, while a
;;; splicing-letrec-syntax transformer's resolve among its peers. ---

(test-equal "splicing-let-syntax transformers see the surrounding scope, not peers"
  'outer
  (let-syntax ((m (syntax-rules () ((_) 'outer))))
    (splicing-let-syntax ((m (syntax-rules () ((_) 'inner)))
                          (n (syntax-rules () ((_) (m)))))
      (n))))

(test-equal "splicing-letrec-syntax transformers see their peers"
  'inner
  (let-syntax ((m (syntax-rules () ((_) 'outer))))
    (splicing-letrec-syntax ((m (syntax-rules () ((_) 'inner)))
                             (n (syntax-rules () ((_) (m)))))
      (n))))

;;; --- empty bindings: behaves like begin as long as nothing shadows ---

(test-equal "splicing-let-syntax with no bindings runs its forms in order"
  '(1 2 3)
  (let ((log '()))
    (splicing-let-syntax ()
      (set! log (cons 1 log))
      (set! log (cons 2 log)))
    (set! log (cons 3 log))
    (reverse log)))

;;; --- documented gap: the SRFI's own defining example ---
;;;
;;; Per SRFI 188: (let ((x 'let-syntax)) (splicing-let-syntax () (define x
;;; 'splicing-let-syntax) #f) x) is specified to evaluate to
;;; 'splicing-let-syntax, because the internal define is supposed to splice
;;; into (and thus redefine a name in) the enclosing scope, the way begin
;;; does. Kaappi's splicing-let-syntax does not splice (see file header), so
;;; this evaluates to 'let-syntax instead -- the same answer plain
;;; non-splicing let-syntax gives. This test locks in and documents that
;;; known, deliberate deviation rather than leaving it to be rediscovered as
;;; a surprise.
(test-equal "known gap: internal define does not escape (spec says it should)"
  'let-syntax
  (let ((x 'let-syntax))
    (splicing-let-syntax ()
      (define x 'splicing-let-syntax)
      #f)
    x))

;;; the same gap, spelled out for splicing-letrec-syntax too
(test-equal "known gap: same non-splicing behavior for splicing-letrec-syntax"
  'letrec-syntax
  (let ((x 'letrec-syntax))
    (splicing-letrec-syntax ()
      (define x 'splicing-letrec-syntax)
      #f)
    x))

;;; the gap is total, not partial: a FRESH (non-shadowing) name defined
;;; inside the body is not visible after the form either.
(test-error "known gap: a fresh name defined in the body is not visible after it"
  (eval '(let ((y 1))
           (splicing-let-syntax () (define srfi188-fresh 7) #f)
           (+ y srfi188-fresh))
        (environment '(scheme base) '(srfi 188))))

;;; --- the underlying `begin`-splicing mechanism the .sld header's
;;; rationale is built on.  R7RS 4.2.3: a definition-context `begin`
;;; "causes the contained expressions and definitions to be evaluated
;;; exactly as if the enclosing begin construct were not present" -- so
;;; every pair below must agree.  They do not: the begin-wrapped form is
;;; correct inside a procedure and wrong at top level, where the definition
;;; escapes into the global environment (#2075).  The header states the
;;; top-level answer as if it were universal.
;;;
;;; Enabled assertions pin today's answers plus the three controls that
;;; isolate the defect; the commented ones are what R7RS requires.
;;;
;;; These four probes must be evaluated at TRUE top level and their results
;;; stashed, because SRFI-64's own `test-equal` evaluates its expression
;;; inside a lambda -- which supplies the very enclosing procedure scope
;;; whose absence is the defect, and so answers `inner` from inside the
;;; assertion while the same text answers `outer` outside it. ---

(define srfi188-g 'global)
(define srfi188-probe-let
  (let ((srfi188-g 'outer)) (begin (define srfi188-g 'inner)) srfi188-g))
(define srfi188-probe-global srfi188-g)

(define srfi188-h 'global)
(define srfi188-probe-nested
  (let ((z 1)) (let ((srfi188-h 'outer)) (begin (define srfi188-h 'inner)) srfi188-h)))

(define srfi188-s 'global)
(define srfi188-probe-letstar
  (let* ((srfi188-s 'outer)) (begin (define srfi188-s 'inner)) srfi188-s))

(define srfi188-c 'global)
(define srfi188-probe-control
  (let ((srfi188-c 'outer)) (define srfi188-c 'inner) srfi188-c))
(define srfi188-probe-control-global srfi188-c)

(test-equal "control: an unwrapped internal define shadows, at top level"
  'inner srfi188-probe-control)
(test-equal "control: an unwrapped internal define does not touch the global"
  'global srfi188-probe-control-global)

(test-equal "control: a begin-wrapped internal define shadows inside a lambda"
  'inner
  ((lambda () (let ((srfi188-l 'outer)) (begin (define srfi188-l 'inner)) srfi188-l))))

(test-equal "control: a doubly-nested begin also shadows inside a lambda"
  'inner
  ((lambda () (let ((srfi188-n 'outer)) (begin (begin (define srfi188-n 'inner))) srfi188-n))))

;; FAIL: #2075 (begin-wrapped internal define does not shadow at top level)
;; (test-equal "R7RS 4.2.3: a begin-wrapped internal define shadows at top level"
;;   'inner srfi188-probe-let)
;; FAIL: #2075 (the escaped definition clobbers the enclosing global)
;; (test-equal "R7RS 4.2.3: the definition does not escape the let"
;;   'global srfi188-probe-global)
;; FAIL: #2075 (same, one let deeper -- still no enclosing procedure)
;; (test-equal "R7RS 4.2.3: same, nested one let deeper"
;;   'inner srfi188-probe-nested)
;; FAIL: #2075 (let* leaks the same way)
;; (test-equal "R7RS 4.2.3: let* body behaves the same as let"
;;   'inner srfi188-probe-letstar)

(test-equal "begin-wrapped define at top level does not shadow (see #2075)"
  'outer srfi188-probe-let)
(test-equal "the escaped definition overwrote the global instead (see #2075)"
  'inner srfi188-probe-global)
(test-equal "same leak one let deeper -- still no enclosing procedure (see #2075)"
  'outer srfi188-probe-nested)
(test-equal "let* body leaks identically (see #2075)"
  'outer srfi188-probe-letstar)

(let ((runner (test-runner-current)))
  (test-end "srfi-188")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
