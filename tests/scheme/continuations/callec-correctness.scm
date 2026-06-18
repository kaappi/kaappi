;; call/ec (escape continuation) correctness checks.
;; Note: nested *capture* of an outer continuation while an inner one escapes is
;; a pre-existing limitation of the continuation machinery (call/cc has it too),
;; so these tests exercise escape-only usage, which is what call/ec is for.
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "callec-correctness")

;; 1. Simple escape
(test-eqv "simple escape" 11
  (+ 1 (call/ec (lambda (k) (k 10)))))

;; 2. proc returns normally (no escape)
(test-eqv "proc returns normally" 42
  (call/ec (lambda (k) 42)))

;; 3. Escape out of deep non-tail nesting
(define (sum-to n k)
  (if (= n 0) (k 'done) (+ n (sum-to (- n 1) k))))
(test-eq "deep non-tail escape" 'done
  (call/ec (lambda (k) (sum-to 20 k))))

;; 4. Escape short-circuits surrounding computation
(test-eqv "escape short-circuits" 99
  (call/ec (lambda (k) (* 2 (+ 3 (k 99))))))

;; 5. dynamic-wind after-thunk runs on escape (before/during/after, not 'never)
(define trace '())
(define (note x) (set! trace (cons x trace)))
(call/ec
 (lambda (k)
   (dynamic-wind
     (lambda () (note 'before))
     (lambda () (note 'during) (k 'out) (note 'never))
     (lambda () (note 'after)))))
(test-equal "dynamic-wind ordering" '(before during after)
  (reverse trace))

;; 6. Escape as an early-exit "return" from a recursive search
(define (first-even lst)
  (call/ec
   (lambda (return)
     (let loop ((xs lst))
       (cond ((null? xs) #f)
             ((even? (car xs)) (return (car xs)))
             (else (loop (cdr xs))))))))
(test-eqv "early-exit search" 8
  (first-even '(1 3 5 8 9)))

;; 7. Invoking an escape continuation outside its extent raises an error
(define saved #f)
(call/ec (lambda (k) (set! saved k)))
(test-eq "escape outside extent raises error" 'caught-escape-error
  (guard (exn (#t 'caught-escape-error))
    (saved 'too-late)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callec-correctness")
(if (> %test-fail-count 0) (exit 1))
