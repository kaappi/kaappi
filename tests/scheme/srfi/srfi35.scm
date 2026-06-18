;;; SRFI 35 (Conditions) conformance tests

(import (scheme base) (scheme process-context) (srfi 35))

(define failures 0)
(define (check name got expected)
  (if (equal? got expected)
      (begin (display "  PASS ") (display name) (newline))
      (begin (display "  FAIL ") (display name)
             (display " got: ") (display got)
             (display " expected: ") (display expected)
             (newline)
             (set! failures (+ failures 1)))))

;; Root condition type
(check "condition-type? &condition" (condition-type? &condition) #t)
(check "condition-type-name" (condition-type-name &condition) '&condition)

;; Standard hierarchy
(check "condition-subtype? &message" (condition-subtype? &message &condition) #t)
(check "condition-subtype? &serious" (condition-subtype? &serious &condition) #t)
(check "condition-subtype? &error" (condition-subtype? &error &serious) #t)
(check "condition-subtype? &error->&condition" (condition-subtype? &error &condition) #t)
(check "not subtype message/serious" (condition-subtype? &message &serious) #f)

;; make-condition
(let ((c (make-condition &message 'message "hello")))
  (check "condition?" (condition? c) #t)
  (check "condition-message" (condition-message c) "hello")
  (check "has-type &message" (condition-has-type? c &message) #t)
  (check "has-type &condition" (condition-has-type? c &condition) #t)
  (check "not has-type &error" (condition-has-type? c &error) #f))

;; make-condition &error (no fields)
(let ((c (make-condition &error)))
  (check "error condition?" (condition? c) #t)
  (check "error has-type &error" (condition-has-type? c &error) #t)
  (check "error has-type &serious" (condition-has-type? c &serious) #t))

;; define-condition-type
(define-condition-type &my-error &error
  my-error?
  (info my-error-info))

(check "custom type is condition-type" (condition-type? &my-error) #t)
(check "custom subtype" (condition-subtype? &my-error &error) #t)

(let ((c (make-condition &my-error 'info 42)))
  (check "custom predicate" (my-error? c) #t)
  (check "custom accessor" (my-error-info c) 42)
  (check "custom has-type &error" (condition-has-type? c &error) #t)
  (check "custom has-type &serious" (condition-has-type? c &serious) #t))

;; Compound conditions
(let* ((c1 (make-condition &message 'message "oops"))
       (c2 (make-condition &error))
       (cc (make-compound-condition c1 c2)))
  (check "compound has &message" (condition-has-type? cc &message) #t)
  (check "compound has &error" (condition-has-type? cc &error) #t)
  (check "compound message" (condition-message cc) "oops"))

;; condition syntax
(let ((c (condition (&message (message "test msg")))))
  (check "condition syntax" (condition-message c) "test msg"))

;; extract-condition
(let* ((c (make-condition &my-error 'info 99))
       (e (extract-condition c &error)))
  (check "extract-condition" (condition-has-type? e &error) #t))

(if (> failures 0) (exit 1))
