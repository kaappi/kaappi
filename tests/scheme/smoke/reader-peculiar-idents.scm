;; Regression test for #647: peculiar identifiers like ->foo
;; truncated to just the sign character.

(import (scheme base) (scheme read) (scheme process-context) (srfi 64))

(test-begin "reader-peculiar-idents")

(define (read-symbol-name text)
  (symbol->string (read (open-input-string text))))

;; Arrow-style identifiers (most common real-world case)
(define ->string (lambda (x) x))
(test-assert "->string reads as one symbol" (eq? '->string '->string))

;; Peculiar identifiers with various special-initial chars after sign.
;; Each was truncated to its bare sign character before #647.
(for-each
  (lambda (text)
    (test-equal (string-append "reads " text " whole") text (read-symbol-name text)))
  '("->foo" "-<tag>" "+>=" "-!default" "-$var" "-%pct" "-&ref" "-*glob"
    "-/path" "-:key" "-=eq" "-?pred" "-^up" "-_priv" "-~approx"
    ;; + prefix too
    "+>cmp" "+!bang"
    ;; These already worked (letter/dot/sign after sign) — sanity check
    "-foo" "+.z"))

(let ((runner (test-runner-current)))
  (test-end "reader-peculiar-idents")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
