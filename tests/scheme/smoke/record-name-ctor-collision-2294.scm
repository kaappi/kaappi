;; Behavior pin for kaappi#2294: R7RS §5.5 is silent on whether <name> and
;; <constructor name> may be the same identifier. Kaappi accepts the
;; collision, with the constructor winning the name — Chibi and Guile reject
;; it, so the outcome is implementation-dependent and such code is not
;; portable (documented in CONFORMANCE.md's SRFI 9 section). This test pins
;; Kaappi's side of that contract so the documentation cannot drift.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 237))

(test-begin "record-name-ctor-collision-2294")

;; R7RS form: type name and constructor name are the same identifier.
(define-record-type foo (foo x) foo? (x bar))

(test-assert "constructor wins the name (foo is a procedure)"
  (procedure? foo))
(test-assert "foo constructs a record"
  (foo? (foo 1)))
(test-equal "accessor works on the colliding constructor's record"
  1 (bar (foo 1)))

;; R6RS clause-syntax (SRFI 237) name spec: same collision, same outcome —
;; the constructor define rebinds the name over the rtd binding.
(define-record-type (r6foo r6foo r6foo?) (fields (immutable v)))

(test-assert "R6RS clause syntax: constructor wins the name too"
  (procedure? r6foo))
(test-assert "R6RS clause syntax: constructor builds a record"
  (r6foo? (r6foo 7)))
(test-equal "R6RS clause syntax: field accessor works"
  7 (r6foo-v (r6foo 7)))
;; SRFI 237 specifies that the record name evaluates to the record
;; descriptor; the collision means that binding does NOT survive — the name
;; is the constructor, not the descriptor.
(test-assert "R6RS clause syntax: colliding name is not the record descriptor"
  (not (record-type-descriptor? r6foo)))

(let ((runner (test-runner-current)))
  (test-end "record-name-ctor-collision-2294")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
