;; SRFI-98 (environment variables) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi98.scm

(import (scheme base) (srfi 98) (scheme process-context) (srfi 64))
;; Windows preserves case but names are case-insensitive ("Path"), so
;; the alist lookup must compare case-insensitively there.
(define (env-assoc name env)
  (cond-expand
    (windows (assoc name env string-ci=?))
    (else (assoc name env))))

(test-begin "srfi-98")

;; PATH is set in any sane test environment
(test-equal #t (string? (get-environment-variable "PATH")))
(test-equal #f (get-environment-variable "KAAPPI_SURELY_UNSET_VAR_98_AUDIT"))

(define env (get-environment-variables))
(test-equal #t (list? env))
(test-equal #t (pair? (env-assoc "PATH" env)))
(test-equal #t (string? (cdr (env-assoc "PATH" env))))

;; every entry is a (string . string) pair
(test-equal #t
  (let loop ((e env))
    (or (null? e)
        (and (pair? (car e))
             (string? (caar e))
             (string? (cdar e))
             (loop (cdr e))))))

;; the alist agrees with single-variable lookup
(test-equal (get-environment-variable "PATH") (cdr (env-assoc "PATH" env)))

(let ((runner (test-runner-current)))
  (test-end "srfi-98")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
