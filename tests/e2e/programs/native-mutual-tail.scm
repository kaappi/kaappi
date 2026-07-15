; Guaranteed constant-stack mutual tail recursion via tailcc + musttail (#1499).
;
; even?/odd? exercise both directions of a 2-cycle: the forward call
; (my-even? -> my-odd?, defined later) resolves through the pre-scan reservation,
; the backward call (my-odd? -> my-even?) through native_fns. Both lower to
; `musttail call tailcc`. The depth here (2,000,000) is far past what an 8 MB
; stack holds as real frames, so a native binary that did NOT tail-call would
; overflow and crash — the e2e diff against the (VM-TCO) interpreter is thus a
; constant-stack regression test, not just an output check.
(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))
(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))

(display (my-even? 2000000)) (newline) ; #t
(display (my-odd? 2000001)) (newline)  ; #t
(display (my-even? 2000001)) (newline) ; #f

; A 3-function cycle — each call is in tail position, so all three are musttail.
(define (count-a n) (if (= n 0) 'done-a (count-b (- n 1))))
(define (count-b n) (if (= n 0) 'done-b (count-c (- n 1))))
(define (count-c n) (if (= n 0) 'done-c (count-a (- n 1))))

(display (count-a 1500000)) (newline)

; A non-tail direct call to a fast entry: a register-argument `call tailcc`
; (no args array), not a musttail. Verifies the fast entry is also the
; ordinary direct-call target.
(define (sq x) (* x x))
(define (sum-of-squares a b) (+ (sq a) (sq b)))
(display (sum-of-squares 3 4)) (newline) ; 25

; A tail call nested inside an `if` inside a mutual cycle, mixed with a
; self-tail loop (which stays a branch loop, not a musttail).
(define (ping n acc) (if (= n 0) acc (pong (- n 1) (+ acc 1))))
(define (pong n acc) (if (= n 0) acc (ping (- n 1) (+ acc 2))))
(display (ping 1000000 0)) (newline)
