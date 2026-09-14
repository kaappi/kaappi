(define-library (srfi 174)
  (import (scheme base))
  (export timespec timespec? timespec-seconds timespec-nanoseconds
          timespec=? timespec<? timespec>? timespec<=? timespec>=?
          timespec->inexact inexact->timespec timespec-hash)
  (begin
    (define-record-type <timespec>
      (timespec seconds nanoseconds)
      timespec?
      (seconds timespec-seconds)
      (nanoseconds timespec-nanoseconds))

    (define (timespec=? a b)
      (and (= (timespec-seconds a) (timespec-seconds b))
           (= (timespec-nanoseconds a) (timespec-nanoseconds b))))

    (define (timespec<? a b)
      (or (< (timespec-seconds a) (timespec-seconds b))
          (and (= (timespec-seconds a) (timespec-seconds b))
               (< (timespec-nanoseconds a) (timespec-nanoseconds b)))))

    (define (timespec>? a b) (timespec<? b a))
    (define (timespec<=? a b) (not (timespec>? a b)))
    (define (timespec>=? a b) (not (timespec<? a b)))

    (define (timespec->inexact ts)
      (+ (inexact (timespec-seconds ts))
         (/ (inexact (timespec-nanoseconds ts)) 1e9)))

    (define (inexact->timespec x)
      (let* ((s (exact (floor x)))
             (ns (exact (truncate (* (- x s) 1e9)))))
        (timespec s ns)))

    (define (timespec-hash ts)
      (let ((s (timespec-seconds ts))
            (ns (timespec-nanoseconds ts)))
        (abs (+ (* s 1000000007) ns))))))
