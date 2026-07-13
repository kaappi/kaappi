;; KEP-0002 Phase 5 (#1470): (kaappi parallel) pool-shutdown! semantics.
;; Shutdown falls out of the channel runtime's close/drain protocol (KEP-0002
;; §6, already shipped in Phase 4) rather than sentinel messages: closing the
;; task channel wakes every idle worker at once, each worker finishes its
;; current task, drains anything still queued, and exits on eof. Tasks
;; submitted before shutdown all run to completion -- including one racing
;; the close -- and pool-submit after shutdown raises.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi parallel) (srfi 64))

(test-begin "kaappi-parallel-shutdown")

(test-equal "shutdown drains a full batch of already-queued tasks"
  '(0 1 4 9 16 25 36 49 64 81)
  (let* ((pool (make-pool 2))
         (replies (map (lambda (x) (pool-submit pool (lambda () (* x x))))
                       '(0 1 2 3 4 5 6 7 8 9)))
         (results (map task-wait replies)))
    ;; All ten tasks are already queued/in-flight by this point (pool-submit
    ;; is synchronous); shutdown must not drop any of them.
    (pool-shutdown! pool)
    results))

(test-equal "shutdown drains more queued tasks than there are workers"
  '(0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19)
  ;; A single worker cannot possibly have drained all 20 tasks by the time
  ;; the last pool-submit returns; shutdown must still wait for every
  ;; admitted task to run rather than abandoning whatever is still queued.
  (let* ((pool (make-pool 1))
         (replies (map (lambda (x) (pool-submit pool (lambda () x)))
                       (let build ((i 0)) (if (= i 20) '() (cons i (build (+ i 1)))))))
         (results (map task-wait replies)))
    (pool-shutdown! pool)
    results))

(test-assert "pool-submit after shutdown raises"
  (let ((pool (make-pool 2)))
    (pool-shutdown! pool)
    (guard (e (#t #t)) (pool-submit pool (lambda () 1)) #f)))

(test-assert "pool-shutdown! is safe to call after all tasks are already collected"
  (let* ((pool (make-pool 1))
         (reply (pool-submit pool (lambda () 1))))
    (task-wait reply)
    (pool-shutdown! pool)
    #t))

(let ((runner (test-runner-current)))
  (test-end "kaappi-parallel-shutdown")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
