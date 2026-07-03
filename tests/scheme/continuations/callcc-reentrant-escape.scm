;; Regression test: call/cc escape inside a re-entrant native call.
;;
;; Natives like with-exception-handler, guard, and dynamic-wind run Scheme
;; code through a nested dispatch loop (callThunk/callHandler). Restoring a
;; continuation captured inside that extent used to unwind all the way to the
;; outermost loop, abandoning the native's pending result-register write: the
;; whole expression evaluated to the with-exception-handler builtin instead of
;; the escaped value. Fixed by resuming in the innermost dispatch loop whose
;; scope-root frame (identified by birth id) survived the restore.
;;
;; Manual assertions (not SRFI-64) so this file stands alone even if the
;; test framework itself regresses.
(import (scheme base) (scheme write) (scheme process-context))

(define failures 0)
(define (check name expected actual)
  (if (equal? expected actual)
      (begin (display "ok: ") (display name) (newline))
      (begin
        (set! failures (+ failures 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write actual) (newline))))

;; --- with-exception-handler extent ---

(check "weh: tail call/cc, tail k" 42
  (with-exception-handler (lambda (e) 'err)
    (lambda () (call/cc (lambda (k) (k 42))))))

(check "weh: tail call/cc, non-tail k" 42
  (with-exception-handler (lambda (e) 'err)
    (lambda () (call/cc (lambda (k) (+ 0 (k 42)))))))

(check "weh: non-tail call/cc" 42
  (with-exception-handler (lambda (e) 'err)
    (lambda () (+ 1 (call/cc (lambda (k) (k 41)))))))

;; --- guard extent ---

(define (sum-to n k)
  (if (= n 0)
      (k 'done)
      (+ n (sum-to (- n 1) k))))

(check "guard: deep non-tail escape" 'done
  (guard (e (#t 'caught))
    (call/cc (lambda (k) (sum-to 20 k)))))

(check "guard: inner escape, no arithmetic" 5
  (guard (e (#t 'caught))
    (call/cc (lambda (o) (call/cc (lambda (i) (i 5)))))))

(check "guard: outer escape from inner extent" 7
  (guard (e (#t 'caught))
    (call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (o 7))))))))

;; --- dynamic-wind interaction ---

(define trace '())
(define (note x) (set! trace (cons x trace)))

(check "guard: dynamic-wind ordering with escape" 'out
  (guard (e (#t 'caught))
    (call/cc
     (lambda (k)
       (dynamic-wind
         (lambda () (note 'before))
         (lambda () (note 'during) (k 'out) (note 'never))
         (lambda () (note 'after)))))))

(check "guard: dynamic-wind trace" '(before during after) (reverse trace))

;; Out-of-lineage restore: the continuation predates the dynamic-wind, so
;; invoking it inside the wind thunk must escape past dynamic-wind's native
;; frame rather than pose as the thunk's normal return (used to corrupt the
;; wind stack).
(check "dynamic-wind: out-of-lineage restore" 'ok
  (let ((k #f) (done (vector #f)))
    (define (deep n)
      (if (= n 0)
          (call/cc (lambda (c) (set! k c) 0))
          (+ 1 (deep (- n 1)))))
    (deep 5)
    (if (not (vector-ref done 0))
        (begin
          (vector-set! done 0 #t)
          (dynamic-wind (lambda () #f) (lambda () (k 0)) (lambda () #f))))
    'ok))

(if (> failures 0)
    (begin
      (display failures) (display " failure(s)") (newline)
      (exit 1)))
