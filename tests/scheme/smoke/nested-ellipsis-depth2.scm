;; Regression test: syntax-rules templates using pattern variables at
;; ellipsis depth 2 — e.g. ((a (b c) ...) ...) — failed to expand with
;; "compile error: error.InvalidSyntax" (EllipsisDepthMismatch in the
;; expander). Surfaced by SRFI-35's `condition` construction macro:
;; (condition (&message (message "test msg"))).
;;
;; Uses manual checks (not SRFI-64) and define+set! so that a compile
;; error in a macro-using form is still caught: the set! form is skipped,
;; the sentinel value survives, and the check fails.

(import (scheme base) (scheme write) (scheme process-context))

(define failures 0)
(define (check name got expected)
  (if (equal? got expected)
      (begin (display "  PASS ") (display name) (newline))
      (begin (display "  FAIL ") (display name)
             (display " got: ") (write got)
             (display " expected: ") (write expected)
             (newline)
             (set! failures (+ failures 1)))))

;; Same shape as SRFI-35's `condition` macro: depth-1 var (key) alongside
;; depth-2 vars (f, v), with quoted depth-2 vars in the template.
(define-syntax alist
  (syntax-rules ()
    ((alist (key (f v) ...) ...)
     (list (cons 'key (list (cons 'f v) ...)) ...))))

(define r1 'compile-error)
(set! r1 (alist (k1 (a 1) (b 2)) (k2 (c 3))))
(check "depth-2 vars with quote" r1 '((k1 (a . 1) (b . 2)) (k2 (c . 3))))

(define r2 'compile-error)
(set! r2 (alist))
(check "zero outer repetitions" r2 '())

(define r3 'compile-error)
(set! r3 (alist (k)))
(check "zero inner repetitions" r3 '((k)))

;; Depth-2 vars in an evaluated (non-quoted) position.
(define-syntax nest+
  (syntax-rules ()
    ((_ (a (b c) ...) ...)
     (+ (+ a (* b c) ...) ...))))

(define r4 'compile-error)
(set! r4 (nest+ (1 (2 3) (4 5)) (10 (6 7))))
(check "depth-2 arithmetic" r4 79)

(if (> failures 0) (exit 1))
