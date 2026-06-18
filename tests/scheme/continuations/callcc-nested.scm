;; Nested continuation capture -- inner continuation escapes while captured
;; inside an outer call/cc. Previously failed with NotAProcedure because the
;; call/cc proc frame was restored with dst=0 instead of the call/cc result
;; register; fixed by threading the result register through callHandler.
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "callcc-nested")

;; Inner escapes, no surrounding arithmetic
(test-eqv "inner escape, no arithmetic" 5
  (call/cc (lambda (o) (call/cc (lambda (i) (i 5))))))

;; Inner escapes, surrounding arithmetic in the outer extent
(test-eqv "inner escape, outer arithmetic" 6
  (call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (i 5)))))))

;; Inner captured via let binding (non-tail), then escapes
(test-eqv "inner via let binding" 6
  (call/cc (lambda (o)
    (let ((x (call/cc (lambda (i) (i 5))))) (+ 1 x)))))

;; Outer continuation escaped from within the inner extent
(test-eqv "outer escape from inner extent" 7
  (call/cc (lambda (o) (+ 1 (call/cc (lambda (i) (o 7)))))))

;; Triple nesting, innermost escapes through two outer frames
(test-eqv "triple nesting" 111
  (call/cc (lambda (a)
    (+ 1 (call/cc (lambda (b)
      (+ 10 (call/cc (lambda (c) (c 100))))))))))

;; Mixed call/cc and call/ec nesting
(test-eqv "call/ec outer, call/cc inner" 6
  (call/ec (lambda (o) (+ 1 (call/cc (lambda (i) (i 5)))))))

(test-eqv "call/cc outer, call/ec inner" 6
  (call/cc (lambda (o) (+ 1 (call/ec (lambda (i) (i 5)))))))

;; dynamic-wind after-thunk still runs when an inner nested escape unwinds
(define lg '())
(define (note x) (set! lg (cons x lg)))
(call/cc (lambda (o)
  (+ 1 (call/cc (lambda (i)
    (dynamic-wind
      (lambda () (note 'before))
      (lambda () (i 9))
      (lambda () (note 'after))))))))
(test-equal "dynamic-wind with nested escape" '(before after)
  (reverse lg))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callcc-nested")
(if (> %test-fail-count 0) (exit 1))
