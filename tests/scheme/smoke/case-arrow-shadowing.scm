;; Regression test for #52: case must respect lexical shadowing of =>

(import (scheme base) (scheme write))

(define (test name expected actual)
  (if (equal? expected actual)
    (begin (display "PASS: ") (display name) (newline))
    (begin (display "FAIL: ") (display name)
           (display " expected=") (write expected)
           (display " actual=") (write actual) (newline))))

;; When => is locally bound, case should NOT treat it as the arrow keyword.
;; The clause body (=> foo) compiles as (begin => foo), returning foo.
;; Without the fix, the arrow form is taken, which tries to call foo as
;; a procedure and errors.
(test "case datum clause with shadowed =>"
  'F
  (let ((=> (lambda (a b) (list 'app a b))) (foo 'F))
    (case 1 ((1) => foo))))

(test "case else clause with shadowed =>"
  'F
  (let ((=> (lambda (a b) (list 'app a b))) (foo 'F))
    (case 1 (else => foo))))

;; Normal arrow form still works when => is not shadowed
(test "case arrow form unshadowed"
  2
  (case 1 ((1) => (lambda (x) (+ x 1)))))

;; Verify => can be used as a regular procedure call when shadowed
(test "shadowed => as procedure in case body"
  '(called 1)
  (let ((=> (lambda (x) (list 'called x))))
    (case 1 ((1) (=> 1)))))
