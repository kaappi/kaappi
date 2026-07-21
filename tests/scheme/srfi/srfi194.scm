;; SRFI 194 — Random data generators tests

(import (scheme base)
        (scheme inexact)
        (scheme complex)
        (srfi 27)
        (srfi 133)
        (srfi 158)
        (srfi 194)
        (srfi 64))

(test-begin "srfi-194")

;; ---- clamp-real-number ----

(test-group "clamp-real-number"
  (test-equal 0.0 (clamp-real-number 0.0 1.0 -0.5))
  (test-equal 1.0 (clamp-real-number 0.0 1.0 1.5))
  (test-equal 0.5 (clamp-real-number 0.0 1.0 0.5))
  (test-equal 0.0 (clamp-real-number 0.0 1.0 0.0))
  (test-equal 1.0 (clamp-real-number 0.0 1.0 1.0)))

;; ---- current-random-source / with-random-source ----

(test-group "with-random-source"
  (let ((rs (make-random-source)))
    (random-source-pseudo-randomize! rs 42 0)
    (with-random-source rs
      (lambda ()
        (test-assert (random-source? (current-random-source)))))))

;; ---- make-random-source-generator ----

(test-group "make-random-source-generator"
  (let ((rsg (make-random-source-generator 0)))
    (let ((rs1 (rsg))
          (rs2 (rsg)))
      (test-assert (random-source? rs1))
      (test-assert (random-source? rs2)))))

;; ---- make-random-integer-generator ----

(test-group "random-integer"
  (let ((gen (make-random-integer-generator 0 10)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= 0 v) (< v 10)))))))

;; ---- make-random-u1-generator ----

(test-group "random-u1"
  (let ((gen (make-random-u1-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (or (= v 0) (= v 1)))))))

;; ---- make-random-u8-generator ----

(test-group "random-u8"
  (let ((gen (make-random-u8-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= 0 v) (< v 256)))))))

;; ---- make-random-s8-generator ----

(test-group "random-s8"
  (let ((gen (make-random-s8-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= -128 v) (< v 128)))))))

;; ---- make-random-u16-generator ----

(test-group "random-u16"
  (let ((gen (make-random-u16-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= 0 v) (< v 65536)))))))

;; ---- make-random-s16-generator ----

(test-group "random-s16"
  (let ((gen (make-random-s16-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= -32768 v) (< v 32768)))))))

;; ---- make-random-u32/s32/u64/s64 generators ----

(test-group "random-u32"
  (let ((gen (make-random-u32-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= 0 v) (< v (expt 2 32))))))))

(test-group "random-s32"
  (let ((gen (make-random-s32-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v)
                          (<= (- (expt 2 31)) v)
                          (< v (expt 2 31))))))))

(test-group "random-u64"
  (let ((gen (make-random-u64-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= 0 v) (< v (expt 2 64))))))))

(test-group "random-s64"
  (let ((gen (make-random-s64-generator)))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v)
                          (<= (- (expt 2 63)) v)
                          (< v (expt 2 63))))))))

;; ---- make-random-real-generator ----

(test-group "random-real"
  (let ((gen (make-random-real-generator 1.0 5.0)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (and (real? v) (>= v 1.0) (< v 5.0)))))))

;; ---- make-random-boolean-generator ----

(test-group "random-boolean"
  (let ((gen (make-random-boolean-generator))
        (trues 0))
    (do ((i 0 (+ i 1)))
        ((= i 1000))
      (when (gen) (set! trues (+ trues 1))))
    ;; Should be roughly 50/50; check within reasonable range
    (test-assert (and (> trues 350) (< trues 650)))))

;; ---- make-random-char-generator ----

(test-group "random-char"
  (let ((gen (make-random-char-generator "abcdef")))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (char? v))
        (test-assert (string-contains "abcdef" (string v)))))))

;; ---- make-random-string-generator ----

(test-group "random-string"
  (let ((gen (make-random-string-generator 10 "abc")))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (string? v))
        (test-assert (< (string-length v) 10))))))

