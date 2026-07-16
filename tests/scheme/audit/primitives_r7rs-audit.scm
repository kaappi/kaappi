;; Audit tests for src/primitives_r7rs.zig — (scheme time), (scheme
;; process-context), (scheme eval), (scheme load), (scheme r5rs)
;; environments, parameters, disassemble.
;; Audit campaign Phase 2.14 (#1137). Complements
;; compliance/r7rs-control-io-gaps.scm (Phase 1D) and the exit-semantics
;; shell test tests/scheme/errors/exit-wind.sh (added with this file —
;; exit/emergency-exit terminate the process, so they can't be asserted here).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme eval) (scheme repl) (scheme time)
        (scheme process-context) (scheme load) (scheme r5rs) (scheme file))
(import (srfi 64))

(test-begin "primitives_r7rs audit")

;;; --- (scheme time) ---
(test-equal #t (let ((s (current-second))) (and (inexact? s) (> s 1.7e9))))
(test-equal #t (exact? (current-jiffy)))
(test-equal #t (integer? (current-jiffy)))
;; monotonic within a run
(test-equal #t (let ((a (current-jiffy)) (b (current-jiffy))) (>= b a)))
(test-equal #t (let ((j (jiffies-per-second))) (and (exact? j) (positive? j))))
;; R7RS 6.14 example shape: measuring elapsed time stays finite and >= 0
(test-equal #t (let* ((start (current-jiffy))
                      (_ (make-list 1000))
                      (elapsed (/ (- (current-jiffy) start) (jiffies-per-second))))
                 (and (>= elapsed 0) (< elapsed 60))))

;;; --- (scheme process-context) ---
;; command-line: non-empty list of strings, first is the command name
(test-equal #t (let ((cl (command-line)))
                 (and (list? cl) (pair? cl) (string? (car cl)))))
(test-equal #t (string? (get-environment-variable "PATH")))
(test-equal #f (get-environment-variable "KAAPPI_DEFINITELY_NOT_SET_XYZ"))
(test-equal 'caught (guard (e (#t 'caught)) (get-environment-variable 42)))
(test-equal 'caught (guard (e (#t 'caught)) (get-environment-variable 'PATH)))
;; alist of (name . value) string pairs, PATH present
(test-equal #t (let ((env (get-environment-variables)))
                 (and (list? env)
                      (pair? (car env))
                      (string? (caar env))
                      (string? (cdar env))
                      ;; Windows preserves case but names are
                      ;; case-insensitive ("Path"), so compare ci there.
                      (and (cond-expand
                             (windows (assoc "PATH" env string-ci=?))
                             (else (assoc "PATH" env)))
                           #t))))
;; exit/emergency-exit semantics (afters run for exit, skipped for
;; emergency-exit; #f→1, #t→0, default→0) are covered by
;; tests/scheme/errors/exit-wind.sh since they terminate the process.

;;; --- eval ---
(test-equal 3 (eval '(+ 1 2)))
(test-equal 21 (eval '(* 7 3) (environment '(scheme base))))
(test-equal 'macro-ok (eval '(when #t 'macro-ok)))
(test-equal 'caught (guard (e (#t 'caught)) (eval '(error "boom"))))
(test-equal 'caught (guard (e (#t 'caught)) (eval 'kaappi-undefined-var-xyz)))
(test-equal 'caught (guard (e (#t 'caught)) (eval '(car))))
;; definitions in the interaction environment persist
(test-equal 77 (begin (eval '(define r7rs-audit-def-probe 77) (interaction-environment))
                      (eval 'r7rs-audit-def-probe (interaction-environment))))
;; eval with a non-environment second argument must error (regression for
;; #1188: it used to be silently ignored, evaluating in the interaction
;; environment).
(test-equal 'caught (guard (e (#t 'caught)) (eval '(+ 1 2) 42)))
(test-equal 'caught (guard (e (#t 'caught)) (eval '(+ 1 2) "not-an-env")))

;;; --- environment ---
(test-equal #t (procedure? (lambda () (environment '(scheme base)))))
(test-equal 5 (eval '(- 8 3) (environment '(scheme base))))
;; multiple import sets merge
(test-equal #t (eval '(procedure? read) (environment '(scheme base) '(scheme read))))
(test-equal 'caught (guard (e (#t 'caught)) (environment 42)))
(test-equal 'caught (guard (e (#t 'caught)) (environment '(no such library))))
;; R7RS 6.12: the arguments are IMPORT SETS, so only/except/prefix/rename
;; must be accepted.
(test-equal 3 (eval '(+ 1 2) (environment '(only (scheme base) +))))
(test-equal 3 (eval '(base:+ 1 2) (environment '(prefix (scheme base) base:))))

;;; --- interaction-environment / null-environment / scheme-report-environment ---
(test-equal #t (and (interaction-environment) #t))
;; null-environment provides syntax but no procedure bindings
(test-equal 1 (eval '(if #t 1 2) (null-environment 5)))
(test-equal 'no-car (guard (e (#t 'no-car)) (eval '(car '(1)) (null-environment 5))))
;; scheme-report-environment provides the base procedures
(test-equal 1 (eval '(car '(1 2)) (scheme-report-environment 5)))
(test-equal 'caught (guard (e (#t 'caught)) (null-environment 4)))
(test-equal 'caught (guard (e (#t 'caught)) (scheme-report-environment 6)))
(test-equal 'caught (guard (e (#t 'caught)) (null-environment "5")))

