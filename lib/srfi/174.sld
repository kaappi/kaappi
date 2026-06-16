(define-library (srfi 174)
  (import (scheme base))
  (export timespec timespec? timespec-seconds timespec-nanoseconds
          timespec=? timespec<? timespec>? timespec<=? timespec>=?)
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
    (define (timespec>=? a b) (not (timespec<? a b)))))
