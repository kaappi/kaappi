;;; Kaappi WASM timer test (KEP-0001 Phase 4).
;;; Exercises the WASI reactor backend's CLOCK subscription under a real
;;; WASI runtime: thread-sleep! parks the fiber on the reactor's timer
;;; heap, and the scheduler's blocking wait is a poll_oneoff call bounded
;;; by the nearest deadline. Any FAIL line (or a hang) fails CI.

(define failures 0)
(define (check label ok)
  (display (if ok "PASS " "FAIL "))
  (display label)
  (newline)
  (if (not ok) (set! failures (+ failures 1))))

(define (now-seconds)
  (/ (current-jiffy) (jiffies-per-second)))

;; Main-fiber sleep: the current fiber drives the scheduler in place and
;; the reactor waits out the deadline. Never wakes early.
(define t0 (now-seconds))
(thread-sleep! 0.15)
(check "main-fiber sleep waits out the full duration"
       (>= (- (now-seconds) t0) 0.15))

;; Zero and negative durations return immediately (no reactor round trip).
(define t1 (now-seconds))
(thread-sleep! 0)
(thread-sleep! -1)
(check "zero/negative sleep returns immediately"
       (< (- (now-seconds) t1) 0.1))

;; Two sleeping fibers park on the same timer heap; the nearer deadline
;; wakes first regardless of spawn order.
(define order '())
(define slow (spawn (lambda ()
                      (thread-sleep! 0.08)
                      (set! order (cons 'slow order)))))
(define fast (spawn (lambda ()
                      (thread-sleep! 0.02)
                      (set! order (cons 'fast order)))))
(fiber-join slow)
(fiber-join fast)
(check "nearer deadline wakes first" (equal? (reverse order) '(fast slow)))

;; A sleeping fiber must not stall a runnable sibling: the worker finishes
;; its (yield-punctuated) loop while the sleeper is still parked.
(define progress 0)
(define sleeper (spawn (lambda () (thread-sleep! 0.1) progress)))
(define worker (spawn (lambda ()
                        (let loop ((i 0))
                          (if (< i 5)
                              (begin (set! progress (+ progress 1))
                                     (yield)
                                     (loop (+ i 1)))
                              'done)))))
(define worker-result (fiber-join worker))
(check "sleeping fiber does not block a runnable sibling"
       (and (equal? worker-result 'done)
            (= progress 5)
            (= (fiber-join sleeper) 5)))

(if (> failures 0)
    (begin (display "TIMER TESTS FAILED") (newline) (exit 1))
    (begin (display "all timer tests passed") (newline)))
