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
          date->string string->date
          date->time-utc time-utc->date
          date-week-day date-year-day date-week-number
          current-julian-day
          date->julian-day julian-day->date
          leap-year?)
  (begin

    ;; time?, make-time, time-type, time-second, time-nanosecond are
    ;; built-in primitives imported from (scheme time).

    (define time-utc 'time-utc)
    (define time-tai 'time-tai)
    (define time-monotonic 'time-monotonic)
    (define time-duration 'time-duration)

    (define (current-time . args)
      (let ((type (if (pair? args) (car args) time-utc))
            (secs (current-second)))
        (let ((s (exact (truncate secs)))
              (ns (exact (truncate (* (- secs (truncate secs)) 1000000000)))))
          (make-time type ns s))))

    ;; Comparison
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

    ;; Arithmetic
    (define (time-difference t1 t2)
      (let ((ds (- (time-second t1) (time-second t2)))
            (dn (- (time-nanosecond t1) (time-nanosecond t2))))
        (if (< dn 0)
            (make-time time-duration (+ dn 1000000000) (- ds 1))
            (make-time time-duration dn ds))))
    (define time-difference! time-difference)

    (define (add-duration t dur)
      (let ((s (+ (time-second t) (time-second dur)))
            (ns (+ (time-nanosecond t) (time-nanosecond dur))))
        (if (>= ns 1000000000)
            (make-time (time-type t) (- ns 1000000000) (+ s 1))
            (make-time (time-type t) ns s))))

    (define (subtract-duration t dur)
      (let ((s (- (time-second t) (time-second dur)))
            (ns (- (time-nanosecond t) (time-nanosecond dur))))
        (if (< ns 0)
            (make-time (time-type t) (+ ns 1000000000) (- s 1))
            (make-time (time-type t) ns s))))

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

    ;; Leap year
    (define (leap-year? y)
      (and (= (modulo y 4) 0)
           (or (not (= (modulo y 100) 0))
               (= (modulo y 400) 0))))

    ;; Days in month
    (define (days-in-month m y)
      (case m
        ((1 3 5 7 8 10 12) 31)
        ((4 6 9 11) 30)
        ((2) (if (leap-year? y) 29 28))
        (else 30)))

    ;; Day of year (1-based)
    (define (date-year-day date)
      (let ((m (date-month date)) (d (date-day date)) (y (date-year date)))
        (let loop ((i 1) (acc 0))
          (if (= i m) (+ acc d)
              (loop (+ i 1) (+ acc (days-in-month i y)))))))

    ;; Day of week (0=Sunday, 6=Saturday) — Tomohiko Sakamoto's algorithm
    (define (date-week-day date)
      (let* ((y (date-year date))
             (m (date-month date))
             (d (date-day date))
             (t (list 0 3 2 5 0 3 5 1 4 6 2 4))
             (yr (if (< m 3) (- y 1) y)))
        (modulo (+ yr (quotient yr 4) (- (quotient yr 100))
                   (quotient yr 400) (list-ref t (- m 1)) d)
                7)))

    ;; ISO week number
    (define (date-week-number date)
      (let ((yday (date-year-day date))
            (wday (date-week-day date)))
        (quotient (+ yday 6 (- (if (= wday 0) 6 (- wday 1)))) 7)))

    ;; Epoch conversions
    (define (time-utc->date t . args)
      (let ((offset (if (pair? args) (car args) 0)))
        (epoch->date (+ (time-second t) offset)
                     (time-nanosecond t) offset)))

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

    ;; Date -> time-utc
    (define (date->time-utc date)
      (let ((epoch-days (ymd->days (date-year date)
                                   (date-month date)
                                   (date-day date)))
            (secs (+ (* (date-hour date) 3600)
                     (* (date-minute date) 60)
                     (date-second date))))
        (make-time time-utc
                    (date-nanosecond date)
                    (- (+ (* epoch-days 86400) secs)
                       (date-zone-offset date)))))

    (define (ymd->days y m d)
      (let* ((yr (if (<= m 2) (- y 1) y))
             (era (quotient (if (>= yr 0) yr (- yr 399)) 400))
             (yoe (- yr (* era 400)))
             (mo (if (<= m 2) (+ m 9) (- m 3)))
             (doy (+ (quotient (+ (* 153 mo) 2) 5) (- d 1)))
             (doe (+ doy (- (+ (* 365 yoe) (quotient yoe 4))
                            (quotient yoe 100)))))
        (- (+ doe (* era 146097)) 719468)))

    (define (current-date . args)
      (let ((offset (if (pair? args) (car args) 0)))
        (time-utc->date (current-time time-utc) offset)))

    ;; Julian day
    (define (current-julian-day)
      (+ (/ (time-second (current-time time-utc)) 86400.0) 2440587.5))

    (define (date->julian-day date)
      (let ((epoch-days (ymd->days (date-year date)
                                   (date-month date)
                                   (date-day date))))
        (+ epoch-days 2440587.5
           (/ (+ (* (date-hour date) 3600)
                 (* (date-minute date) 60)
                 (date-second date))
              86400.0))))

    (define (julian-day->date jd . args)
      (let* ((offset (if (pair? args) (car args) 0))
             (epoch-secs (exact (truncate (* (- jd 2440587.5) 86400)))))
        (epoch->date (+ epoch-secs offset) 0 offset)))

    ;; Month/day names
    (define month-names
      '#("" "January" "February" "March" "April" "May" "June"
         "July" "August" "September" "October" "November" "December"))
    (define month-abbrevs
      '#("" "Jan" "Feb" "Mar" "Apr" "May" "Jun"
         "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
    (define day-names
      '#("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday"))
    (define day-abbrevs
      '#("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

    ;; Formatting
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
        ((char=? ch #\e) (write-space-padded (date-day date) 2 port))
        ((char=? ch #\H) (write-padded (date-hour date) 2 port))
        ((char=? ch #\M) (write-padded (date-minute date) 2 port))
        ((char=? ch #\S) (write-padded (date-second date) 2 port))
        ((char=? ch #\N) (write-padded (date-nanosecond date) 9 port))
        ((char=? ch #\a) (write-string (vector-ref day-abbrevs (date-week-day date)) port))
        ((char=? ch #\A) (write-string (vector-ref day-names (date-week-day date)) port))
        ((char=? ch #\b) (write-string (vector-ref month-abbrevs (date-month date)) port))
        ((char=? ch #\B) (write-string (vector-ref month-names (date-month date)) port))
        ((char=? ch #\j) (write-padded (date-year-day date) 3 port))
        ((char=? ch #\W) (write-padded (date-week-number date) 2 port))
        ((char=? ch #\w) (write-string (number->string (date-week-day date)) port))
        ((char=? ch #\z) (write-tz-offset (date-zone-offset date) port))
        ((char=? ch #\~) (write-char #\~ port))
        ((char=? ch #\n) (newline port))
        ((char=? ch #\t) (write-char #\tab port))
        (else (write-char #\~ port) (write-char ch port))))

    (define (write-padded n width port)
      (let ((s (number->string (abs n))))
        (when (< n 0) (write-char #\- port))
        (let loop ((i (string-length s)))
          (when (< i width) (write-char #\0 port) (loop (+ i 1))))
        (write-string s port)))

    (define (write-space-padded n width port)
      (let ((s (number->string n)))
        (let loop ((i (string-length s)))
          (when (< i width) (write-char #\space port) (loop (+ i 1))))
        (write-string s port)))

    (define (write-tz-offset offset port)
      (let* ((sign (if (>= offset 0) #\+ #\-))
             (abs-off (abs offset))
             (hrs (quotient abs-off 3600))
             (mins (quotient (modulo abs-off 3600) 60)))
        (write-char sign port)
        (write-padded hrs 2 port)
        (write-padded mins 2 port)))

    (define (abs x) (if (< x 0) (- x) x))

    ;; Parsing
    (define (string->date str fmt)
      (let ((len (string-length str))
            (flen (string-length fmt)))
        (let loop ((si 0) (fi 0)
                   (yr 0) (mo 1) (dy 1) (hr 0) (mn 0) (sc 0) (ns 0) (zo 0))
          (cond
            ((>= fi flen)
             (make-date ns sc mn hr dy mo yr zo))
            ((and (char=? (string-ref fmt fi) #\~)
                  (< (+ fi 1) flen))
             (let ((ch (string-ref fmt (+ fi 1))))
               (cond
                 ((char=? ch #\Y)
                  (let ((v (read-digits str si 4)))
                    (loop (+ si 4) (+ fi 2) v mo dy hr mn sc ns zo)))
                 ((char=? ch #\m)
                  (let ((v (read-digits str si 2)))
                    (loop (+ si 2) (+ fi 2) yr v dy hr mn sc ns zo)))
                 ((char=? ch #\d)
                  (let ((v (read-digits str si 2)))
                    (loop (+ si 2) (+ fi 2) yr mo v hr mn sc ns zo)))
                 ((char=? ch #\H)
                  (let ((v (read-digits str si 2)))
                    (loop (+ si 2) (+ fi 2) yr mo dy v mn sc ns zo)))
                 ((char=? ch #\M)
                  (let ((v (read-digits str si 2)))
                    (loop (+ si 2) (+ fi 2) yr mo dy hr v sc ns zo)))
                 ((char=? ch #\S)
                  (let ((v (read-digits str si 2)))
                    (loop (+ si 2) (+ fi 2) yr mo dy hr mn v ns zo)))
                 (else
                  (loop si (+ fi 2) yr mo dy hr mn sc ns zo)))))
            (else
             (loop (+ si 1) (+ fi 1) yr mo dy hr mn sc ns zo))))))

    (define (read-digits str start count)
      (if (> (+ start count) (string-length str)) 0
          (or (string->number (substring str start (+ start count))) 0)))))
