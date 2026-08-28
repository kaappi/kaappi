;; Regression test for kaappi#2404: walkers that touch a macro-use input
;; as if it were acyclic spin forever on the genuine cycles R7RS datum
;; labels (§7.1.2) produce — `(eq? x (cdr x))` is #t for
;; '#0=(zz . #0#), so this is a real cycle, not a reader artifact.
;;
;; Two walkers are exercised:
;;
;;   * compiler.collectSetTargets, whose cdr-spine loops had no bound (the
;;     scan's depth cap counts only car recursion). Pre-existing on
;;     origin/main: a cyclic macro operand re-emitted into a body position
;;     — e.g. as a test-assert operand — reached it and hung. Now bounded
;;     by SET_SCAN_SPINE_CAP; exhaustion degrades to the scan's ordinary
;;     loses-optimization truncation (set_targets_all boxing), and the
;;     ellipsis case shows matchEllipsis's own MAX_ELLIPSIS_VALUES cap
;;     already terminating on an infinite spine.
;;   * expander.erFormMentionsSymbol (compare's input walk), which the
;;     #2401 review introduced and fixed with a node budget + depth cap in
;;     the same class.
;;
;; erRenameDatum on the same cyclic input aborts on the root stack
;; instead (#2403) — a different failure mode needing its own semantic
;; decision, not covered here.
;;
;; A hang here fails by timeout, which run-all.sh reports.

(define-syntax cyc-m
  (syntax-rules () ((cyc-m x) 'ok-fixed)))
(define-syntax cyc-mell
  (syntax-rules () ((_ x ...) 'ok-ell)))

;; Fixed-arity pattern: the scanner walks the operand's spine; the
;; matcher stops at the pattern's end.
(if (not (eq? (cyc-m #0=(zz . #0#)) 'ok-fixed))
    (begin (display "FAIL: fixed-arity macro on cyclic input") (newline) (exit 1)))

;; Ellipsis pattern against the infinite spine: bounded by the matcher's
;; ellipsis-values cap.
(if (not (eq? (cyc-mell #0=(zz . #0#)) 'ok-ell))
    (begin (display "FAIL: ellipsis macro on cyclic input") (newline) (exit 1)))

;; The compare walk: the searched spelling is absent from the input, so
;; the walk cannot short-circuit before reaching the cycle (the exact
;; shape the #2404 report used).
(define-syntax cyc-self-else?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (rename 'else) (rename 'else))))))
(define cyc-compare-result (cyc-self-else? #0=(zz . #0#)))
(if (not (eq? cyc-compare-result #t))
    (begin (display "FAIL: compare on cyclic input") (newline) (exit 1)))

(display "cyclic-macro-input-2404: ok") (newline)
