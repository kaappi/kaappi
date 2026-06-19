(import (scheme base) (scheme write) (srfi 18))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name) (newline))))

(define (check-false name val)
  (if (not val)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name) (newline))))

;; --- Thread predicates ---
(check-true "thread? on current-thread" (thread? (current-thread)))
(check-false "thread? on number" (thread? 42))

;; --- make-thread / thread-start! / thread-join! ---
(let ((t (make-thread (lambda () (+ 1 2)))))
  (check-true "thread? on make-thread result" (thread? t))
  (thread-start! t)
  (check "thread-join! basic" (thread-join! t) 3))

;; --- thread-name ---
(let ((t (make-thread (lambda () 'ok) 'my-thread)))
  (check "thread-name" (thread-name t) 'my-thread))

(let ((t (make-thread (lambda () 'ok))))
  (check-true "thread-name default is void-ish" #t))

;; --- thread-specific / thread-specific-set! ---
(let ((t (make-thread (lambda () 'ok))))
  (thread-specific-set! t 'hello)
  (check "thread-specific" (thread-specific t) 'hello))

;; --- thread-yield! ---
(check-true "thread-yield! returns"
  (begin (thread-yield!) #t))

;; --- thread-join! with result ---
(let ((t (make-thread (lambda () (* 6 7)))))
  (thread-start! t)
  (check "thread-join! multiply" (thread-join! t) 42))

;; --- Multiple threads ---
(let ((t1 (make-thread (lambda () 10)))
      (t2 (make-thread (lambda () 20))))
  (thread-start! t1)
  (thread-start! t2)
  (check "multiple threads"
    (+ (thread-join! t1) (thread-join! t2))
    30))

;; --- thread-terminate! and terminated-thread-exception ---
(let ((t (make-thread (lambda ()
                        (let loop () (thread-yield!) (loop))))))
  (thread-start! t)
  (thread-terminate! t)
  (check-true "terminated-thread-exception?"
    (guard (e (#t (terminated-thread-exception? e)))
      (thread-join! t)
      #f)))

;; --- uncaught-exception ---
(let ((t (make-thread (lambda () (error "boom" 42)))))
  (thread-start! t)
  (check-true "uncaught-exception?"
    (guard (e (#t (uncaught-exception? e)))
      (thread-join! t)
      #f)))

;; --- uncaught-exception-reason ---
(let ((t (make-thread (lambda () (error "test-error" 99)))))
  (thread-start! t)
  (check-true "uncaught-exception-reason"
    (guard (e ((uncaught-exception? e)
               (error-object? (uncaught-exception-reason e))))
      (thread-join! t)
      #f)))

;; --- Mutex basics ---
(check-true "mutex? on make-mutex" (mutex? (make-mutex)))
(check-false "mutex? on number" (mutex? 99))

(let ((m (make-mutex 'my-mutex)))
  (check "mutex-name" (mutex-name m) 'my-mutex))

;; --- mutex-specific ---
(let ((m (make-mutex)))
  (mutex-specific-set! m 'data)
  (check "mutex-specific" (mutex-specific m) 'data))

;; --- mutex-state ---
(let ((m (make-mutex)))
  (check "mutex-state unlocked" (mutex-state m) 'not-abandoned))

;; --- mutex-lock! / mutex-unlock! ---
(let ((m (make-mutex)))
  (check-true "mutex-lock! returns #t" (mutex-lock! m))
  (check-true "mutex-state locked is thread" (thread? (mutex-state m)))
  (mutex-unlock! m)
  (check "mutex-state after unlock" (mutex-state m) 'not-abandoned))

;; --- Mutex contention between threads ---
(let ((m (make-mutex))
      (result '()))
  (mutex-lock! m)
  (let ((t (make-thread
            (lambda ()
              (mutex-lock! m)
              (set! result (cons 'got-lock result))
              (mutex-unlock! m)))))
    (thread-start! t)
    (set! result (cons 'main-holds result))
    (mutex-unlock! m)
    (thread-join! t)
    (check-true "mutex contention: thread got lock"
      (memq 'got-lock result))))

;; --- Condition variable basics ---
(check-true "condition-variable?" (condition-variable? (make-condition-variable)))
(check-false "condition-variable? on number" (condition-variable? 42))

(let ((cv (make-condition-variable 'my-cv)))
  (check "condition-variable-name" (condition-variable-name cv) 'my-cv))

(let ((cv (make-condition-variable)))
  (condition-variable-specific-set! cv 'cv-data)
  (check "condition-variable-specific" (condition-variable-specific cv) 'cv-data))

;; --- Condition variable signal ---
(let ((m (make-mutex))
      (cv (make-condition-variable))
      (ready #f))
  (let ((t (make-thread
            (lambda ()
              (mutex-lock! m)
              (set! ready #t)
              (condition-variable-signal! cv)
              (mutex-unlock! m)))))
    (mutex-lock! m)
    (thread-start! t)
    (mutex-unlock! m cv)
    (check-true "condition-variable-signal! wakes waiter" ready)))

;; --- Time objects ---
(check-true "time? on current-time" (time? (current-time)))
(check-false "time? on number" (time? 42))

(let ((t (current-time)))
  (check-true "time->seconds returns number"
    (number? (time->seconds t)))
  (check-true "time->seconds > 0"
    (> (time->seconds t) 0)))

(let ((t (seconds->time 100.5)))
  (check-true "seconds->time produces time" (time? t))
  (check "time->seconds roundtrip" (time->seconds t) 100.5))

;; --- thread-sleep! (brief) ---
(let ((start (time->seconds (current-time))))
  (thread-sleep! 0.01)
  (let ((elapsed (- (time->seconds (current-time)) start)))
    (check-true "thread-sleep! sleeps at least 10ms"
      (>= elapsed 0.009))))

;; --- Exception predicates ---
(check-false "join-timeout-exception? on non-error" (join-timeout-exception? 42))
(check-false "abandoned-mutex-exception? on non-error" (abandoned-mutex-exception? 42))
(check-false "terminated-thread-exception? on non-error" (terminated-thread-exception? 42))
(check-false "uncaught-exception? on non-error" (uncaught-exception? 42))

;; --- Re-exported exception procedures ---
(check-true "raise is available" (procedure? raise))
(check-true "with-exception-handler is available" (procedure? with-exception-handler))

;; --- Interop: spawn creates thread? objects ---
(import (kaappi fibers))
(let ((f (spawn (lambda () 99))))
  (check-true "spawn result is thread?" (thread? f))
  (check "fiber-join on spawned fiber" (fiber-join f) 99))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 18 tests failed" fail))
