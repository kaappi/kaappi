;; Stress test for cross-thread fiber.status atomic ordering (#1028).
;; Spawns and joins many OS threads in tight succession to exercise
;; the release/acquire window between child status writes and parent reads.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "srfi18-atomic-stress")

;; Spawn and join 20 successful threads
(test-assert "spawn-join 20 successful threads"
  (let loop ((i 0) (ok #t))
    (if (= i 20) ok
        (let* ((n (+ i 1))
               (t (make-thread (lambda () (* n n)))))
          (thread-start! t)
          (loop n (and ok (= (thread-join! t) (* n n))))))))

;; Batch spawn then batch join
(test-assert "batch spawn then batch join"
  (let ((threads (let loop ((i 0) (acc '()))
                   (if (= i 10) (reverse acc)
                       (let ((n (+ i 100)))
                         (loop (+ i 1)
                               (cons (make-thread (lambda () n)) acc)))))))
    (for-each thread-start! threads)
    (let ((results (map thread-join! threads)))
      (= (length results) 10))))

;; Threads that raise errors
(test-assert "join erroring threads"
  (let loop ((i 0) (ok #t))
    (if (= i 10) ok
        (let ((t (make-thread (lambda () (error "stress" i)))))
          (thread-start! t)
          (loop (+ i 1)
                (and ok
                     (guard (e ((uncaught-exception? e) #t) (#t #f))
                       (thread-join! t) #f)))))))

;; Terminate and join
(test-assert "terminate and join"
  (let loop ((i 0) (ok #t))
    (if (= i 5) ok
        (let ((t (make-thread (lambda () (let lp () (thread-yield!) (lp))))))
          (thread-start! t)
          (thread-terminate! t)
          (loop (+ i 1)
                (and ok
                     (guard (e ((terminated-thread-exception? e) #t) (#t #f))
                       (thread-join! t) #f)))))))

;; Multiple rounds of mixed workloads
(test-assert "three rounds of mixed spawn-join"
  (let round-loop ((r 0))
    (if (= r 3) #t
        (let ((t1 (make-thread (lambda () (+ r 1))))
              (t2 (make-thread (lambda () (error "round" r))))
              (t3 (make-thread (lambda () (let lp () (thread-yield!) (lp))))))
          (thread-start! t1)
          (thread-start! t2)
          (thread-start! t3)
          (thread-terminate! t3)
          (let ((r1 (thread-join! t1))
                (r2 (guard (e (#t 'caught)) (thread-join! t2)))
                (r3 (guard (e (#t 'caught)) (thread-join! t3))))
            (if (and (= r1 (+ r 1)) (eq? r2 'caught) (eq? r3 'caught))
                (round-loop (+ r 1))
                #f))))))

(let ((runner (test-runner-current)))
  (test-end "srfi18-atomic-stress")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
