;;; Time library compliance tests (R7RS 6.14)

;; current-second returns a real number
(display (number? (current-second)))  ; => #t
(newline)

;; current-jiffy returns an integer
(display (integer? (current-jiffy)))  ; => #t
(newline)

;; jiffies-per-second
(display (> (jiffies-per-second) 0))  ; => #t
(newline)

;; current-second is positive (after Unix epoch)
(display (> (current-second) 0))  ; => #t
(newline)

;; Two consecutive jiffies should be monotonically increasing or equal
(let ((j1 (current-jiffy))
      (j2 (current-jiffy)))
  (display (>= j2 j1)))  ; => #t
(newline)
