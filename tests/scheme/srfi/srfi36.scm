(import (scheme base) (scheme write) (srfi 35) (srfi 36))

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
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name) (newline))))

(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name) (newline))))

;;; Type predicates on types
(check-true "&i/o-error is condition type" (condition-type? &i/o-error))
(check-true "&i/o-port-error is condition type" (condition-type? &i/o-port-error))
(check-true "&i/o-filename-error is condition type" (condition-type? &i/o-filename-error))
(check-true "&read-error is condition type" (condition-type? &read-error))

;;; Basic i/o-error
(let ((c (make-condition &i/o-error)))
  (check-true "i/o-error?" (i/o-error? c))
  (check-false "not read-error?" (read-error? c)))

;;; Port error with field
(let ((c (make-condition &i/o-port-error 'port (current-input-port))))
  (check-true "i/o-port-error?" (i/o-port-error? c))
  (check-true "i/o-error? on port-error" (i/o-error? c))
  (check "i/o-error-port" (i/o-error-port c) (current-input-port)))

;;; Read error subtypes
(let ((c (make-condition &i/o-read-error 'port (current-input-port))))
  (check-true "i/o-read-error?" (i/o-read-error? c))
  (check-true "i/o-port-error? on read" (i/o-port-error? c))
  (check-true "i/o-error? on read" (i/o-error? c)))

;;; Write error
(let ((c (make-condition &i/o-write-error 'port (current-output-port))))
  (check-true "i/o-write-error?" (i/o-write-error? c))
  (check-false "not i/o-read-error?" (i/o-read-error? c)))

;;; Closed error
(let ((c (make-condition &i/o-closed-error 'port (current-input-port))))
  (check-true "i/o-closed-error?" (i/o-closed-error? c))
  (check-true "i/o-port-error? on closed" (i/o-port-error? c)))

;;; Filename error with field
(let ((c (make-condition &i/o-filename-error 'filename "/tmp/test.txt")))
  (check-true "i/o-filename-error?" (i/o-filename-error? c))
  (check-true "i/o-error? on filename" (i/o-error? c))
  (check "i/o-error-filename" (i/o-error-filename c) "/tmp/test.txt"))

;;; No-such-file
(let ((c (make-condition &i/o-no-such-file-error 'filename "/missing")))
  (check-true "i/o-no-such-file-error?" (i/o-no-such-file-error? c))
  (check-true "i/o-filename-error? on no-such-file" (i/o-filename-error? c))
  (check "filename on no-such-file" (i/o-error-filename c) "/missing"))

;;; File-already-exists
(let ((c (make-condition &i/o-file-already-exists-error 'filename "/exists")))
  (check-true "i/o-file-already-exists-error?" (i/o-file-already-exists-error? c))
  (check-false "not no-such-file?" (i/o-no-such-file-error? c)))

;;; Protection and read-only
(let ((c (make-condition &i/o-file-is-read-only-error 'filename "/ro")))
  (check-true "i/o-file-is-read-only-error?" (i/o-file-is-read-only-error? c))
  (check-true "i/o-file-protection-error?" (i/o-file-protection-error? c))
  (check-true "i/o-filename-error?" (i/o-filename-error? c)))

;;; Malformed filename
(let ((c (make-condition &i/o-malformed-filename-error 'filename "")))
  (check-true "i/o-malformed-filename-error?" (i/o-malformed-filename-error? c)))

;;; Read error with all fields
(let ((c (make-condition &read-error 'line 10 'column 5 'position 42 'span 3)))
  (check-true "read-error?" (read-error? c))
  (check "read-error-line" (read-error-line c) 10)
  (check "read-error-column" (read-error-column c) 5)
  (check "read-error-position" (read-error-position c) 42)
  (check "read-error-span" (read-error-span c) 3)
  (check-false "not i/o-error?" (i/o-error? c)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 36 tests failed" fail))
