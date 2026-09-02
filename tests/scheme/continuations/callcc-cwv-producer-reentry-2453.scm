;; kaappi#2453 part 2: a continuation captured inside call-with-values'
;; PRODUCER must be resumable after that call has returned, in both positions.
;;
;; #2451 moved the form's CONSUMER into the dispatch loop (the apply/tail_apply
;; the lowering emits); the producer kept running under the native
;; `%call-with-values->list` frame, so resuming a continuation captured inside
;; it raised KP3000 at best (part 1 made the diagnostic honest) — and before
;; that misfired as `apply: last argument must be a list`.
;;
;; The producer is now called with an ordinary `call` opcode: its frame is a
;; VM frame in the caller's bytecode, copied by continuation capture and
;; restored by resume exactly like any other. A new `values_list` opcode
;; spreads the produced value(s) into the argument list the consumer is
;; applied over, so a resume re-runs that spread and the consumer with the
;; newly produced values.
;;
;; The native path (a declined fast path routing to the built-in
;; call-with-values) keeps the returned-native-call restriction and its honest
;; KP3000; that half is covered by callcc-cwv-native-kp3000-2453.scm.

(import (scheme base) (scheme write) (srfi 64))

(define %test-fail-count 0)
(test-begin "callcc-cwv-producer-reentry-2453")

;; Calls `driver` with a producer that captures a continuation on every entry,
;; then re-invokes that continuation until the producer has run three times.
;; Returns the final count: 3 when the capture is resumable past the form's
;; return, 1 (or an error) when it is not.
(define (reentry-count driver produce)
  (let ((saved #f) (n 0))
    (define (p)
      (call/cc (lambda (k) (set! saved k)))
      (set! n (+ n 1))
      (produce))
    (driver p)
    (if (< n 3) (saved 'again) n)))

(test-eqv "non-tail: producer re-entry past the form's return"
  3 (reentry-count (lambda (p) (call-with-values p (lambda (x) x)) 'done)
                   (lambda () 1)))

(test-eqv "tail: producer re-entry past the form's return"
  3 (reentry-count (lambda (p) (call-with-values p (lambda (x) x)))
                   (lambda () 1)))

(test-eqv "producer re-entry with several values"
  3 (reentry-count (lambda (p) (call-with-values p (lambda (a b) (+ a b))) 'done)
                   (lambda () (values 1 2))))

(test-eqv "producer re-entry with no values"
  3 (reentry-count (lambda (p) (call-with-values p (lambda () 'any)) 'done)
                   (lambda () (values))))

;; A resume must re-run the spread and the consumer with the NEWLY produced
;; values, not replay the first pass's: the producer below returns how many
;; values it has produced so far, and the consumer records each one.
(let ((saved #f) (total '()))
  (define (p)
    (call/cc (lambda (k) (set! saved k)))
    (length total))
  (define (consume x) (set! total (append total (list x))))
  (call-with-values p consume)
  (if (< (length total) 3) (saved 'again) #f)
  (test-equal "resume re-spreads the newly produced values"
    '(0 1 2) total))

;; --- the ordinary semantics the lowering must not disturb ------------------

(test-eqv "call-with-values passes a single value" 84
  (call-with-values (lambda () 42) (lambda (x) (* x 2))))

(test-eqv "call-with-values passes several values" 6
  (call-with-values (lambda () (values 1 2 3)) +))

(test-eq "call-with-values with no values calls the consumer with none" 'none
  (call-with-values (lambda () (values)) (lambda () 'none)))

(let ((producer-ran #f))
  (test-equal "a non-procedure consumer names call-with-values, and the producer body never runs"
    "type error in 'call-with-values': expected procedure, got 5"
    (guard (e ((error-object? e) (error-object-message e)) (#t 'not-an-error))
      (+ 0 (call-with-values (lambda () (set! producer-ran #t) 1) 5))))
  (test-eq "the producer was not invoked before the consumer was rejected" #f producer-ran))

(test-equal "a non-procedure producer names call-with-values"
  "type error in 'call-with-values': expected procedure, got 5"
  (guard (e ((error-object? e) (error-object-message e)) (#t 'not-an-error))
    (+ 0 (call-with-values 5 (lambda (x) x)))))

(test-equal "with both operands bad, the producer is reported first"
  "type error in 'call-with-values': expected procedure, got 7"
  (guard (e ((error-object? e) (error-object-message e)) (#t 'not-an-error))
    (+ 0 (call-with-values 7 5))))

(test-equal "a bad consumer arity is the consumer's arity error"
  "expected 2 arguments, got 1"
  (guard (e ((error-object? e) (error-object-message e)) (#t 'not-an-error))
    (+ 0 (call-with-values (lambda () 1) (lambda (a b) a)))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callcc-cwv-producer-reentry-2453")
(if (> %test-fail-count 0) (exit 1))
