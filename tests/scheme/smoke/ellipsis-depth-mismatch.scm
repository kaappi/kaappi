;; Regression test for #682: ellipsis depth mismatch should be detected
;; (R7RS 4.3.2 / SRFI 149 rule 1: a pattern variable may be used under AT
;; MOST as many template ellipses as its pattern depth; under-using it --
;; matching at depth N, using it at depth < N -- is a syntax error).
;;
;; The valid shapes expand correctly; every invalid shape must raise, and
;; the raise is asserted, not a particular wrong value. The invalid cases
;; are probed through `eval` because the error fires at macro-EXPANSION
;; time: a literal call would abort this file at compile time instead of
;; raising inside the assertion.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "ellipsis-depth-mismatch")

;; Valid: same-depth pattern variables under single ellipsis
(define-syntax ok-depth
  (syntax-rules ()
    ((_ (a ...) (b ...))
     (list (list a b) ...))))
(test-equal "same-depth pattern variables under single ellipsis"
  '((1 10) (2 20)) (ok-depth (1 2) (10 20)))

;; Valid: depth-2 variable used at depth 2 (nested ellipsis)
(define-syntax ok-nested
  (syntax-rules ()
    ((_ ((a ...) ...) (b ...))
     (list (list a b) ... ...))))
(test-equal "depth-2 variable used at depth 2 (nested ellipsis)"
  '((1 10) (2 10) (3 20) (4 20))
  (ok-nested ((1 2) (3 4)) (10 20)))

;; Valid: consecutive ellipses flatten a depth-2 binding ((x ... ...))
(define-syntax ok-flatten
  (syntax-rules ()
    ((_ (a ...) ...) (list a ... ...))))
(test-equal "consecutive ellipses flatten a depth-2 binding"
  '(1 2 3 4) (ok-flatten (1 2) (3 4)))

;; Invalid #682's own repro: `a` matched at depth 2, used at depth 1.
(test-error "depth 2->1 under-use is a syntax error (#682's own repro)"
  (eval '(let-syntax ((m (syntax-rules ()
                           ((_ ((a ...) ...) (b ...))
                            (list (list a b) ...)))))
           (m ((1 2) (3 4)) (10 20)))
        (environment '(scheme base))))

;; Invalid: depth-1 variable used at depth 0 (no ellipsis at all).
(test-error "depth 1->0 under-use (no ellipsis) is a syntax error (#682)"
  (eval '(let-syntax ((m (syntax-rules () ((_ a ...) '(under a)))))
           (m 1 2 3))
        (environment '(scheme base))))

;; Invalid: depth-2 variable used at depth 1 via a quoted template.
(test-error "quoted depth 2->1 under-use is a syntax error (#682)"
  (eval '(let-syntax ((m (syntax-rules () ((_ ((x ...) ...)) '(x ...)))))
           (m ((1 2) (3 4))))
        (environment '(scheme base))))

;; Invalid: the under-use check is STRUCTURAL, not gated on the consuming
;; run being instantiated. A depth-3 variable used at depth 2, with the
;; input matching ZERO outer repetitions, must still error rather than
;; silently expand to (); ditto the vector spelling.
(test-error "depth 3->2 under-use fires even with an empty outer match"
  (eval '(let-syntax ((m (syntax-rules () ((_ (((b ...) ...) ...)) '((b ...) ...)))))
           (m ()))
        (environment '(scheme base))))
(test-error "depth 3->2 under-use via a vector pattern fires with an empty match"
  (eval '(let-syntax ((m (syntax-rules () ((_ (#((b ...) ...) ...)) '((b ...) ...)))))
           (m ()))
        (environment '(scheme base))))

;; The control: the same shapes at their CORRECT template depth, with an
;; empty match, expand to the empty list (not an error).
(define-syntax ok-empty-outer
  (syntax-rules () ((_ ((b ...) ...)) '((b ...) ...))))
(test-equal "empty outer match at the correct depth expands to the empty list"
  '() (ok-empty-outer ()))

(let ((runner (test-runner-current)))
  (test-end "ellipsis-depth-mismatch")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
