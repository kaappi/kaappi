;; KEP-0002 Phase 5 (#1470): (kaappi parallel) pool lifecycle -- make-pool,
;; pool-submit, task-wait. Every task thunk and result crosses a pool worker
;; boundary by copy (SRFI-18 thread deep-copy / channel envelopes), so a
;; pool shares no mutable state with its caller; tests that need to observe
;; a worker's side effect do so over a channel, not a shared variable.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi parallel) (srfi 64))

(test-begin "kaappi-parallel-pool")

(test-equal "pool-submit + task-wait round trip"
  42
  (let* ((pool (make-pool 2))
         (reply (pool-submit pool (lambda () (* 6 7))))
         (result (task-wait reply)))
    (pool-shutdown! pool)
    result))

(test-equal "several tasks on one pool, replies stay independent"
  '(1 4 9 16 25)
  (let* ((pool (make-pool 3))
         (replies (map (lambda (x) (pool-submit pool (lambda () (* x x))))
                       '(1 2 3 4 5)))
         (results (map task-wait replies)))
    (pool-shutdown! pool)
    results))

(test-equal "a single-worker pool serializes tasks correctly"
  '(1 4 9 16 25)
  (let* ((pool (make-pool 1))
         (replies (map (lambda (x) (pool-submit pool (lambda () (* x x))))
                       '(1 2 3 4 5)))
         (results (map task-wait replies)))
    (pool-shutdown! pool)
    results))

(test-assert "a task's exception propagates through task-wait, catchable with guard"
  (let* ((pool (make-pool 2))
         (reply (pool-submit pool (lambda () (error "boom")))))
    (let ((caught (guard (e (#t 'caught)) (task-wait reply) 'not-caught)))
      (pool-shutdown! pool)
      (eq? caught 'caught))))

(test-equal "a raised non-condition value propagates through task-wait too"
  'my-symbol
  (let* ((pool (make-pool 2))
         (reply (pool-submit pool (lambda () (raise 'my-symbol)))))
    (let ((result (guard (e (#t e)) (task-wait reply))))
      (pool-shutdown! pool)
      result)))

(test-assert "one task's exception does not affect other tasks on the same pool"
  (let* ((pool (make-pool 2))
         (bad (pool-submit pool (lambda () (error "boom"))))
         (good (pool-submit pool (lambda () (* 7 6)))))
    (guard (e (#t #f)) (task-wait bad))
    (let ((result (task-wait good)))
      (pool-shutdown! pool)
      (= result 42))))

(test-assert "make-pool rejects a non-positive argument"
  (guard (e (#t #t)) (make-pool 0) #f))

(test-assert "make-pool rejects a non-integer argument"
  (guard (e (#t #t)) (make-pool 1.5) #f))

(test-assert "pool-submit rejects a non-procedure thunk"
  (let ((pool (make-pool 1)))
    (let ((rejected (guard (e (#t #t)) (pool-submit pool "not-a-procedure") #f)))
      (pool-shutdown! pool)
      rejected)))

(let ((runner (test-runner-current)))
  (test-end "kaappi-parallel-pool")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
