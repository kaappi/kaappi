;; Audit tests for src/primitives_lazy.zig — audit Phase 2.16
;; Covers force, promise?, make-promise plus the delay/delay-force compiler
;; forms they back (R7RS 4.2.5, SRFI-45 semantics).
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/audit/primitives_lazy-audit.scm

(import (scheme base) (scheme lazy) (scheme process-context) (srfi 64))

(test-begin "primitives_lazy audit")

;;; --- force / delay basics and memoization (R7RS 4.2.5) ---
(test-equal 3 (force (delay (+ 1 2))))

;; the thunk runs exactly once; later forces return the cached value
(let ()
  (define count 0)
  (define p (delay (begin (set! count (+ count 1)) count)))
  (test-equal 1 (force p))
  (test-equal 1 (force p))
  (test-equal 1 count))

;; delayed expression does not run until forced
(let ()
  (define ran #f)
  (define p (delay (begin (set! ran #t) 'v)))
  (test-equal #f ran)
  (test-equal 'v (force p))
  (test-equal #t ran))

;;; --- force on non-promise (R7RS: may be returned unchanged) ---
(test-equal 42 (force 42))
(test-equal "s" (force "s"))
(test-equal '() (force '()))
(test-equal #t (eq? car (force car)))

;;; --- promise? ---
(test-equal #t (promise? (delay 1)))
(test-equal #t (promise? (delay-force (delay 1))))
(test-equal #t (promise? (make-promise 1)))
(test-equal #f (promise? 1))
(test-equal #f (promise? car))
(test-equal #f (promise? '(delay 1)))
(test-equal #f (promise? "promise"))
;; forcing does not change promise-ness
(let ((p (delay 1)))
  (force p)
  (test-equal #t (promise? p)))

;;; --- make-promise ---
(test-equal 4 (force (make-promise 4)))
;; R7RS: "If argument is already a promise, it is returned." — same object.
(let ((p (delay 1)))
  (test-equal #t (eq? p (make-promise p))))
(let ((p (make-promise 5)))
  (test-equal #t (eq? p (make-promise p))))
;; eager: the argument is evaluated, not wrapped as a thunk
(test-equal #t (eq? car (force (make-promise car))))
(let ()
  (define count 0)
  (make-promise (set! count (+ count 1)))
  (test-equal 1 count))

;;; --- delay-force (iterative forcing, R7RS 4.2.5 / SRFI-45) ---
(test-equal 42 (force (delay-force (delay 42))))
(test-equal 42 (force (delay-force (delay-force (delay 42)))))

;; a 50000-deep delay-force chain must force in bounded space
(letrec ((chain (lambda (n)
                  (if (= n 0)
                      (delay 'done)
                      (delay-force (chain (- n 1)))))))
  (test-equal 'done (force (chain 50000))))

;; memoization through delay-force: the body runs once
(let ()
  (define count 0)
  (define p (delay-force (begin (set! count (+ count 1)) (delay count))))
  (test-equal 1 (force p))
  (test-equal 1 (force p))
  (test-equal 1 count))

;;; --- error propagation through force ---
(test-equal "boom" (guard (e (#t (error-object-message e)))
                     (force (delay (error "boom")))))
(test-equal "deep" (guard (e (#t (error-object-message e)))
                     (force (delay-force (delay-force (delay (error "deep")))))))

;;; --- SRFI-45 §8 cycle detection ---
;; a delay-force whose thunk returns the promise currently being forced is
;; detected and raises a catchable error
(define cyc (delay-force cyc))
(test-equal 'caught (guard (e (#t 'caught)) (force cyc)))

;; Direct re-entrant force — catchable error:
(define selfp (delay (force selfp)))
(test-equal 'caught (guard (e (#t 'caught)) (force selfp)))

;;; --- stream-style self-reference after memoization ---
(letrec ((ones (delay (cons 1 (delay (force ones))))))
  (test-equal 1 (car (force ones)))
  (test-equal 1 (car (force (cdr (force ones))))))

;;; --- forcing flag cleared on abnormal thunk exit (#1374) ---
;; A raising thunk must reset the forcing flag, so a later delay-force
;; chain re-raises the original error instead of a spurious
;; "re-entrant forcing of promise".
(let ()
  (define p (delay (error "boom")))
  (test-equal 'caught (guard (e (#t 'caught)) (force p)))
  (test-equal "boom" (guard (e (#t (error-object-message e)))
                       (force (delay-force p)))))

;; A call/cc escape out of the thunk must also reset the forcing flag
;; (the native forceFn cleared it on any abnormal exit, escapes included).
;; The flag itself is no longer observable (%promise-forcing? is not
;; globally reachable since #1375), so probe it behaviorally: if the escape
;; left it set, forcing p through a delay-force chain would raise
;; "re-entrant forcing of promise" instead of re-running the thunk.
(let ()
  (define p #f)
  (define fired #f)
  (define v (call/cc (lambda (escape)
                       (set! p (delay (if fired
                                          'done
                                          (begin (set! fired #t)
                                                 (escape 'out)))))
                       (force p))))
  (test-equal 'out v)
  (test-equal 'done (force (delay-force p))))

;;; --- continuation captured in a promise thunk, reinvoked after force ---
;; force is bytecode-driven (#1347): a full continuation captured inside
;; the thunk can be reinvoked after force returns. The promise is already
;; memoized on re-entry, so the cached value is delivered each time.
(let ()
  (define k #f)
  (define n 0)
  (define acc '())
  (let ((r (force (delay (call/cc (lambda (c) (set! k c) 'first))))))
    (set! n (+ n 1))
    (set! acc (cons r acc))
    (if (< n 3) (k 'again) #f))
  (test-equal 3 n)
  (test-equal '(first first first) acc))

(let ((runner (test-runner-current)))
  (test-end "primitives_lazy audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
