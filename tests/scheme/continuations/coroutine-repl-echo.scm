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
;; That "left bare on purpose" is also why this file uses a bare `(exit 1)`
;; instead of the SRFI-64 epilogue every other file in the corpus uses
;; (kaappi#2116): `(test-equal ... (coroutine-run counter))` CONSUMES the
;; value, which is exactly the shape that hid the bug in the first place. The
;; forms stay bare and the values are recorded through a side channel instead,
;; so the file now also catches a coroutine that resumes in the wrong order or
;; yields the wrong value — neither of which an abort-only verdict could see.
;;
;; Covers two coroutine shapes:
;;   1. Two saved continuations in top-level globals (resume / return).
;;   2. The same machinery captured in closure state via a factory.

;; Only `(scheme process-context)`, for `exit`: the verdict at the bottom
;; should not depend on Kaappi registering `exit` as an ambient script-mode
;; global. Everything else stays ambient. Verified that adding this import
;; leaves the top-level echo — the whole point of the file — byte-identical.
(import (scheme process-context))

(define yielded '())
(define (note x) (set! yielded (cons x yielded)) x)

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
  (yield (note "one"))
  (yield (note "two"))
  (note "three"))

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
      (yield (note 'a))
      (yield (note 'b))
      (note 'c))))

;; Bare echo again — prints a, b, c across three re-entries.
(gen)
(gen)
(gen)

;; A visible marker so a passing run is obvious; if any call above regressed,
;; the runtime error aborts before reaching here and flips the exit code.
(display "coroutine-repl-echo ok")
(newline)

;; The verdict the abort alone cannot give: the right values, in the right
;; order, each produced exactly once across the six re-entries.
(if (not (equal? (reverse yielded) '("one" "two" "three" a b c)))
    (begin
      (display "FAIL: yielded ")
      (write (reverse yielded))
      (display " expected (\"one\" \"two\" \"three\" a b c)")
      (newline)
      (exit 1)))
