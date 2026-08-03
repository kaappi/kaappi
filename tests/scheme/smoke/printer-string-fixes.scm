;; Regression tests for #855 (char literal semicolon) and #829 (string-prefix?/suffix?)

(import (scheme base) (scheme read) (scheme write)
        (scheme process-context) (srfi 13) (srfi 64))

(test-begin "printer-string-fixes")

;; #855: write of control chars should not emit trailing semicolon
(test-equal "write/read round trip of a control character literal"
  (list #\x05 1 2)
  (let* ((p (open-output-string))
         (_ (write (list #\x05 1 2) p))
         (s (get-output-string p)))
    (read (open-input-string s))))

;; #829: string-prefix? optional args apply to s1, not s2
;; s1[0:2]="he" is a prefix of "hell"
(test-assert "string-prefix? start/end apply to s1"
             (string-prefix? "hello" "hell" 0 2))
;; s1[2:]="llo" is a suffix of "llo"
(test-assert "string-suffix? start applies to s1"
             (string-suffix? "hello" "llo" 2))
(test-assert "\"abc\" is a prefix of \"abcdef\"" (string-prefix? "abc" "abcdef"))
(test-assert "\"xyz\" is not a prefix of \"abcdef\""
             (not (string-prefix? "xyz" "abcdef")))

(let ((runner (test-runner-current)))
  (test-end "printer-string-fixes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
