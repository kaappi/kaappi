;; SRFI-189 Maybe/Either tests.
;;
;; Regression focus: nothing was exported as a value, but per SRFI-189 it
;; is a procedure — (nothing) returns the unique Nothing object. Calling
;; (nothing) raised "not a procedure".
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 189))

(test-begin "srfi-189")

;; nothing is a procedure returning the unique Nothing object
(test-assert "nothing? (nothing)" (nothing? (nothing)))
(test-assert "nothing unique" (eq? (nothing) (nothing)))
(test-assert "maybe? (nothing)" (maybe? (nothing)))
(test-assert "just? (nothing) is false" (not (just? (nothing))))

;; just / maybe basics
(test-assert "just?" (just? (just 42)))
(test-assert "nothing? just is false" (not (nothing? (just 42))))
(test-equal "maybe-ref just" 7 (maybe-ref (just 7)))
(test-equal "maybe-ref/default nothing" 'dflt (maybe-ref/default (nothing) 'dflt))
(test-equal "maybe-ref/default just" 1 (maybe-ref/default (just 1) 'dflt))

;; maybe-map / maybe-filter / maybe-bind propagate Nothing
(test-equal "maybe-map just" 6 (maybe-ref (maybe-map (lambda (x) (* x 2)) (just 3))))
(test-assert "maybe-map nothing" (nothing? (maybe-map (lambda (x) x) (nothing))))
(test-assert "maybe-filter fail" (nothing? (maybe-filter odd? (just 2))))
(test-equal "maybe-filter pass" 3 (maybe-ref (maybe-filter odd? (just 3))))
(test-equal "maybe-bind just" 5
  (maybe-ref (maybe-bind (just 4) (lambda (x) (just (+ x 1))))))
(test-assert "maybe-bind nothing"
  (nothing? (maybe-bind (nothing) (lambda (x) (just x)))))

;; values->maybe
(test-assert "values->maybe none" (nothing? (values->maybe)))
(test-equal "values->maybe one" 9 (maybe-ref (values->maybe 9)))

(let ((runner (test-runner-current)))
  (test-end "srfi-189")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
