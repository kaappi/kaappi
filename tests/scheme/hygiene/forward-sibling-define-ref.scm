;; Regression test: a macro template may reference a sibling internal
;; define that appears later in the same body. R7RS 5.3.2 gives body
;; defines letrec* scope, so the macro-definition environment includes
;; bar399 even though it is defined after the macro. The expander used
;; to hygiene-rename the free reference to a gensym, producing
;; "undefined variable '__hyg_N_bar399'" (R7RS suite line 580).
;;
;; Note: compile/runtime errors abort a top-level form without setting
;; a non-zero exit code, so the result is checked via a flag in a
;; separate top-level form.

(define ok #f)

(let ()
  (define-syntax foo399
    (syntax-rules () ((foo399) (bar399))))
  (define (quux399)
    (foo399))
  (define (bar399)
    42)
  (if (equal? (quux399) 42)
      (set! ok #t)
      (begin
        (display "FAIL: expected 42, got ")
        (display (quux399))
        (newline))))

(if ok
    (begin (display "PASS") (newline))
    (begin (display "FAIL: forward sibling define reference") (newline) (exit 1)))
