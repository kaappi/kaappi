;; Regression test for #921: write/display must remain single-line
;; (pretty-printing is REPL-only; write/display are R7RS-conformant).

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "prettyprint-width-921")

;; write must produce single-line output for long lists
(test-equal "write long list is single-line"
  "(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
  (let ((p (open-output-string)))
    (write (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20) p)
    (get-output-string p)))

;; display must produce single-line output for long lists
(test-equal "display long list is single-line"
  "(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
  (let ((p (open-output-string)))
    (display (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20) p)
    (get-output-string p)))

;; write must produce single-line output for long vectors
(test-equal "write long vector is single-line"
  "#(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20)"
  (let ((p (open-output-string)))
    (write (vector 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20) p)
    (get-output-string p)))

;; Nested structures
(test-equal "write nested lists is single-line"
  "((1 2 3) (4 5 6) (7 8 9) (10 11 12))"
  (let ((p (open-output-string)))
    (write (list (list 1 2 3) (list 4 5 6) (list 7 8 9) (list 10 11 12)) p)
    (get-output-string p)))

;; write-shared with no sharing is single-line
(test-equal "write-shared non-shared long list is single-line"
  "(1 2 3 4 5 6 7 8 9 10)"
  (let ((p (open-output-string)))
    (write-shared (list 1 2 3 4 5 6 7 8 9 10) p)
    (get-output-string p)))

(let ((runner (test-runner-current)))
  (test-end "prettyprint-width-921")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
