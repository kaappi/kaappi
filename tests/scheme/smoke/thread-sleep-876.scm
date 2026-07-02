;; Regression test for #876: thread-sleep! must actually sleep

(import (srfi 18))
(define s0 (time->seconds (current-time)))
(thread-sleep! 0.1)
(define s1 (time->seconds (current-time)))
(display (>= (- s1 s0) 0.09))
(newline)
