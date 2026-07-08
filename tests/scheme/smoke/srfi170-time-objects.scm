;; Regression test for #1162: posix-time/monotonic-time return SRFI-19 time objects
(import (scheme base) (scheme write) (scheme time) (scheme process-context)
        (srfi 19) (srfi 170) (srfi 64))

(test-begin "srfi170-time-objects")

;; posix-time returns an SRFI-19 time object
(test-assert "posix-time returns time object" (time? (posix-time)))
(test-equal "posix-time type is time-utc" 'time-utc (time-type (posix-time)))
(test-assert "posix-time seconds > epoch" (> (time-second (posix-time)) 1700000000))
(test-assert "posix-time nanoseconds in range"
  (let ((ns (time-nanosecond (posix-time))))
    (and (>= ns 0) (< ns 1000000000))))

;; monotonic-time returns an SRFI-19 time object
(test-assert "monotonic-time returns time object" (time? (monotonic-time)))
(test-equal "monotonic-time type is time-monotonic"
  'time-monotonic (time-type (monotonic-time)))
(test-assert "monotonic-time seconds non-negative" (>= (time-second (monotonic-time)) 0))
(test-assert "monotonic-time nanoseconds in range"
  (let ((ns (time-nanosecond (monotonic-time))))
    (and (>= ns 0) (< ns 1000000000))))

;; SRFI-19 time operations work on posix-time results
(test-assert "time-difference works"
  (let* ((t1 (posix-time))
         (t2 (posix-time))
         (diff (time-difference t2 t1)))
    (>= (time-second diff) 0)))

;; SRFI-19 make-time creates compatible objects
(test-assert "make-time creates time object" (time? (make-time 'time-utc 0 1000)))
(test-equal "make-time second" 1000 (time-second (make-time 'time-utc 500 1000)))
(test-equal "make-time nanosecond" 500 (time-nanosecond (make-time 'time-utc 500 1000)))
(test-equal "make-time type" 'time-utc (time-type (make-time 'time-utc 0 0)))

;; SRFI-19 current-time also returns compatible objects
(test-assert "srfi-19 current-time is time?" (time? (current-time)))
(test-equal "srfi-19 current-time default type" 'time-utc (time-type (current-time)))
(test-equal "srfi-19 current-time monotonic type"
  'time-monotonic (time-type (current-time 'time-monotonic)))

(let ((runner (test-runner-current)))
  (test-end "srfi170-time-objects")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
