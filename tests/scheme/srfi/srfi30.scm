;; SRFI-30 (Nested Multi-line Comments) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi30.scm
;;
;; This syntax is part of R7RS itself and Kaappi's reader already
;; implements it (see lib/srfi/30.sld's header); this just confirms
;; the import succeeds and nesting works as specified.

(import (scheme base) (scheme process-context) (srfi 30) (srfi 64))

(test-begin "srfi-30")

(test-equal "block comment: simple, non-nested" 1 #| this is a comment |# 1)

#| an outer comment #| a nested comment |# still inside the outer comment |#
(test-assert "nested block comment: whole file still parses past the nesting" #t)

(test-equal "nested block comment: collapses to a single comment, not two"
  '(1)
  (list #| a #| b |# c |# 1))

(test-equal "block comment: can appear between any two tokens"
  3
  (+ 1 #| comment |# 2))

(let ((runner (test-runner-current)))
  (test-end "srfi-30")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
