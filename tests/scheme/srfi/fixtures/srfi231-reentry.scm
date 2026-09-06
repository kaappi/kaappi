;; Shared driver for the SRFI 231 call/cc-safety regressions (kaappi#2539,
;; reported by the SRFI's author). Included by the srfi231-*.scm suites;
;; a fixture, so it opens no SRFI-64 suite of its own.
;;
;; (re-entry-results collect) drives `collect` -- a procedure of one
;; argument, a getter over 0..3 that captures its continuation at x=1 and
;; x=3 on the first run -- through a two-continuation, two-re-entry
;; schedule and returns every result, newest first. Any collector keeping
;; a shared mutable accumulator -- a set! cell or a scratch vector --
;; leaks the second cont1 re-entry's 20 into both cont2 results; one
;; re-entry alone cannot see that, which is how the scratch design passed
;; the official suite's continuation cases. re-entry-expected is the
;; answer for a collector that returns the four values in order.
(define (re-entry-results collect)
  (let* ((cont1 #f) (cont2 #f) (i 5) (first-run? #t)
         (f (lambda (x)
              (call-with-current-continuation
               (lambda (c)
                 (if first-run?
                     (case x ((1) (set! cont1 c)) ((3) (set! cont2 c)) (else #f)))
                 x))))
         (results '()))
    (let ((r (collect f)))
      (set! first-run? #f)
      (set! results (cons r results)))
    (case i
      ((5) (set! i (- i 1)) (cont1 10))
      ((4) (set! i (- i 1)) (cont1 20))
      ((3) (set! i (- i 1)) (cont2 10))
      ((2) (set! i (- i 1)) (cont2 20))
      (else #t))
    results))
(define re-entry-expected '((0 1 2 20) (0 1 2 10) (0 20 2 3) (0 10 2 3) (0 1 2 3)))
