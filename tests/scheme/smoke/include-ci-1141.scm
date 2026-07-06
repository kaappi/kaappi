;; Regression test for #1141: include-ci must fold case when reading files.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "include-ci-1141")

;; Top-level include-ci: file defines (DEFINE Top-Level-Folded 77)
(include-ci "lib1141/upper-toplevel.scm")
(test-equal "top-level include-ci folds identifiers" 77 top-level-folded)

;; Library include-ci: .sld uses (include-ci "upper-body.scm")
;; which defines (DEFINE Lib-Folded-Value 99)
(import (lib1141 ci-lib))
(test-equal "library include-ci folds identifiers" 99 lib-folded-value)

;; #!no-fold-case inside an include-ci'd file restores case sensitivity.
;; The file defines no-fold-before (folded) then switches off folding and
;; defines No-Fold-After (case-sensitive).
(include-ci "lib1141/upper-with-nofold.scm")
(test-equal "include-ci folds before #!no-fold-case" 10 no-fold-before)
(test-equal "include-ci respects #!no-fold-case" 20 No-Fold-After)

(let ((runner (test-runner-current)))
  (test-end "include-ci-1141")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
