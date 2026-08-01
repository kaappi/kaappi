;;; Audit: lib/srfi/27.sld + src/primitives_random.zig (SRFI 27 — Sources of
;;; Random Bits)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 27, https://srfi.schemers.org/srfi-27/srfi-27.html
;;;
;;; There is no tests/scheme/srfi/srfi27.scm — the two existing files
;;; (srfi-27-unit.scm, srfi27-state.scm) never mention random-integer,
;;; random-real, random-source? or random-source-randomize!.
;;;
;;; A random source cannot be asserted by value, so this file asserts the two
;;; things the spec DOES fix:
;;;   * shape — exactness, range, and the exclusivity of each bound;
;;;   * reproducibility — the same pseudo-randomization or the same restored
;;;     state must replay the same sequence, and different seeds must not.
;;; Distributional sanity is asserted only as "every bucket of a small range
;;; is hit at least once over many draws", which is a property, not a value.
;;;
;;; Known and NOT re-filed: #1913 (the all-zero-seed random port's own state
;;; fails random-port-state?) is a SRFI 271 issue over the same primitives.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi27-audit.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 27))

(test-begin "srfi27 audit")

(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))

(define (repeat n proc)
  (let loop ((i 0) (acc '())) (if (= i n) (reverse acc) (loop (+ i 1) (cons (proc) acc)))))

;;; ------------------------------------------------------------------
;;; random-integer. "(random-integer n) -> Returns the next number of the
;;; sequence ... an exact integer in {0, ..., n-1}."
;;; ------------------------------------------------------------------

(test-assert "random-integer 10 always lands in [0,10)"
             (let loop ((i 0))
               (or (= i 2000)
                   (let ((r (random-integer 10)))
                     (and (exact-integer? r) (>= r 0) (< r 10) (loop (+ i 1)))))))
(test-assert "random-integer 1 is always 0"
             (let loop ((i 0)) (or (= i 200) (and (= 0 (random-integer 1)) (loop (+ i 1))))))
(test-assert "random-integer's upper bound is exclusive: 2 never yields 2"
             (let loop ((i 0)) (or (= i 2000) (and (< (random-integer 2) 2) (loop (+ i 1))))))
(test-assert "random-integer 2 does yield both 0 and 1 over many draws"
             (let loop ((i 0) (saw0 #f) (saw1 #f))
               (cond ((and saw0 saw1) #t)
                     ((= i 2000) #f)
                     (else (let ((r (random-integer 2)))
                             (loop (+ i 1) (or saw0 (= r 0)) (or saw1 (= r 1))))))))
(test-assert "random-integer 8 hits every bucket over many draws"
             (let ((seen (make-vector 8 #f)))
               (let loop ((i 0))
                 (when (< i 4000) (vector-set! seen (random-integer 8) #t) (loop (+ i 1))))
               (let check ((j 0)) (or (= j 8) (and (vector-ref seen j) (check (+ j 1)))))))
(test-assert "random-integer accepts a bignum bound and stays inside it"
             (let ((n (expt 2 100)))
               (let loop ((i 0))
                 (or (= i 200)
                     (let ((r (random-integer n)))
                       (and (exact-integer? r) (>= r 0) (< r n) (loop (+ i 1))))))))
(test-assert "random-integer of a bignum bound is not always small"
             (let ((n (expt 2 100)))
               (let loop ((i 0))
                 (cond ((= i 200) #f)
                       ((> (random-integer n) (expt 2 90)) #t)
                       (else (loop (+ i 1)))))))
;; "It is an error if n is not a positive integer."
(test-assert "random-integer 0 is rejected" (raises? (lambda () (random-integer 0))))
(test-assert "random-integer with a negative bound is rejected"
             (raises? (lambda () (random-integer -5))))

;;; ------------------------------------------------------------------
;;; random-real. "Returns the next number of the sequence ... an inexact
;;; number strictly between 0 and 1."
;;; ------------------------------------------------------------------

(test-assert "random-real is inexact and strictly inside (0,1)"
             (let loop ((i 0))
               (or (= i 2000)
                   (let ((r (random-real)))
                     (and (real? r) (inexact? r) (> r 0) (< r 1) (loop (+ i 1)))))))
(test-assert "random-real is not constant"
             (let ((a (random-real)))
               (let loop ((i 0)) (cond ((= i 200) #f)
                                       ((not (= a (random-real))) #t)
                                       (else (loop (+ i 1)))))))
(test-assert "random-real covers both halves of (0,1) over many draws"
             (let loop ((i 0) (lo #f) (hi #f))
               (cond ((and lo hi) #t)
                     ((= i 2000) #f)
                     (else (let ((r (random-real)))
                             (loop (+ i 1) (or lo (< r 0.5)) (or hi (> r 0.5))))))))

;;; ------------------------------------------------------------------
;;; Random sources
;;; ------------------------------------------------------------------

(test-assert "random-source? on the default source" (random-source? default-random-source))
(test-assert "random-source? on a fresh source" (random-source? (make-random-source)))
(test-assert "random-source? on a number" (not (random-source? 42)))
(test-assert "random-source? on a procedure" (not (random-source? car)))
(test-assert "make-random-source returns a new object each time"
             (not (eq? (make-random-source) (make-random-source))))
(test-assert "make-random-source is not the default source"
             (not (eq? (make-random-source) default-random-source)))
(test-assert "random-source-make-integers returns a procedure"
             (procedure? (random-source-make-integers (make-random-source))))
(test-assert "random-source-make-reals returns a procedure"
             (procedure? (random-source-make-reals (make-random-source))))
(test-assert "an integers generator from the default source obeys its bound"
             (let ((g (random-source-make-integers default-random-source)))
               (let loop ((i 0))
                 (or (= i 500)
                     (let ((r (g 100))) (and (exact-integer? r) (>= r 0) (< r 100)
                                             (loop (+ i 1))))))))
(test-assert "an integers generator rejects a bound of 0"
             (raises? (lambda () ((random-source-make-integers (make-random-source)) 0))))
(test-assert "a reals generator with no unit stays strictly inside (0,1)"
             (let ((g (random-source-make-reals (make-random-source))))
               (let loop ((i 0))
                 (or (= i 500) (let ((r (g))) (and (> r 0) (< r 1) (loop (+ i 1))))))))
;; "unit must satisfy 0 < unit < 1"
(test-assert "a reals generator with unit 1/10 stays strictly inside (0,1)"
             (let ((g (random-source-make-reals (make-random-source) 1/10)))
               (let loop ((i 0))
                 (or (= i 500) (let ((r (g))) (and (> r 0) (< r 1) (loop (+ i 1))))))))
(test-assert "a reals generator with an exact unit yields multiples of it"
             (let ((g (random-source-make-reals (make-random-source) 1/8)))
               (let loop ((i 0))
                 (or (= i 200) (and (exact-integer? (* 8 (g))) (loop (+ i 1)))))))
(test-assert "random-source-make-reals rejects a unit of 1"
             (raises? (lambda () (random-source-make-reals (make-random-source) 1))))
(test-assert "random-source-make-reals rejects a unit above 1"
             (raises? (lambda () (random-source-make-reals (make-random-source) 2))))
(test-assert "random-source-make-reals rejects a unit of 0"
             (raises? (lambda () (random-source-make-reals (make-random-source) 0))))
(test-assert "random-source-make-reals rejects a negative unit"
             (raises? (lambda () (random-source-make-reals (make-random-source) -1/2))))

;;; ------------------------------------------------------------------
;;; Reproducibility. "random-source-pseudo-randomize! changes the state of
;;; the random source s into the initial state of the (i, j)-th independent
;;; random source" — the SAME (i, j) must therefore replay the SAME sequence.
;;; ------------------------------------------------------------------

(define (draws-after-pseudo i j n)
  (let ((s (make-random-source)))
    (random-source-pseudo-randomize! s i j)
    (let ((g (random-source-make-integers s)))
      (repeat n (lambda () (g 1000000))))))

(test-equal "the same (i,j) replays the same sequence"
            (draws-after-pseudo 1 2 10) (draws-after-pseudo 1 2 10))
(test-equal "the same (i,j) replays the same sequence at (0,0)"
            (draws-after-pseudo 0 0 10) (draws-after-pseudo 0 0 10))
(test-equal "the same (i,j) replays the same sequence for large indices"
            (draws-after-pseudo 12345 67890 10) (draws-after-pseudo 12345 67890 10))
(test-assert "a different i gives a different sequence"
             (not (equal? (draws-after-pseudo 1 2 10) (draws-after-pseudo 3 2 10))))
(test-assert "a different j gives a different sequence"
             (not (equal? (draws-after-pseudo 1 2 10) (draws-after-pseudo 1 4 10))))
(test-assert "(0,0) and (1,1) are different sources"
             (not (equal? (draws-after-pseudo 0 0 10) (draws-after-pseudo 1 1 10))))
(test-assert "pseudo-randomize! on the SAME source object resets it"
             (let ((s (make-random-source)))
               (random-source-pseudo-randomize! s 7 8)
               (let* ((g1 (random-source-make-integers s))
                      (a (repeat 10 (lambda () (g1 1000000)))))
                 (random-source-pseudo-randomize! s 7 8)
                 (let ((g2 (random-source-make-integers s)))
                   (equal? a (repeat 10 (lambda () (g2 1000000))))))))
(test-assert "a pseudo-randomized sequence is not constant"
             (let ((d (draws-after-pseudo 5 5 20)))
               (let loop ((l (cdr d))) (cond ((null? l) #f)
                                             ((not (= (car l) (car d))) #t)
                                             (else (loop (cdr l)))))))
(test-assert "every draw of a pseudo-randomized sequence obeys its bound"
             (let loop ((l (draws-after-pseudo 9 9 50)))
               (or (null? l) (and (exact-integer? (car l)) (>= (car l) 0) (< (car l) 1000000)
                                  (loop (cdr l))))))

;;; ------------------------------------------------------------------
;;; State capture and restore. "random-source-state-ref returns an external
;;; representation of the internal state of s" and state-set! restores it.
;;; ------------------------------------------------------------------

(test-assert "restoring a captured state replays the same sequence"
             (let* ((s (make-random-source))
                    (st (random-source-state-ref s))
                    (g (random-source-make-integers s))
                    (a (repeat 10 (lambda () (g 1000000)))))
               (random-source-state-set! s st)
               (let ((g2 (random-source-make-integers s)))
                 (equal? a (repeat 10 (lambda () (g2 1000000)))))))
(test-assert "a state captured mid-sequence resumes from that point"
             (let* ((s (make-random-source))
                    (g (random-source-make-integers s)))
               (repeat 5 (lambda () (g 1000000)))
               (let* ((st (random-source-state-ref s))
                      (a (repeat 10 (lambda () (g 1000000)))))
                 (random-source-state-set! s st)
                 (equal? a (repeat 10 (lambda () (g 1000000)))))))
(test-assert "a state copied into a DIFFERENT source replays the same sequence"
             (let* ((s (make-random-source)) (t (make-random-source)))
               (random-source-state-set! t (random-source-state-ref s))
               (let ((g (random-source-make-integers s)) (h (random-source-make-integers t)))
                 (equal? (repeat 10 (lambda () (g 100000)))
                         (repeat 10 (lambda () (h 100000)))))))
(test-assert "a captured state survives being captured again unchanged"
             (let* ((s (make-random-source))
                    (st1 (random-source-state-ref s))
                    (st2 (random-source-state-ref s)))
               (random-source-state-set! s st1)
               (let ((a (repeat 5 (lambda () ((random-source-make-integers s) 100000)))))
                 (random-source-state-set! s st2)
                 (equal? a (repeat 5 (lambda () ((random-source-make-integers s) 100000)))))))
(test-assert "a state captured after pseudo-randomization restores that source"
             (let ((s (make-random-source)))
               (random-source-pseudo-randomize! s 11 22)
               (let* ((st (random-source-state-ref s))
                      (g (random-source-make-integers s))
                      (a (repeat 10 (lambda () (g 1000)))))
                 (random-source-state-set! s st)
                 (let ((g2 (random-source-make-integers s)))
                   (equal? a (repeat 10 (lambda () (g2 1000))))))))
(test-assert "two sources pseudo-randomized differently have different states"
             (let ((s (make-random-source)) (t (make-random-source)))
               (random-source-pseudo-randomize! s 1 1)
               (random-source-pseudo-randomize! t 2 2)
               (not (equal? (random-source-state-ref s) (random-source-state-ref t)))))
(test-assert "a source's own state round-trips through state-set! unchanged"
             (let* ((s (make-random-source)) (st (random-source-state-ref s)))
               (random-source-state-set! s st)
               (equal? st (random-source-state-ref s))))

;;; ------------------------------------------------------------------
;;; randomize!. Nothing about its result is specified beyond "changes the
;;; state ... to a truly random one", so only the call and its effect on
;;; subsequent draws are asserted.
;;; ------------------------------------------------------------------

(test-assert "random-source-randomize! runs without error"
             (begin (random-source-randomize! (make-random-source)) #t))
(test-assert "a randomized source still produces in-range integers"
             (let ((s (make-random-source)))
               (random-source-randomize! s)
               (let ((g (random-source-make-integers s)))
                 (let loop ((i 0))
                   (or (= i 500) (let ((r (g 100))) (and (>= r 0) (< r 100) (loop (+ i 1)))))))))
(test-assert "randomize! changes the state away from a pseudo-randomized one"
             (let ((s (make-random-source)))
               (random-source-pseudo-randomize! s 1 1)
               (let ((before (random-source-state-ref s)))
                 (random-source-randomize! s)
                 (not (equal? before (random-source-state-ref s))))))
(test-assert "randomize! on the default source runs without error"
             (begin (random-source-randomize! default-random-source) #t))

;;; ------------------------------------------------------------------
;;; Independence of sources
;;; ------------------------------------------------------------------

(test-assert "drawing from one source does not advance another"
             (let ((s (make-random-source)) (t (make-random-source)))
               (random-source-pseudo-randomize! s 3 3)
               (random-source-pseudo-randomize! t 3 3)
               (let ((g (random-source-make-integers s)) (h (random-source-make-integers t)))
                 (g 1000) (g 1000) (g 1000)
                 ;; t has not been drawn from; its next value must equal s's first.
                 (random-source-pseudo-randomize! s 3 3)
                 (let ((g2 (random-source-make-integers s)))
                   (= (g2 1000) (h 1000))))))
(test-assert "two generators made from the same source share its state"
             (let ((s (make-random-source)))
               (random-source-pseudo-randomize! s 4 4)
               (let* ((g (random-source-make-integers s))
                      (h (random-source-make-integers s))
                      (a (g 1000000)) (b (h 1000000)))
                 ;; a and b come from consecutive draws of one stream, so
                 ;; replaying the source must reproduce both, in order.
                 (random-source-pseudo-randomize! s 4 4)
                 (let ((k (random-source-make-integers s)))
                   (and (= a (k 1000000)) (= b (k 1000000)))))))

(let ((runner (test-runner-current)))
  (test-end "srfi27 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
