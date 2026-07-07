(import (scheme base) (scheme write) (srfi 27))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name val)
  (if val
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " — expected true")
        (newline))))

;; Bug 1: State truncation — state-ref/state-set! must be a lossless roundtrip.
;; Previously, state words were stored as fixnums (48-bit), truncating u64 values.

(define rs (make-random-source))
(define rand-int (random-source-make-integers rs))

;; Advance the PRNG to produce state with high bits set
(let loop ((i 0))
  (when (< i 1000)
    (rand-int 100)
    (loop (+ i 1))))

(define saved-state (random-source-state-ref rs))

;; Generate some numbers from the saved state
(random-source-state-set! rs saved-state)
(define n1 (rand-int 1000000))
(define n2 (rand-int 1000000))
(define n3 (rand-int 1000000))

;; Restore state and verify same sequence
(random-source-state-set! rs saved-state)
(check "state roundtrip n1" (rand-int 1000000) n1)
(check "state roundtrip n2" (rand-int 1000000) n2)
(check "state roundtrip n3" (rand-int 1000000) n3)

;; Bug 2: pseudo-randomize! must reject negative arguments (was panicking)
(define rs2 (make-random-source))
(define pseudo-err-i #f)
(guard (e (#t (set! pseudo-err-i #t)))
  (random-source-pseudo-randomize! rs2 -1 0))
(check-true "pseudo-randomize! rejects negative i" pseudo-err-i)

(define pseudo-err-j #f)
(guard (e (#t (set! pseudo-err-j #t)))
  (random-source-pseudo-randomize! rs2 0 -1))
(check-true "pseudo-randomize! rejects negative j" pseudo-err-j)

;; Bug 3: state-set! must reject all-zero state (Xoshiro256 invariant)
(define rs3 (make-random-source))
(define zero-err #f)
(guard (e (#t (set! zero-err #t)))
  (random-source-state-set! rs3 '(0 0 0 0)))
(check-true "state-set! rejects all-zero state" zero-err)

;; Verify state words are integers (now bignums for full 64-bit)
(define state-words (random-source-state-ref default-random-source))
(check-true "state is a list of 4" (= 4 (length state-words)))
(check-true "state words are integers"
  (and (integer? (car state-words))
       (integer? (cadr state-words))
       (integer? (caddr state-words))
       (integer? (cadddr state-words))))

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI-27 state tests failed" fail))
