;; Regression test for #647: peculiar identifiers like ->foo
;; truncated to just the sign character.

(import (scheme base) (scheme read) (scheme process-context) (srfi 64))

(test-begin "reader-peculiar-idents")

(define (read-symbol-name text)
  (symbol->string (read (open-input-string text))))

;; Arrow-style identifiers (most common real-world case). Asserted on the
;; symbol's TEXT, not `(eq? '->string '->string)` — under the #647 regression
;; both quoted occurrences truncate to `-` identically and `eq?` is still #t,
;; so that spelling cannot detect the bug it names.
(define ->string (lambda (x) x))
(test-equal "->string reads as one whole symbol"
            "->string" (symbol->string '->string))
(test-assert "and the binding under that name is reachable" (procedure? ->string))

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
