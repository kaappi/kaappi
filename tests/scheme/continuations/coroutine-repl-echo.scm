;; Regression: a continuation captured with call/cc must survive the top-level
;; value-echo. Both file mode and piped-stdin mode print each non-void
;; top-level result, and that printing path previously misdetected the escape
;; as leaving the continuation, so the *next* re-entry through the saved
;; continuation failed with "not a procedure". Wrapping every call in
;; (display ...) hid the bug because the result was then consumed instead of
;; echoed. These forms are therefore left BARE on purpose: if the bug returns,
;; the second coroutine call raises "not a procedure" and the script exits
;; non-zero, which run-all.sh flags.
;;
;; Covers two coroutine shapes:
;;   1. Two saved continuations in top-level globals (resume / return).
;;   2. The same machinery captured in closure state via a factory.

(define resume #f)
(define return #f)

(define (yield value)
  (call/cc (lambda (k)
             (set! resume k)
             (return value))))

(define (coroutine-run proc)
  (call/cc (lambda (caller)
             (set! return caller)
             (if resume
                 (resume #f)
                 (proc yield)))))

(define (counter yield)
  (yield "one")
  (yield "two")
  "three")

;; Bare echo — must print "one" "two" "three" without breaking the saved
;; continuation between calls.
(coroutine-run counter)
(coroutine-run counter)
(coroutine-run counter)

;; ---- Closure-state factory: each coroutine owns its own resume/return ----

(define (make-coroutine proc)
  (let ((resume #f)
        (return #f))
    (define (yield value)
      (call/cc (lambda (k)
                 (set! resume k)
                 (return value))))
    (lambda ()
      (call/cc (lambda (caller)
                 (set! return caller)
                 (if resume
                     (resume #f)
                     (proc yield)))))))

(define gen
  (make-coroutine
    (lambda (yield)
      (yield 'a)
      (yield 'b)
      'c)))

;; Bare echo again — prints a, b, c across three re-entries.
(gen)
(gen)
(gen)

;; A visible marker so a passing run is obvious; if any call above regressed,
;; the runtime error aborts before reaching here and flips the exit code.
(display "coroutine-repl-echo ok")
(newline)
