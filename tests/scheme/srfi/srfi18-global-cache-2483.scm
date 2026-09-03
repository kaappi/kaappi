;; Regression test for kaappi#2483: a child OS thread's per-function global
;; caches must be invalidated by the ROOT's rebindings, not only by its own.
;;
;; The globals generation counter used to be a per-VM field that
;; VM.initForThread neither copied nor shared, so a child that had cached a
;; global kept calling the old binding after the root redefined it -- and a
;; guard_builtin (kaappi#2469) kept its fast path after the root redefined the
;; builtin, because the cached value still matched the pristine primitive.
;;
;; The handoff is ordered through a mutex and two condition variables shared
;; as globals (the supported way to share sync primitives across OS threads):
;; the child provably fills its caches BEFORE the root rebinds and re-reads
;; AFTER. Every wait has a timeout so a lost wakeup fails instead of hanging.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18))

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

(define m (make-mutex))
(define cv-cached (make-condition-variable))
(define cv-rebound (make-condition-variable))

(define (f) 'first)

(define (child)
  ;; call_global caches f; guard_builtin caches the pristine apply.
  (let ((f-before (f))
        (apply-before (apply + (list 1 2))))
    (mutex-lock! m)
    (condition-variable-signal! cv-cached)
    ;; Atomically release m and wait for the root's rebinding.
    (mutex-unlock! m cv-rebound 60)
    (list f-before apply-before (f) (apply + (list 1 2)))))

(define t (make-thread child))

(let ()
  (mutex-lock! m)
  (thread-start! t)
  ;; Blocks until the child has filled its caches: the child cannot signal
  ;; before it holds m, which this wait is what releases.
  (check "root woke for the child's cached signal (not a timeout)"
    (mutex-unlock! m cv-cached 60) #t))

;; The child has cached both bindings and is now parked on (or about to park
;; on) cv-rebound; it re-reads only after the signal below.
(define (f) 'second)
(define (apply proc args) 'user-apply)

(let ()
  ;; Reacquire m: the child releases it only by entering its own wait, so
  ;; once this returns the child is enqueued on cv-rebound -- no lost wakeup.
  (mutex-lock! m)
  (condition-variable-signal! cv-rebound)
  (mutex-unlock! m)
  (check "child re-reads a global rebound by the root (call_global) and a builtin rebound by the root (guard_builtin)"
    (thread-join! t 60 'join-timeout)
    '(first 3 second user-apply)))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
