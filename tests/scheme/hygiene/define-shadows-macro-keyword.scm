;; Regression test: an internal define must shadow a macro keyword bound
;; outside the body (R7RS 5.3). The first form's (foo bar x) expands to a
;; define-syntax for bar whose registration escapes the let body; the
;; second form's (define bar (lambda (a b) ...)) is a variable binding
;; for the whole body, so (bar x y) must compile as a procedure call.
;; Previously it was expanded as a use of the leaked one-argument macro,
;; aborting the form with error.InvalidSyntax (R7RS suite line 633).
;;
;; Note: compile errors abort a top-level form without setting a non-zero
;; exit code, so the result is checked via a flag in a separate form.

(define ok #f)

;; Leak a generated macro named gen-bar out of a let body
;; (mirrors R7RS suite lines 547-555).
(let ()
  (define-syntax gen-foo
    (syntax-rules ()
      ((gen-foo gen-bar y)
       (define-syntax gen-bar
         (syntax-rules ()
           ((gen-bar x) 'y))))))
  (gen-foo gen-bar marker)
  (if (not (eq? (gen-bar 1) 'marker))
      (begin (display "FAIL: generated macro broken") (newline) (exit 1))))

;; Now an internal define of the same name must shadow the macro keyword.
(let ((r (let ((x 5))
           (define use-it (lambda (y) (gen-bar x y)))
           (define gen-bar (lambda (a b) (+ (* a b) a)))
           (use-it (+ x 3)))))
  (if (equal? r 45)
      (set! ok #t)
      (begin
        (display "FAIL: expected 45, got ")
        (display r)
        (newline))))

(if ok
    (begin (display "PASS") (newline))
    (begin (display "FAIL: internal define did not shadow macro keyword") (newline) (exit 1)))
