;; Regression test for #642: Mutex.abandoned is never set to true
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

;; Test 1: properly unlocked mutex is NOT abandoned
(let ((m (make-mutex 'no-abandon-test)))
  (mutex-lock! m)
  (mutex-unlock! m)
  (check "mutex-state after proper unlock" (mutex-state m) 'not-abandoned))

;; Test 2: never-locked mutex is not abandoned
(let ((m (make-mutex 'never-locked)))
  (check "mutex-state never locked" (mutex-state m) 'not-abandoned))

;; Test 3: thread-terminate! on current thread abandons the held mutex
;; Note: thread-terminate! on current thread sets vm.yielded which
;; causes a runtime error on the next dispatch cycle, so we can only
;; verify one check after the terminate call.
(let ((m (make-mutex 'abandon-test)))
  (mutex-lock! m)
  (check-true "mutex locked before terminate" (thread? (mutex-state m)))
  (thread-terminate! (current-thread))
  (check "mutex abandoned after thread-terminate!" (mutex-state m) 'abandoned))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "abandoned mutex tests failed" fail))