;;; --- load ---
;; round trip: write a program, load it, definitions become visible
(define load-probe-path "/tmp/kaappi-audit-load-probe.scm")
(test-equal 99 (begin
                 (when (file-exists? load-probe-path) (delete-file load-probe-path))
                 (with-output-to-file load-probe-path
                   (lambda ()
                     (write '(define r7rs-audit-loaded-var 99))
                     (newline)))
                 (load load-probe-path)
                 (let ((v (eval 'r7rs-audit-loaded-var (interaction-environment))))
                   (delete-file load-probe-path)
                   v)))
;; load returns the value of the last expression
(test-equal 42 (begin
                 (with-output-to-file load-probe-path
                   (lambda () (write '(* 6 7)) (newline)))
                 (let ((v (load load-probe-path)))
                   (delete-file load-probe-path)
                   v)))
;; missing file raises a file-error
(test-equal '(caught #t)
    (guard (e (#t (list 'caught (file-error? e))))
      (load "/nonexistent-kaappi-audit-xyz.scm")))
;; syntax errors in the loaded file are catchable
(test-equal 'caught (begin
                      (with-output-to-file load-probe-path
                        (lambda () (display "(unclosed (paren")))
                      (let ((r (guard (e (#t 'caught)) (load load-probe-path))))
                        (delete-file load-probe-path)
                        r)))
(test-equal 'caught (guard (e (#t 'caught)) (load 42)))
;; R7RS 6.14: (load filename environment-specifier)
(begin
  (with-output-to-file load-probe-path
    (lambda () (display "(define _load-env-audit-var (+ 1 2))")))
  (load load-probe-path (interaction-environment))
  (delete-file load-probe-path)
  (test-equal 3 _load-env-audit-var))

;;; --- parameters (make-parameter, converter behavior) ---
(test-equal 10 (let ((p (make-parameter 10))) (p)))
(test-equal 20 (let ((p (make-parameter 10 (lambda (x) (* x 2))))) (p)))
;; converter runs at make-parameter time and errors propagate
(test-equal 'conv-err (guard (e (#t 'conv-err)) (make-parameter 1 (lambda (x) (error "conv")))))
(test-equal 'caught (guard (e (#t 'caught)) (make-parameter 1 5)))
;; converter also runs on parameterize
(test-equal '(30 20)
    (let ((p (make-parameter 10 (lambda (x) (* x 2)))))
      (list (parameterize ((p 15)) (p)) (p))))

;;; --- disassemble (kaappi extension) ---
(test-equal 'caught (guard (e (#t 'caught)) (disassemble car)))
(test-equal 'caught (guard (e (#t 'caught)) (disassemble 42)))

(let ((runner (test-runner-current)))
  (test-end "primitives_r7rs audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
