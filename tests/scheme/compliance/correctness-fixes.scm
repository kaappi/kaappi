;;; Regression tests for correctness fixes
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "correctness-fixes")

;; --- call-with-values arity validation ---
(test-group "call-with-values arity"
  (test-equal "single value to 1-arg consumer"
    42
    (call-with-values (lambda () 42) (lambda (x) x)))

  (test-equal "single value to variadic consumer"
    '(42)
    (call-with-values (lambda () 42) list))

  (test-equal "multi value to multi-arg consumer"
    '(1 2 3)
    (call-with-values (lambda () (values 1 2 3)) list))

  (test-equal "zero values to zero-arg consumer"
    99
    (call-with-values (lambda () (values)) (lambda () 99)))

  ;; Arity mismatch: single value to 2-arg consumer should raise an error
  (test-assert "single value to 2-arg consumer raises error"
    (guard (e (#t #t))
      (call-with-values (lambda () 42) (lambda (x y) (+ x y)))
      #f)))

;; --- parameterize: value expressions evaluated once ---
(define p (make-parameter 0))

(test-eqv "basic parameterize"
  42
  (parameterize ((p 42)) (p)))

;; Value expression evaluated only once
(let ((count 0))
  (parameterize ((p (begin (set! count (+ count 1)) count)))
    'done)
  (test-eqv "value expression evaluated once" 1 count))

;; Parameterize restores old value
(parameterize ((p 0))
  (test-eqv "before parameterize" 0 (p))
  (parameterize ((p 99))
    (test-eqv "inside parameterize" 99 (p)))
  (test-eqv "after parameterize" 0 (p)))

;; Parameterize with converter
(let ((cp (make-parameter 0 (lambda (x) (* x 2)))))
  (test-eqv "converter applied"
    20
    (parameterize ((cp 10)) (cp))))

;; --- parameterize + continuation interaction ---
(define p2 (make-parameter 'initial))

;; Parameter value correct inside parameterize with call/cc
(test-equal "parameter correct inside parameterize"
  'inside
  (parameterize ((p2 'inside))
    (call-with-current-continuation
      (lambda (c) (p2)))))

;; Continuation captured inside parameterize restores parameter on exit
(test-equal "continuation restores parameter on exit"
  'initial
  (let ((k #f))
    (parameterize ((p2 'inside))
      (call-with-current-continuation
        (lambda (c) (set! k c) 'inside)))
    (p2)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "correctness-fixes")
(if (> %test-fail-count 0) (exit 1))
