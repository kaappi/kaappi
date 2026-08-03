;; Regression test for #870: full continuation restore misread as escape
;; by callThunk — wind_count underflow panic when invoked inside dynamic-wind.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "continuation-wind-870")

(define (main)
  (let ((k #f) (done (vector #f)))
    (define (deep n)
      (if (= n 0)
          (call/cc (lambda (c) (set! k c) 0))
          (+ 1 (deep (- n 1)))))
    (deep 5)
    (if (not (vector-ref done 0))
        (begin
          (vector-set! done 0 #t)
          (dynamic-wind
            (lambda () #f)
            (lambda () (k 0))
            (lambda () #f))))
    'ok))

(test-equal "re-entering a full continuation from inside dynamic-wind" 'ok (main))

(let ((runner (test-runner-current)))
  (test-end "continuation-wind-870")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
