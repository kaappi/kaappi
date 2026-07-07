;; Regression test for #1256: stale registers in tail-call window extension.
;; A function with a small frame tail-calls one with a larger frame;
;; under -Dgc-stress=true the GC would scan dangling pointers in the
;; extended register window.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "tail-call-stale-regs-1256")

;; Helper with many locals so its frame is large — writes registers
;; beyond a small caller's window, then returns.
(define (big-frame a b c d e f)
  (let ((x (+ a b))
        (y (+ c d))
        (z (+ e f))
        (w (list a b c d e f)))
    (+ x y z (length w))))

;; Small-frame function that calls big-frame (child writes high regs),
;; then tail-calls another function whose locals_count exceeds the
;; caller's — the window extension must be cleared.
(define (small-then-tail-call n)
  (let ((tmp (big-frame 1 2 3 4 5 6)))
    (if (> n 0)
        (medium-frame n tmp)
        tmp)))

;; Target of the tail call — has more locals than small-then-tail-call.
(define (medium-frame n prev)
  (let ((a (+ n 1))
        (b (+ n 2))
        (c (+ n 3))
        (d (+ n 4))
        (e (+ n 5)))
    (+ a b c d e prev)))

(test-equal "tail-call window extension" 67 (small-then-tail-call 5))

;; Repeat to increase allocation pressure
(let loop ((i 0))
  (when (< i 20)
    (test-equal (string-append "iteration " (number->string i))
      (small-then-tail-call 5)
      (small-then-tail-call 5))
    (loop (+ i 1))))

;; tail_call_cc path: tail call/cc into a larger-frame receiver
(define (tail-cc-test)
  (let ((k (call-with-current-continuation
             (lambda (escape)
               (let ((a 1) (b 2) (c 3) (d 4) (e 5))
                 (escape (+ a b c d e)))))))
    k))

(test-equal "tail-call/cc window extension" 15 (tail-cc-test))

(let ((runner (test-runner-current)))
  (test-end "tail-call-stale-regs-1256")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
