;; Audit tests for src/primitives_srfi18.zig — SRFI-18 threads, mutexes,
;; condition variables, time. Audit campaign Phase 2.1 (#1137).
;; Complements tests/scheme/srfi/srfi18*.scm (basics, cross-thread, races).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (srfi 18))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_srfi18 audit")

;;; --- predicates: correct domain, no crashes on wrong types ---
(test-equal #t (thread? (current-thread)))
(test-equal #f (thread? 42))
(test-equal #f (thread? "thread"))
(test-equal #f (mutex? (current-thread)))
(test-equal #t (mutex? (make-mutex)))
(test-equal #f (mutex? '()))
(test-equal #t (condition-variable? (make-condition-variable)))
(test-equal #f (condition-variable? (make-mutex)))
(test-equal #t (time? (current-time)))
(test-equal #f (time? 3.14))

;;; --- current-thread ---
(test-equal #t (eq? (current-thread) (current-thread)))

;;; --- make-thread / accessors ---
(let ((t (make-thread (lambda () 'r) 'my-name)))
  (test-equal 'my-name (thread-name t))
  (test-equal #t (begin (thread-specific-set! t '(payload)) #t))
  (test-equal '(payload) (thread-specific t)))
;; type errors are catchable, not crashes
(test-equal #t (guard (e (#t #t)) (make-thread 42)))
(test-equal #t (guard (e (#t #t)) (thread-name 42)))
(test-equal #t (guard (e (#t #t)) (thread-specific "x")))
(test-equal #t (guard (e (#t #t)) (thread-specific-set! #f 1)))
(test-equal #t (guard (e (#t #t)) (thread-start! 'not-a-thread)))
(test-equal #t (guard (e (#t #t)) (thread-join! "nope")))
(test-equal #t (guard (e (#t #t)) (thread-terminate! 5)))
(test-equal '() (thread-join! (thread-start! (make-thread list))))

;;; --- thread lifecycle ---
;; starting a thread twice is an error (SRFI-18: thread must be new)
(let ((t (make-thread (lambda () (thread-sleep! 0.2) 'done))))
  (thread-start! t)
  (test-equal #t (guard (e (#t #t)) (thread-start! t) #f))
  (test-equal 'done (thread-join! t)))
;; joining self raises
(test-equal #t (guard (e (#t #t)) (thread-join! (current-thread)) #f))
;; join timeout-val is returned instead of raising; join after completion works
(let ((t (make-thread (lambda () (thread-sleep! 0.5) 'slow-done))))
  (thread-start! t)
  (test-equal 'tv (thread-join! t 0.02 'tv))
  (test-equal 'slow-done (thread-join! t)))
;; join timeout without timeout-val raises join-timeout-exception
(let ((t (make-thread (lambda () (thread-sleep! 0.5) 'x))))
  (thread-start! t)
  (test-equal #t (guard (e (#t (join-timeout-exception? e)))
                   (thread-join! t 0.02)
                   #f))
  (test-equal 'x (thread-join! t)))

;;; --- thread-sleep! ---
(test-equal #t (begin (thread-sleep! 0) #t))            ; zero: immediate
(test-equal #t (begin (thread-sleep! -1) #t))           ; negative: immediate
(test-equal #t (begin (thread-sleep! 1/100) #t))        ; rational seconds
(test-equal #t (begin (thread-sleep! (seconds->time 0)) #t)) ; past time object
(test-equal #t (guard (e (#t #t)) (thread-sleep! "5"))) ; type error catchable
(test-equal #t (guard (e (#t #t)) (thread-sleep! #f)))

;;; --- mutexes ---
(let ((m (make-mutex 'audit-mutex)))
  (test-equal 'audit-mutex (mutex-name m))
  (test-equal 'not-abandoned (mutex-state m))
  (test-equal #t (begin (mutex-specific-set! m 'ms) #t))
  (test-equal 'ms (mutex-specific m))
  (test-equal #t (mutex-lock! m))
  (test-equal #t (thread? (mutex-state m)))              ; owner is a thread
  (test-equal #t (mutex-unlock! m))
  (test-equal 'not-abandoned (mutex-state m)))
;; unlocking an unlocked mutex is allowed (SRFI-18 places no precondition)
(let ((m (make-mutex)))
  (test-equal #t (mutex-unlock! m)))
;; unnamed mutex has some name value; accessors reject non-mutexes
(test-equal #t (guard (e (#t #t)) (mutex-name 42)))
(test-equal #t (guard (e (#t #t)) (mutex-state "m")))
(test-equal #t (guard (e (#t #t)) (mutex-lock! 'sym)))
(test-equal #t (guard (e (#t #t)) (mutex-unlock! 9)))
(test-equal #t (guard (e (#t #t)) (mutex-specific 9)))
(test-equal #t (guard (e (#t #t)) (mutex-specific-set! 9 1)))
(let ((m (make-mutex)))
  (mutex-lock! m)
  (test-equal #f (mutex-lock! m 0.05)))
(let ((m (make-mutex)))
  (mutex-lock! m #f #f)
  (test-equal 'not-owned (mutex-state m)))

;;; --- condition variables ---
(let ((cv (make-condition-variable 'audit-cv)))
  (test-equal 'audit-cv (condition-variable-name cv))
  (test-equal #t (begin (condition-variable-specific-set! cv 'cs) #t))
  (test-equal 'cs (condition-variable-specific cv))
  ;; signal/broadcast with no waiters are no-ops, not errors
  (test-equal #t (begin (condition-variable-signal! cv) #t))
  (test-equal #t (begin (condition-variable-broadcast! cv) #t)))
(test-equal #t (guard (e (#t #t)) (condition-variable-name 42)))
(test-equal #t (guard (e (#t #t)) (condition-variable-signal! 42)))
(test-equal #t (guard (e (#t #t)) (condition-variable-broadcast! "cv")))
(test-equal #t (guard (e (#t #t)) (condition-variable-specific 1)))
(test-equal #t (guard (e (#t #t)) (condition-variable-specific-set! 1 2)))
(let ((m (make-mutex)) (cv (make-condition-variable)))
  (mutex-lock! m)
  (test-equal #f (mutex-unlock! m cv 0.01)))

;;; --- time ---
(let ((t (seconds->time 123.5)))
  (test-equal #t (time? t))
  (test-equal 123.5 (time->seconds t)))
(test-equal 100.0 (time->seconds (seconds->time 100)))   ; exact input accepted
(test-equal -5.0 (time->seconds (seconds->time -5)))     ; negative allowed
(test-equal #t (> (time->seconds (current-time)) 0))
(test-equal #t (guard (e (#t #t)) (time->seconds 42)))
(test-equal #t (guard (e (#t #t)) (seconds->time "x")))

;;; --- exception predicates: #f on arbitrary values, no crashes ---
(test-equal #f (join-timeout-exception? 42))
(test-equal #f (abandoned-mutex-exception? "x"))
(test-equal #f (terminated-thread-exception? '()))
(test-equal #f (uncaught-exception? #f))
(test-equal #f (join-timeout-exception? (guard (e (#t e)) (error "plain"))))
(test-equal #t (guard (e (#t #t)) (uncaught-exception-reason 42)))
;; uncaught-exception-reason returns the raised object (deep-copied)
(let ((t (make-thread (lambda () (raise 'boom)))))
  (thread-start! t)
  (test-equal 'boom (guard (e ((uncaught-exception? e) (uncaught-exception-reason e)))
                      (thread-join! t)
                      #f)))

(let ((runner (test-runner-current)))
  (test-end "primitives_srfi18 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
