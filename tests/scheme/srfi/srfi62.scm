;; SRFI-62 (S-expression comments) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi62.scm
;;
;; This syntax is part of R7RS itself and Kaappi's reader already
;; implements it (see lib/srfi/62.sld's header); this just confirms
;; the import succeeds and the datum-comment behavior is correct.

(import (scheme base) (scheme process-context) (srfi 62) (srfi 64))

(test-begin "srfi-62")

(test-equal "datum comment: discards the next atom" '(1 2) (list 1 #;99 2))

(test-equal "datum comment: discards the next compound datum"
  '(1 2)
  (list 1 #;(this is entirely ignored (even nested)) 2))

(test-equal "datum comment: multiple in sequence"
  '(1 4)
  (list 1 #;2 #;3 4))

(test-equal "datum comment: works at the start of a list" '(2) (list #;1 2))

(let ((runner (test-runner-current)))
  (test-end "srfi-62")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
