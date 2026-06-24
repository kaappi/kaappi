;; SRFI-18 deep copy rejection tests
;; Verifies that uncopyable types (ports, continuations) produce
;; catchable errors when returned from threads.

(import (srfi 18) (scheme base) (scheme write))

(define pass-count 0)
(define fail-count 0)

(define (check desc ok?)
  (if ok?
    (begin (set! pass-count (+ pass-count 1))
           (display "  pass: ") (display desc) (newline))
    (begin (set! fail-count (+ fail-count 1))
           (display "  FAIL: ") (display desc) (newline))))

;; Thread returning a port should raise an exception on join
(let ((t (make-thread (lambda () (open-input-string "test")))))
  (thread-start! t)
  (check "port return raises exception"
    (guard (e (#t #t))
      (thread-join! t)
      #f)))

;; Thread returning a continuation should raise an exception on join
(let ((t (make-thread (lambda () (call-with-current-continuation (lambda (k) k))))))
  (thread-start! t)
  (check "continuation return raises exception"
    (guard (e (#t #t))
      (thread-join! t)
      #f)))

;; The exception from uncopyable port is catchable and has a message
(let ((t (make-thread (lambda () (open-input-string "hello")))))
  (thread-start! t)
  (check "port error is catchable with descriptive message"
    (guard (e ((error-object? e)
               (string-contains (error-object-message e) "uncopyable")))
      (thread-join! t)
      #f)))

;; Normal values still work fine after rejection tests
(let ((t (make-thread (lambda () (+ 1 2 3)))))
  (thread-start! t)
  (check "normal thread still works" (= (thread-join! t) 6)))

(display pass-count) (display " pass, ")
(display fail-count) (display " fail") (newline)
(when (> fail-count 0)
  (error "SRFI-18 deep copy rejection tests failed"))
