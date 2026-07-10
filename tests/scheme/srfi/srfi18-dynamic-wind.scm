;; Regression test for #1377: dynamic-wind inside SRFI-18 child threads.
;;
;; Since PR #1374, dynamic-wind is a Scheme closure that manages the wind
;; stack via %push-wind/%pop-wind in its own bytecode. A thread thunk is
;; invoked through callWithArgs, which pushes a returns_to_native frame;
;; when the thunk tail-calls dynamic-wind that frame is reused. The Return
;; opcode's caller-wind cleanup then spuriously unwound the wind record
;; pushed by dynamic-wind's own bytecode as soon as the wound thunk
;; returned, so the subsequent %pop-wind underflowed and the thread died
;; with "uncaught exception in thread".
(import (scheme base) (scheme write) (scheme process-context)
        (scheme lazy) (srfi 18))

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

;; --- dynamic-wind in tail position of the thread thunk (#1377 repro) ---
(let ((t (make-thread (lambda ()
                        (dynamic-wind (lambda () #f)
                                      (lambda () 42)
                                      (lambda () #f))))))
  (thread-start! t)
  (check "dynamic-wind tail in thread thunk" (thread-join! t) 42))

;; --- dynamic-wind in non-tail position of the thread thunk ---
(let ((t (make-thread (lambda ()
                        (let ((r (dynamic-wind (lambda () #f)
                                               (lambda () 42)
                                               (lambda () #f))))
                          (+ r 1))))))
  (thread-start! t)
  (check "dynamic-wind non-tail in thread thunk" (thread-join! t) 43))

;; --- before/after run exactly once each, in order ---
;; The trace is built on the child heap and returned through thread-join!.
(let ((t (make-thread (lambda ()
                        (let ((trace '()))
                          (let ((r (dynamic-wind
                                    (lambda () (set! trace (cons 'before trace)))
                                    (lambda () (set! trace (cons 'during trace)) 'val)
                                    (lambda () (set! trace (cons 'after trace))))))
                            (list r (reverse trace))))))))
  (thread-start! t)
  (check "dynamic-wind before/after order in thread"
         (thread-join! t) '(val (before during after))))

;; --- nested dynamic-wind in a thread ---
(let ((t (make-thread (lambda ()
                        (dynamic-wind
                         (lambda () #f)
                         (lambda ()
                           (dynamic-wind (lambda () #f)
                                         (lambda () 7)
                                         (lambda () #f)))
                         (lambda () #f))))))
  (thread-start! t)
  (check "nested dynamic-wind in thread" (thread-join! t) 7))

;; --- after-thunk runs when the wound thunk raises; join sees the error ---
(let ((t (make-thread (lambda ()
                        (dynamic-wind (lambda () #f)
                                      (lambda () (raise 'boom))
                                      (lambda () #f))))))
  (thread-start! t)
  (check "dynamic-wind raise in thread joins as uncaught-exception"
         (guard (e (#t (if (uncaught-exception? e) 'uncaught 'other)))
           (thread-join! t))
         'uncaught))

;; --- escape continuation out of the wound thunk in a thread ---
(let ((t (make-thread (lambda ()
                        (let ((log '()))
                          (let ((v (call/cc
                                    (lambda (k)
                                      (dynamic-wind
                                       (lambda () (set! log (cons 'b log)))
                                       (lambda () (k 'escaped) 'never)
                                       (lambda () (set! log (cons 'a log))))))))
                            (list v (reverse log))))))))
  (thread-start! t)
  (check "escape from dynamic-wind thunk in thread"
         (thread-join! t) '(escaped (b a))))

;; --- guard + raise through dynamic-wind in a thread ---
(let ((t (make-thread (lambda ()
                        (let ((log '()))
                          (let ((v (guard (e (#t (list 'caught e)))
                                     (dynamic-wind
                                      (lambda () (set! log (cons 'b log)))
                                      (lambda () (raise 'oops))
                                      (lambda () (set! log (cons 'a log)))))))
                            (list v (reverse log))))))))
  (thread-start! t)
  (check "guard+raise through dynamic-wind in thread"
         (thread-join! t) '((caught oops) (b a))))

;; --- parameterize (compiles to dynamic-wind) in a thread ---
(define p (make-parameter 1))
(let ((t (make-thread (lambda () (parameterize ((p 5)) (p))))))
  (thread-start! t)
  (check "parameterize in thread" (thread-join! t) 5))

;; --- force (uses dynamic-wind internally) in a thread ---
(let ((t (make-thread (lambda () (force (delay (* 6 7)))))))
  (thread-start! t)
  (check "force in thread" (thread-join! t) 42))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
