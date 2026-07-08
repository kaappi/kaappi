;; Regression test for #1193: SRFI-27 random procedures must accept bignums
(import (scheme base) (scheme write) (scheme process-context) (srfi 27) (srfi 64))

(test-begin "srfi27-bignum")

;; random-integer with bignum bound
(test-assert "random-integer (expt 2 64)"
  (let ((r (random-integer (expt 2 64))))
    (and (exact? r) (>= r 0) (< r (expt 2 64)))))

(test-assert "random-integer (expt 2 128)"
  (let ((r (random-integer (expt 2 128))))
    (and (exact? r) (>= r 0) (< r (expt 2 128)))))

;; bounds whose top limb has the MSB set (top_bits = 64)
(test-assert "random-integer (expt 2 127) — saturated top limb"
  (let ((r (random-integer (expt 2 127))))
    (and (exact? r) (>= r 0) (< r (expt 2 127)))))

(test-assert "random-integer (- (expt 2 128) 1) — all-ones limbs"
  (let ((r (random-integer (- (expt 2 128) 1))))
    (and (exact? r) (>= r 0) (< r (- (expt 2 128) 1)))))

;; random-source-make-integers with bignum bound
(test-assert "rs-make-integers bignum"
  (let* ((s (make-random-source))
         (rand (random-source-make-integers s))
         (r (rand (expt 2 64))))
    (and (exact? r) (>= r 0) (< r (expt 2 64)))))

;; random-source-pseudo-randomize! with bignum i/j
(test-assert "pseudo-randomize! bignum i"
  (begin (random-source-pseudo-randomize! (make-random-source) (expt 2 64) 1) #t))

(test-assert "pseudo-randomize! bignum j"
  (begin (random-source-pseudo-randomize! (make-random-source) 0 (expt 2 64)) #t))

;; determinism: same bignum (i,j) → same stream
(test-assert "pseudo-randomize! bignum determinism"
  (let ((s1 (make-random-source))
        (s2 (make-random-source)))
    (random-source-pseudo-randomize! s1 (expt 2 64) (expt 2 100))
    (random-source-pseudo-randomize! s2 (expt 2 64) (expt 2 100))
    (let ((r1 (random-source-make-integers s1))
          (r2 (random-source-make-integers s2)))
      (= (r1 1000000) (r2 1000000)))))

(let ((runner (test-runner-current)))
  (test-end "srfi27-bignum")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
