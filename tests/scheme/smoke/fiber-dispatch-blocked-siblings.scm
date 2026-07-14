;; Regression test for #1477: the scheduler must dispatch correctly and
;; fairly when most fibers are blocked. Many siblings park forever on a
;; never-written channel while two workers ping-pong via (yield). Before the
;; O(1) ready ring, every dispatch (and every yield's advisory check) scanned
;; past all the blocked fibers; this guards the ring path's behavior under
;; that shape -- no lost wakeups, no starvation, no hang.
(import (scheme base) (scheme write) (srfi 64) (kaappi fibers))

(test-begin "fiber-dispatch-blocked-siblings")

(define ch (make-channel))              ; never written -> receivers block forever
(do ((i 0 (+ i 1))) ((= i 200))
  (spawn (lambda () (channel-receive ch))))

;; Two workers each record their turns and yield, 5 rounds apiece.
(define order '())
(define (worker tag)
  (lambda ()
    (do ((i 0 (+ i 1))) ((= i 5) tag)
      (set! order (cons tag order))
      (yield))))
(define w1 (spawn (worker 'a)))
(define w2 (spawn (worker 'b)))

;; Join at top level (not inside a test-* form): under SRFI-64's re-entrant
;; native frame (yield no-ops there, #1184) the workers wouldn't interleave,
;; which is a property of yield, not of the scheduler under test.
(define r1 (fiber-join w1))
(define r2 (fiber-join w2))
(define final-order (reverse order))

(test-equal "worker 1 completes with its result" 'a r1)
(test-equal "worker 2 completes with its result" 'b r2)
(test-equal "both workers ran all 5 rounds each" 10 (length final-order))
;; Fair round-robin interleaves the two; the buggy "run one to completion
;; first" order would be all of one tag then all of the other.
(test-assert "workers interleaved, neither starved the other"
  (not (or (equal? final-order '(a a a a a b b b b b))
           (equal? final-order '(b b b b b a a a a a)))))

(let ((runner (test-runner-current)))
  (test-end "fiber-dispatch-blocked-siblings")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
