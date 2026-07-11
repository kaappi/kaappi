(import (scheme base) (scheme write) (srfi 18) (kaappi fibers))

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

;;; ---- Thread creation and joining ----
(check-true "thread? current" (thread? (current-thread)))
(check-false "thread? number" (thread? 42))
(check-false "thread? string" (thread? "hello"))

(let ((t (make-thread (lambda () (+ 1 2)))))
  (check-true "thread? make-thread" (thread? t))
  (thread-start! t)
  (check "thread-join! basic" (thread-join! t) 3))

(let ((t (make-thread (lambda () (* 6 7)))))
  (thread-start! t)
  (check "thread-join! multiply" (thread-join! t) 42))

;;; ---- Thread name ----
(let ((t (make-thread (lambda () 'ok) 'my-thread)))
  (check "thread-name" (thread-name t) 'my-thread))

(let ((t (make-thread (lambda () 'ok) "string-name")))
  (check "thread-name string" (thread-name t) "string-name"))

;;; ---- Thread specific ----
(let ((t (make-thread (lambda () 'ok))))
  (thread-specific-set! t 'hello)
  (check "thread-specific" (thread-specific t) 'hello)
  (thread-specific-set! t 42)
  (check "thread-specific overwrite" (thread-specific t) 42))

;;; ---- Thread yield ----
(check-true "thread-yield! returns" (begin (thread-yield!) #t))

;;; ---- Multiple threads ----
(let ((t1 (make-thread (lambda () 10)))
      (t2 (make-thread (lambda () 20)))
      (t3 (make-thread (lambda () 30))))
  (thread-start! t1)
  (thread-start! t2)
  (thread-start! t3)
  (check "3 threads" (+ (thread-join! t1) (thread-join! t2) (thread-join! t3)) 60))

;;; ---- Thread with closures ----
(let ((x 100))
  (let ((t (make-thread (lambda () (+ x 1)))))
    (thread-start! t)
    (check "thread closure" (thread-join! t) 101)))

;;; ---- Thread terminate ----
(let ((t (make-thread (lambda () (let loop () (thread-yield!) (loop))))))
  (thread-start! t)
  (thread-terminate! t)
  (check-true "terminated-thread-exception?"
    (guard (e (#t (terminated-thread-exception? e)))
      (thread-join! t)
      #f)))

;;; ---- Uncaught exception ----
(let ((t (make-thread (lambda () (error "boom" 42)))))
  (thread-start! t)
  (check-true "uncaught-exception?"
    (guard (e (#t (uncaught-exception? e)))
      (thread-join! t)
      #f)))

(let ((t (make-thread (lambda () (error "test-error" 99)))))
  (thread-start! t)
  (check-true "uncaught-exception-reason"
    (guard (e ((uncaught-exception? e)
               (error-object? (uncaught-exception-reason e))))
      (thread-join! t)
      #f)))

;;; ---- thread-join! with timeout ----
;; join with timeout may not be supported; skip for coverage

;;; ---- Mutex basics ----
(check-true "mutex? make-mutex" (mutex? (make-mutex)))
(check-false "mutex? number" (mutex? 99))
(check-false "mutex? string" (mutex? "hello"))

(let ((m (make-mutex 'my-mutex)))
  (check "mutex-name" (mutex-name m) 'my-mutex))

(let ((m (make-mutex)))
  (mutex-specific-set! m 'data)
  (check "mutex-specific" (mutex-specific m) 'data)
  (mutex-specific-set! m 42)
  (check "mutex-specific overwrite" (mutex-specific m) 42))

;;; ---- Mutex state ----
(let ((m (make-mutex)))
  (check "mutex-state unlocked" (mutex-state m) 'not-abandoned))

(let ((m (make-mutex)))
  (mutex-lock! m)
  (check-true "mutex-state locked is thread" (thread? (mutex-state m)))
  (mutex-unlock! m)
  (check "mutex-state after unlock" (mutex-state m) 'not-abandoned))

;;; ---- Mutex lock/unlock ----
(let ((m (make-mutex)))
  (check-true "mutex-lock! returns #t" (mutex-lock! m))
  (mutex-unlock! m))

;;; ---- Mutex contention ----
;; OS threads (thread-start!) run on isolated heaps and cannot share mutexes
;; or condition variables captured by a thread thunk's closure (deep-copying
;; a thunk that closes over one raises "uncopyable type"), so contention is
;; exercised on the same-heap fiber path instead -- matching the pattern in
;; tests/scheme/srfi/srfi18.scm.
(let ((m (make-mutex))
      (result '()))
  (mutex-lock! m)
  (let ((t (spawn
            (lambda ()
              (mutex-lock! m)
              (set! result (cons 'got-lock result))
              (mutex-unlock! m)))))
    (set! result (cons 'main-holds result))
    (mutex-unlock! m)
    (fiber-join t)
    (check-true "mutex contention" (memq 'got-lock result))))

;;; ---- Mutex with timeout ----
;; mutex-lock! with timeout may not be supported; skip for coverage

;;; ---- Condition variable basics ----
(check-true "condition-variable?" (condition-variable? (make-condition-variable)))
(check-false "condition-variable? number" (condition-variable? 42))
(check-false "condition-variable? string" (condition-variable? "hello"))

(let ((cv (make-condition-variable 'my-cv)))
  (check "condition-variable-name" (condition-variable-name cv) 'my-cv))

(let ((cv (make-condition-variable)))
  (condition-variable-specific-set! cv 'cv-data)
  (check "condition-variable-specific" (condition-variable-specific cv) 'cv-data))

;;; ---- Condition variable signal ----
;; Fiber path again -- see the "Mutex contention" note above.
(let ((m (make-mutex))
      (cv (make-condition-variable))
      (ready #f))
  (let ((t (spawn
            (lambda ()
              (mutex-lock! m)
              (set! ready #t)
              (condition-variable-signal! cv)
              (mutex-unlock! m)))))
    (mutex-lock! m)
    (mutex-unlock! m cv)
    (fiber-join t)
    (check-true "cv-signal wakes waiter" ready)))

;;; ---- Condition variable broadcast ----
;; Fiber path again -- see the "Mutex contention" note above. fiber-join on
;; t1 before either fiber has reached the cv wait drives the scheduler (via
;; its own "run something else while target isn't done" loop) far enough
;; for both t1 and t2 to lock m, release it via mutex-unlock!+cv, and park
;; on cv -- exactly the state broadcast! needs to find waiters to wake.
(let ((m (make-mutex))
      (cv (make-condition-variable))
      (count 0))
  (let ((t1 (spawn
             (lambda ()
               (mutex-lock! m)
               (mutex-unlock! m cv)
               (set! count (+ count 1)))))
        (t2 (spawn
             (lambda ()
               (mutex-lock! m)
               (mutex-unlock! m cv)
               (set! count (+ count 1))))))
    (fiber-join t1)
    (condition-variable-broadcast! cv)
    (fiber-join t1)
    (fiber-join t2)
    (check "cv-broadcast wakes all" count 2)))

;;; ---- Time objects ----
(check-true "time? current-time" (time? (current-time)))
(check-false "time? number" (time? 42))
(check-false "time? string" (time? "hello"))

(let ((t (current-time)))
  (check-true "time->seconds number" (number? (time->seconds t)))
  (check-true "time->seconds > 0" (> (time->seconds t) 0)))

(let ((t (seconds->time 100.5)))
  (check-true "seconds->time produces time" (time? t))
  (check "time->seconds roundtrip" (time->seconds t) 100.5))

(let ((t (seconds->time 0)))
  (check "seconds->time zero" (time->seconds t) 0.0))

(let ((t (seconds->time 1000000)))
  (check "seconds->time large" (time->seconds t) 1000000.0))

;;; ---- thread-sleep! ----
(let ((start (time->seconds (current-time))))
  (thread-sleep! 0.01)
  (let ((elapsed (- (time->seconds (current-time)) start)))
    (check-true "thread-sleep! elapsed" (>= elapsed 0.009))))

;;; thread-sleep! with time object
(let ((start (time->seconds (current-time))))
  (thread-sleep! (seconds->time (+ (time->seconds (current-time)) 0.01)))
  (let ((elapsed (- (time->seconds (current-time)) start)))
    (check-true "thread-sleep! with time" (>= elapsed 0.009))))

;;; ---- Exception predicates on non-exceptions ----
(check-false "join-timeout-exception? non" (join-timeout-exception? 42))
(check-false "abandoned-mutex-exception? non" (abandoned-mutex-exception? 42))
(check-false "terminated-thread-exception? non" (terminated-thread-exception? 42))
(check-false "uncaught-exception? non" (uncaught-exception? 42))
(check-false "join-timeout-exception? string" (join-timeout-exception? "hello"))
(check-false "abandoned-mutex-exception? string" (abandoned-mutex-exception? "hello"))

;;; ---- Thread returning complex values ----
(let ((t (make-thread (lambda () '(1 2 3)))))
  (thread-start! t)
  (check "thread returns list" (thread-join! t) '(1 2 3)))

(let ((t (make-thread (lambda () #(a b c)))))
  (thread-start! t)
  (check "thread returns vector" (thread-join! t) #(a b c)))

(let ((t (make-thread (lambda () "hello"))))
  (thread-start! t)
  (check "thread returns string" (thread-join! t) "hello"))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI-18 coverage tests failed" fail))
