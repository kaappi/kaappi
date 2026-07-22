;;; SRFI 7 (Feature-based program configuration language) conformance tests
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi7.scm
;;;
;;; SRFI 7's `program` form is a pre-R7RS configuration language, not
;;; ordinary Scheme code; these tests exercise each clause type (code,
;;; requires, files, feature-cond) both standalone and combined, plus the
;;; error paths this port adds on top of the verbatim reference (see
;;; lib/srfi/7.sld header).

(import (scheme base) (scheme write) (scheme file) (scheme process-context)
        (srfi 7) (srfi 64))

(test-begin "srfi-7")

;;; --- code: plain inlined forms ---

(define code-probe #f)
(program (code (set! code-probe 'ran)))
(test-equal "code clause runs its forms" 'ran code-probe)

(program (code (define code-defined-var 123)))
(test-equal "code clause definitions are visible afterward" 123 code-defined-var)

;;; --- code: multiple forms, multiple code clauses ---

(define code-log '())
(program
  (code (set! code-log (cons 1 code-log)))
  (code (set! code-log (cons 2 code-log))
        (set! code-log (cons 3 code-log))))
(test-equal "multiple code clauses run in order" '(3 2 1) code-log)

;;; --- requires: satisfied ---

(define requires-probe #f)
(program
  (requires srfi-1)
  (code (set! requires-probe 'reached)))
(test-equal "requires with satisfied feature lets the program continue"
  'reached requires-probe)

;;; --- requires: unsatisfied => error ---

(test-assert "requires with missing feature signals an error"
  (guard (e (#t #t))
    (program (requires this-feature-does-not-exist-anywhere))
    #f))

;;; --- feature-cond: matching clause, no else ---

(define fc-probe1 #f)
(program
  (feature-cond
    (srfi-1 (code (set! fc-probe1 'srfi-1-branch)))
    (else (code (set! fc-probe1 'else-branch)))))
(test-equal "feature-cond picks the first satisfied clause" 'srfi-1-branch fc-probe1)

;;; --- feature-cond: else branch taken ---

(define fc-probe2 #f)
(program
  (feature-cond
    (this-feature-does-not-exist-anywhere (code (set! fc-probe2 'wrong)))
    (else (code (set! fc-probe2 'else-branch)))))
(test-equal "feature-cond falls through to else" 'else-branch fc-probe2)

;;; --- feature-cond: no clause satisfied, no else => error ---

(test-assert "feature-cond with nothing satisfied and no else signals an error"
  (guard (e (#t #t))
    (program (feature-cond (this-feature-does-not-exist-anywhere (code #f))))
    #f))

;;; --- feature-cond: and/or/not feature requirements ---

(define fc-probe3 #f)
(program
  (feature-cond
    ((and srfi-1 (not this-feature-does-not-exist-anywhere))
     (code (set! fc-probe3 'and-not-branch)))
    (else (code (set! fc-probe3 'else-branch)))))
(test-equal "feature-cond supports and/not requirements" 'and-not-branch fc-probe3)

(define fc-probe4 #f)
(program
  (feature-cond
    ((or this-feature-does-not-exist-anywhere srfi-1)
     (code (set! fc-probe4 'or-branch)))
    (else (code (set! fc-probe4 'else-branch)))))
(test-equal "feature-cond supports or requirements" 'or-branch fc-probe4)

;;; --- feature-cond: nested program clauses inside a branch ---

(define fc-nested-log '())
(program
  (feature-cond
    (srfi-1
     (requires srfi-1)
     (code (set! fc-nested-log (cons 'a fc-nested-log)))
     (code (set! fc-nested-log (cons 'b fc-nested-log))))))
(test-equal "feature-cond branches may contain multiple program clauses"
  '(b a) fc-nested-log)

;;; --- files: loads and splices a file's forms ---

(define loadee-path "/tmp/kaappi-srfi7-test-loadee.scm")
(call-with-output-file loadee-path
  (lambda (out)
    (write '(define srfi7-loaded-var 'from-file) out)
    (newline out)
    (write '(set! code-log (cons 'loaded code-log)) out)
    (newline out)))

(program (files "/tmp/kaappi-srfi7-test-loadee.scm"))
(test-equal "files clause loads definitions into the current environment"
  'from-file srfi7-loaded-var)
(test-equal "files clause's forms execute in order relative to load"
  'loaded (car code-log))

(delete-file loadee-path)

;;; --- empty program ---

(test-assert "empty program is a no-op that does not error" (begin (program) #t))

;;; --- combined clauses in one program form ---

(define combined-log '())
(program
  (code (set! combined-log (cons 'start combined-log)))
  (requires srfi-1)
  (feature-cond
    (srfi-1 (code (set! combined-log (cons 'srfi-1 combined-log))))
    (else (code (set! combined-log (cons 'else combined-log)))))
  (code (set! combined-log (cons 'end combined-log))))
(test-equal "clauses within one program form run in declared order"
  '(end srfi-1 start) combined-log)

(let ((runner (test-runner-current)))
  (test-end "srfi-7")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
