;; Regression test for issue #639: tail call with args passing pointer
;; to caller's stack alloca, corrupting arguments in native backend.
;;
;; Must produce the same output when run via interpreter and native backend.

(define (add3 a b c) (+ a b c))
(display (= (add3 10 20 30) 60))
(newline)

(define (sum5 a b c d e) (+ a b c d e))
(display (= (sum5 1 2 3 4 5) 15))
(newline)

(define (forward a b c) (add3 a b c))
(display (= (forward 100 200 300) 600))
(newline)
