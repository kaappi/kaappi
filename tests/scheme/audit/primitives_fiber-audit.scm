;; Audit tests for src/primitives_fiber.zig — kaappi fibers and channels
;; (spawn, yield, fiber-join, fiber?, make-channel, channel-send,
;; channel-receive, channel?).
;; Audit campaign Phase 2.12 (#1137). Complements tests/scheme/smoke/fiber-*.scm.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.
;;
;; NOTE: test order matters. Deadlock tests leak permanently-parked fibers
;; (that is inherent — there is no fiber-kill), and the spawn-limit test at
;; the end deliberately fills every scheduler slot. Nothing that needs a
;; free slot may run after it.

(import (scheme base) (scheme write) (kaappi fibers))
(import (chibi test))

(test-begin "primitives_fiber audit")

;;; --- channels without any fibers ---
;; receive on an empty channel with no scheduler must raise, not hang
(test 'deadlock-caught
    (guard (e (#t 'deadlock-caught)) (channel-receive (make-channel))))
(test 42 (let ((ch (make-channel))) (channel-send ch 42) (channel-receive ch)))
;; FIFO ordering
(test '(1 2 3)
    (let ((ch (make-channel)))
      (channel-send ch 1) (channel-send ch 2) (channel-send ch 3)
      (list (channel-receive ch) (channel-receive ch) (channel-receive ch))))
;; values pass through by reference (same heap object)
(test #t (let ((ch (make-channel)) (x (list 1 2)))
           (channel-send ch x)
           (eq? x (channel-receive ch))))
;; interleaved send/receive
(test '(1 2)
    (let ((ch (make-channel)))
      (channel-send ch 1)
      (let ((a (channel-receive ch)))
        (channel-send ch 2)
        (list a (channel-receive ch)))))

;;; --- predicates ---
(test #t (channel? (make-channel)))
(test #f (channel? 42))
(test #f (channel? '()))
(test #f (fiber? (make-channel)))
(test #f (fiber? 42))

;;; --- type errors are catchable ---
(test 'caught (guard (e (#t 'caught)) (channel-send 42 'v)))
(test 'caught (guard (e (#t 'caught)) (channel-receive "not-a-channel")))
(test 'caught (guard (e (#t 'caught)) (fiber-join 42)))
(test 'caught (guard (e (#t 'caught)) (spawn 42)))
;; native procedures are rejected as spawn thunks (resolution of #551;
;; same class as #1155 for SRFI-18 make-thread)
(test 'caught (guard (e (#t 'caught)) (spawn newline)))

;;; --- yield ---
;; top-level yield with no scheduler is a no-op
(test 'ok (begin (yield) 'ok))

;;; --- spawn / fiber-join ---
(test #t (fiber? (spawn (lambda () 1))))
(test 42 (fiber-join (spawn (lambda () (* 6 7)))))
;; yield with a runnable scheduler is fine
;; SKIP: yield raises inside with-exception-handler after spawn (#1314)
;; (test 'ok (begin (yield) 'ok))
;; join is memoized: joining twice returns the same result
(test '(once once)
    (let ((f (spawn (lambda () 'once))))
      (list (fiber-join f) (fiber-join f))))
;; fibers spawning fibers
(test 11 (fiber-join (spawn (lambda ()
                              (+ 1 (fiber-join (spawn (lambda () 10))))))))
;; producer fiber wakes a blocked main receive
(test 'hello (let ((ch (make-channel)))
               (spawn (lambda () (channel-send ch 'hello)))
               (channel-receive ch)))
;; two-stage pipeline through the scheduler
(test 30 (let ((a (make-channel)) (b (make-channel)))
           (spawn (lambda () (channel-send b (* 3 (channel-receive a)))))
           (spawn (lambda () (channel-send a 10)))
           (channel-receive b)))

;;; --- errors inside fibers ---
;; join re-raises the fiber's exception, with the error object intact
(test '(caught "fiber-boom")
    (guard (e (#t (list 'caught (error-object-message e))))
      (fiber-join (spawn (lambda () (error "fiber-boom"))))))
;; re-raised on every join
(test '(c1 c2)
    (let ((f (spawn (lambda () (error "boom2")))))
      (list (guard (e (#t 'c1)) (fiber-join f))
            (guard (e (#t 'c2)) (fiber-join f)))))
;; a guard inside the fiber handles its own error normally
(test 'handled (fiber-join (spawn (lambda ()
                                    (guard (e (#t 'handled)) (error "x"))))))

;;; --- deadlock detection (each leaks a parked fiber; that is inherent) ---
;; joining a fiber blocked on a never-sent channel raises, not hangs
(test 'deadlock-caught
    (guard (e (#t 'deadlock-caught))
      (let ((ch (make-channel)))
        (fiber-join (spawn (lambda () (channel-receive ch)))))))
;; cyclic join raises, not hangs
(test 'deadlock-caught
    (guard (e (#t 'deadlock-caught))
      (letrec ((fa (spawn (lambda () (fiber-join fb))))
               (fb (spawn (lambda () (fiber-join fa)))))
        (fiber-join fa))))
;; deadlock errors carry a useful message
(test #t (guard (e (#t (and (error-object? e)
                            (> (string-length (error-object-message e)) 10))))
           (channel-receive (make-channel))
           #f))

;;; --- spawn limit (MAX_FIBERS = 64) — fills all remaining slots; keep last ---
(test '(limit-hit #t)
    (guard (e (#t (list 'limit-hit (error-object? e))))
      (let loop ((i 0))
        (if (= i 70) 'no-limit
            (begin (spawn (lambda () (channel-receive (make-channel))))
                   (loop (+ i 1)))))))
;; sends/receives that need no new slot still work at the limit
(test 1 (let ((ch (make-channel))) (channel-send ch 1) (channel-receive ch)))
;; With every slot holding a permanently-parked fiber, a top-level (yield)
;; raises a bare error whose message is just "error" — but the main fiber
;; can obviously still run (the send/receive above works). Yield is
;; advisory and should be a no-op here.
;; FAIL: #1184 (yield raises a contentless error when all other fibers are parked)
;; (test 'yield-ok (begin (yield) 'yield-ok))

(test-end "primitives_fiber audit")
