;;; Kaappi WASM (kaappi parallel) test (KEP-0002 Phase 5, #1470).
;;; WASM has no real OS threads, so (library (srfi 18)) is unavailable and
;;; make-pool degrades to spawning fiber workers on the calling thread's
;;; scheduler instead. The library itself is embedded directly into the
;;; binary (src/vm_library.zig's embedded_libraries table) rather than
;;; loaded from lib/kaappi/parallel.sld on disk, since a WASI host has no
;;; guarantee that path is mounted anywhere reachable. Any FAIL line (or a
;;; hang) fails CI.

(import (scheme base) (kaappi parallel))

(define failures 0)
(define (check label ok)
  (display (if ok "PASS " "FAIL "))
  (display label)
  (newline)
  (if (not ok) (set! failures (+ failures 1))))

(check "processor-count is 1 on WASM" (= (processor-count) 1))

(define pool (make-pool 3))
(define reply (pool-submit pool (lambda () (* 6 7))))
(check "pool-submit + task-wait over fiber workers" (= (task-wait reply) 42))
(pool-shutdown! pool)

(check "parallel-map over fiber workers preserves order"
       (equal? (parallel-map (lambda (x) (* x x)) '(1 2 3 4 5))
               '(1 4 9 16 25)))

(define out (make-channel))
(parallel-for-each (lambda (x) (channel-send out (* x 10))) '(1 2 3))
(check "parallel-for-each runs every task"
       (let ((a (channel-receive out)) (b (channel-receive out)) (c (channel-receive out)))
         (= (+ a b c) 60)))

(check "a task's exception propagates through task-wait"
       (let* ((pool2 (make-pool 2))
              (bad (pool-submit pool2 (lambda () (error "boom"))))
              (caught (guard (e (#t 'caught)) (task-wait bad) 'not-caught)))
         (pool-shutdown! pool2)
         (eq? caught 'caught)))

(check "pool-submit after shutdown raises"
       (let ((pool3 (make-pool 1)))
         (pool-shutdown! pool3)
         (guard (e (#t #t)) (pool-submit pool3 (lambda () 1)) #f)))

(if (> failures 0)
    (begin (display "PARALLEL TESTS FAILED") (newline) (exit 1))
    (begin (display "all parallel tests passed") (newline)))
