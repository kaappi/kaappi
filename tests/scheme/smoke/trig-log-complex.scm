;; Regression test for #435, #426, #421:
;; Trig/log functions must return complex results where appropriate

(import (scheme base) (scheme write) (scheme inexact) (scheme complex))

(define (approx= a b tol) (< (abs (- a b)) tol))

;; #435: exp with complex argument — Euler's formula
(let ((r (exp (make-rectangular 0 3.14159265358979))))
  (unless (approx= (real-part r) -1.0 1e-10)
    (error "exp(i*pi) real part should be ~-1"))
  (unless (approx= (imag-part r) 0.0 1e-10)
    (error "exp(i*pi) imag part should be ~0")))

;; sin with complex
(let ((r (sin (make-rectangular 0 1))))
  (unless (approx= (real-part r) 0.0 1e-10)
    (error "sin(i) real part should be ~0"))
  (unless (approx= (imag-part r) 1.1752 1e-3)
    (error "sin(i) imag part should be ~1.1752")))

;; cos with complex
(let ((r (cos (make-rectangular 0 1))))
  (unless (approx= (real-part r) 1.5431 1e-3)
    (error "cos(i) real part should be ~1.5431"))
  (unless (approx= (imag-part r) 0.0 1e-10)
    (error "cos(i) imag part should be ~0")))

;; #426: asin outside [-1,1] returns complex
(let ((r (asin 2)))
  (unless (complex? r)
    (error "(asin 2) should return a complex number"))
  (unless (approx= (real-part r) 1.5708 1e-3)
    (error "(asin 2) real part should be ~pi/2")))

;; acos outside [-1,1] returns complex
(let ((r (acos 2)))
  (unless (complex? r)
    (error "(acos 2) should return a complex number")))

;; #421: log of negative returns complex
(let ((r (log -1)))
  (unless (approx= (real-part r) 0.0 1e-10)
    (error "(log -1) real part should be 0"))
  (unless (approx= (imag-part r) 3.14159 1e-4)
    (error "(log -1) imag part should be pi")))

(let ((r (log -2)))
  (unless (approx= (real-part r) 0.6931 1e-3)
    (error "(log -2) real part should be ln(2)"))
  (unless (approx= (imag-part r) 3.14159 1e-4)
    (error "(log -2) imag part should be pi")))

;; exp with complex: general case
(let ((r (exp (make-rectangular 1 1))))
  (unless (approx= (real-part r) 1.4687 1e-3)
    (error "exp(1+i) real part wrong"))
  (unless (approx= (imag-part r) 2.2874 1e-3)
    (error "exp(1+i) imag part wrong")))

(display "PASS")
(newline)
