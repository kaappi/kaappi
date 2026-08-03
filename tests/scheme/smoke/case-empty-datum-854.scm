;; Regression test for #854: case rejects empty datum list
;; R7RS allows empty datum lists in case clauses — the clause
;; is dead code (never matches) and should be silently skipped.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "case-empty-datum-854")

;; Empty datum list before matching clause
(test-equal "empty datum list before the matching clause"
  'one
  (case 1
    (() 'never)
    ((1) 'one)
    (else 'other)))

;; Empty datum list after matching clause
(test-equal "empty datum list after the matching clause"
  'two
  (case 2
    ((2) 'two)
    (() 'never)
    (else 'other)))

;; Only empty datum lists, falls through to else
(test-equal "only empty datum lists falls through to else"
  'fallthrough
  (case 3
    (() 'never1)
    (() 'never2)
    (else 'fallthrough)))

;; Only empty datum lists, no else — result is unspecified, but compiling and
;; running at all is the point.
(test-assert "only empty datum lists with no else still compiles and runs"
  (begin (case 4 (() 'never)) #t))

(let ((runner (test-runner-current)))
  (test-end "case-empty-datum-854")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
