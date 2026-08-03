;; Regression test for #52: case must respect lexical shadowing of =>

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "case-arrow-shadowing")

;; When => is locally bound, case should NOT treat it as the arrow keyword.
;; The clause body (=> foo) compiles as (begin => foo), returning foo.
;; Without the fix, the arrow form is taken, which tries to call foo as
;; a procedure and errors.
(test-equal "case datum clause with shadowed =>"
  'F
  (let ((=> (lambda (a b) (list 'app a b))) (foo 'F))
    (case 1 ((1) => foo))))

(test-equal "case else clause with shadowed =>"
  'F
  (let ((=> (lambda (a b) (list 'app a b))) (foo 'F))
    (case 1 (else => foo))))

;; Normal arrow form still works when => is not shadowed
(test-equal "case arrow form unshadowed"
  2
  (case 1 ((1) => (lambda (x) (+ x 1)))))

;; Verify => can be used as a regular procedure call when shadowed
(test-equal "shadowed => as procedure in case body"
  '(called 1)
  (let ((=> (lambda (x) (list 'called x))))
    (case 1 ((1) (=> 1)))))

(let ((runner (test-runner-current)))
  (test-end "case-arrow-shadowing")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
