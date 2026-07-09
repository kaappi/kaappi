;; Audit tests for src/primitives_srfi18.zig — SRFI-18 threads, mutexes,
;; condition variables, time. Audit campaign Phase 2.1 (#1137).
;; Complements tests/scheme/srfi/srfi18*.scm (basics, cross-thread, races).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (srfi 18))
(import (chibi test))

(test-begin "primitives_srfi18 audit")

;;; --- predicates: correct domain, no crashes on wrong types ---
(test #t (thread? (current-thread)))
(test #f (thread? 42))
(test #f (thread? "thread"))
(test #f (mutex? (current-thread)))
(test #t (mutex? (make-mutex)))
(test #f (mutex? '()))
(test #t (condition-variable? (make-condition-variable)))
(test #f (condition-variable? (make-mutex)))
(test #t (time? (current-time)))
(test #f (time? 3.14))

;;; --- current-thread ---
(test #t (eq? (current-thread) (current-thread)))

;;; --- make-thread / accessors ---
(let ((t (make-thread (lambda () 'r) 'my-name)))
  (test 'my-name (thread-name t))
  (test #t (begin (thread-specific-set! t '(payload)) #t))
  (test '(payload) (thread-specific t)))
;; type errors are catchable, not crashes
(test #t (guard (e (#t #t)) (make-thread 42)))
(test #t (guard (e (#t #t)) (thread-name 42)))
(test #t (guard (e (#t #t)) (thread-specific "x")))
(test #t (guard (e (#t #t)) (thread-specific-set! #f 1)))
(test #t (guard (e (#t #t)) (thread-start! 'not-a-thread)))
(test #t (guard (e (#t #t)) (thread-join! "nope")))
(test #t (guard (e (#t #t)) (thread-terminate! 5)))
(test '() (thread-join! (thread-start! (make-thread list))))

;;; --- thread lifecycle ---
;; starting a thread twice is an error (SRFI-18: thread must be new)
(let ((t (make-thread (lambda () (thread-sleep! 0.2) 'done))))
  (thread-start! t)
  (test #t (guard (e (#t #t)) (thread-start! t) #f))
  (test 'done (thread-join! t)))
;; joining self raises
(test #t (guard (e (#t #t)) (thread-join! (current-thread)) #f))
;; join timeout-val is returned instead of raising; join after completion works
(let ((t (make-thread (lambda () (thread-sleep! 0.5) 'slow-done))))
  (thread-start! t)
  (test 'tv (thread-join! t 0.02 'tv))
  (test 'slow-done (thread-join! t)))
;; join timeout without timeout-val raises join-timeout-exception
(let ((t (make-thread (lambda () (thread-sleep! 0.5) 'x))))
  (thread-start! t)
  (test #t (guard (e (#t (join-timeout-exception? e)))
             (thread-join! t 0.02)
             #f))
  (test 'x (thread-join! t)))

;;; --- thread-sleep! ---
(test #t (begin (thread-sleep! 0) #t))            ; zero: immediate
(test #t (begin (thread-sleep! -1) #t))           ; negative: immediate
(test #t (begin (thread-sleep! 1/100) #t))        ; rational seconds
(test #t (begin (thread-sleep! (seconds->time 0)) #t)) ; past time object
(test #t (guard (e (#t #t)) (thread-sleep! "5"))) ; type error catchable
(test #t (guard (e (#t #t)) (thread-sleep! #f)))

;;; --- mutexes ---
(let ((m (make-mutex 'audit-mutex)))
  (test 'audit-mutex (mutex-name m))
  (test 'not-abandoned (mutex-state m))
  (test #t (begin (mutex-specific-set! m 'ms) #t))
  (test 'ms (mutex-specific m))
  (test #t (mutex-lock! m))
  (test #t (thread? (mutex-state m)))              ; owner is a thread
  (test #t (mutex-unlock! m))
  (test 'not-abandoned (mutex-state m)))
;; unlocking an unlocked mutex is allowed (SRFI-18 places no precondition)
(let ((m (make-mutex)))
  (test #t (mutex-unlock! m)))
;; unnamed mutex has some name value; accessors reject non-mutexes
(test #t (guard (e (#t #t)) (mutex-name 42)))
(test #t (guard (e (#t #t)) (mutex-state "m")))
(test #t (guard (e (#t #t)) (mutex-lock! 'sym)))
(test #t (guard (e (#t #t)) (mutex-unlock! 9)))
(test #t (guard (e (#t #t)) (mutex-specific 9)))
(test #t (guard (e (#t #t)) (mutex-specific-set! 9 1)))
(let ((m (make-mutex)))
  (mutex-lock! m)
  (test #f (mutex-lock! m 0.05)))
(let ((m (make-mutex)))
  (mutex-lock! m #f #f)
  (test 'not-owned (mutex-state m)))

;;; --- condition variables ---
(let ((cv (make-condition-variable 'audit-cv)))
  (test 'audit-cv (condition-variable-name cv))
  (test #t (begin (condition-variable-specific-set! cv 'cs) #t))
  (test 'cs (condition-variable-specific cv))
  ;; signal/broadcast with no waiters are no-ops, not errors
  (test #t (begin (condition-variable-signal! cv) #t))
  (test #t (begin (condition-variable-broadcast! cv) #t)))
(test #t (guard (e (#t #t)) (condition-variable-name 42)))
(test #t (guard (e (#t #t)) (condition-variable-signal! 42)))
(test #t (guard (e (#t #t)) (condition-variable-broadcast! "cv")))
(test #t (guard (e (#t #t)) (condition-variable-specific 1)))
(test #t (guard (e (#t #t)) (condition-variable-specific-set! 1 2)))
(let ((m (make-mutex)) (cv (make-condition-variable)))
  (mutex-lock! m)
  (test #f (mutex-unlock! m cv 0.01)))

;;; --- time ---
(let ((t (seconds->time 123.5)))
  (test #t (time? t))
  (test 123.5 (time->seconds t)))
(test 100.0 (time->seconds (seconds->time 100)))   ; exact input accepted
(test -5.0 (time->seconds (seconds->time -5)))     ; negative allowed
(test #t (> (time->seconds (current-time)) 0))
(test #t (guard (e (#t #t)) (time->seconds 42)))
(test #t (guard (e (#t #t)) (seconds->time "x")))

;;; --- exception predicates: #f on arbitrary values, no crashes ---
(test #f (join-timeout-exception? 42))
(test #f (abandoned-mutex-exception? "x"))
(test #f (terminated-thread-exception? '()))
(test #f (uncaught-exception? #f))
(test #f (join-timeout-exception? (guard (e (#t e)) (error "plain"))))
(test #t (guard (e (#t #t)) (uncaught-exception-reason 42)))
;; uncaught-exception-reason returns the raised object (deep-copied)
(let ((t (make-thread (lambda () (raise 'boom)))))
  (thread-start! t)
  (test 'boom (guard (e ((uncaught-exception? e) (uncaught-exception-reason e)))
                (thread-join! t)
                #f)))

(test-end "primitives_srfi18 audit")
