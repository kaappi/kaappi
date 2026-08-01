;; SRFI-98 (environment variables) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi98.scm
;;
;; Two procedures. `get-environment-variable name` returns the variable's
;; value as a string, or #f if it is not set; `get-environment-variables`
;; returns "the names and values of all the environment variables as an
;; alist" of (string . string) pairs.
;;
;; Grown in audit v2 Phase 3.8 from 7 assertions. Every value here is
;; platform- and environment-dependent -- this runs on macOS, five Linux
;; architectures, three BSDs and two Windows targets in CI -- so nothing
;; below asserts a variable's VALUE. What is asserted is shape (string or
;; #f, never anything else), agreement between the two procedures in both
;; directions, argument handling, and the aliasing question the SRFI leaves
;; open but which matters for safety: whether a caller can corrupt the
;; environment by mutating the returned alist.

(import (scheme base) (srfi 98) (scheme process-context) (srfi 64))

;; Windows preserves case but names are case-insensitive ("Path"), so
;; the alist lookup must compare case-insensitively there.
(define (env-assoc name env)
  (cond-expand
    (windows (assoc name env string-ci=?))
    (else (assoc name env))))

(test-begin "srfi-98")

;;; --- get-environment-variable: shape ---

;; PATH is set in any sane test environment, on every supported platform.
(test-assert "PATH is a string" (string? (get-environment-variable "PATH")))
(test-equal "an unset variable is #f" #f
  (get-environment-variable "KAAPPI_SURELY_UNSET_VAR_98_AUDIT"))
(test-equal "an unset variable with an unusual name is still #f" #f
  (get-environment-variable "KAAPPI-98-AUDIT.unset var"))
(test-equal "the empty name is not set" #f (get-environment-variable ""))
(test-equal "a name containing '=' cannot be set, so it is #f" #f
  (get-environment-variable "KAAPPI_98=AUDIT"))

(test-assert "repeated lookups agree"
  (equal? (get-environment-variable "PATH") (get-environment-variable "PATH")))

;;; --- get-environment-variable: arguments ---

(test-error "a non-string name is a type error" (get-environment-variable 'PATH))
(test-error "a character name is a type error" (get-environment-variable #\P))
(test-error "no argument is an arity error" (get-environment-variable))
(test-error "a surplus argument is an arity error"
  (get-environment-variable "PATH" "extra"))

;;; --- get-environment-variables: shape ---

(define env (get-environment-variables))

(test-assert "the result is a list" (list? env))
(test-assert "the result is not empty" (pair? env))
(test-assert "PATH has an entry" (pair? (env-assoc "PATH" env)))
(test-assert "PATH's entry has a string value"
  (string? (cdr (env-assoc "PATH" env))))

(test-assert "every entry is a (string . string) pair"
  (let loop ((e env))
    (or (null? e)
        (and (pair? (car e))
             (string? (caar e))
             (string? (cdar e))
             (loop (cdr e))))))

;; Windows' command processor injects pseudo-variables whose names begin
;; with '=' (the per-drive current directories, e.g. "=C:"), so this and
;; the whole-alist agreement scan below are POSIX-only.
(cond-expand
  (windows)
  (else
    (test-assert "no entry name contains '='"
      (let loop ((e env))
        (or (null? e)
            (and (not (memv #\= (string->list (caar e))))
                 (loop (cdr e))))))))

(test-assert "no entry name is empty"
  (let loop ((e env))
    (or (null? e) (and (> (string-length (caar e)) 0) (loop (cdr e))))))

(test-error "a surplus argument is an arity error"
  (get-environment-variables "extra"))

;;; --- the two procedures agree, in both directions ---

(test-equal "the alist agrees with single-variable lookup for PATH"
  (get-environment-variable "PATH") (cdr (env-assoc "PATH" env)))

(cond-expand
  (windows)
  (else
    (test-assert "every alist entry agrees with a single-variable lookup"
      (let loop ((e env))
        (or (null? e)
            (and (equal? (cdar e) (get-environment-variable (caar e)))
                 (loop (cdr e))))))))

(test-assert "a name absent from the alist looks up as #f"
  (and (not (env-assoc "KAAPPI_SURELY_UNSET_VAR_98_AUDIT" env))
       (eq? #f (get-environment-variable "KAAPPI_SURELY_UNSET_VAR_98_AUDIT"))))

;;; --- aliasing.  The SRFI does not say whether the alist is fresh, but a
;;; shared one would let a caller corrupt the process environment by
;;; mutating a returned pair. Kaappi returns a fresh list of fresh pairs
;;; each call: equal? but not eq?, and a mutation is not observed by the
;;; next call. ---

(test-assert "two calls return equal alists"
  (equal? (get-environment-variables) (get-environment-variables)))
(test-assert "two calls do not return the same list object"
  (not (eq? (get-environment-variables) (get-environment-variables))))
(test-assert "mutating a returned pair does not affect the next call"
  (let ((a (get-environment-variables)))
    (set-cdr! (car a) "KAAPPI-98-AUDIT-CLOBBERED")
    (not (equal? (cdr (car (get-environment-variables)))
                 "KAAPPI-98-AUDIT-CLOBBERED"))))
(test-assert "mutating a returned pair does not affect single-variable lookup"
  (let* ((a (get-environment-variables))
         (name (caar a)))
    (set-cdr! (car a) "KAAPPI-98-AUDIT-CLOBBERED-2")
    (not (equal? (get-environment-variable name)
                 "KAAPPI-98-AUDIT-CLOBBERED-2"))))

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-98" 'yes (cond-expand (srfi-98 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-98")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
