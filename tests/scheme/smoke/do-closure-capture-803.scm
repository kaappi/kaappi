;; Regression test for #803: a closure created inside a `do` loop body corrupts
;; the captured variable. `do` compiles to a same-frame backward jump, so the
;; one-shot `box_local` emitted at the closure-creation point re-ran every
;; iteration (wrapping the box in a fresh box, leaking the internal box pair
;; `(v . #<void>)`), and accesses compiled before the capturing lambda used
;; unboxed register moves that bypassed the box after the loop jumped back.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "do-closure-capture-803")

;; Case A: the internal box pair must not leak as the closure's value.
(test-equal "captured enclosing var reads correctly after loop"
  1
  (let ((x 1) (f #f))
    (do ((i 0 (+ i 1)))
        ((= i 2))
      (set! f (lambda () x)))
    (f)))

;; Case B: an unboxed read compiled before the capturing lambda must still see
;; the variable's value (not the raw box pair) on later iterations.
(test-equal "read before capturing lambda stays unboxed-correct"
  '(1 1)
  (let ((x 1) (out '()) (f #f))
    (do ((i 0 (+ i 1)))
        ((= i 2))
      (set! out (cons x out))
      (set! f (lambda () x)))
    out))

;; Case C: a set! compiled before the capturing lambda must update the box, so
;; the closure observes the latest value rather than a stale one.
(test-equal "set! before capturing lambda updates the box"
  11
  (let ((x 1) (f #f))
    (do ((i 0 (+ i 1)))
        ((= i 2))
      (set! x (+ i 10))
      (unless f (set! f (lambda () x))))
    (f)))

;; The same shape without a loop was always correct — keep it covered.
(test-equal "capture without a loop"
  1
  (let ((x 1) (f #f)) (set! f (lambda () x)) (f)))

;; R7RS binds `do` variables to fresh locations each iteration, so a closure
;; made in one pass keeps that pass's value. This behaviour must be preserved.
(test-equal "do variable captured in body has fresh location per iteration"
  '(2 1 0)
  (let ((fs '()))
    (do ((i 0 (+ i 1))) ((= i 3))
      (set! fs (cons (lambda () i) fs)))
    (map (lambda (p) (p)) fs)))

;; Capturing a `do` variable from the step expression is also fresh per pass.
(test-equal "do variable captured in step has fresh location per iteration"
  '(0 1 4)
  (let ((qs '()))
    (do ((i 0 (+ i 1))) ((= i 3) (set! qs (reverse qs)))
      (set! qs (cons (lambda () (* i i)) qs)))
    (map (lambda (p) (p)) qs)))

;; Nested `do` loops both capturing their own variable used to crash by leaking
;; a box pair into arithmetic; each closure must see its own (i, j).
(test-equal "nested do loops capture fresh locations"
  '((1 1) (1 0) (0 1) (0 0))
  (let ((rs '()))
    (do ((i 0 (+ i 1))) ((= i 2))
      (do ((j 0 (+ j 1))) ((= j 2))
        (set! rs (cons (lambda () (list i j)) rs))))
    (map (lambda (p) (p)) rs)))

;; A plain accumulating `do` with no capture must be unaffected.
(test-equal "do without capture is unchanged"
  10
  (do ((i 0 (+ i 1)) (acc 0 (+ acc i))) ((= i 5) acc)))

;; An enclosing variable mutated in the loop and captured by many closures is a
;; single shared location — all closures observe the final value.
(test-equal "shared enclosing var mutated in loop"
  '(3 3 3)
  (let ((c 0) (fns '()))
    (do ((i 0 (+ i 1))) ((= i 3))
      (set! c (+ c 1))
      (set! fns (cons (lambda () c) fns)))
    (map (lambda (p) (p)) fns)))

(let ((runner (test-runner-current)))
  (test-end "do-closure-capture-803")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
