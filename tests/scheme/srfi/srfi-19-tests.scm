(import (scheme base) (scheme write) (srfi 19))

(define pass 0)
(define fail 0)

(define-syntax check
  (syntax-rules (=>)
    ((_ expr => expected)
     (let ((result expr) (exp expected))
       (if (equal? result exp)
           (set! pass (+ pass 1))
           (begin
             (set! fail (+ fail 1))
             (display "FAIL: ") (write 'expr)
             (display " => ") (write result)
             (display ", expected ") (write exp)
             (newline)))))))

(define-syntax check-true
  (syntax-rules ()
    ((_ expr)
     (if expr (set! pass (+ pass 1))
         (begin (set! fail (+ fail 1))
                (display "FAIL: ") (write 'expr)
                (display " is false\n"))))))

;; --- Time creation ---

(display "Time creation\n")

(let ((t (make-time time-utc 0 1000)))
  (check (time? t) => #t)
  (check (time-type t) => 'time-utc)
  (check (time-second t) => 1000)
  (check (time-nanosecond t) => 0))

(let ((t (make-time time-duration 500000000 3)))
  (check (time-type t) => 'time-duration)
  (check (time-second t) => 3)
  (check (time-nanosecond t) => 500000000))

;; --- current-time ---

(display "current-time\n")

(let ((t (current-time)))
  (check-true (time? t))
  (check (time-type t) => 'time-utc)
  (check-true (> (time-second t) 1700000000))
  (check-true (>= (time-nanosecond t) 0)))

(let ((t (current-time time-monotonic)))
  (check (time-type t) => 'time-monotonic))

;; --- Time comparison ---

(display "Time comparison\n")

(let ((t1 (make-time time-utc 0 100))
      (t2 (make-time time-utc 0 200))
      (t3 (make-time time-utc 0 100)))
  (check (time=? t1 t3) => #t)
  (check (time=? t1 t2) => #f)
  (check (time<? t1 t2) => #t)
  (check (time<? t2 t1) => #f)
  (check (time>? t2 t1) => #t)
  (check (time<=? t1 t3) => #t)
  (check (time<=? t1 t2) => #t)
  (check (time>=? t2 t1) => #t))

;; Nanosecond-level comparison
(let ((t1 (make-time time-utc 100 1000))
      (t2 (make-time time-utc 200 1000)))
  (check (time<? t1 t2) => #t)
  (check (time>? t2 t1) => #t)
  (check (time=? t1 t2) => #f))

;; --- Time arithmetic ---

(display "Time arithmetic\n")

(let* ((t1 (make-time time-utc 0 1000))
       (t2 (make-time time-utc 0 600))
       (diff (time-difference t1 t2)))
  (check (time-type diff) => 'time-duration)
  (check (time-second diff) => 400)
  (check (time-nanosecond diff) => 0))

;; Difference with nanosecond borrow
(let* ((t1 (make-time time-utc 100 1001))
       (t2 (make-time time-utc 200 1000))
       (diff (time-difference t1 t2)))
  (check (time-second diff) => 0)
  (check (time-nanosecond diff) => 999999900))

;; Add duration
(let* ((t (make-time time-utc 0 100))
       (dur (make-time time-duration 0 50))
       (result (add-duration t dur)))
  (check (time-second result) => 150)
  (check (time-nanosecond result) => 0)
  (check (time-type result) => 'time-utc))

;; Add duration with nanosecond overflow
(let* ((t (make-time time-utc 500000000 100))
       (dur (make-time time-duration 600000000 0))
       (result (add-duration t dur)))
  (check (time-second result) => 101)
  (check (time-nanosecond result) => 100000000))

;; Subtract duration
(let* ((t (make-time time-utc 0 200))
       (dur (make-time time-duration 0 50))
       (result (subtract-duration t dur)))
  (check (time-second result) => 150))

;; --- Date creation ---

(display "Date creation\n")

(let ((d (make-date 0 30 15 10 23 6 2026 0)))
  (check (date? d) => #t)
  (check (date-year d) => 2026)
  (check (date-month d) => 6)
  (check (date-day d) => 23)
  (check (date-hour d) => 10)
  (check (date-minute d) => 15)
  (check (date-second d) => 30)
  (check (date-nanosecond d) => 0)
  (check (date-zone-offset d) => 0))

;; --- current-date ---

(display "current-date\n")

(let ((d (current-date)))
  (check-true (date? d))
  (check-true (>= (date-year d) 2024))
  (check-true (and (>= (date-month d) 1) (<= (date-month d) 12)))
  (check-true (and (>= (date-day d) 1) (<= (date-day d) 31)))
  (check-true (and (>= (date-hour d) 0) (<= (date-hour d) 23)))
  (check-true (and (>= (date-minute d) 0) (<= (date-minute d) 59)))
  (check-true (and (>= (date-second d) 0) (<= (date-second d) 60))))

;; --- time-utc->date ---

(display "time-utc->date\n")

;; Unix epoch = 1970-01-01 00:00:00 UTC
(let ((d (time-utc->date (make-time time-utc 0 0))))
  (check (date-year d) => 1970)
  (check (date-month d) => 1)
  (check (date-day d) => 1)
  (check (date-hour d) => 0)
  (check (date-minute d) => 0)
  (check (date-second d) => 0))

;; 2024-01-01 00:00:00 UTC = 1704067200
(let ((d (time-utc->date (make-time time-utc 0 1704067200))))
  (check (date-year d) => 2024)
  (check (date-month d) => 1)
  (check (date-day d) => 1))

;; 2000-03-01 00:00:00 UTC = 951868800 (leap year boundary)
(let ((d (time-utc->date (make-time time-utc 0 951868800))))
  (check (date-year d) => 2000)
  (check (date-month d) => 3)
  (check (date-day d) => 1))

;; --- date->string formatting ---

(display "date->string\n")

(let ((d (make-date 0 5 30 14 15 3 2025 0)))
  (check (date->string d "~Y-~m-~d") => "2025-03-15")
  (check (date->string d "~H:~M:~S") => "14:30:05")
  (check (date->string d "~Y-~m-~d ~H:~M:~S") => "2025-03-15 14:30:05")
  (check (date->string d "~~") => "~"))

;; Padding
(let ((d (make-date 0 3 7 9 5 1 2025 0)))
  (check (date->string d "~Y-~m-~d ~H:~M:~S") => "2025-01-05 09:07:03"))

;; --- Julian day ---

(display "Julian day\n")

(let ((jd (current-julian-day)))
  (check-true (> jd 2460000.0)))

;; --- Leap year ---

(display "Leap year\n")

(check (leap-year? 2000) => #t)
(check (leap-year? 2024) => #t)
(check (leap-year? 1900) => #f)
(check (leap-year? 2023) => #f)

;; --- Day of week ---

(display "Day of week\n")

;; 2025-03-15 is a Saturday (6)
(check (date-week-day (make-date 0 0 0 0 15 3 2025 0)) => 6)
;; 1970-01-01 is a Thursday (4)
(check (date-week-day (make-date 0 0 0 0 1 1 1970 0)) => 4)
;; 2024-12-25 is a Wednesday (3)
(check (date-week-day (make-date 0 0 0 0 25 12 2024 0)) => 3)

;; --- Day of year ---

(display "Day of year\n")

(check (date-year-day (make-date 0 0 0 0 1 1 2025 0)) => 1)
(check (date-year-day (make-date 0 0 0 0 31 12 2025 0)) => 365)
(check (date-year-day (make-date 0 0 0 0 31 12 2024 0)) => 366)
(check (date-year-day (make-date 0 0 0 0 1 3 2024 0)) => 61)

;; --- Timezone offset ---

(display "Timezone\n")

;; UTC+5:30 (IST)
(define ist-offset (* (+ (* 5 3600) (* 30 60)) 1))
(let ((d (time-utc->date (make-time time-utc 0 0) ist-offset)))
  (check (date-hour d) => 5)
  (check (date-minute d) => 30)
  (check (date-zone-offset d) => ist-offset))

;; UTC-5 (EST)
(let ((d (time-utc->date (make-time time-utc 0 86400) -18000)))
  (check (date-hour d) => 19)
  (check (date-day d) => 1))

;; --- date->time-utc round-trip ---

(display "date->time-utc\n")

(let* ((t1 (make-time time-utc 0 1704067200))
       (d (time-utc->date t1))
       (t2 (date->time-utc d)))
  (check (time-second t2) => 1704067200))

(let* ((d (make-date 0 0 0 12 15 6 2025 0))
       (t (date->time-utc d))
       (d2 (time-utc->date t)))
  (check (date-year d2) => 2025)
  (check (date-month d2) => 6)
  (check (date-day d2) => 15)
  (check (date-hour d2) => 12))

;; --- Extended format directives ---

(display "Extended formatting\n")

(let ((d (make-date 0 5 30 14 15 3 2025 0)))
  (check (date->string d "~a") => "Sat")
  (check (date->string d "~A") => "Saturday")
  (check (date->string d "~b") => "Mar")
  (check (date->string d "~B") => "March")
  (check (date->string d "~w") => "6")
  (check (date->string d "~e ~b ~Y") => "15 Mar 2025"))

;; Day of year / week number
(let ((d (make-date 0 0 0 0 15 3 2025 0)))
  (check (date->string d "~j") => "074"))

;; Timezone offset formatting
(let ((d (make-date 0 0 0 0 1 1 2025 3600)))
  (check (date->string d "~z") => "+0100"))
(let ((d (make-date 0 0 0 0 1 1 2025 -18000)))
  (check (date->string d "~z") => "-0500"))
(let ((d (make-date 0 0 0 0 1 1 2025 0)))
  (check (date->string d "~z") => "+0000"))

;; --- string->date ---

(display "string->date\n")

(let ((d (string->date "2025-03-15" "~Y-~m-~d")))
  (check (date-year d) => 2025)
  (check (date-month d) => 3)
  (check (date-day d) => 15))

(let ((d (string->date "2025-03-15 14:30:05" "~Y-~m-~d ~H:~M:~S")))
  (check (date-year d) => 2025)
  (check (date-hour d) => 14)
  (check (date-minute d) => 30)
  (check (date-second d) => 5))

;; --- Julian day ---

(display "Julian day conversions\n")

(let ((jd (date->julian-day (make-date 0 0 0 12 1 1 2000 0))))
  (check-true (> jd 2451544.0))
  (check-true (< jd 2451546.0)))

(let* ((d1 (make-date 0 0 0 0 15 3 2025 0))
       (jd (date->julian-day d1))
       (d2 (julian-day->date jd)))
  (check (date-year d2) => 2025)
  (check (date-month d2) => 3)
  (check (date-day d2) => 15))

;; --- Round-trip: time -> date -> string ---

(display "Round-trip\n")

(let* ((t (make-time time-utc 0 0))
       (d (time-utc->date t))
       (s (date->string d "~Y-~m-~d")))
  (check s => "1970-01-01"))

;; --- Summary ---

(newline)
(display pass) (display " passed, ")
(display fail) (display " failed\n")
(when (> fail 0) (exit 1))
