;; SRFI 194 — Random data generators
;; Reference: https://srfi.schemers.org/srfi-194/
;; SPDX-FileCopyrightText: 2020 Arvydas Silanskas
;; SPDX-FileCopyrightText: 2020 Bradley Lucier
;; SPDX-FileCopyrightText: 2020 Linas Vepstas
;; SPDX-License-Identifier: MIT

(define-library (srfi 194)
  (import (scheme base)
          (scheme case-lambda)
          (scheme inexact)
          (scheme complex)
          (srfi 27)
          (srfi 133)
          (srfi 158))
  (export
    clamp-real-number
    current-random-source
    with-random-source
    make-random-integer-generator
    make-random-u1-generator
    make-random-u8-generator make-random-s8-generator
    make-random-u16-generator make-random-s16-generator
    make-random-u32-generator make-random-s32-generator
    make-random-u64-generator make-random-s64-generator
    make-random-boolean-generator
    make-random-char-generator
    make-random-string-generator
    make-random-real-generator
    make-random-rectangular-generator
    make-random-polar-generator
    make-bernoulli-generator
    make-binomial-generator
    make-categorical-generator
    make-normal-generator
    make-exponential-generator
    make-geometric-generator
    make-poisson-generator
    make-zipf-generator
    make-sphere-generator
    make-ellipsoid-generator
    make-ball-generator
    make-random-source-generator
    gsampling)
  (begin

    ;; ---- Parameters ----

    (define current-random-source (make-parameter default-random-source))

    (define (with-random-source random-source thunk)
      (unless (random-source? random-source)
        (error "expected random source"))
      (parameterize ((current-random-source random-source))
        (thunk)))

    ;; ---- Random source generator ----

    (define (make-random-source-generator s)
      (if (not (and (exact? s)
                    (integer? s)
                    (not (negative? s))))
          (error "make-random-source-generator: expected nonnegative exact integer" s)
          (let ((substream 0))
            (lambda ()
              (let ((new-source (make-random-source)))
                (random-source-pseudo-randomize! new-source s substream)
                (set! substream (+ substream 1))
                new-source)))))

    ;; ---- Primitive random generators ----

    (define (make-random-integer-generator low-bound up-bound)
      (unless (and (integer? low-bound) (exact? low-bound))
        (error "expected exact integer for lower bound"))
      (unless (and (integer? up-bound) (exact? up-bound))
        (error "expected exact integer for upper bound"))
      (unless (< low-bound up-bound)
        (error "upper bound should be greater than lower bound"))
      (let ((rand-int-proc (random-source-make-integers (current-random-source)))
            (range (- up-bound low-bound)))
        (lambda ()
          (+ low-bound (rand-int-proc range)))))

    (define (make-random-u1-generator)
      (make-random-integer-generator 0 2))
    (define (make-random-u8-generator)
      (make-random-integer-generator 0 256))
    (define (make-random-s8-generator)
      (make-random-integer-generator -128 128))
    (define (make-random-u16-generator)
      (make-random-integer-generator 0 65536))
    (define (make-random-s16-generator)
      (make-random-integer-generator -32768 32768))
    (define (make-random-u32-generator)
      (make-random-integer-generator 0 (expt 2 32)))
    (define (make-random-s32-generator)
      (make-random-integer-generator (- (expt 2 31)) (expt 2 31)))
    (define (make-random-u64-generator)
      (make-random-integer-generator 0 (expt 2 64)))
    (define (make-random-s64-generator)
      (make-random-integer-generator (- (expt 2 63)) (expt 2 63)))

    (define (clamp-real-number lower-bound upper-bound value)
      (cond ((not (real? lower-bound))
             (error "expected real number for lower bound"))
            ((not (real? upper-bound))
             (error "expected real number for upper bound"))
            ((not (<= lower-bound upper-bound))
             (error "lower bound must be <= upper bound"))
            ((< value lower-bound) lower-bound)
            ((> value upper-bound) upper-bound)
            (else value)))

    (define (make-random-real-generator low-bound up-bound)
      (unless (and (real? low-bound) (finite? low-bound))
        (error "expected finite real number for lower bound"))
      (unless (and (real? up-bound) (finite? up-bound))
        (error "expected finite real number for upper bound"))
      (unless (< low-bound up-bound)
        (error "lower bound must be < upper bound"))
      (let ((rand-real-proc (random-source-make-reals (current-random-source))))
        (lambda ()
          (let ((t (rand-real-proc)))
            (+ (* t low-bound)
               (* (- 1.0 t) up-bound))))))

    (define (make-random-rectangular-generator
              real-lower-bound real-upper-bound
              imag-lower-bound imag-upper-bound)
      (let ((real-gen (make-random-real-generator real-lower-bound real-upper-bound))
            (imag-gen (make-random-real-generator imag-lower-bound imag-upper-bound)))
        (lambda ()
          (make-rectangular (real-gen) (imag-gen)))))

    (define PI (* 4 (atan 1.0)))

    (define make-random-polar-generator
      (case-lambda
        ((magnitude-lower-bound magnitude-upper-bound)
         (make-random-polar-generator 0+0i magnitude-lower-bound magnitude-upper-bound 0 (* 2 PI)))
        ((origin magnitude-lower-bound magnitude-upper-bound)
         (make-random-polar-generator origin magnitude-lower-bound magnitude-upper-bound 0 (* 2 PI)))
        ((magnitude-lower-bound magnitude-upper-bound angle-lower-bound angle-upper-bound)
         (make-random-polar-generator 0+0i magnitude-lower-bound magnitude-upper-bound angle-lower-bound angle-upper-bound))
        ((origin magnitude-lower-bound magnitude-upper-bound angle-lower-bound angle-upper-bound)
         (unless (complex? origin)
           (error "origin should be complex number"))
         (unless (and (real? magnitude-lower-bound)
                      (real? magnitude-upper-bound)
                      (real? angle-lower-bound)
                      (real? angle-upper-bound))
           (error "magnitude and angle bounds should be real numbers"))
         (unless (and (<= 0 magnitude-lower-bound)
                      (<= 0 magnitude-upper-bound))
           (error "magnitude bounds should be positive"))
         (unless (< magnitude-lower-bound magnitude-upper-bound)
           (error "magnitude lower bound should be less than upper bound"))
         (when (= angle-lower-bound angle-upper-bound)
           (error "angle bounds shouldn't be equal"))
         (let* ((b (square magnitude-lower-bound))
                (m (- (square magnitude-upper-bound) b))
                (t-gen (make-random-real-generator 0. 1.))
                (phi-gen (make-random-real-generator angle-lower-bound angle-upper-bound)))
           (lambda ()
             (let* ((t (t-gen))
                    (phi (phi-gen))
                    (r (sqrt (+ (* m t) b))))
               (+ origin (make-polar r phi))))))))

    (define (make-random-boolean-generator)
      (let ((u1 (make-random-u1-generator)))
        (lambda ()
          (zero? (u1)))))

    (define (make-random-char-generator str)
      (when (not (string? str))
        (error "expected string"))
      (unless (> (string-length str) 0)
        (error "given string is of length 0"))
      (let ((int-gen (make-random-integer-generator 0 (string-length str))))
        (lambda ()
          (string-ref str (int-gen)))))

    (define (make-random-string-generator k str)
      (let ((char-gen (make-random-char-generator str))
            (int-gen (make-random-integer-generator 0 k)))
        (lambda ()
          (generator->string char-gen (int-gen)))))

    ;; ---- Non-uniform distributions ----

    (define (make-bernoulli-generator p)
      (unless (real? p)
        (error "expected p to be real"))
      (unless (<= 0 p 1)
        (error "expected 0 <= p <= 1"))
      (let ((rand-real-proc (random-source-make-reals (current-random-source))))
        (lambda ()
          (if (<= (rand-real-proc) p)
              1
              0))))

    (define (make-categorical-generator weights-vec)
      (let ((weight-sum
             (vector-fold
               (lambda (sum p)
                 (unless (and (number? p) (> p 0))
                   (error "parameter must be a vector of positive numbers"))
                 (+ sum p))
               0
               weights-vec))
            (length (vector-length weights-vec)))
        (let ((real-gen (make-random-real-generator 0 weight-sum)))
          (lambda ()
            (let ((roll (real-gen)))
              (let loop ((sum 0) (i 0))
                (let ((newsum (+ sum (vector-ref weights-vec i))))
                  (if (or (< roll newsum)
                          (= i (- length 1)))
                      i
                      (loop newsum (+ i 1))))))))))

    ;; Normal distribution — Box-Muller algorithm
    (define make-normal-generator
      (case-lambda
        (()
         (make-normal-generator 0.0 1.0))
        ((mean)
         (make-normal-generator mean 1.0))
        ((mean deviation)
         (let ((rand-real-proc (random-source-make-reals (current-random-source)))
               (state #f))
           (unless (and (real? mean) (finite? mean))
             (error "expected mean to be finite real number"))
           (unless (and (real? deviation) (finite? deviation) (> deviation 0))
             (error "expected deviation to be positive finite real number"))
           (lambda ()
             (if state
                 (let ((result state))
                   (set! state #f)
                   result)
                 (let* ((r (sqrt (* -2 (log (rand-real-proc)))))
                        (theta (* 2 PI (rand-real-proc))))
                   (set! state (+ mean (* deviation r (cos theta))))
                   (+ mean (* deviation r (sin theta))))))))))

    (define (make-exponential-generator mean)
      (unless (and (real? mean) (finite? mean) (positive? mean))
        (error "expected mean to be finite positive real number"))
      (let ((rand-real-proc (random-source-make-reals (current-random-source))))
        (lambda ()
          (- (* mean (log (rand-real-proc)))))))

    (define (make-geometric-generator p)
      (define (log1p x)
        (let ((u (+ 1.0 x)))
          (cond ((= u 1.0) x)
                ((= u x) (log u))
                (else (* (log u) (/ x (- u 1.0)))))))
      (unless (and (real? p) (> p 0) (<= p 1))
        (error "expected p to be real number, 0 < p <= 1"))
      (if (zero? (- p 1.))
          (lambda () 1)
          (let ((c (/ (log1p (- p))))
                (rand-real-proc (random-source-make-reals (current-random-source))))
            (lambda ()
              (exact (ceiling (* c (log (rand-real-proc)))))))))

    ;; Poisson distribution
    (define log-fact-table #f)

    (define (make-log-fact-table!)
      (let ((table (make-vector 256)))
        (vector-set! table 0 0)
        (do ((i 1 (+ i 1)))
            ((> i 255) #t)
          (vector-set! table i (+ (vector-ref table (- i 1))
                                  (log (+ i 1)))))
        (set! log-fact-table table)))

    (define (log-of-fact n)
      (when (not log-fact-table)
        (make-log-fact-table!))
      (cond
        ((<= n 1) 0)
        ((<= n 256) (vector-ref log-fact-table (- n 1)))
        (else (let ((x (+ n 1)))
                (+ (* (- x 0.5) (log x))
                   (- x)
                   (* 0.5 (log (* 2 PI)))
                   (/ 1.0 (* x 12.0)))))))

    (define (make-poisson/small rand-real-proc L)
      (lambda ()
        (do ((exp-L (exp (- L)))
             (k 0 (+ k 1))
             (p 1.0 (* p (rand-real-proc))))
            ((<= p exp-L) (- k 1)))))

    (define (make-poisson/large rand-real-proc L)
      (let* ((c (- 0.767 (/ 3.36 L)))
             (beta (/ PI (sqrt (* 3 L))))
             (alpha (* beta L))
             (k (- (log c) L (log beta))))
        (define (loop)
          (let* ((u (rand-real-proc))
                 (x (/ (- alpha (log (/ (- 1.0 u) u))) beta))
                 (n (exact (floor (+ x 0.5)))))
            (if (< n 0)
                (loop)
                (let* ((v (rand-real-proc))
                       (y (- alpha (* beta x)))
                       (t (+ 1.0 (exp y)))
                       (lhs (+ y (log (/ v (* t t)))))
                       (rhs (+ k (* n (log L)) (- (log-of-fact n)))))
                  (if (<= lhs rhs)
                      n
                      (loop))))))
        loop))

    (define (make-poisson-generator L)
      (unless (and (real? L) (finite? L) (> L 0))
        (error "expected L to be finite positive real number"))
      (let ((rand-real-proc (random-source-make-reals (current-random-source))))
        (if (< L 30)
            (make-poisson/small rand-real-proc L)
            (make-poisson/large rand-real-proc L))))

    ;; gsampling
    (define (gsampling . generators-lst)
      (let ((gen-vec (list->vector generators-lst))
            (rand-int-proc (random-source-make-integers (current-random-source))))
        (define (remove-gen index)
          (let ((new-vec (make-vector (- (vector-length gen-vec) 1))))
            (when (> index 0)
              (vector-copy! new-vec 0 gen-vec 0 index))
            (when (< index (- (vector-length gen-vec) 1))
              (vector-copy! new-vec index gen-vec (+ 1 index)))
            (set! gen-vec new-vec)))
        (define (pick)
          (let* ((index (rand-int-proc (vector-length gen-vec)))
                 (gen (vector-ref gen-vec index))
                 (value (gen)))
            (if (eof-object? value)
                (begin
                  (remove-gen index)
                  (if (= (vector-length gen-vec) 0)
                      (eof-object)
                      (pick)))
                value)))
        (lambda ()
          (if (= 0 (vector-length gen-vec))
              (eof-object)
              (pick)))))

    ;; ---- Binomial distribution ----

    (define (stirling-tail k)
      (let ((small-k-table
             '#(.08106146679532726
                .0413406959554093
                .02767792568499834
                .020790672103765093
                .016644691189821193
                .013876128823070748
                .01189670994589177
                .010411265261972096
                .009255462182712733
                .00833056343336287
                .007573675487951841
                .00694284010720953
                .006408994188004207
                .0059513701127588475
                .005554733551962801
                .0052076559196096404
                .004901395948434738
                .004629153749334028
                .004385560249232324
                .004166319691996922)))
        (if (< k 20)
            (vector-ref small-k-table k)
            (let* ((inexact-k+1 (inexact (+ k 1)))
                   (inexact-k+1^2 (square inexact-k+1)))
              (/ (- #i1/12
                    (/ (- #i1/360
                          (/ #i1/1260 inexact-k+1^2))
                       inexact-k+1^2))
                 inexact-k+1)))))

    (define (make-binomial-generator n p)
      (if (not (and (real? p)
                    (<= 0 p 1)
                    (exact-integer? n)
                    (positive? n)))
          (error "make-binomial-generator: bad parameters" n p)
          (cond ((< 1/2 p)
                 (let ((complement (make-binomial-generator n (- 1 p))))
                   (lambda ()
                     (- n (complement)))))
                ((zero? p)
                 (lambda () 0))
                ((< (* n p) 10)
                 (binomial-geometric n p))
                (else
                 (binomial-rejection n p)))))

    (define (binomial-geometric n p)
      (let ((geom (make-geometric-generator p)))
        (lambda ()
          (let loop ((X -1) (sum 0))
            (if (< n sum)
                X
                (loop (+ X 1) (+ sum (geom))))))))

    (define (binomial-rejection n p)
      (let* ((spq (inexact (sqrt (* n p (- 1 p)))))
             (b (+ 1.15 (* 2.53 spq)))
             (a (+ -0.0873 (* 0.0248 b) (* 0.01 p)))
             (c (+ (* n p) 0.5))
             (v_r (- 0.92 (/ 4.2 b)))
             (alpha (* (+ 2.83 (/ 5.1 b)) spq))
             (lpq (log (/ p (- 1 p))))
             (m (exact (floor (* (+ n 1) p))))
             (rand-real-proc (random-source-make-reals (current-random-source))))
        (lambda ()
          (let loop ()
            (let* ((u (rand-real-proc))
                   (v (rand-real-proc))
                   (u (- u 0.5))
                   (us (- 0.5 (abs u)))
                   (k (exact (floor (+ (* (+ (* 2. (/ a us)) b) u) c)))))
              (cond ((or (< k 0) (< n k))
                     (loop))
                    ((and (<= 0.07 us) (<= v v_r))
                     k)
                    (else
                     (let ((v (log (* v (/ alpha (+ (/ a (square us)) b))))))
                       (if (<= v
                               (+ (* (+ m 0.5)
                                     (log (* (/ (+ m 1.)
                                                (- n m -1.)))))
                                  (* (+ n 1.)
                                     (log (/ (- n m -1.)
                                             (- n k -1.))))
                                  (* (+ k 0.5)
                                     (log (* (/ (- n k -1.)
                                                (+ k 1.)))))
                                  (* (- k m) lpq)
                                  (- (+ (stirling-tail m)
                                        (stirling-tail (- n m)))
                                     (+ (stirling-tail k)
                                        (stirling-tail (- n k))))))
                           k
                           (loop))))))))))

    ;; ---- Zipf distribution ----

    (define (make-zipf-generator/zri n s q)
      (let* ((_1-s (- 1 s))
             (oms (/ 1 _1-s)))
        (define (hat x)
          (expt (+ x q) (- s)))
        (define (big-h x)
          (/ (expt (+ q x) _1-s) _1-s))
        (define (big-h-inv y)
          (- (expt (* y _1-s) oms) q))
        (let* ((big-h-half (- (big-h 1.5) (hat 1)))
               (big-h-n (big-h (+ n 0.5)))
               (cut (- 1 (big-h-inv (- (big-h 1.5) (hat 1)))))
               (dist (make-random-real-generator big-h-half big-h-n)))
          (define (try)
            (let* ((u (dist))
                   (x (big-h-inv u))
                   (kflt (floor (+ x 0.5)))
                   (k (exact kflt)))
              (if (and (< 0 k)
                       (or (<= (- k x) cut)
                           (>= u (- (big-h (+ k 0.5)) (hat k)))))
                  k
                  #f)))
          (define (loop-until)
            (let ((k (try)))
              (if k k (loop-until))))
          loop-until)))

    (define (make-zipf-generator/one n s q)
      (let ((_1-s (- 1 s)))
        (define (hat x)
          (let ((xpq (+ x q)))
            (/ (expt xpq _1-s) xpq)))
        (define (exn lg)
          (define (trm n u lg) (* lg (+ 1 (/ (* _1-s u) n))))
          (trm 2 (trm 3 (trm 4 1 lg) lg) lg))
        (define (lg y)
          (let ((yms (* y _1-s)))
            (define (trm n u r) (- (/ 1 n) (* u r)))
            (* y (trm 1 yms (trm 2 yms (trm 3 yms (trm 4 yms 0)))))))
        (define (big-h x)
          (exn (log (+ q x))))
        (define (big-h-inv y)
          (- (exp (lg y)) q))
        (let* ((big-h-half (- (big-h 1.5) (hat 1)))
               (big-h-n (big-h (+ n 0.5)))
               (cut (- 1 (big-h-inv (- (big-h 1.5) (/ 1 (+ 1 q))))))
               (dist (make-random-real-generator big-h-half big-h-n)))
          (define (try)
            (let* ((u (dist))
                   (x (big-h-inv u))
                   (kflt (floor (+ x 0.5)))
                   (k (exact kflt)))
              (if (and (< 0 k)
                       (or (<= (- k x) cut)
                           (>= u (- (big-h (+ k 0.5)) (hat k)))))
                  k
                  #f)))
          (define (loop-until)
            (let ((k (try)))
              (if k k (loop-until))))
          loop-until)))

    (define make-zipf-generator
      (case-lambda
        ((n) (make-zipf-generator n 1.0 0.0))
        ((n s) (make-zipf-generator n s 0.0))
        ((n s q)
         (if (< 1e-5 (abs (- 1 s)))
             (make-zipf-generator/zri n s q)
             (make-zipf-generator/one n s q)))))

    ;; ---- Sphere, ellipsoid, ball ----

    (define (make-ellipsoid-generator* axes)
      (let ((gauss (make-normal-generator))
            (uniform (make-random-real-generator 0. 1.))
            (min-axis (vector-fold min +inf.0 axes)))

        (define (sphere)
          (let* ((point
                  (vector-map (lambda (_) (gauss)) axes))
                 (norm-inverse
                  (/ (sqrt (vector-fold (lambda (sum x)
                                          (+ sum (square x)))
                                        0.
                                        point)))))
            (vector-map (lambda (x) (* x norm-inverse)) point)))

        (define (ellipsoid-distance ray)
          (sqrt (vector-fold
                 (lambda (sum x a) (+ sum (square (/ x a))))
                 0. ray axes)))

        (define (keep point)
          (< (uniform)
             (* min-axis (ellipsoid-distance point))))

        (define (sample)
          (let ((point (sphere)))
            (if (keep point)
                point
                (sample))))

        (lambda ()
          (vector-map * (sample) axes))))

    (define (make-sphere-generator arg)
      (cond
        ((and (integer? arg) (exact? arg) (positive? arg))
         (make-ellipsoid-generator* (make-vector (+ 1 arg) 1.0)))
        (else
         (error "make-sphere-generator: argument must be a positive exact integer" arg))))

    (define (make-ellipsoid-generator arg)
      (define (return-error)
        (error "make-ellipsoid-generator: argument must be a vector of positive finite reals" arg))
      (if (and (vector? arg)
               (vector-every real? arg))
          (let ((inexact-arg (vector-map inexact arg)))
            (if (vector-every (lambda (x)
                                (and (positive? x) (finite? x)))
                              inexact-arg)
                (make-ellipsoid-generator* inexact-arg)
                (return-error)))
          (return-error)))

    (define (make-ball-generator arg)
      (define (return-error)
        (error "make-ball-generator: argument must be a positive exact integer or vector of positive finite reals" arg))
      (if (and (integer? arg) (exact? arg) (positive? arg))
          (make-ball-generator* (make-vector arg 1.0))
          (if (and (vector? arg)
                   (vector-every real? arg))
              (let ((inexact-arg (vector-map inexact arg)))
                (if (vector-every (lambda (x)
                                    (and (positive? x) (finite? x)))
                                  inexact-arg)
                    (make-ball-generator* inexact-arg)
                    (return-error)))
              (return-error))))

    (define (make-ball-generator* axes)
      (let ((sphere-generator
             (make-sphere-generator (+ (vector-length axes) 1))))
        (lambda ()
          (vector-map (lambda (el axis)
                        (* el axis))
                      (sphere-generator)
                      axes))))

    ))
