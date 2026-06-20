(import (scheme base) (scheme write) (kaappi fibers))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- spawn and fiber-join ----
(let ((f (spawn (lambda () 42))))
  (check "spawn and join" (fiber-join f) 42))

(let ((f (spawn (lambda () (+ 10 20 30)))))
  (check "spawn arithmetic" (fiber-join f) 60))

;;; ---- fiber? predicate ----
(let ((f (spawn (lambda () 'ok))))
  (check-true "fiber? on fiber" (fiber? f))
  (fiber-join f))
(check-false "fiber? on number" (fiber? 42))
(check-false "fiber? on string" (fiber? "hello"))
(check-false "fiber? on list" (fiber? '(1 2 3)))

;;; ---- yield ----
(let ((f (spawn (lambda () (yield) 99))))
  (check "yield then return" (fiber-join f) 99))

;;; ---- Multiple fibers ----
(let ((f1 (spawn (lambda () 10)))
      (f2 (spawn (lambda () 20)))
      (f3 (spawn (lambda () 30))))
  (check "multiple fibers sum"
    (+ (fiber-join f1) (fiber-join f2) (fiber-join f3))
    60))

;;; ---- Fibers with closures ----
(let ((x 100))
  (let ((f (spawn (lambda () (+ x 1)))))
    (check "fiber with closure" (fiber-join f) 101)))

;;; ---- Channels ----
(let ((ch (make-channel)))
  (check-true "channel?" (channel? ch))
  (check-false "channel? number" (channel? 42))
  (check-false "channel? string" (channel? "hello")))

(let ((ch (make-channel)))
  (let ((f (spawn (lambda () (channel-send ch 42)))))
    (check "channel-receive" (channel-receive ch) 42)
    (fiber-join f)))

(let ((ch (make-channel)))
  (let ((f (spawn (lambda () (channel-send ch "hello")))))
    (check "channel string" (channel-receive ch) "hello")
    (fiber-join f)))

;;; ---- Channel with multiple messages ----
(let ((ch (make-channel)))
  (let ((f (spawn (lambda ()
                    (channel-send ch 1)
                    (channel-send ch 2)
                    (channel-send ch 3)))))
    (check "channel msg 1" (channel-receive ch) 1)
    (check "channel msg 2" (channel-receive ch) 2)
    (check "channel msg 3" (channel-receive ch) 3)
    (fiber-join f)))

;;; ---- Producer/consumer pattern ----
(let ((ch (make-channel)))
  (let ((producer (spawn (lambda ()
                           (channel-send ch 10)
                           (channel-send ch 20)
                           (channel-send ch 30))))
        (sum 0))
    (set! sum (+ sum (channel-receive ch)))
    (set! sum (+ sum (channel-receive ch)))
    (set! sum (+ sum (channel-receive ch)))
    (fiber-join producer)
    (check "producer/consumer" sum 60)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Fiber coverage tests failed" fail))
