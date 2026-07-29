;; Regression test for #1828 -- NOT a bug, but locks in the (already
;; correct) behavior the issue mistakenly reported as broken.
;;
;; Issue #1828 claimed that a variable bound by one `=>` step in an
;; `em-syntax-rules` (SRFI 148) macro could not be used as the OPERATOR of
;; a later chained `=>` step's expression -- e.g. binding `the-rtd` in step
;; 1 and calling `(the-rtd ':secret)` in step 2. The reported repro failed
;; with `undefined variable ':prepare'`.
;;
;; Root cause: the repro's own FINAL (non-`=>`) template was UNQUOTED --
;; `(display (list a b c))` -- and called an ordinary procedure (`display`),
;; not an eager macro. SRFI 148's own spec is explicit that an unquoted
;; top-level template "is expanded as if it was a syntax-rules macro. It
;; is an error if the expanded output is not an eager macro use (or a
;; self-quoting syntax element)" -- so a compound call to a non-eager
;; procedure is documented, spec-level invalid input, not an engine bug.
;; `:prepare` leaking as an "undefined variable" is a confusing diagnostic
;; for that documented error case (see lib/srfi/148.sld's header for the
;; `ck`-dispatch mechanism this falls out of), but it is not the "operator
;; position" bug the issue described.
;;
;; Confirmed by taking the issue's EXACT repro and changing ONLY the final
;; template from `(display (list a b c))` to `'(list a b c)` (quoting it,
;; per spec Case 1): it then runs correctly and evaluates to `(1 2 3)`,
;; exactly the issue's own stated expectation. This file locks that in --
;; both at the issue's own 2-level nesting and at a deeper 3-level chain,
;; the shape closer to SRFI 150's actual `parse-type-spec` ->
;; `parse-predicate-spec` -> `parent-rtd` usage that motivated the report
;; (see lib/srfi/150.sld's header) -- as a permanent regression test.
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 148))

(test-begin "em-syntax-rules-operator-chain-1828")

;; --- 2-level chain: the issue's own shape, final template quoted -------
(define-syntax :secret
  (syntax-rules () ((_ . args) (syntax-error "internal: :secret misused"))))

(define-syntax descriptor
  (em-syntax-rules ::: ()
    ((descriptor ':secret) '(1 2 3))
    ((descriptor 'arg :::) (em-error "invalid use"))))

(define-syntax identity
  (em-syntax-rules ()
    ((identity 'x) 'x)))

;; Two chained => steps: the first destructures `the-rtd` from an eager
;; macro call; the second uses `the-rtd` (bound by the FIRST step) as the
;; OPERATOR of its own step-expression -- exactly issue #1828's shape.
(define-syntax test-chain
  (em-syntax-rules ()
    ((test-chain name)
     ((identity 'name) => 'the-rtd)
     ((the-rtd ':secret) => '(a b c))
     '(list a b c))))

(test-equal "operator-position chain (issue #1828's own shape, quoted template)"
  '(1 2 3)
  (test-chain descriptor))

;; --- 3-level chain: each step's bound variable is the NEXT step's ------
;; operator, one level deeper than the issue's repro.
(define-syntax stage-a
  (em-syntax-rules ()
    ((stage-a ':secret) 'stage-b)))

(define-syntax stage-b
  (em-syntax-rules ()
    ((stage-b ':secret) 'stage-c)))

(define-syntax stage-c
  (em-syntax-rules ()
    ((stage-c ':secret) '42)))

(define-syntax three-level-chain
  (em-syntax-rules ()
    ((three-level-chain start)
     ((start ':secret) => 'next1)
     ((next1 ':secret) => 'next2)
     ((next2 ':secret) => 'result)
     'result)))

(test-equal "3-level operator-position chain"
  42
  (three-level-chain stage-a))

(let ((runner (test-runner-current)))
  (test-end "em-syntax-rules-operator-chain-1828")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
