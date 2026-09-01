;; kaappi#2451: a continuation captured under a NON-TAIL `apply` or
;; `call-with-values` must be resumable after that call has returned.
;;
;; Until the `apply` opcode landed, both reached their callee through a native
;; primitive's `vm.callWithArgs` — a fresh VM session under a Zig frame — so
;; re-invoking the continuation once that frame had returned raised
;; "continuation cannot resume across a returned native call" (KP3000). Tail
;; position was exempt, because `tail_apply` had already replaced the frame,
;; which is exactly what made the restriction impossible to predict from the
;; outside: `map`/`for-each`/`vector-map`/`vector-for-each`/`string-for-each`
;; were fine in both positions, `apply`/`call-with-values` only in tail.
;;
;; Each case below runs its capture and its re-invocation inside ONE top-level
;; form: a continuation cannot cross the boundary between two of them (see
;; callcc-correctness.scm case 4), which is a separate, documented limitation.

(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "callcc-native-driver-reentry-2451")

;; Calls `driver` with a callback that captures a continuation, then
;; re-invokes that continuation until the callback has run three times.
;; Returns the final count: 3 when the capture is resumable, 1 when the
;; re-invocation raised instead.
;;
;; `driver` is a procedure rather than a macro on purpose — a macro's template
;; `f` and a use-site `f` are different identifiers under hygiene — and each
;; driver below decides its own tail position by whether a form follows the
;; call under test.
(define (reentry-count driver)
  (let ((saved #f) (n 0))
    (define (f x)
      (call/cc (lambda (k) (set! saved k)))
      (set! n (+ n 1))
      x)
    (driver f)
    (if (< n 3) (saved 'again) n)))

(test-eqv "non-tail apply" 3
  (reentry-count (lambda (f) (apply f (list 1)) 'done)))

(test-eqv "non-tail call-with-values" 3
  (reentry-count (lambda (f) (call-with-values (lambda () 1) f) 'done)))

;; Tail position kept working throughout; pinned so the two positions cannot
;; drift apart again.
(test-eqv "tail apply" 3
  (reentry-count (lambda (f) (apply f (list 1)))))

(test-eqv "tail call-with-values" 3
  (reentry-count (lambda (f) (call-with-values (lambda () 1) f))))

;; The drivers that were always exempt, kept as the contrast the issue's table
;; was built from.
(test-eqv "non-tail map" 3
  (reentry-count (lambda (f) (map f (list 1)) 'done)))

(test-eqv "non-tail for-each" 3
  (reentry-count (lambda (f) (for-each f (list 1)) 'done)))

(test-eqv "non-tail direct call" 3
  (reentry-count (lambda (f) (f 1) 'done)))

;; `apply` with fixed operands ahead of the list, and with an empty list.
(test-eqv "non-tail apply with fixed operands" 3
  (reentry-count (lambda (f) (apply (lambda (a b) (f b)) 1 (list 2)) 'done)))

(test-eqv "non-tail apply with an empty final list" 3
  (reentry-count (lambda (f) (apply (lambda () (f 1)) '()) 'done)))

;; Multiple values reach the consumer, and the consumer is re-enterable.
(test-eqv "non-tail call-with-values with several values" 3
  (reentry-count (lambda (f)
                   (call-with-values (lambda () (values 1 2))
                     (lambda (a b) (f (+ a b))))
                   'done)))

(test-eqv "non-tail call-with-values with no values" 3
  (reentry-count (lambda (f)
                   (call-with-values (lambda () (values)) (lambda () (f 1)))
                   'done)))

;; --- the ordinary semantics the opcode must not disturb -------------------

(test-eqv "apply flattens fixed operands and the list" 10
  (apply + 1 2 (list 3 4)))

(test-eqv "apply with an empty final list" 0 (apply + '()))

(test-eqv "call-with-values passes several values" 6
  (call-with-values (lambda () (values 1 2 3)) +))

(test-eqv "call-with-values passes a single value" 84
  (call-with-values (lambda () 42) (lambda (x) (* x 2))))

;; A rebound or shadowed name must reach the user's procedure, never the
;; superinstruction (kaappi#2033).
(test-eq "a lexically shadowed apply is an ordinary call" 'shadow
  (let ((apply (lambda (f xs) 'shadow)))
    (apply + (list 1 2))))

(test-eq "a lexically shadowed call-with-values is an ordinary call" 'shadow
  (let ((call-with-values (lambda (p c) 'shadow)))
    (call-with-values (lambda () 1) (lambda (x) x))))

;; ...and when the rebinding is an earlier child of the SAME top-level `begin`.
;; The gate reads the live global environment rather than a set!-target list,
;; so it needs the definition to have run by the time the use is compiled; a
;; top-level `begin`'s children are compiled and executed one at a time, which
;; is what makes that hold. (A body compiled BEFORE a later top-level
;; redefinition does keep the builtin — the same compile-time property the
;; constant folder has for `+`, and unchanged by #2451.)
(test-eq "a define earlier in the same begin beats the apply opcode" 'mine
  (begin
    (define (apply f xs) 'mine)
    (let ((v (apply + (list 1 2)))) v)))

(test-eq "a define earlier in the same begin beats the call-with-values lowering" 'mine
  (begin
    (define (call-with-values p c) 'mine)
    (let ((v (call-with-values (lambda () 1) (lambda (x) x)))) v)))

;; Diagnostics: non-tail apply reports through the native applyFn's texts,
;; which the LLVM backend also produces (tests/scheme/compile/
;; native-apply-lowering-1803.sh pins the two against each other).
(define (message-of thunk)
  (guard (e ((error-object? e) (error-object-message e)) (#t 'not-an-error-object))
    (thunk)
    'no-error))

(test-equal "a non-procedure operand names apply"
  "type error in 'apply': expected procedure, got 5"
  (message-of (lambda () (+ 0 (apply 5 (list 1))))))

(test-equal "an improper final list names apply"
  "type error in 'apply': expected proper list, got 2"
  (message-of (lambda () (+ 0 (apply + (cons 1 2))))))

;; A bad consumer is still reported as call-with-values, not as the `apply`
;; the form compiles into.
(test-equal "a non-procedure consumer names call-with-values"
  "type error in 'call-with-values': expected procedure, got 5"
  (message-of (lambda () (+ 0 (call-with-values (lambda () 1) 5)))))

(test-equal "a non-procedure producer names call-with-values"
  "type error in 'call-with-values': expected procedure, got 5"
  (message-of (lambda () (+ 0 (call-with-values 5 +)))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callcc-native-driver-reentry-2451")
(if (> %test-fail-count 0) (exit 1))
