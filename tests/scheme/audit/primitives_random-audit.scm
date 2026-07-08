;; Audit tests for src/primitives_random.zig (SRFI-27) — audit Phase 2.15
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/audit/primitives_random-audit.scm

(import (scheme base) (scheme read) (srfi 27) (chibi test))

(test-begin "primitives_random audit")

;;; --- random-source? ---
(test #t (random-source? (make-random-source)))
(test #f (random-source? 42))
(test #f (random-source? "rs"))
(test #f (random-source? #f))
(test #f (random-source? '()))

;;; --- default-random-source ---
;; SRFI-27: "default-random-source — A random source from which random-integer
;; and random-real have been derived ... an assignment to default-random-source
;; does not change random or random-real" — i.e. it is a variable bound to a
;; random source, not a procedure.
(test #t (random-source? default-random-source))

;; random-integer draws from default-random-source: restoring the default
;; source's state reproduces the random-integer sequence.
(let* ((d default-random-source)
       (st (random-source-state-ref d))
       (x1 (random-integer 1000000)))
  (random-source-state-set! d st)
  (test x1 (random-integer 1000000)))

;;; --- random-integer ---
;; n = 1 has only one possible result
(test 0 (random-integer 1))

;; 500 draws over {0..9}: all in range, exact integers, and every value hit
;; (probability of missing a value is ~1e-22)
(let loop ((i 0) (seen '()) (ok #t))
  (if (= i 500)
      (begin
        (test #t ok)
        (test 10 (length seen)))
      (let ((r (random-integer 10)))
        (loop (+ i 1)
              (if (member r seen) seen (cons r seen))
              (and ok (exact? r) (integer? r) (>= r 0) (< r 10))))))

;; large fixnum range works
(let ((r (random-integer (expt 2 40))))
  (test #t (and (>= r 0) (< r (expt 2 40)))))

;; SRFI-27: "The argument n must be a positive integer, otherwise an error is
;; signalled." (expt 2 64) is a positive integer, so it must be accepted.
;; FAIL: #1193 (random-integer rejects exact integers wider than fixnums)
;; (test #t (let ((r (random-integer (expt 2 64))))
;;            (and (>= r 0) (< r (expt 2 64)))))

;; invalid arguments raise catchable errors
(test #t (guard (e (#t (error-object? e))) (random-integer 0) #f))
(test #t (guard (e (#t (error-object? e))) (random-integer -5) #f))
(test #t (guard (e (#t (error-object? e))) (random-integer "10") #f))
(test #t (guard (e (#t (error-object? e))) (random-integer 'ten) #f))

;;; --- random-real ---
;; SRFI-27: "The next number 0 < x < 1 obtained from default-random-source."
(let loop ((i 0) (ok #t))
  (if (= i 200)
      (test #t ok)
      (let ((r (random-real)))
        (loop (+ i 1) (and ok (real? r) (inexact? r) (> r 0) (< r 1))))))

;;; --- make-random-source determinism ---
;; SRFI-27: "Each random source obtained as (make-random-source) generates the
;; same stream of values, unless the state is modified"
(let* ((s1 (make-random-source))
       (s2 (make-random-source))
       (r1 (random-source-make-integers s1))
       (r2 (random-source-make-integers s2)))
  (test (r1 1000000) (r2 1000000))
  (test (r1 1000000) (r2 1000000))
  (test (r1 1000000) (r2 1000000)))

;;; --- source independence ---
;; advancing one source must not perturb another
(let* ((s1 (make-random-source))
       (s2 (make-random-source))
       (r1 (random-source-make-integers s1))
       (r2 (random-source-make-integers s2))
       (first (r1 1000000)))
  (r1 1000000) (r1 1000000) (r1 1000000)
  (test first (r2 1000000)))

;;; --- random-source-make-integers ---
(let* ((s (make-random-source))
       (rand (random-source-make-integers s)))
  (test 0 (rand 1))
  (let ((r (rand 100)))
    (test #t (and (>= r 0) (< r 100))))
  (test #t (guard (e (#t (error-object? e))) (rand 0) #f))
  (test #t (guard (e (#t (error-object? e))) (rand -1) #f))
  (test #t (guard (e (#t (error-object? e))) (rand 1.5) #f))
  ;; bignum range must be accepted (same requirement as random-integer)
  ;; FAIL: #1193 (%rs-next-int rejects exact integers wider than fixnums)
  ;; (test #t (let ((r (rand (expt 2 64)))) (and (>= r 0) (< r (expt 2 64)))))
  )

;; a generator made from a non-source raises when called
(test #t (guard (e (#t (error-object? e)))
           ((random-source-make-integers 42) 5) #f))

;;; --- random-source-make-reals ---
(let* ((s (make-random-source))
       (rand (random-source-make-reals s)))
  (let ((r (rand)))
    (test #t (and (inexact? r) (> r 0) (< r 1)))))

;; flonum unit: results are flonums in (0,1) — type matches unit
(let* ((s (make-random-source))
       (rand (random-source-make-reals s 0.5)))
  (let ((r (rand)))
    (test #t (and (inexact? r) (> r 0) (< r 1)))))

;; SRFI-27: "The numbers created by rand are of the same numerical type as
;; unit and the potential output values are spaced by at most unit." With an
;; exact unit the results must be exact.
;; FAIL: #1194 (random-source-make-reals ignores the unit argument)
;; (test #t (exact? ((random-source-make-reals (make-random-source) 1/10))))

;; unit outside (0,1) is rejected
(test #t (guard (e (#t (error-object? e)))
           (random-source-make-reals (make-random-source) 2) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-make-reals (make-random-source) 0) #f))

;;; --- random-source-randomize! ---
;; SRFI-27: "Makes an effort to set the state of the random source s to a
;; truly random state." A randomized source should diverge from a fresh one.
(let* ((s1 (make-random-source))
       (s2 (make-random-source)))
  (random-source-randomize! s1)
  (let ((r1 (random-source-make-integers s1))
        (r2 (random-source-make-integers s2)))
    (test #f (and (= (r1 (expt 2 40)) (r2 (expt 2 40)))
                  (= (r1 (expt 2 40)) (r2 (expt 2 40)))
                  (= (r1 (expt 2 40)) (r2 (expt 2 40)))))))
(test #t (guard (e (#t (error-object? e))) (random-source-randomize! 42) #f))

;;; --- random-source-pseudo-randomize! ---
;; SRFI-27: "Changes the state of the random source s into the initial state
;; of the (i, j)-th independent random source, where i and j are non-negative
;; integers." Same (i,j) must give the same stream.
(let ((s1 (make-random-source)) (s2 (make-random-source)))
  (random-source-pseudo-randomize! s1 5 7)
  (random-source-pseudo-randomize! s2 5 7)
  (let ((r1 (random-source-make-integers s1))
        (r2 (random-source-make-integers s2)))
    (test (r1 1000000) (r2 1000000))
    (test (r1 1000000) (r2 1000000))))

;; distinct (i,j) give distinct streams (with very high probability)
(let ((s1 (make-random-source)) (s2 (make-random-source)))
  (random-source-pseudo-randomize! s1 0 1)
  (random-source-pseudo-randomize! s2 1 0)
  (let ((r1 (random-source-make-integers s1))
        (r2 (random-source-make-integers s2)))
    (test #f (and (= (r1 (expt 2 40)) (r2 (expt 2 40)))
                  (= (r1 (expt 2 40)) (r2 (expt 2 40)))))))

;; invalid arguments raise catchable errors
(test #t (guard (e (#t (error-object? e)))
           (random-source-pseudo-randomize! 42 0 0) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-pseudo-randomize! (make-random-source) -1 0) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-pseudo-randomize! (make-random-source) 0 -1) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-pseudo-randomize! (make-random-source) 0.5 0) #f))

;; i and j are unbounded non-negative integers
;; FAIL: #1193 (pseudo-randomize! rejects exact integers wider than fixnums)
;; (test #t (begin (random-source-pseudo-randomize!
;;                  (make-random-source) (expt 2 64) 1)
;;                 #t))

;;; --- random-source-state-ref / random-source-state-set! ---
;; round-trip reproduces the stream
(let* ((s (make-random-source))
       (rand (random-source-make-integers s)))
  (rand 100) (rand 100)
  (let* ((st (random-source-state-ref s))
         (a (rand 1000000))
         (b (rand 1000000)))
    (random-source-state-set! s st)
    (test a (rand 1000000))
    (test b (rand 1000000))))

;; state transplant between sources
(let* ((s1 (make-random-source))
       (s2 (make-random-source))
       (r1 (random-source-make-integers s1))
       (r2 (random-source-make-integers s2)))
  (random-source-randomize! s1)
  (random-source-state-set! s2 (random-source-state-ref s1))
  (test (r1 1000000) (r2 1000000)))

;; SRFI-27: "It is, however, required that a state possess an external
;; representation." write → read round-trip must reproduce the stream.
(let ((s (make-random-source)))
  (random-source-randomize! s)
  (let* ((st (random-source-state-ref s))
         (str (let ((p (open-output-string)))
                (write st p)
                (get-output-string p)))
         (st2 (read (open-input-string str)))
         (rand (random-source-make-integers s))
         (a (rand 1000000)))
    (random-source-state-set! s st2)
    (test a (rand 1000000))))

;; invalid states raise catchable errors
(test #t (guard (e (#t (error-object? e)))
           (random-source-state-set! (make-random-source) '()) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-state-set! (make-random-source) '(1 2 3)) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-state-set! (make-random-source) 42) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-state-set! (make-random-source) '(1 2 3 "x")) #f))
;; all-zero state would wedge the Xoshiro generator
(test #t (guard (e (#t (error-object? e)))
           (random-source-state-set! (make-random-source) '(0 0 0 0)) #f))
(test #t (guard (e (#t (error-object? e)))
           (random-source-state-ref 42) #f))

(test-end "primitives_random audit")
