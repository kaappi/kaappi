(define-library (srfi 78)
  (import (scheme base) (scheme write) (scheme process-context) (srfi 42))
  (export check check-ec check-report check-set-mode!
          check-reset! check-passed?
          check-failed?)
  (begin

    (define %pass 0)
    (define %fail 0)
    (define %mode 'report)
    (define %first-fail #f)

    (define (check-reset!)
      (set! %pass 0)
      (set! %fail 0)
      (set! %first-fail #f))

    (define (check-passed? expected-count)
      (and (= %fail 0) (= %pass expected-count)))

    (define (check-failed?) %fail)

    (define (check-set-mode! mode)
      (unless (memq mode '(off summary report-failed report))
        (error "check-set-mode!: invalid mode" mode))
      (set! %mode mode))

    (define (%report-pass name actual)
      (when (eq? %mode 'report)
        (display "(") (display %pass) (display ") ")
        (write name) (display " => ")
        (write actual) (display " ; correct")
        (newline)))

    (define (%report-fail name actual expected)
      (when (or (eq? %mode 'report) (eq? %mode 'report-failed))
        (display "(") (display (+ %pass %fail)) (display ") ")
        (write name) (display " => ")
        (write actual) (display " ; *** WRONG ***")
        (display " expected: ") (write expected)
        (newline))
      (when (not %first-fail)
        (set! %first-fail (list name actual expected))))

    (define-syntax check
      (syntax-rules (=>)
        ((_ expr => expected)
         (check-proc 'expr (lambda () expr) expected))
        ((_ expr (=> equal) expected)
         (check-proc-equal 'expr (lambda () expr) expected equal))))

    (define (check-proc name thunk expected)
      (unless (eq? %mode 'off)
        (let ((actual (thunk)))
          (if (equal? actual expected)
              (begin
                (set! %pass (+ %pass 1))
                (%report-pass name actual))
              (begin
                (set! %fail (+ %fail 1))
                (%report-fail name actual expected))))))

    (define (check-proc-equal name thunk expected equal)
      (unless (eq? %mode 'off)
        (let ((actual (thunk)))
          (if (equal actual expected)
              (begin
                (set! %pass (+ %pass 1))
                (%report-pass name actual))
              (begin
                (set! %fail (+ %fail 1))
                (%report-fail name actual expected))))))

    (define-syntax check-ec
      (syntax-rules (=>)
        ((_ expr => expected)
         (check expr => expected))
        ((_ expr (=> equal) expected)
         (check expr (=> equal) expected))
        ((_ qualifier expr => expected)
         (check-ec-run 'expr
           (lambda (escape)
             (do-ec qualifier
               (let ((actual expr) (exp expected))
                 (when (not (equal? actual exp))
                   (escape (list actual exp))))))
           ))
        ((_ qualifier expr (=> equal) expected)
         (check-ec-run 'expr
           (lambda (escape)
             (let ((eq-fn equal))
               (do-ec qualifier
                 (let ((actual expr) (exp expected))
                   (when (not (eq-fn actual exp))
                     (escape (list actual exp)))))))))
        ((_ qualifier expr => expected (arg ...))
         (check-ec-run 'expr
           (lambda (escape)
             (do-ec qualifier
               (let ((actual expr) (exp expected))
                 (when (not (equal? actual exp))
                   (escape (list actual exp))))))))
        ((_ qualifier expr (=> equal) expected (arg ...))
         (check-ec-run 'expr
           (lambda (escape)
             (let ((eq-fn equal))
               (do-ec qualifier
                 (let ((actual expr) (exp expected))
                   (when (not (eq-fn actual exp))
                     (escape (list actual exp)))))))))))

    (define (check-ec-run name body-fn)
      (unless (eq? %mode 'off)
        (let ((result (call-with-current-continuation
                        (lambda (escape)
                          (body-fn escape)
                          #t))))
          (if (eq? result #t)
              (begin
                (set! %pass (+ %pass 1))
                (%report-pass name 'ok))
              (begin
                (set! %fail (+ %fail 1))
                (%report-fail name (car result) (cadr result)))))))

    (define (check-report)
      (newline)
      (display "Checks: ")
      (display (+ %pass %fail))
      (display " total, ")
      (display %pass) (display " passed, ")
      (display %fail) (display " failed.")
      (newline)
      (when %first-fail
        (display "First failure: ")
        (write (car %first-fail))
        (display " => ")
        (write (cadr %first-fail))
        (display " ; expected: ")
        (write (car (cddr %first-fail)))
        (newline))
      (when (> %fail 0) (exit 1)))))
