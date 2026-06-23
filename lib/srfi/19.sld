;;; SRFI 19 — Time Data Types and Procedures
(define-library (srfi 19)
  (import (scheme base) (scheme write) (scheme time) (scheme char) (scheme cxr))
  (export current-time time? make-time
          time-type time-second time-nanosecond
          time-utc time-tai time-monotonic time-duration
          time=? time<? time>? time<=? time>=?
          time-difference time-difference!
          add-duration subtract-duration
          current-date make-date date?
          date-year date-month date-day
          date-hour date-minute date-second date-nanosecond
          date-zone-offset
          date->string time-utc->date
          current-julian-day)
  (begin

    ;; Time types
    (define time-utc 'time-utc)
    (define time-tai 'time-tai)
    (define time-monotonic 'time-monotonic)
    (define time-duration 'time-duration)

    ;; Time record
    (define-record-type <time>
      (%make-time type nanosecond second)
      time?
      (type time-type)
      (nanosecond time-nanosecond)
      (second time-second))

    (define (make-time type nanosecond second)
      (%make-time type nanosecond second))

    (define (current-time . args)
      (let ((type (if (pair? args) (car args) time-utc))
            (secs (current-second)))
        (let ((s (exact (truncate secs)))
              (ns (exact (truncate (* (- secs (truncate secs)) 1000000000)))))
          (%make-time type ns s))))

    ;; Time comparison
    (define (time=? t1 t2)
      (and (= (time-second t1) (time-second t2))
           (= (time-nanosecond t1) (time-nanosecond t2))))

    (define (time<? t1 t2)
      (or (< (time-second t1) (time-second t2))
          (and (= (time-second t1) (time-second t2))
               (< (time-nanosecond t1) (time-nanosecond t2)))))

    (define (time>? t1 t2) (time<? t2 t1))
    (define (time<=? t1 t2) (not (time>? t1 t2)))
    (define (time>=? t1 t2) (not (time<? t1 t2)))

    ;; Time arithmetic
    (define (time-difference t1 t2)
      (let ((ds (- (time-second t1) (time-second t2)))
            (dn (- (time-nanosecond t1) (time-nanosecond t2))))
        (if (< dn 0)
            (%make-time time-duration (+ dn 1000000000) (- ds 1))
            (%make-time time-duration dn ds))))

    (define time-difference! time-difference)

    (define (add-duration t dur)
      (let ((s (+ (time-second t) (time-second dur)))
            (ns (+ (time-nanosecond t) (time-nanosecond dur))))
        (if (>= ns 1000000000)
            (%make-time (time-type t) (- ns 1000000000) (+ s 1))
            (%make-time (time-type t) ns s))))

    (define (subtract-duration t dur)
      (let ((s (- (time-second t) (time-second dur)))
            (ns (- (time-nanosecond t) (time-nanosecond dur))))
        (if (< ns 0)
            (%make-time (time-type t) (+ ns 1000000000) (- s 1))
            (%make-time (time-type t) ns s))))

    ;; Date record
    (define-record-type <date>
      (%make-date nanosecond second minute hour day month year zone-offset)
      date?
      (nanosecond date-nanosecond)
      (second date-second)
      (minute date-minute)
      (hour date-hour)
      (day date-day)
      (month date-month)
      (year date-year)
      (zone-offset date-zone-offset))

    (define (make-date ns sec min hr day mon yr zo)
      (%make-date ns sec min hr day mon yr zo))

    ;; Unix epoch conversion
    (define (time-utc->date t . args)
      (let ((offset (if (pair? args) (car args) 0))
            (secs (+ (time-second t) (if (pair? args) (car args) 0))))
        (epoch->date secs (time-nanosecond t) offset)))

    (define (epoch->date secs ns offset)
      (let* ((days (quotient secs 86400))
             (rem (modulo secs 86400))
             (hr (quotient rem 3600))
             (rem2 (modulo rem 3600))
             (mn (quotient rem2 60))
             (sc (modulo rem2 60))
             (ymd (days->ymd (+ days 719468))))
        (%make-date ns sc mn hr
                    (caddr ymd) (cadr ymd) (car ymd)
                    offset)))

    (define (days->ymd z)
      (let* ((era (quotient (if (>= z 0) z (- z 146096)) 146097))
             (doe (- z (* era 146097)))
             (yoe (quotient (- doe (quotient doe 1460)
                              (quotient doe 36524)
                              (- (quotient doe 146096)))
                            365))
             (y (+ yoe (* era 400)))
             (doy (- doe (- (+ (* 365 yoe) (quotient yoe 4))
                            (quotient yoe 100))))
             (mp (quotient (+ (* 5 doy) 2) 153))
             (d (+ (- doy (quotient (+ (* 153 mp) 2) 5)) 1))
             (m (+ mp (if (< mp 10) 3 -9)))
             (yr (+ y (if (<= m 2) 1 0))))
        (list yr m d)))

    (define (current-date . args)
      (let ((offset (if (pair? args) (car args) 0)))
        (time-utc->date (current-time time-utc) offset)))

    (define (current-julian-day)
      (+ (/ (time-second (current-time time-utc)) 86400.0) 2440587.5))

    ;; Date formatting
    (define (date->string date . args)
      (let ((fmt (if (pair? args) (car args) "~Y-~m-~d ~H:~M:~S")))
        (let ((port (open-output-string)))
          (let loop ((i 0))
            (when (< i (string-length fmt))
              (if (and (char=? (string-ref fmt i) #\~)
                       (< (+ i 1) (string-length fmt)))
                  (begin
                    (write-date-char (string-ref fmt (+ i 1)) date port)
                    (loop (+ i 2)))
                  (begin
                    (write-char (string-ref fmt i) port)
                    (loop (+ i 1))))))
          (get-output-string port))))

    (define (write-date-char ch date port)
      (cond
        ((char=? ch #\Y) (write-padded (date-year date) 4 port))
        ((char=? ch #\m) (write-padded (date-month date) 2 port))
        ((char=? ch #\d) (write-padded (date-day date) 2 port))
        ((char=? ch #\H) (write-padded (date-hour date) 2 port))
        ((char=? ch #\M) (write-padded (date-minute date) 2 port))
        ((char=? ch #\S) (write-padded (date-second date) 2 port))
        ((char=? ch #\~) (write-char #\~ port))
        (else (write-char #\~ port) (write-char ch port))))

    (define (write-padded n width port)
      (let ((s (number->string (abs n))))
        (let loop ((i (string-length s)))
          (when (< i width)
            (write-char #\0 port)
            (loop (+ i 1))))
        (write-string s port)))))
