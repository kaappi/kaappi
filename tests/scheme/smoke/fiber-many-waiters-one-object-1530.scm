;; Regression test for #1530: the wake paths index parked fibers by the object
;; they wait on (waiter_index / enrollWaiter), so a wake touches only the
;; waiters on that object instead of scanning every fiber. This drives the
;; broadcast wake with many concurrent waiters on ONE channel: N fibers all
;; block on channel-receive, then channel-close! must wake every one of them
;; (each observes EOF) — no lost wakeup, no hang, regardless of N. It also
;; guards the single-object hand-off shape the mutex/condvar wakes share.
(import (scheme base) (scheme write) (srfi 64) (kaappi fibers))

(test-begin "fiber-many-waiters-one-object-1530")

(define n 500)
(define ch (make-channel))
(define got-eof 0)

;; Spawn N fibers that all park on the same empty channel, so they are all
;; concurrently enrolled under one key at once — the case #1530 makes O(N)
;; instead of O(N^2) across the N wakes.
(define fibers
  (let loop ((i 0) (acc '()))
    (if (= i n)
        acc
        (loop (+ i 1)
              (cons (spawn (lambda ()
                             (if (eof-object? (channel-receive ch))
                                 (begin (set! got-eof (+ got-eof 1)) 'eof)
                                 'value)))
                    acc)))))

;; Give every fiber a turn to reach channel-receive and park, then wake them
;; all with a single close. A lost wakeup here would strand a fiber and make
;; its fiber-join below hang (run-all.sh's per-file timeout catches that).
(yield)
(channel-close! ch)

(define results (map fiber-join fibers))

(test-equal "all N fibers completed" n (length results))
(test-equal "every waiter woke on close and saw EOF" n got-eof)
(test-assert "and each returned the EOF marker"
  (let loop ((rs results))
    (cond ((null? rs) #t)
          ((eq? (car rs) 'eof) (loop (cdr rs)))
          (else #f))))

(let ((runner (test-runner-current)))
  (test-end "fiber-many-waiters-one-object-1530")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
