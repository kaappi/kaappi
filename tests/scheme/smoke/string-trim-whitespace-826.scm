;;; Regression test for #826: string-trim should treat VT and FF as whitespace

(import (scheme base) (scheme process-context) (srfi 13) (srfi 64))

(test-begin "string-trim-whitespace-826")

(define vt (string (integer->char #x0B)))
(define ff (string (integer->char #x0C)))

;; string-trim strips leading whitespace
(test-equal "leading VT" "hello" (string-trim (string-append vt "hello")))
(test-equal "leading FF" "hello" (string-trim (string-append ff "hello")))
(test-equal "leading VT, FF and the ASCII five"
            "hello" (string-trim (string-append vt ff " \t\n\rhello")))

;; string-trim-right strips trailing whitespace
(test-equal "trailing VT" "hello" (string-trim-right (string-append "hello" vt)))
(test-equal "trailing FF" "hello" (string-trim-right (string-append "hello" ff)))

;; string-trim-both strips both
(test-equal "VT before and FF after"
            "hello" (string-trim-both (string-append vt "hello" ff)))

(let ((runner (test-runner-current)))
  (test-end "string-trim-whitespace-826")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
