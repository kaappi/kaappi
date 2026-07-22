;;; SRFI 188 (Splicing binding constructs for syntactic keywords) tests
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi188.scm
;;;
;;; See lib/srfi/188.sld for why this port implements both forms as plain
;;; delegates to non-splicing let-syntax/letrec-syntax rather than attempting
;;; (and subtly failing at) real splicing. This suite tests that the
;;; delegate behaves correctly as let-syntax/letrec-syntax, and separately
;;; documents -- rather than silently getting wrong -- the one behavior the
;;; SRFI's own spec exists for.

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

(let ((runner (test-runner-current)))
  (test-end "srfi-188")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
