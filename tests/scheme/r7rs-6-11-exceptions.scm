(test-begin "6.11 Exceptions")

(test 65
    (with-exception-handler
     (lambda (con) 42)
     (lambda ()
       (+ (raise-continuable "should be a number")
          23))))

(test #t
    (error-object? (guard (exn (else exn)) (error "BOOM!" 1 2 3))))
(test "BOOM!"
    (error-object-message (guard (exn (else exn)) (error "BOOM!" 1 2 3))))
(test '(1 2 3)
    (error-object-irritants (guard (exn (else exn)) (error "BOOM!" 1 2 3))))

(test #f
    (file-error? (guard (exn (else exn)) (error "BOOM!"))))
(test #t
    (file-error? (guard (exn (else exn)) (open-input-file " no such file "))))

(test #f
    (read-error? (guard (exn (else exn)) (error "BOOM!"))))
(test #t
    (read-error? (guard (exn (else exn)) (read (open-input-string ")")))))
(test #t
    (read-error? (guard (exn (else exn)) (read (open-input-string "\"")))))

(define something-went-wrong #f)
(define (test-exception-handler-1 v)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
      (lambda (x)
        (set! something-went-wrong (list "condition: " x))
        (k 'exception))
      (lambda ()
        (+ 1 (if (> v 0) (+ v 100) (raise 'an-error))))))))
(test 106 (test-exception-handler-1 5))
(test #f something-went-wrong)
(test 'exception (test-exception-handler-1 -1))
(test '("condition: " an-error) something-went-wrong)

(set! something-went-wrong #f)
(define (test-exception-handler-2 v)
  (guard (ex (else 'caught-another-exception))
    (with-exception-handler
     (lambda (x)
       (set! something-went-wrong #t)
       (list "exception:" x))
     (lambda ()
       (+ 1 (if (> v 0) (+ v 100) (raise 'an-error)))))))
(test 106 (test-exception-handler-2 5))
(test #f something-went-wrong)
(test 'caught-another-exception (test-exception-handler-2 -1))
(test #t something-went-wrong)

;; Based on an example from R6RS-lib section 7.1 Exceptions.
;; R7RS section 6.11 Exceptions has a simplified version.
(let* ((out (open-output-string))
       (value (with-exception-handler
               (lambda (con)
                 (cond
                  ((not (list? con))
                   (raise con))
                  ((list? con)
                   (display (car con) out))
                  (else
                   (display "a warning has been issued" out)))
                 42)
               (lambda ()
                 (+ (raise-continuable
                     (list "should be a number"))
                    23)))))
  (test "should be a number" (get-output-string out))
  (test 65 value))

;; From SRFI-34 "Examples" section - #3
(define (test-exception-handler-3 v out)
  (guard (condition
          (else
           (display "condition: " out)
           (write condition out)
           (display #\! out)
           'exception))
         (+ 1 (if (= v 0) (raise 'an-error) (/ 10 v)))))
(let* ((out (open-output-string))
       (value (test-exception-handler-3 0 out)))
  (test 'exception value)
  (test "condition: an-error!" (get-output-string out)))

(define (test-exception-handler-4 v out)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
      (lambda (x)
        (display "reraised " out)
        (write x out) (display #\! out)
        (k 'zero))
      (lambda ()
        (guard (condition
                ((positive? condition)
                 'positive)
                ((negative? condition)
                 'negative))
          (raise v)))))))

;; From SRFI-34 "Examples" section - #5
(let* ((out (open-output-string))
       (value (test-exception-handler-4 1 out)))
  (test "" (get-output-string out))
  (test 'positive value))
;; From SRFI-34 "Examples" section - #6
(let* ((out (open-output-string))
       (value (test-exception-handler-4 -1 out)))
  (test "" (get-output-string out))
  (test 'negative value))
;; From SRFI-34 "Examples" section - #7
(let* ((out (open-output-string))
       (value (test-exception-handler-4 0 out)))
  (test "reraised 0!" (get-output-string out))
  (test 'zero value))

;; From SRFI-34 "Examples" section - #8
(test 42
    (guard (condition
            ((assq 'a condition) => cdr)
            ((assq 'b condition)))
      (raise (list (cons 'a 42)))))

;; From SRFI-34 "Examples" section - #9
(test '(b . 23)
    (guard (condition
            ((assq 'a condition) => cdr)
            ((assq 'b condition)))
      (raise (list (cons 'b 23)))))

(test 'caught-d
    (guard (condition
            ((assq 'c condition) 'caught-c)
            ((assq 'd condition) 'caught-d))
      (list
       (sqrt 8)
       (guard (condition
               ((assq 'a condition) => cdr)
               ((assq 'b condition)))
         (raise (list (cons 'd 24)))))))

(test-end)
