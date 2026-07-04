;; Regression test for issue #1035:
;; (define f (lambda ...)) must compile self-recursive tail calls as
;; self_tail_call (a loop), not generic tail_call.

;; Without the optimization, 100k recursions would overflow the stack.
(define count-down
  (lambda (n acc)
    (if (= n 0)
        acc
        (count-down (- n 1) (+ acc 1)))))

(define result (count-down 100000 0))
(unless (= result 100000)
  (error "bare-lambda self-tail-call failed" result))

(display "OK")
(newline)
