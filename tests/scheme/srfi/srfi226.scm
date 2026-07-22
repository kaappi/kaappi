;; SRFI-226 (Control Features) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi226.scm
;;
;; Covers the reduced subset Kaappi implements: (srfi 226 control prompts),
;; (srfi 226 control continuations), (srfi 226 control times). See the
;; header of lib/srfi/226/control/prompts.sld for what's out of scope
;; (composable continuations, continuation marks, fluids, the exceptions/
;; conditions/threads libraries, interrupts, thread-locals) and why.

(import (scheme base) (scheme process-context)
        (srfi 226 control prompts) (srfi 226 control continuations)
        (srfi 226 control times) (srfi 64))

(test-begin "srfi-226")

;;; --- prompts ---
(test-assert "make-continuation-prompt-tag: returns a prompt tag" (continuation-prompt-tag? (make-continuation-prompt-tag)))
(test-assert "default-continuation-prompt-tag: is a prompt tag" (continuation-prompt-tag? (default-continuation-prompt-tag)))
(test-assert "continuation-prompt-tag?: false for non-tags" (not (continuation-prompt-tag? 'not-a-tag)))
(test-assert "make-continuation-prompt-tag: each call is fresh/uncomparable"
  (not (eq? (make-continuation-prompt-tag) (make-continuation-prompt-tag))))

;; the spec's own worked example
(test-equal "call-with-continuation-prompt + abort-current-continuation"
  '(foo bar)
  (let ((tag (make-continuation-prompt-tag)))
    (call-with-continuation-prompt
      (lambda () (+ 1 (abort-current-continuation tag 'foo 'bar) 2))
      tag
      list)))

(test-equal "call-with-continuation-prompt: no abort, thunk's value passes through"
  42
  (call-with-continuation-prompt (lambda () 42)))

(test-equal "call-with-continuation-prompt: default handler just returns aborted values"
  99
  (let ((tag (make-continuation-prompt-tag)))
    (call-with-continuation-prompt (lambda () (abort-current-continuation tag 99)) tag)))

(test-equal "abort-current-continuation: finds the nearest matching tag, skipping others"
  'inner
  (let ((outer (make-continuation-prompt-tag)) (inner (make-continuation-prompt-tag)))
    (call-with-continuation-prompt
      (lambda ()
        (call-with-continuation-prompt
          (lambda () (abort-current-continuation inner 'inner))
          inner (lambda (v) v)))
      outer (lambda (v) 'outer))))

;;; --- continuations ---
(test-equal "call/cc: ordinary use" 3 (call/cc (lambda (k) (+ 1 2))))
(test-equal "call/cc: escape" 42 (+ 1 (call/cc (lambda (k) (k 41) 999))))
(test-equal "call-with-current-continuation: exported" 5 (call-with-current-continuation (lambda (k) 5)))
(test-equal "call-with-non-composable-continuation: escape" 41 (call-with-non-composable-continuation (lambda (k) (k 41))))

(test-equal "call-with-continuation-barrier: runs the thunk" 7 (call-with-continuation-barrier (lambda () 7)))

(let ((tag (make-continuation-prompt-tag)))
  (test-assert "continuation-prompt-available?: false before the prompt is installed"
    (not (continuation-prompt-available? tag)))
  (call-with-continuation-prompt
    (lambda ()
      (test-assert "continuation-prompt-available?: true inside the prompt's dynamic extent"
        (continuation-prompt-available? tag)))
    tag))

;;; --- unwind-protect ---
(let ((log '()))
  (unwind-protect (set! log (cons 'body log)) (set! log (cons 'cleanup log)))
  (test-equal "unwind-protect: cleanup runs after normal exit" '(body cleanup) (reverse log)))

(let ((log '()))
  (call/cc (lambda (k)
    (unwind-protect (begin (set! log (cons 'body log)) (k #f) (set! log (cons 'unreached log)))
                     (set! log (cons 'cleanup log)))))
  (test-equal "unwind-protect: cleanup still runs when escaping via a continuation" '(body cleanup) (reverse log)))

;;; --- times ---
(test-assert "time?: true for current-time" (time? (current-time)))
(test-assert "time?: false for a non-time value" (not (time? 5)))
(test-assert "seconds+: returns a time object" (time? (seconds+ (current-time) 10)))

(let ((runner (test-runner-current)))
  (test-end "srfi-226")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
