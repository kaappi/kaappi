;; Regression test for #875: dynamic-wind after-thunk must run exactly once
;; even when the exit is via a continuation (call/ec or call/cc).

(define count 0)

(call-with-current-continuation
  (lambda (exit)
    (dynamic-wind
      (lambda () #f)
      (lambda () (exit 'done))
      (lambda () (set! count (+ count 1))))))

(display (= count 1))
(newline)
