;; kaappi#2453 part 1: a continuation captured inside call-with-values'
;; PRODUCER, resumed after the form returned, must report
;; "continuation cannot resume across a returned native call" (KP3000) on
;; every path that still drives the producer from a native frame — not a
;; misleading `apply: last argument must be a list` blaming an operand the
;; user never wrote.
;;
;; This file exercises the NATIVE call-with-values: the by-name route the
;; form takes when the compiler's fast-path gate has declined, which is what
;; a top-level redefinition that is later RESTORED to the genuine binding
;; produces. The redefinition is compiled before the use (so the gate
;; declines and the use becomes an ordinary by-name call), and the restore
;; runs before the use executes (so the name resolves to the native again):
;;
;;   (define (call-with-values p c) ...)   ; gate declines from here on
;;   (define (go) (call-with-values ...))  ; compiled by-name
;;   (define call-with-values saved)       ; genuine native restored
;;   (go)                                  ; native drives the producer
;;
;; The superinstruction lowering's own producer no longer runs under a
;; native frame at all (part 2, and #2451 before it for the consumer); that
;; half is covered by callcc-cwv-producer-reentry-2453.scm.
;;
;; Before this fix the producer's frame was pushed by callThunk with
;; returns_to_native = false, so the late resume fell through the KP3000
;; check and delivered the producer's value into a stale register of the
;; enclosing bytecode frame — surfacing as KP3002 from an apply the user
;; never wrote (or worse). callThunkReturningToNative marks the frame, and
;; the resume now raises the honest error every other returned-native-call
;; resume raises.

(import (scheme base) (scheme write) (srfi 64))

(define %test-fail-count 0)
(test-begin "callcc-cwv-native-kp3000-2453")

(define saved-2453-orig-cwv call-with-values)

;; The shared state the producer mutates across resumes.
(define saved-2453-k #f)
(define n-2453 0)
(define (p-2453)
  (call/cc (lambda (k) (set! saved-2453-k k)))
  (set! n-2453 (+ n-2453 1))
  1)

;; Decline the fast path by redefining first, compile the users by-name,
;; then restore the genuine binding so the by-name call reaches the native.
(define (call-with-values p c) 'user)
(define (go-2453)
  (call-with-values p-2453 (lambda (x) x)) 'done)          ; non-tail
(define (go-2453-tail)
  (call-with-values p-2453 (lambda (x) x)))                ; tail
(define call-with-values saved-2453-orig-cwv)

;; The guard must enclose the CAPTURE, not just the resume: invoking the
;; continuation restores the handler stack as of capture time, so a guard
;; entered after (go) returned is not on the restored stack and cannot see
;; the error the resumed producer's return raises.
(define (drive-2453 go-thunk)
  (set! n-2453 0)
  (guard (e ((error-object? e) (error-object-message e))
            (#t 'not-an-error-object))
    (go-thunk)
    (saved-2453-k 'again)
    'no-error))

;; Non-tail: the producer ran under the native's frame; resuming after the
;; form returned must raise the accurate KP3000 diagnostic.
(test-equal "non-tail: resumed producer reports the returned-native diagnostic"
  "continuation cannot resume across a returned native call"
  (drive-2453 go-2453))

;; Tail position: same native producer driving, same diagnostic.
(test-equal "tail: resumed producer reports the returned-native diagnostic"
  "continuation cannot resume across a returned native call"
  (drive-2453 go-2453-tail))

;; The diagnostic must not be the misleading apply type error the bug
;; produced (the message names neither apply nor a list operand).
(test-equal "genuine binding restored: ordinary call-with-values works again"
  '(1 2)
  (call-with-values (lambda () (values 1 2)) list))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callcc-cwv-native-kp3000-2453")
(if (> %test-fail-count 0) (exit 1))
