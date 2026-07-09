;; Regression test for #1194: random-source-make-reals ignores the unit argument
(import (scheme base) (scheme write) (scheme process-context) (srfi 27) (srfi 64))

(test-begin "srfi-27-unit")

;; No unit: returns inexact flonum in (0, 1)
(let ((rand (random-source-make-reals (make-random-source))))
  (let ((r (rand)))
    (test-assert "no-unit: inexact" (inexact? r))
    (test-assert "no-unit: in (0,1)" (and (> r 0) (< r 1)))))

;; Inexact unit: returns inexact flonum in (0, 1)
(let ((rand (random-source-make-reals (make-random-source) 0.1)))
  (let ((r (rand)))
    (test-assert "inexact-unit: inexact" (inexact? r))
    (test-assert "inexact-unit: in (0,1)" (and (> r 0) (< r 1)))))

;; Exact unit 1/10: results must be exact rationals, multiples of 1/10
(let ((rand (random-source-make-reals (make-random-source) 1/10)))
  (do ((i 0 (+ i 1)))
      ((= i 20))
    (let ((r (rand)))
      (test-assert "exact-unit: exact" (exact? r))
      (test-assert "exact-unit: in (0,1)" (and (> r 0) (< r 1)))
      (test-assert "exact-unit: multiple of 1/10" (integer? (* r 10))))))

;; Exact unit 1/4: values in {1/4, 2/4, 3/4}
(let ((rand (random-source-make-reals (make-random-source) 1/4)))
  (do ((i 0 (+ i 1)))
      ((= i 20))
    (let ((r (rand)))
      (test-assert "1/4-unit: exact" (exact? r))
      (test-assert "1/4-unit: in (0,1)" (and (> r 0) (< r 1)))
      (test-assert "1/4-unit: multiple of 1/4" (integer? (* r 4))))))

;; Exact unit 3/10: non-integer reciprocal (1/unit = 10/3, floor = 3)
;; Values: {3/10, 6/10, 9/10}
(let ((rand (random-source-make-reals (make-random-source) 3/10)))
  (do ((i 0 (+ i 1)))
      ((= i 20))
    (let ((r (rand)))
      (test-assert "3/10-unit: exact" (exact? r))
      (test-assert "3/10-unit: in (0,1)" (and (> r 0) (< r 1)))
      (test-assert "3/10-unit: multiple of 3/10" (integer? (/ r 3/10))))))

;; Exact unit 3/5: 1/unit = 5/3, floor = 1, only value is 3/5
(let ((rand (random-source-make-reals (make-random-source) 3/5)))
  (do ((i 0 (+ i 1)))
      ((= i 10))
    (let ((r (rand)))
      (test-assert "3/5-unit: exact" (exact? r))
      (test-assert "3/5-unit: equals 3/5" (= r 3/5)))))

;; Exact unit 2/3: in (1/2, 1), only value is 2/3
(let ((rand (random-source-make-reals (make-random-source) 2/3)))
  (do ((i 0 (+ i 1)))
      ((= i 10))
    (let ((r (rand)))
      (test-assert "2/3-unit: exact" (exact? r))
      (test-assert "2/3-unit: equals 2/3" (= r 2/3)))))

;; Invalid unit: out of range
(test-assert "unit=2 rejected"
  (guard (e (#t (error-object? e)))
    (random-source-make-reals (make-random-source) 2) #f))
(test-assert "unit=0 rejected"
  (guard (e (#t (error-object? e)))
    (random-source-make-reals (make-random-source) 0) #f))
(test-assert "unit=-0.5 rejected"
  (guard (e (#t (error-object? e)))
    (random-source-make-reals (make-random-source) -0.5) #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-27-unit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
