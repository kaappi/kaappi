;;; Regression test for issue #637: Complex number printing must not drop
;;; real/imaginary part when it equals negative zero.

(import (scheme base) (scheme write) (scheme inexact))

;; 1.0-0.0i: imaginary part is -0.0, must not be dropped
(let* ((x (read (open-input-string "1.0-0.0i")))
       (s (let ((p (open-output-string)))
            (write x p)
            (get-output-string p))))
  (unless (string=? s "1.0-0.0i")
    (display "FAIL: expected 1.0-0.0i, got ") (display s) (newline)
    (exit 1)))

;; -0.0+2.0i: real part is -0.0, must not be dropped
(let* ((y (read (open-input-string "-0.0+2.0i")))
       (s (let ((p (open-output-string)))
            (write y p)
            (get-output-string p))))
  (unless (string=? s "-0.0+2.0i")
    (display "FAIL: expected -0.0+2.0i, got ") (display s) (newline)
    (exit 1)))

;; Normal complex should still work
(let* ((z (read (open-input-string "3.0+4.0i")))
       (s (let ((p (open-output-string)))
            (write z p)
            (get-output-string p))))
  (unless (string=? s "3.0+4.0i")
    (display "FAIL: expected 3.0+4.0i, got ") (display s) (newline)
    (exit 1)))

;; Positive zero imaginary must NOT collapse: 5.0+0.0i is complex (an
;; inexact zero imaginary part keeps the value complex, R7RS 6.2.6,
;; kaappi#2269), so write emits the full form and the value round-trips.
(let* ((w (read (open-input-string "5.0+0.0i")))
       (s (let ((p (open-output-string)))
            (write w p)
            (get-output-string p))))
  (unless (string=? s "5.0+0.0i")
    (display "FAIL: expected 5.0+0.0i, got ") (display s) (newline)
    (exit 1)))

(display "OK")
(newline)
