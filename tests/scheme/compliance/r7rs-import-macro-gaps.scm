;; R7RS 5.2/5.6 library gap tests: macro exports through import sets and
;; cond-expand library declarations — audit Phase 4C (libraries).
;; Complements r7rs-libraries-gaps.scm (values through nested import sets)
;; with the macro-binding side. Spec: docs/errata-corrected-r7rs.pdf 5.1-5.6.
;; Circular imports were probed separately: (p4c ca) <-> (p4c cb) reports
;; "circular import: ..." and exits nonzero — detected, no hang, no crash.

(define-library (gaps4c macros)
  (import (scheme base))
  (export (rename int-double pub-double) mk-adder tagged-val)
  (begin
    (define-syntax int-double (syntax-rules () ((_ x) (* 2 x))))
    (define-syntax mk-adder (syntax-rules () ((_ n) (lambda (m) (+ n m)))))
    (define tagged-val 'plain)))

(define-library (gaps4c ce)
  (import (scheme base))
  (export which)
  (cond-expand
    (kaappi (begin (define which 'kaappi-branch)))
    (else (begin (define which 'else-branch)))))

(define-library (gaps4c ce2)
  (import (scheme base))
  (export which2)
  (cond-expand
    ((and r7rs (not nonexistent-feature-xyz))
     (begin (define which2 'and-not)))
    (else (begin (define which2 'nope)))))

(define-library (gaps4c multi)
  (import (scheme base))
  (export mv-a mv-b)
  (begin (define mv-a 1))
  (begin (define mv-b 2)))

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "r7rs-import-macro-gaps")

;;; --- (export (rename ...)) of a MACRO, imported with prefix ---
(import (prefix (gaps4c macros) m:))
(test-equal "renamed macro export through prefix import" 42
  (m:pub-double 21))
(test-equal "macro through prefix import" 7 ((m:mk-adder 3) 4))
(test-equal "value through prefix import" 'plain m:tagged-val)

;;; --- macro through only / rename import sets ---
(import (only (gaps4c macros) mk-adder))
(test-equal "macro through only import" 2 ((mk-adder 1) 1))
(import (rename (gaps4c macros) (mk-adder make-adder)))
(test-equal "macro through rename import" 10 ((make-adder 4) 6))

;;; --- macro through nested import sets ---
(import (only (rename (gaps4c macros) (pub-double dbl)) dbl))
(test-equal "macro through only-of-rename" 42 (dbl 21))
(import (except (gaps4c macros) tagged-val))
(test-equal "macro survives except of unrelated name" 6 (m:pub-double 3))

;;; --- cond-expand as a library declaration ---
(import (gaps4c ce) (gaps4c ce2))
(test-equal "cond-expand feature branch in library" 'kaappi-branch which)
(test-equal "cond-expand (and ... (not ...)) in library" 'and-not which2)

;;; --- multiple begin declarations ---
(import (gaps4c multi))
(test-equal "multiple begin declarations" '(1 2) (list mv-a mv-b))

(let ((runner (test-runner-current)))
  (test-end "r7rs-import-macro-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
