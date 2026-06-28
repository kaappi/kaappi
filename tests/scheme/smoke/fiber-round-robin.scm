;; Regression test for #227: Fiber scheduling starvation.
;; With the naive index-0 scan, fiber 0 runs to completion before
;; fiber 1 or 2 get any CPU time.  Round-robin scheduling ensures
;; fibers interleave: no fiber should run all its turns before
;; another starts.

(import (scheme base)
        (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " got=") (write got)
        (display " expected=") (write expected)
        (newline))))

;; Each fiber sends its id then yields, repeating 3 times.
;; The execution log records which fiber ran in what order.
(define log-ch (make-channel))

(define f0 (spawn (lambda ()
                    (channel-send log-ch 'a)
                    (yield)
                    (channel-send log-ch 'a)
                    (yield)
                    (channel-send log-ch 'a))))

(define f1 (spawn (lambda ()
                    (channel-send log-ch 'b)
                    (yield)
                    (channel-send log-ch 'b)
                    (yield)
                    (channel-send log-ch 'b))))

(define f2 (spawn (lambda ()
                    (channel-send log-ch 'c)
                    (yield)
                    (channel-send log-ch 'c)
                    (yield)
                    (channel-send log-ch 'c))))

;; Wait for all fibers to complete
(fiber-join f0)
(fiber-join f1)
(fiber-join f2)

;; Drain the log
(define log
  (let loop ((acc '()) (n 0))
    (if (= n 9)
        (reverse acc)
        (loop (cons (channel-receive log-ch) acc) (+ n 1)))))

;; With fair scheduling, no fiber monopolizes the CPU.
;; Check: the first 3 log entries must NOT all be the same symbol.
;; Under naive index-0 scan: (a a a b b b c c c)
;; Under round-robin:        (a b c a b c a b c) or similar interleaving
(define first-three (list (list-ref log 0) (list-ref log 1) (list-ref log 2)))

(check "scheduling is fair (first 3 not all same)"
  (not (and (eq? (list-ref first-three 0) (list-ref first-three 1))
            (eq? (list-ref first-three 1) (list-ref first-three 2))))
  #t)

;; Verify all 9 messages arrived with correct counts
(define (count-sym sym lst)
  (let loop ((l lst) (n 0))
    (if (null? l) n
        (loop (cdr l) (if (eq? (car l) sym) (+ n 1) n)))))

(check "fiber-a ran 3 times" (count-sym 'a log) 3)
(check "fiber-b ran 3 times" (count-sym 'b log) 3)
(check "fiber-c ran 3 times" (count-sym 'c log) 3)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (error "fiber round-robin tests failed" fail))
