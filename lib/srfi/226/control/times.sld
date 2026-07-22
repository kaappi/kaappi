;;; SRFI 226 (srfi 226 control times) — minimal time objects
;;;
;;; Only what SRFI 226 itself specifies: an opaque time object, the
;;; current time, and offsetting a time by a number of seconds. This is
;;; much smaller than SRFI 19's calendar/TAI/UTC system — SRFI 226 only
;;; needs enough of a time type for things like a thread-join! deadline.

(define-library (srfi 226 control times)
  (export time? current-time seconds+)
  (import (scheme base) (scheme time))
  (begin

    (define-record-type <srfi-226-time>
      (%make-time seconds)
      time?
      (seconds %time-seconds))

    (define (current-time) (%make-time (current-second)))

    (define (seconds+ time x) (%make-time (+ (%time-seconds time) x)))))
