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

(let ((runner (test-runner-current)))
  (test-end "include-ci-1141")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
