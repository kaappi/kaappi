;; #1886: the exception-handler and dynamic-wind stacks must grow, and a VM
;; limit must never arrive as a catchable condition.
;;
;; Both stacks were fixed 64-entry inline arrays. Past 64 the overflow came
;; back as VMError.StackOverflow, which `with-exception-handler` relabelled
;; OutOfMemory and then converted into an ordinary Scheme error object -- so
;; the *enclosing* guard caught it, its `(#t ...)` clause returned a plausible
;; value, and the program exited 0. The reported symptom: a recursive `guard`
;; that must return 0 at every depth returned `(0 1 37)` for depths 63/64/100.
;;
;; Nothing here is exotic; a recursive procedure wrapping its own recursive
;; call in `guard` or `dynamic-wind` is ordinary code. The depths below run
;; well past 64 so the stacks have to double several times (64 -> 128 -> 256
;; -> 512), not merely clear the old boundary by one.
;;
;; The other half of the fix -- that genuinely exceeding a limit is NOT
;; catchable -- needs exit codes and stderr, so it lives in
;; tests/scheme/errors/error-format.sh.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "handler-wind-depth-1886")

;; --- guard: the issue's own reproduction ---

;; Each level wraps the recursive call in its own guard. The innermost call
;; (n = 0) raises, and its OWN guard catches it, so every depth returns 0.
(define (f n)
  (guard (e (#t n))
    (if (= n 0) (raise 'b) (f (- n 1)))))

(test-equal "nested guard at the old boundary" '(0 0 0) (list (f 63) (f 64) (f 65)))
(test-equal "nested guard well past the old boundary" 0 (f 100))
(test-equal "nested guard past several growth doublings" 0 (f 300))

;; The raise must still reach the innermost guard, not merely return something
;; that happens to be 0: raise from the middle of the nest and check that the
;; clause which runs is the one at that level.
(define (g n raise-at)
  (guard (e ((symbol? e) (list 'caught-at n e)))
    (if (= n raise-at) (raise 'boom) (g (- n 1) raise-at))))

(test-equal "raise reaches the innermost enclosing guard, depth 200"
  '(caught-at 0 boom) (g 200 0))
(test-equal "raise mid-nest reaches its own level, not an outer one"
  '(caught-at 150 boom) (g 200 150))

;; A guard whose clauses do not match must re-raise outward, past 64 levels.
(define (h n)
  (guard (e ((string? e) 'string-clause))
    (if (= n 0) (raise 'not-a-string) (h (- n 1)))))

(test-equal "non-matching clauses re-raise through 200 levels"
  'outer (guard (e ((symbol? e) 'outer)) (h 200)))

;; --- with-exception-handler ---

;; Where guard produced a wrong value, this produced no signal at all: the
;; handler simply received the synthetic #<error "error"> and the program ran
;; to completion.
(define (w n)
  (if (= n 0)
      'ok
      (with-exception-handler (lambda (e) e) (lambda () (w (- n 1))))))

(test-equal "nested with-exception-handler, depth 100" 'ok (w 100))
(test-equal "nested with-exception-handler, depth 300" 'ok (w 300))

;; --- dynamic-wind ---

(define (dw n)
  (if (= n 0)
      'ok
      (dynamic-wind (lambda () #f) (lambda () (dw (- n 1))) (lambda () #f))))

(test-equal "nested dynamic-wind, depth 100" 'ok (dw 100))
(test-equal "nested dynamic-wind, depth 300" 'ok (dw 300))

;; Every before/after thunk must actually run -- a stack that silently stopped
;; recording winds past its capacity would still return 'ok above.
(define befores 0)
(define afters 0)
(define (dw-counted n)
  (if (= n 0)
      'done
      (dynamic-wind
        (lambda () (set! befores (+ befores 1)))
        (lambda () (dw-counted (- n 1)))
        (lambda () (set! afters (+ afters 1))))))

(test-equal "deep dynamic-wind runs every thunk" 'done (dw-counted 200))
(test-equal "every before thunk ran" 200 befores)
(test-equal "every after thunk ran" 200 afters)

;; An escape out of a deep wind nest must unwind every after-thunk on the way.
(set! afters 0)
(test-equal "escaping a deep wind nest returns the escape value"
  'escaped
  (call-with-current-continuation
    (lambda (k)
      (define (deep n)
        (if (= n 0)
            (k 'escaped)
            (dynamic-wind
              (lambda () #f)
              (lambda () (deep (- n 1)))
              (lambda () (set! afters (+ afters 1))))))
      (deep 200))))
(test-equal "escaping ran every after thunk" 200 afters)

;; --- the two stacks interleaved ---

(define (mixed n)
  (if (= n 0)
      (raise 'inner)
      (dynamic-wind
        (lambda () #f)
        (lambda () (guard (e (#f 'never)) (mixed (- n 1))))
        (lambda () #f))))

(test-equal "interleaved guard and dynamic-wind, depth 150"
  'inner (guard (e ((symbol? e) e)) (mixed 150)))

;; --- continuations captured with a deep handler stack ---

;; captureContinuation snapshots the whole handler stack and
;; restoreContinuation copies it back, so restore now has to grow the target
;; stack before the memcpy. Both continuations below are invoked while the
;; nest that was live at capture is still live -- resuming one after its
;; native `guard` frames have returned is a separate, pre-existing limitation
;; (README, "Known limitations"), unrelated to depth: it fails at depth 1.

(define escape-hit #f)
(define (deep-escape d k)
  (if (= d 0) (k 'escaped) (guard (e (#f 'never)) (deep-escape (- d 1) k))))
(test-equal "escaping out of a 150-deep handler nest"
  'escaped
  (call-with-current-continuation (lambda (k) (deep-escape 150 k))))

;; Restore into a 150-entry handler stack, then raise: the handler stack must
;; come back intact, so the innermost guard (d = 1) is the one that catches.
;; A truncated or corrupted restore would land on some other level, or none.
(define (deep-restore d)
  (if (= d 0)
      (let ((v (call-with-current-continuation
                 (lambda (c) (set! escape-hit c) 'first))))
        (if (eq? v 'first) (escape-hit 'second) (raise 'boom)))
      (guard (e ((symbol? e) (list 'caught-at d e))) (deep-restore (- d 1)))))
(test-equal "the handler stack survives a 150-entry capture and restore"
  '(caught-at 1 boom) (deep-restore 150))

;; --- an ordinary error is still catchable ---

;; The fix stops VM *limits* from reaching a guard clause; genuine program
;; faults must still be caught, at any depth.
(test-equal "a type error is still catchable at depth 100"
  'caught
  (let loop ((n 100))
    (if (= n 0)
        (guard (e (#t 'caught)) (car 5))
        (guard (e (#t 'wrong-level)) (loop (- n 1))))))

(test-equal "an unbound variable is still catchable"
  #t (guard (e (#t #t)) (no-such-variable-anywhere)))

(let ((runner (test-runner-current)))
  (test-end "handler-wind-depth-1886")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
