;; SRFI-174 (POSIX timespecs) conformance tests — audit Phase 3.4
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi174.scm

(import (scheme base) (srfi 174) (chibi test))

(test-begin "srfi-174")

;;; --- construction and accessors ---
(define t1 (timespec 5 500000000))
(test #t (timespec? t1))
(test #f (timespec? 5))
(test #f (timespec? '(5 . 500000000)))
(test 5 (timespec-seconds t1))
(test 500000000 (timespec-nanoseconds t1))

;; negative seconds are legal (time before the epoch)
(define neg (timespec -2 750000000))
(test -2 (timespec-seconds neg))
(test 750000000 (timespec-nanoseconds neg))

;;; --- equality ---
(test #t (timespec=? (timespec 1 2) (timespec 1 2)))
(test #f (timespec=? (timespec 1 2) (timespec 1 3)))
(test #f (timespec=? (timespec 1 2) (timespec 2 2)))

;;; --- ordering ---
(test #t (timespec<? (timespec 1 0) (timespec 2 0)))
(test #t (timespec<? (timespec 1 100) (timespec 1 200)))
(test #f (timespec<? (timespec 1 200) (timespec 1 100)))
(test #f (timespec<? (timespec 1 0) (timespec 1 0)))
(test #t (timespec<? (timespec -2 0) (timespec 1 0)))
(test #t (timespec>? (timespec 2 0) (timespec 1 999999999)))
(test #t (timespec<=? (timespec 1 5) (timespec 1 5)))
(test #t (timespec>=? (timespec 1 5) (timespec 1 5)))
(test #f (timespec>=? (timespec 0 5) (timespec 1 5)))

;;; --- conversions and hashing ---
(test 1.5 (timespec->inexact (timespec 1 500000000)))
(test 0.0 (timespec->inexact (timespec 0 0)))
(test #t (timespec=? (timespec 1 500000000) (inexact->timespec 1.5)))
(test #t (timespec=? (timespec 0 0) (inexact->timespec 0.0)))
(test #t (timespec=? (timespec -2 750000000) (inexact->timespec -1.25)))
(test -1.25 (timespec->inexact (timespec -2 750000000)))
(test #t (exact-integer? (timespec-hash (timespec 1 2))))
(test #t (>= (timespec-hash (timespec 1 2)) 0))
(test (timespec-hash (timespec 3 4)) (timespec-hash (timespec 3 4)))

(test-end "srfi-174")
