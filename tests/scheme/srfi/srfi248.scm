;; SRFI 248 — Minimal Delimited Continuations.
;;
;; Exercises with-unwind-handler, empty-continuation?, and the extended guard
;; (with a continuation variable) against the examples in the SRFI, plus the
;; interaction with plain raise, runtime errors, and re-raising to an outer
;; handler.
(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 248))

(test-begin "srfi-248")

;; ---- with-unwind-handler ----

(test-equal "no raise returns thunk result"
            42
            (with-unwind-handler (lambda (o k) 'unused) (lambda () (+ 40 2))))

(test-equal "catches raise-continuable"
            '(caught 99)
            (with-unwind-handler (lambda (o k) (list 'caught o))
                                 (lambda () (raise-continuable 99))))

(test-equal "catches plain raise"
            '(caught boom)
            (with-unwind-handler (lambda (o k) (list 'caught o))
                                 (lambda () (raise 'boom) 'unreached)))

;; handler resumes the delimited continuation (composition with the current
;; caller): k = (lambda (v) (not v)).
(test-equal "handler resumes k (non-tail)"
            '(resumed . #f)
            (with-unwind-handler (lambda (o k) (cons 'resumed (k #t)))
                                 (lambda () (not (raise-continuable 42)))))

;; k result reused by the handler.
(test-equal "handler composes with k"
            21
            (with-unwind-handler (lambda (o k) (+ 1 (k 10)))
                                 (lambda () (* 2 (raise-continuable 'p)))))

;; innermost with-unwind-handler wins.
(test-equal "nested, inner catches"
            '(in 7)
            (with-unwind-handler
             (lambda (o k) (list 'outer o))
             (lambda ()
               (list 'in (with-unwind-handler
                          (lambda (o k) o)
                          (lambda () (raise-continuable 7)))))))

;; a dynamic-wind after-thunk of the guarded thunk still runs when the handler
;; unwinds it (order relative to the handler is a documented caveat).
(test-assert "dynamic-wind before/after both run under unwind handler"
             (let ((log '()))
               (with-unwind-handler
                (lambda (o k) (set! log (cons 'handler log)) 'done)
                (lambda ()
                  (dynamic-wind
                   (lambda () (set! log (cons 'before log)))
                   (lambda () (raise-continuable 'x))
                   (lambda () (set! log (cons 'after log))))))
               (and (memq 'before log) (memq 'after log) (memq 'handler log) #t)))

;; ---- empty-continuation? ----

(define (empty-probe thunk)
  (with-unwind-handler (lambda (o k) (empty-continuation? k)) thunk))

(test-equal "empty: raise-continuable in tail context"
            #t
            (empty-probe (lambda () (raise-continuable 42))))
(test-equal "non-empty: result consumed by not"
            #f
            (empty-probe (lambda () (not (raise-continuable 42)))))
(test-equal "non-empty: begin non-tail"
            #f
            (empty-probe (lambda () (begin (raise-continuable 42) 99))))
(test-equal "non-empty: argument position"
            #f
            (empty-probe (lambda () (+ 1 (raise-continuable 42)))))
;; A raise in tail position of a helper that is itself called non-tail is NOT
;; empty — the continuation is (not []) (regression for the frame-count baseline).
(test-equal "non-empty: tail raise in non-tail-called helper"
            #f
            (empty-probe (lambda () (not ((lambda () (raise-continuable 42)))))))
;; The whole call chain is tail, so it is empty.
(test-equal "empty: raise through a tail-called helper"
            #t
            (empty-probe (lambda () ((lambda () (raise-continuable 42))))))

;; ---- extended guard (with continuation variable) ----

;; Coroutine generator, the motivating SRFI 248 example.
(define (make-coroutine-generator proc)
  (define (yield val) (raise-continuable (cons '&yield val)))
  (define thunk
    (lambda ()
      (guard (c k
                ((and (pair? c) (eq? (car c) '&yield))
                 (set! thunk k)
                 (cdr c)))
        (proc yield)
        (eof-object))))
  (lambda () (thunk)))

(let ((g (make-coroutine-generator
          (lambda (yield) (yield 1) (yield 2) (yield 3)))))
  (test-equal "generator value 1" 1 (g))
  (test-equal "generator value 2" 2 (g))
  (test-equal "generator value 3" 3 (g))
  (test-assert "generator exhausted" (eof-object? (g))))

;; for-each->fold, the second SRFI 248 example.
(define (for-each->fold for-each)
  (lambda (proc nil)
    ((guard (c k
               ((and (pair? c) (eq? (car c) '&y))
                (lambda (s) ((k) (proc s (cdr c))))))
       (for-each (lambda (x) (raise-continuable (cons '&y x))))
       values)
     nil)))
(test-equal "for-each->fold sum"
            10
            ((for-each->fold (lambda (p) (for-each p '(1 2 3 4)))) + 0))

;; ---- guard: standard (one-variable) form still works ----

(test-equal "one-var guard catches"
            '(caught oops)
            (guard (e (#t (list 'caught e))) (raise 'oops)))

(test-equal "one-var guard else"
            'elsed
            (guard (e (else 'elsed)) (raise 'z)))

(test-equal "one-var guard =>"
            43
            (guard (e ((assv 42 '((42 . 43))) => cdr)) (raise 'nope)))

(test-equal "one-var guard catches runtime error"
            'handled
            (guard (e (#t 'handled)) (car 5)))

;; Documented caveat: guard is built on with-unwind-handler, whose handler runs
;; at the raise point, so a clause runs before a guarded-body dynamic-wind
;; after-thunk (R7RS-small runs it after). This test pins the current behaviour;
;; all three effects run, only their order differs from R7RS-small.
(test-equal "guard clause runs before body dynamic-wind after-thunk (caveat)"
            '(in caught out)
            (let ((log '()))
              (guard (e (#t (set! log (cons 'caught log))))
                (dynamic-wind
                 (lambda () (set! log (cons 'in log)))
                 (lambda () (raise 'boom))
                 (lambda () (set! log (cons 'out log)))))
              (reverse log)))

;; no clause matches -> re-raise (raise-continuable) to the outer handler.
(test-equal "guard re-raises to outer handler"
            '(outer boom)
            (with-exception-handler
             (lambda (e) (list 'outer e))
             (lambda ()
               (guard (e ((eq? e 'never) 'no))
                 (raise-continuable 'boom)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-248")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
