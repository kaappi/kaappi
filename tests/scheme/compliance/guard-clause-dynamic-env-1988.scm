;; #1988: a `guard` clause runs in the dynamic environment of its own `guard`
;; expression (R7RS 4.2.7), not the one live at the raise point.
;;
;; The two differ only when something establishes an extent between the two:
;; a `parameterize` or a `dynamic-wind` sitting between an outer `guard` and an
;; inner `guard` that declines.  A plain `raise` hides the defect, because it
;; unwinds before any handler is called; the `raise-continuable` a declining
;; `guard` issues for its implicit re-raise does not, so the outer guard's
;; clauses used to see the inner guard's parameterization and to run *before*
;; the intervening after-thunk.
;;
;; The fix unwinds the dynamic environment to the guard's before evaluating the
;; clauses (`%unwind-to-escape`) while deliberately leaving the call stack
;; standing, so the last group below — a clause reinstating a continuation
;; captured inside the guard body — has to keep working too.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "guard-clause-dynamic-env-1988")

(define p (make-parameter 1))

;; --- parameterize between the guards ---------------------------------------
;; Every clause here belongs to a guard sitting *outside* (parameterize ((p 2)))
;; so every one of them must see p = 1.

(test-equal "no inner guard"
  1
  (guard (e (#t (p)))
    (parameterize ((p 2))
      (raise 'boom))))

(test-equal "declining inner guard"
  1
  (guard (e (#t (p)))
    (parameterize ((p 2))
      (guard (e ((number? e) 'no-match))
        (raise 'boom)))))

(test-equal "declining inner guard, raise deeper still"
  1
  (guard (e (#t (p)))
    (parameterize ((p 2))
      (guard (e ((number? e) 'no-match))
        (parameterize ((p 3))
          (raise 'boom))))))

(test-equal "two declining guards"
  1
  (guard (e (#t (p)))
    (parameterize ((p 2))
      (guard (e ((number? e) 'no-match))
        (guard (e ((string? e) 'no-match))
          (raise 'boom))))))

(test-equal "declining inner guard, raise-continuable"
  1
  (guard (e (#t (p)))
    (parameterize ((p 2))
      (guard (e ((number? e) 'no-match))
        (raise-continuable 'boom)))))

;; No extent between the two guards: correct before the fix as well, and the
;; case that made the defect easy to miss.
(test-equal "declining inner guard, no extent between"
  1
  (guard (e (#t (p)))
    (guard (e ((number? e) 'no-match))
      (parameterize ((p 2))
        (raise 'boom)))))

(test-equal "clause of a guard that handles"
  1
  (guard (e (#t (p)))
    (parameterize ((p 2))
      (raise 'boom))))

(test-equal "parameter restored after the guard returns" 1 (p))

;; --- dynamic-wind between the guards ---------------------------------------
;; The after-thunk belongs to an extent the clause is outside of, so it must
;; run on the way out to the guard, before the clause body.

(define log1 '())
(guard (e (#t (set! log1 (cons 'clause log1))))
  (dynamic-wind
    (lambda () (set! log1 (cons 'before log1)))
    (lambda () (raise 'x))
    (lambda () (set! log1 (cons 'after log1)))))
(test-equal "wind order, no inner guard" '(before after clause) (reverse log1))

(define log2 '())
(guard (e (#t (set! log2 (cons 'clause log2))))
  (dynamic-wind
    (lambda () (set! log2 (cons 'before log2)))
    (lambda ()
      (guard (e ((number? e) 'no-match))
        (raise 'x)))
    (lambda () (set! log2 (cons 'after log2)))))
(test-equal "wind order, declining inner guard" '(before after clause) (reverse log2))

;; An after-thunk runs exactly once, even though the unwind is now split
;; across `%unwind-to-escape` and the escape that follows it.
(define winds 0)
(define wind-once
  (guard (e (#t 'caught))
    (dynamic-wind
      (lambda () #t)
      (lambda () (guard (e ((number? e) 'no-match)) (raise 'x)))
      (lambda () (set! winds (+ winds 1))))))
(test-equal "after-thunk runs exactly once" 1 winds)
(test-equal "and the outer guard still caught" 'caught wind-once)

;; --- the clauses still have the guard body's frames ------------------------
;; A clause may reinstate a continuation captured inside the guard body — this
;; is how (srfi 255)'s restarters work — so unwinding the dynamic environment
;; ahead of the clauses must not take the call stack with it. Here `k` belongs
;; to the guard body and outlives the `error`, which unwinds no further than
;; the inner handler; the clause resumes it, and the body returns normally.

(test-equal "clause reinstates a continuation captured in the guard body"
  99
  (guard (c (#t ((cdr c) 99)))
    (call-with-current-continuation
      (lambda (k)
        (with-exception-handler
          (lambda (e) (raise-continuable (cons e k)))
          (lambda () (error "boom") 'not-reached))))))

;; --- a declining guard leaves no state behind ------------------------------
;; The implicit re-raise pops the guard's own handler, calls the outer one, and
;; that handler escapes — so the pop must stand. Putting the handler back (which
;; is right when this frame is genuinely being unwound through) stranded one
;; slot per declining guard: a later raise found the stale entry and called an
;; escape whose extent had ended, and 32768 of them exhausted the handler stack.

(test-equal "a later raise is not caught by a declined guard's stale handler"
  'outer
  (with-exception-handler
    (lambda (e) 'outer)
    (lambda ()
      (guard (e (#t 'caught)) (raise-continuable 'x))
      (raise-continuable 'y))))

(test-equal "declining guards do not accumulate handler-stack entries"
  40000
  (let loop ((i 0))
    (if (= i 40000)
        i
        (begin
          (guard (e (#t 'x)) (guard (e ((number? e) 'no-match)) (raise 'y)))
          (loop (+ i 1))))))

;; --- shapes the fix must leave alone ---------------------------------------

(test-equal "guard returns its body's value" 7 (guard (e (#t 'caught)) 7))
(test-equal "guard catches" 'caught (guard (e (#t 'caught)) (raise 'x)))
(test-equal "clause sees the raised object" 'x (guard (e (#t e)) (raise 'x)))
(test-equal "declining guard reaches the outer one"
  'outer
  (guard (e (#t 'outer))
    (guard (e ((number? e) 'no-match)) (raise 'x))))
(test-equal "body may open with internal definitions"
  3
  (guard (e (#t 'caught)) (define a 1) (define b 2) (+ a b)))
(test-equal "body returning multiple values"
  '(1 2)
  (call-with-values (lambda () (guard (e (#t 'caught)) (values 1 2))) list))
(test-equal "a raise from a clause goes to the enclosing handler"
  '(outer from-clause)
  (guard (outer-e (#t (list 'outer outer-e)))
    (guard (e (#t (raise 'from-clause)))
      (raise 'x))))
(test-equal "declining guard leaves the re-raise continuable"
  'from-outer
  (with-exception-handler
    (lambda (e) 'from-outer)
    (lambda ()
      (guard (e ((number? e) 'no-match))
        (raise-continuable 'x)))))

(let ((runner (test-runner-current)))
  (test-end "guard-clause-dynamic-env-1988")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
