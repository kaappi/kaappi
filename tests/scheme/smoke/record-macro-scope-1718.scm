;; Regression test for #1718: a program that imports a library shadowing a
;; core special form (here `lambda`, non-fixed-point expansion) must not
;; corrupt compilation of unrelated libraries loaded afterward.
;;
;; Before the fix, define-record-type/define-values desugaring compiled its
;; internally-synthesized (lambda ...) forms against the process-global
;; vm.macros table instead of an isolated one. Once `lambda` was shadowed
;; anywhere in the program, EVERY later define-record-type/define-values in
;; ANY library -- not just the one doing the shadowing -- saw the shadow too,
;; failing with a generic "CompileError while loading library" far from the
;; actual cause. See lib1718/shadow.sld, lib1718/victim.sld,
;; lib1718/dv-victim.sld.
;;
;; No SRFI-64 here (unlike most tests in this directory): test-assert/
;; test-equal, and even a plain (define (f ...) ...) shorthand, expand
;; through `lambda` themselves, so anything defined or asserted AFTER
;; importing the shadow would legitimately fail too (a non-converging macro
;; shadow breaks every use of the shadowed form in the *importing* program
;; from that point on -- expected behavior, see lib1718/shadow.sld's
;; header). The interesting property under test is that it does NOT also
;; break unrelated *libraries*, so the checking helper is defined BEFORE
;; the shadow import and only plain procedure calls (no lambda-desugaring
;; syntax) appear after it, matching the convention in tests/scheme/hygiene/
;; for the same reason.
(import (scheme base) (scheme write) (scheme process-context))

(define failed #f)
(define (check label ok)
  (if ok
      (begin (display "  PASS  ") (display label) (newline))
      (begin (set! failed #t)
             (display "  FAIL  ") (display label) (newline))))

;; Import the shadow -- this puts a non-fixed-point `lambda` macro into the
;; process-global vm.macros. Everything above this point is unaffected
;; (already compiled); everything below must avoid writing new `lambda`- or
;; `define`-shorthand-using source of its own.
(import (lib1718 shadow))

;; Now import unrelated libraries using define-record-type and
;; define-values. Before the fix, loading these would fail.
(import (lib1718 victim))
(import (lib1718 dv-victim))

(check "record constructor works" (procedure? make-point))
(check "record predicate works" (point? (make-point 1 2)))
(check "record accessor x" (= 1 (point-x (make-point 1 2))))
(check "record accessor y" (= 2 (point-y (make-point 1 2))))
(check "define-values initializer using lambda still works" (= 42 dv-result))

(if failed (exit 1) (begin (display "PASS") (newline)))
