;; SRFI-98 (environment variables) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi98.scm

(import (scheme base) (srfi 98) (chibi test))

(test-begin "srfi-98")

;; PATH is set in any sane test environment
(test #t (string? (get-environment-variable "PATH")))
(test #f (get-environment-variable "KAAPPI_SURELY_UNSET_VAR_98_AUDIT"))

(define env (get-environment-variables))
(test #t (list? env))
(test #t (pair? (assoc "PATH" env)))
(test #t (string? (cdr (assoc "PATH" env))))

;; every entry is a (string . string) pair
(test #t
  (let loop ((e env))
    (or (null? e)
        (and (pair? (car e))
             (string? (caar e))
             (string? (cdar e))
             (loop (cdr e))))))

;; the alist agrees with single-variable lookup
(test (get-environment-variable "PATH") (cdr (assoc "PATH" env)))

(test-end "srfi-98")
