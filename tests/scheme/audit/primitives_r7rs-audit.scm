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
(import (chibi test))

(test-begin "primitives_r7rs audit")

;;; --- (scheme time) ---
(test #t (let ((s (current-second))) (and (inexact? s) (> s 1.7e9))))
(test #t (exact? (current-jiffy)))
(test #t (integer? (current-jiffy)))
;; monotonic within a run
(test #t (let ((a (current-jiffy)) (b (current-jiffy))) (>= b a)))
(test #t (let ((j (jiffies-per-second))) (and (exact? j) (positive? j))))
;; R7RS 6.14 example shape: measuring elapsed time stays finite and >= 0
(test #t (let* ((start (current-jiffy))
                (_ (make-list 1000))
                (elapsed (/ (- (current-jiffy) start) (jiffies-per-second))))
           (and (>= elapsed 0) (< elapsed 60))))

;;; --- (scheme process-context) ---
;; command-line: non-empty list of strings, first is the command name
(test #t (let ((cl (command-line)))
           (and (list? cl) (pair? cl) (string? (car cl)))))
(test #t (string? (get-environment-variable "PATH")))
(test #f (get-environment-variable "KAAPPI_DEFINITELY_NOT_SET_XYZ"))
(test 'caught (guard (e (#t 'caught)) (get-environment-variable 42)))
(test 'caught (guard (e (#t 'caught)) (get-environment-variable 'PATH)))
;; alist of (name . value) string pairs, PATH present
(test #t (let ((env (get-environment-variables)))
           (and (list? env)
                (pair? (car env))
                (string? (caar env))
                (string? (cdar env))
                (and (assoc "PATH" env) #t))))
;; exit/emergency-exit semantics (afters run for exit, skipped for
;; emergency-exit; #f→1, #t→0, default→0) are covered by
;; tests/scheme/errors/exit-wind.sh since they terminate the process.

;;; --- eval ---
(test 3 (eval '(+ 1 2)))
(test 21 (eval '(* 7 3) (environment '(scheme base))))
(test 'macro-ok (eval '(when #t 'macro-ok)))
(test 'caught (guard (e (#t 'caught)) (eval '(error "boom"))))
(test 'caught (guard (e (#t 'caught)) (eval 'kaappi-undefined-var-xyz)))
(test 'caught (guard (e (#t 'caught)) (eval '(car))))
;; definitions in the interaction environment persist
(test 77 (begin (eval '(define r7rs-audit-def-probe 77) (interaction-environment))
                (eval 'r7rs-audit-def-probe (interaction-environment))))
;; eval with a non-environment second argument must error (regression for
;; #1188: it used to be silently ignored, evaluating in the interaction
;; environment).
(test 'caught (guard (e (#t 'caught)) (eval '(+ 1 2) 42)))
(test 'caught (guard (e (#t 'caught)) (eval '(+ 1 2) "not-an-env")))

;;; --- environment ---
(test #t (procedure? (lambda () (environment '(scheme base)))))
(test 5 (eval '(- 8 3) (environment '(scheme base))))
;; multiple import sets merge
(test #t (eval '(procedure? read) (environment '(scheme base) '(scheme read))))
(test 'caught (guard (e (#t 'caught)) (environment 42)))
(test 'caught (guard (e (#t 'caught)) (environment '(no such library))))
;; R7RS 6.12: the arguments are IMPORT SETS, so only/except/prefix/rename
;; must be accepted.
(test 3 (eval '(+ 1 2) (environment '(only (scheme base) +))))
(test 3 (eval '(base:+ 1 2) (environment '(prefix (scheme base) base:))))

;;; --- interaction-environment / null-environment / scheme-report-environment ---
(test #t (and (interaction-environment) #t))
;; null-environment provides syntax but no procedure bindings
(test 1 (eval '(if #t 1 2) (null-environment 5)))
(test 'no-car (guard (e (#t 'no-car)) (eval '(car '(1)) (null-environment 5))))
;; scheme-report-environment provides the base procedures
(test 1 (eval '(car '(1 2)) (scheme-report-environment 5)))
(test 'caught (guard (e (#t 'caught)) (null-environment 4)))
(test 'caught (guard (e (#t 'caught)) (scheme-report-environment 6)))
(test 'caught (guard (e (#t 'caught)) (null-environment "5")))

;;; --- load ---
;; round trip: write a program, load it, definitions become visible
(define load-probe-path "/tmp/kaappi-audit-load-probe.scm")
(test 99 (begin
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
(test 42 (begin
           (with-output-to-file load-probe-path
             (lambda () (write '(* 6 7)) (newline)))
           (let ((v (load load-probe-path)))
             (delete-file load-probe-path)
             v)))
;; missing file raises a file-error
(test '(caught #t)
    (guard (e (#t (list 'caught (file-error? e))))
      (load "/nonexistent-kaappi-audit-xyz.scm")))
;; syntax errors in the loaded file are catchable
(test 'caught (begin
                (with-output-to-file load-probe-path
                  (lambda () (display "(unclosed (paren")))
                (let ((r (guard (e (#t 'caught)) (load load-probe-path))))
                  (delete-file load-probe-path)
                  r)))
(test 'caught (guard (e (#t 'caught)) (load 42)))
;; R7RS 6.14: (load filename environment-specifier)
(begin
  (with-output-to-file load-probe-path
    (lambda () (display "(define _load-env-audit-var (+ 1 2))")))
  (load load-probe-path (interaction-environment))
  (delete-file load-probe-path)
  (test 3 _load-env-audit-var))

;;; --- parameters (make-parameter, converter behavior) ---
(test 10 (let ((p (make-parameter 10))) (p)))
(test 20 (let ((p (make-parameter 10 (lambda (x) (* x 2))))) (p)))
;; converter runs at make-parameter time and errors propagate
(test 'conv-err (guard (e (#t 'conv-err)) (make-parameter 1 (lambda (x) (error "conv")))))
(test 'caught (guard (e (#t 'caught)) (make-parameter 1 5)))
;; converter also runs on parameterize
(test '(30 20)
    (let ((p (make-parameter 10 (lambda (x) (* x 2)))))
      (list (parameterize ((p 15)) (p)) (p))))

;;; --- disassemble (kaappi extension) ---
(test 'caught (guard (e (#t 'caught)) (disassemble car)))
(test 'caught (guard (e (#t 'caught)) (disassemble 42)))

(test-end "primitives_r7rs audit")
