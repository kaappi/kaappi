;;; Lazy evaluation compliance tests (R7RS 4.2.5)
(import (scheme base) (scheme lazy) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "lazy")

;; --- promise? ---
(test-group "promise?"
  (test-eqv "delay creates a promise" #t (promise? (delay 1)))
  (test-eqv "integer is not a promise" #f (promise? 42)))

;; --- force / delay ---
(test-group "force/delay"
  (test-eqv "force evaluates delayed expression" 3 (force (delay (+ 1 2)))))

;; --- make-promise ---
(test-group "make-promise"
  (test-eqv "force on make-promise returns value" 42 (force (make-promise 42))))

;; --- memoization ---
(test-group "memoization"
  (let ((count 0))
    (let ((p (delay (begin (set! count (+ count 1)) count))))
      (test-eqv "first force evaluates body" 1 (force p))
      (test-eqv "second force returns cached value" 1 (force p)))))

;; --- nested delay ---
(test-group "nested delay"
  (test-eqv "force nested delays" 99 (force (delay (force (delay 99))))))

;; --- re-entrant forcing (SRFI-45 §8) ---

;; Valid recursive forcing with termination (R7RS 4.2.5 example)
(let ()
  (define x 5)
  (define count 0)
  (define p
    (delay (begin (set! count (+ count 1))
                  (if (> count x) count (force p)))))
  (test-eqv "recursive force with termination" 6 (force p)))

;; Forcing intermediate promise of a completed delay-force chain (#1264)
(test-group "delay-force chain intermediate"
  (let ()
    (define inner (delay 42))
    (define outer (delay-force inner))
    (test-eqv "force outer yields value" 42 (force outer))
    (test-eqv "force inner after chain yields value" 42 (force inner)))
  (let ()
    (define a (delay 42))
    (define b (delay-force a))
    (define c (delay-force b))
    (test-eqv "three-deep chain" 42 (force c))
    (test-eqv "middle promise after chain" 42 (force b))
    (test-eqv "innermost promise after chain" 42 (force a))))

;; Cyclic delay-force detected via forcing flag
(let ()
  (define p (delay-force (delay p)))
  (test-assert "delay-force self-reference raises error"
    (guard (exn (#t #t))
      (force p) #f)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "lazy")
(if (> %test-fail-count 0) (exit 1))
