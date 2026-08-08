;; Regression test for #682: ellipsis depth mismatch should be detected
;; (R7RS 4.3.2 / SRFI 149 rule 1: a pattern variable may be used under AT
;; MOST as many template ellipses as its pattern depth; under-using it --
;; matching at depth N, using it at depth < N -- is a syntax error).
;;
;; The valid shapes expand correctly; every invalid shape must raise, and
;; the raise is asserted, not a particular wrong value. The invalid cases
;; are probed through `eval` because the error fires at macro-EXPANSION
;; time: a literal call would abort this script at compile time instead
;; of being catchable by `guard`.

(import (scheme base) (scheme write))

(define (compile-errors? thunk)
  (guard (exn (#t #t))
    (thunk)
    #f))

;; Valid: same-depth pattern variables under single ellipsis
(define-syntax ok-depth
  (syntax-rules ()
    ((_ (a ...) (b ...))
     (list (list a b) ...))))
(let ((result (ok-depth (1 2) (10 20))))
  (if (equal? result '((1 10) (2 20)))
    (display "PASS")
    (begin (display "FAIL: got ") (display result) (exit 1))))
(newline)

;; Valid: depth-2 variable used at depth 2 (nested ellipsis)
(define-syntax ok-nested
  (syntax-rules ()
    ((_ ((a ...) ...) (b ...))
     (list (list a b) ... ...))))
(let ((result (ok-nested ((1 2) (3 4)) (10 20))))
  (if (equal? result '((1 10) (2 10) (3 20) (4 20)))
    (display "PASS")
    (begin (display "FAIL: got ") (display result) (exit 1))))
(newline)

;; Valid: consecutive ellipses flatten a depth-2 binding ((x ... ...))
(define-syntax ok-flatten
  (syntax-rules ()
    ((_ (a ...) ...) (list a ... ...))))
(let ((result (ok-flatten (1 2) (3 4))))
  (if (equal? result '(1 2 3 4))
    (display "PASS")
    (begin (display "FAIL: got ") (display result) (exit 1))))
(newline)

;; Invalid #682's own repro: `a` matched at depth 2, used at depth 1.
(unless (compile-errors?
          (lambda ()
            (eval '(let-syntax ((m (syntax-rules ()
                                     ((_ ((a ...) ...) (b ...))
                                      (list (list a b) ...)))))
                     (m ((1 2) (3 4)) (10 20))))))
  (display "FAIL: depth 2->1 under-use did not raise") (newline) (exit 1))
(display "PASS") (newline)

;; Invalid: depth-1 variable used at depth 0 (no ellipsis at all).
(unless (compile-errors?
          (lambda ()
            (eval '(let-syntax ((m (syntax-rules () ((_ a ...) '(under a)))))
                     (m 1 2 3)))))
  (display "FAIL: depth 1->0 under-use did not raise") (newline) (exit 1))
(display "PASS") (newline)

;; Invalid: depth-2 variable used at depth 1 via a quoted template.
(unless (compile-errors?
          (lambda ()
            (eval '(let-syntax ((m (syntax-rules () ((_ ((x ...) ...)) '(x ...)))))
                     (m ((1 2) (3 4)))))))
  (display "FAIL: quoted depth 2->1 under-use did not raise") (newline) (exit 1))
(display "PASS") (newline)