;; ---- make-random-rectangular-generator ----

(test-group "random-rectangular"
  (let ((gen (make-random-rectangular-generator -1.0 1.0 -2.0 2.0)))
    (do ((i 0 (+ i 1)))
        ((= i 50))
      (let ((v (gen)))
        (test-assert (complex? v))
        (test-assert (and (>= (real-part v) -1.0) (< (real-part v) 1.0)))
        (test-assert (and (>= (imag-part v) -2.0) (< (imag-part v) 2.0)))))))

;; ---- make-random-polar-generator ----

(test-group "random-polar"
  (let ((gen (make-random-polar-generator 1.0 5.0)))
    (do ((i 0 (+ i 1)))
        ((= i 50))
      (let ((v (gen)))
        (test-assert (complex? v))
        (let ((mag (magnitude v)))
          (test-assert (and (>= mag 0.99) (<= mag 5.01))))))))

;; ---- make-bernoulli-generator ----

(test-group "bernoulli"
  (let ((gen (make-bernoulli-generator 0.5))
        (ones 0))
    (do ((i 0 (+ i 1)))
        ((= i 1000))
      (let ((v (gen)))
        (test-assert (or (= v 0) (= v 1)))
        (when (= v 1) (set! ones (+ ones 1)))))
    ;; Roughly 50% should be 1
    (test-assert (and (> ones 350) (< ones 650)))))

;; ---- make-categorical-generator ----

(test-group "categorical"
  (let ((gen (make-categorical-generator #(1 1 1)))
        (counts (make-vector 3 0)))
    (do ((i 0 (+ i 1)))
        ((= i 3000))
      (let ((v (gen)))
        (test-assert (and (exact-integer? v) (<= 0 v) (< v 3)))
        (vector-set! counts v (+ 1 (vector-ref counts v)))))
    ;; With equal weights, each category should be ~1000 out of 3000
    (test-assert (> (vector-ref counts 0) 700))
    (test-assert (> (vector-ref counts 1) 700))
    (test-assert (> (vector-ref counts 2) 700))))

;; ---- make-normal-generator ----

(test-group "normal"
  (let ((gen (make-normal-generator 0.0 1.0))
        (sum 0.0)
        (n 1000))
    (do ((i 0 (+ i 1)))
        ((= i n))
      (let ((v (gen)))
        (test-assert (real? v))
        (set! sum (+ sum v))))
    ;; Mean should be approximately 0
    (let ((mean (/ sum n)))
      (test-assert (< (abs mean) 0.2)))))

;; ---- make-exponential-generator ----

(test-group "exponential"
  (let ((gen (make-exponential-generator 1.0)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (real? v))
        (test-assert (> v 0))))))

;; ---- make-geometric-generator ----

(test-group "geometric"
  (let ((gen (make-geometric-generator 0.5)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (exact-integer? v))
        (test-assert (>= v 1))))))

;; ---- make-poisson-generator ----

(test-group "poisson-small"
  (let ((gen (make-poisson-generator 5.0))
        (sum 0)
        (n 1000))
    (do ((i 0 (+ i 1)))
        ((= i n))
      (let ((v (gen)))
        (test-assert (exact-integer? v))
        (test-assert (>= v 0))
        (set! sum (+ sum v))))
    ;; Mean should be approximately 5
    (let ((mean (/ sum n)))
      (test-assert (and (> mean 3.0) (< mean 7.0))))))

(test-group "poisson-large"
  (let ((gen (make-poisson-generator 50.0)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (exact-integer? v))
        (test-assert (>= v 0))))))

;; ---- make-binomial-generator ----

(test-group "binomial"
  (let ((gen (make-binomial-generator 10 0.5))
        (sum 0)
        (n 1000))
    (do ((i 0 (+ i 1)))
        ((= i n))
      (let ((v (gen)))
        (test-assert (exact-integer? v))
        (test-assert (and (<= 0 v) (<= v 10)))
        (set! sum (+ sum v))))
    ;; Mean should be approximately n*p = 5
    (let ((mean (/ sum n)))
      (test-assert (and (> mean 3.0) (< mean 7.0))))))

