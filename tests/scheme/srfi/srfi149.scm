;; SRFI 149 (Basic Syntax-rules Template Extensions) tests. Kaappi's
;; expander already implements both of this SRFI's extensions (consecutive
;; ellipses; excess-ellipsis replication for mixed-depth siblings) with no
;; engine changes -- see lib/srfi/149.sld's header for the full rationale
;; and src/tests_macros.zig for the matching Zig-level unit tests. Part of
;; issue #1699 (SRFI macro & syntax extension libraries).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi149.scm
;;
;; Grown in audit v2 Phase 3.8 from 6 assertions. The SRFI's own two worked
;; examples were already here; what follows adds the cases its prose leaves
;; without an example -- semantics rule 4 (consecutive ellipses over a
;; COMPOUND template element), three consecutive ellipses, ragged innermost
;; replication -- plus the depth-UNDERFLOW cases that rule 1 and R7RS 4.3.2
;; both make an error and this expander accepts silently (#682).

(import (scheme base) (scheme process-context) (srfi 64) (srfi 149))

(test-begin "srfi-149")

;;; --- the spec's own example 1: consecutive ellipses flatten a
;;; depth-2 variable one level, written without the extra parens R7RS's
;;; own stricter grammar would otherwise require ---
(define-syntax my-append
  (syntax-rules ()
    ((_ (a ...) ...) (list a ... ...))))

(test-equal "spec example 1: my-append flattens two groups"
  '(1 2 3 4 5 6) (my-append (1 2 3) (4 5 6)))
(test-equal "spec example 1: no groups at all" '() (my-append))
(test-equal "spec example 1: one group of one element" '(1) (my-append (1)))
(test-equal "consecutive ellipses skip empty groups"
  '(1) (my-append () () (1)))
(test-equal "consecutive ellipses over only-empty groups yield the empty list"
  '() (my-append () ()))

;;; --- the spec's own example 2: a mixed-depth sibling pair (a at depth
;;; 1, b at depth 2) sharing one ellipsis-driven template position; the
;;; excess ellipsis consuming b's extra nesting replicates a (already
;;; resolved to a scalar one level up) at the innermost position ---
(define-syntax foo
  (syntax-rules ()
    ((_ (a b ...) ...) (list (list (list 'a 'b) ...) ...))))

(test-equal "spec example 2: mixed-depth siblings replicate innermost"
  '(((bar 1) (bar 2)) ((baz 3) (baz 4)))
  (foo (bar 1 2) (baz 3 4)))

;;; --- innermost vs outermost, discriminated.  Semantics rule 2: "If a
;;; pattern variable in a subtemplate is followed by more instances of
;;; <ellipsis> than the subpattern in which it occurs is followed, the
;;; input elements by which it is replaced in the output are repeated for
;;; the innermost excess instances of <ellipsis>."  With RAGGED inner
;;; groups this discriminates: under the outermost (R6RS) convention the
;;; depth-1 variable's two elements would have to line up with a
;;; three-element inner group, which cannot be built at all. ---
(define-syntax ragged
  (syntax-rules ()
    ((_ (a ...) ((b ...) ...)) '(((a b) ...) ...))))

(test-equal "innermost replication survives ragged inner groups"
  '(((x 1) (x 2) (x 3)) ((y 4)))
  (ragged (x y) ((1 2 3) (4))))

;;; the depth-1 sibling zipped against a SHORTER driver: SRFI 149 rule 2
;;; repeats the depth-1 variable's elements for the innermost excess
;;; ellipsis, so the outer run iterates min(counts) times and the surplus
;;; element is dropped.  chibi-scheme (the SRFI's reference implementation)
;;; agrees; guile 3.0 rejects unequal outer counts, which this expander
;;; deliberately does not (kaappi#682).
(test-equal "excess replication zips a longer depth-1 variable"
  '(((x 1) (x 2)) ((y 3)))
  (ragged (x y z) ((1 2) (3))))

;;; and the reverse: a SHORTER depth-1 variable truncates the driver.
(test-equal "excess replication zips a shorter depth-1 variable"
  '(((x 1) (x 2)) ((y 3)))
  (ragged (x y) ((1 2) (3) (4))))

;;; an EMPTY driver: the outer run repeats zero times, so the depth-1
;;; variable's elements are never consumed.  Both chibi and guile return
;;; the empty list; kaappi rejected the shape with EllipsisCountMismatch
;;; until the count check became depth-aware (kaappi#682).
(test-equal "excess replication with an empty driver yields the empty list"
  '()
  (ragged (x y) ()))
(test-equal "excess replication with an empty variable and empty driver"
  '()
  (ragged () ()))

;;; a depth-0 variable carried through two excess ellipsis levels
(define-syntax broadcast2
  (syntax-rules ()
    ((_ k ((a ...) ...)) '(((k a) ...) ...))))

(test-equal "depth-0 variable broadcasts through two excess ellipses"
  '(((K 1) (K 2)) ((K 3)))
  (broadcast2 K ((1 2) (3))))

;;; --- semantics rule 4: "If a template element is immediately followed
;;; by more than one instance of the identifier <ellipsis>, the semantics
;;; are analogous to when the instances of <ellipsis> are not in immediate
;;; succession but belonging to nested subtemplates."  The SRFI gives no
;;; example for a COMPOUND template element, which is the case that
;;; actually discriminates the reading: `(a a) ... ...` must mean
;;; `((a a) ...) ...` flattened once, NOT each `a` independently consuming
;;; an ellipsis level.  Kaappi and Guile 3.0 agree here; chibi-scheme 0.12
;;; answers ((1 2) (1 2) (3) (3)), which is a defect in chibi. ---
(define-syntax consec-compound
  (syntax-rules ()
    ((_ (a ...) ...) '((a a) ... ...))))
(define-syntax nested-compound
  (syntax-rules ()
    ((_ (a ...) ...) '(((a a) ...) ...))))

(test-equal "rule 4: consecutive ellipses over a compound template element"
  '((1 1) (2 2) (3 3)) (consec-compound (1 2) (3)))
(test-equal "rule 4: the nested spelling it is defined to be analogous to"
  '(((1 1) (2 2)) ((3 3))) (nested-compound (1 2) (3)))
(test-equal "rule 4: the consecutive form is the nested form, flattened once"
  (apply append (nested-compound (1 2) (3)))
  (consec-compound (1 2) (3)))

;;; three consecutive ellipses over a depth-3 variable
(define-syntax consec3
  (syntax-rules ()
    ((_ ((a ...) ...) ...) '(a ... ... ...))))

(test-equal "three consecutive ellipses flatten three levels"
  '((1 2) (3) (4))
  (consec3 (((1 2) (3))) (((4)))))

;;; consecutive ellipses inside a vector template
(define-syntax consec-vector
  (syntax-rules ()
    ((_ (a ...) ...) '#(a ... ...))))

(test-equal "consecutive ellipses inside a vector template"
  '#(1 2 3) (consec-vector (1 2) (3)))

;;; --- consecutive-ellipsis flatten composes with a following fixed
;;; tail: the flatten mechanism must resume ordinary template
;;; instantiation for whatever follows it, not swallow the rest ---
(define-syntax flatten-then-tail
  (syntax-rules ()
    ((_ (a ...) ... last) (list a ... ... last))))

(test-equal "flatten composes with a following fixed tail"
  '(1 2 3 4 5 done) (flatten-then-tail (1 2) (3 4 5) 'done))

;;; a fixed HEAD before the flatten, too
(define-syntax head-then-flatten
  (syntax-rules ()
    ((_ first (a ...) ...) (list first a ... ...))))

(test-equal "flatten composes with a preceding fixed head"
  '(start 1 2 3) (head-then-flatten 'start (1 2) (3)))

;;; --- ordinary depth-0 broadcast (the R7RS baseline this SRFI extends,
;;; unaffected) still works correctly alongside the new forms ---
(define-syntax broadcast
  (syntax-rules ()
    ((_ x (y ...)) (list (list x y) ...))))

(test-equal "depth-0 broadcast (the R7RS baseline) is unaffected"
  '((k 1) (k 2) (k 3)) (broadcast 'k (1 2 3)))

;;; the R7RS ellipsis escape still works alongside the extensions
(define-syntax escaped
  (syntax-rules ()
    ((_ a) '(a (... ...)))))

(test-equal "the R7RS ellipsis escape still yields a literal ellipsis"
  '(z ...) (escaped z))

;;; --- DEPTH UNDERFLOW (#682, reopened by this unit).
;;;
;;; SRFI 149 relaxes R7RS 4.3.2's depth rule UPWARD ONLY -- semantics rule
;;; 1: "Pattern variables that occur in subpatterns followed by zero or
;;; more instances of the identifier <ellipsis> are allowed only in
;;; subtemplates that are followed by as many OR MORE instances of
;;; <ellipsis>."  R7RS 4.3.2 is stricter still ("as many").  Using a
;;; variable at a LOWER depth than it matched is therefore an error under
;;; both; this expander previously substituted the empty list instead,
;;; silently discarding the matched input.  chibi and Guile reject the
;;; define-syntax itself.  The error fires at macro-EXPANSION time, so
;;; each case is probed through `eval` -- a literal call would abort the
;;; enclosing test form at compile time rather than raise inside it.
;;;
;;; Fixed by kaappi#682: both assertions below now pass; the three
;;; test-equal pins that asserted the wrong `()` answers were removed.

(test-error "depth underflow 1->0 is an error (#682)"
  (eval '(let-syntax ((m (syntax-rules () ((_ a ...) '(under a)))))
           (m 1 2 3))
        (environment '(scheme base))))
(test-error "depth underflow 2->1 is an error (#682's own repro)"
  (eval '(let-syntax ((m (syntax-rules () ((_ ((a ...) ...) (b ...)) '((a b) ...)))))
           (m ((1 2) (3 4)) (10 20)))
        (environment '(scheme base))))

;;; the discriminating control: at the CORRECT depth the same shapes
;;; expand exactly right, so the defect is the missing depth comparison
;;; and not the ellipsis machinery.
(define-syntax at-correct-depth
  (syntax-rules ()
    ((_ a ...) '(under a ...))))
(define-syntax two-at-two
  (syntax-rules ()
    ((_ ((a ...) ...) (b ...)) '(((a b) ...) ...))))

(test-equal "control: the same variable at its own depth expands correctly"
  '(under 1 2 3) (at-correct-depth 1 2 3))
(test-equal "control: a depth-2 variable used at depth 2 expands correctly"
  '(((1 10) (2 10)) ((3 20) (4 20)))
  (two-at-two ((1 2) (3 4)) (10 20)))

(let ((runner (test-runner-current)))
  (test-end "srfi-149")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
