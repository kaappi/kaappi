;;; Kaappi WASM (command-line) test — regression test for kaappi#2109.
;;;
;;; main.zig's WASM entry returned before vm.command_line_args was set, so
;;; (command-line) returned '() on wasm32 while every other target reported the
;;; script path as its first element (R7RS 6.14). The fix repopulates the field
;;; from the WASI argv the entry already iterates.
;;;
;;; Any FAIL line fails CI.

(import (scheme base) (scheme write) (scheme process-context))

(define failures 0)
(define (check label ok)
  (display (if ok "PASS " "FAIL "))
  (display label)
  (newline)
  (if (not ok) (set! failures (+ failures 1))))

(define args (command-line))

(define (string-suffix? s suffix)
  (let ((ls (string-length s))
        (lx (string-length suffix)))
    (and (>= ls lx)
         (string=? (substring s (- ls lx) ls) suffix))))

(check "(command-line) is a non-empty list" (and (list? args) (>= (length args) 1)))
(check "(command-line) first element is a string" (string? (car args)))
(check "(command-line) first element names this script"
       (string-suffix? (car args) "command-line.scm"))

(if (> failures 0)
    (begin (display "COMMAND-LINE TESTS FAILED") (newline) (exit 1))
    (begin (display "all command-line tests passed") (newline)))