(test-group "binomial-edge-cases"
  ;; p=0 should always return 0
  (let ((gen (make-binomial-generator 10 0)))
    (do ((i 0 (+ i 1)))
        ((= i 10))
      (test-equal 0 (gen))))
  ;; p=1 should always return n
  (let ((gen (make-binomial-generator 10 1)))
    (do ((i 0 (+ i 1)))
        ((= i 10))
      (test-equal 10 (gen)))))

;; ---- make-zipf-generator ----

(test-group "zipf"
  (let ((gen (make-zipf-generator 100 2.0)))
    (do ((i 0 (+ i 1)))
        ((= i 100))
      (let ((v (gen)))
        (test-assert (exact-integer? v))
        (test-assert (and (>= v 1) (<= v 100)))))))

;; ---- make-sphere-generator ----

(test-group "sphere"
  (let ((gen (make-sphere-generator 2)))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (vector? v))
        (test-equal 3 (vector-length v))
        ;; Points on a unit 2-sphere should have magnitude ~1
        (let ((mag (sqrt (vector-fold (lambda (s x) (+ s (* x x))) 0.0 v))))
          (test-assert (< (abs (- mag 1.0)) 0.01)))))))

;; ---- make-ellipsoid-generator ----

(test-group "ellipsoid"
  (let ((gen (make-ellipsoid-generator #(2.0 3.0 4.0))))
    (do ((i 0 (+ i 1)))
        ((= i 20))
      (let ((v (gen)))
        (test-assert (vector? v))
        (test-equal 3 (vector-length v))
        ;; Points on the ellipsoid: sum of (x/a)^2 should be ~1
        (let ((d (+ (square (/ (vector-ref v 0) 2.0))
                    (square (/ (vector-ref v 1) 3.0))
                    (square (/ (vector-ref v 2) 4.0)))))
          (test-assert (< (abs (- d 1.0)) 0.01)))))))

;; ---- make-ball-generator ----

(test-group "ball"
  (let ((gen (make-ball-generator 3)))
    (do ((i 0 (+ i 1)))
        ((= i 50))
      (let ((v (gen)))
        (test-assert (vector? v))
        (test-equal 3 (vector-length v))
        ;; Points in a unit ball should have magnitude <= 1
        (let ((mag (sqrt (vector-fold (lambda (s x) (+ s (* x x))) 0.0 v))))
          (test-assert (<= mag 1.01)))))))

;; ---- gsampling ----

(test-group "gsampling"
  ;; Test that gsampling draws from all generators
  (let* ((g1 (generator 'a 'b 'c))
         (g2 (generator 1 2 3))
         (gs (gsampling g1 g2))
         (vals (generator->list gs)))
    (test-equal 6 (length vals))
    ;; All values should come from the two sources
    (for-each (lambda (v)
                (test-assert (or (symbol? v) (number? v))))
              vals))

  ;; Empty generators → immediate eof
  (let ((gs (gsampling (generator) (generator))))
    (test-assert (eof-object? (gs)))))

;; ---- Determinism with same random source ----

(test-group "deterministic"
  (let ((rs1 (make-random-source))
        (rs2 (make-random-source)))
    (random-source-pseudo-randomize! rs1 0 0)
    (random-source-pseudo-randomize! rs2 0 0)
    ;; Same seed should produce same sequence
    (let ((gen1 (with-random-source rs1
                  (lambda () (make-random-integer-generator 0 100))))
          (gen2 (with-random-source rs2
                  (lambda () (make-random-integer-generator 0 100)))))
      (do ((i 0 (+ i 1)))
          ((= i 20))
        (test-equal (gen1) (gen2))))))

;; ---- Grab runner and exit ----

(let ((runner (test-runner-current)))
  (test-end "srfi-194")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
