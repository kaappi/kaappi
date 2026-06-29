;; Regression tests for #e/#i exactness prefix handling
;; Issue #296

(import (scheme base) (scheme write))

;; #e on complex numbers
(display (exact? (make-rectangular (real-part #e1+2i) (imag-part #e1+2i)))) ; #t
(newline)
(display (= (real-part #e1+2i) 1)) ; #t
(newline)
(display (= (imag-part #e1+2i) 2)) ; #t
(newline)

;; #i on large integers (bignums)
(display (inexact? #i99999999999999999999999999999)) ; #t
(newline)
(display (number? #i99999999999999999999999999999)) ; #t
(newline)

;; #e on flonum still works
(display (exact? #e1.5))   ; #t
(newline)
(display (= #e1.5 3/2))   ; #t
(newline)

;; #i on fixnum still works
(display (inexact? #i42))  ; #t
(newline)

(display "all passed")
(newline)
