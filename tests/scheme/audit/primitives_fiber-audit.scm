;; Audit tests for src/primitives_fiber.zig — kaappi fibers and channels
;; (spawn, yield, fiber-join, fiber?, make-channel, channel-send,
;; channel-receive, channel?).
;; Audit campaign Phase 2.12 (#1137). Complements tests/scheme/smoke/fiber-*.scm.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.
;;
;; NOTE: test order matters. Deadlock tests leak permanently-parked fibers
;; (that is inherent — there is no fiber-kill), and the spawn test at the
;; end deliberately spawns 70 more permanently-parked fibers. Nothing
;; requiring a bounded fiber count may run after it.

(import (scheme base) (scheme write) (kaappi fibers))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_fiber audit")

;;; --- channels without any fibers ---
;; receive on an empty channel with no scheduler must raise, not hang
(test-equal 'deadlock-caught
    (guard (e (#t 'deadlock-caught)) (channel-receive (make-channel))))
(test-equal 42 (let ((ch (make-channel))) (channel-send ch 42) (channel-receive ch)))
;; FIFO ordering
(test-equal '(1 2 3)
    (let ((ch (make-channel)))
      (channel-send ch 1) (channel-send ch 2) (channel-send ch 3)
      (list (channel-receive ch) (channel-receive ch) (channel-receive ch))))
;; values pass through by reference (same heap object)
(test-equal #t (let ((ch (make-channel)) (x (list 1 2)))
                 (channel-send ch x)
                 (eq? x (channel-receive ch))))
;; interleaved send/receive
(test-equal '(1 2)
    (let ((ch (make-channel)))
      (channel-send ch 1)
      (let ((a (channel-receive ch)))
        (channel-send ch 2)
        (list a (channel-receive ch)))))

;;; --- predicates ---
(test-equal #t (channel? (make-channel)))
(test-equal #f (channel? 42))
(test-equal #f (channel? '()))
(test-equal #f (fiber? (make-channel)))
(test-equal #f (fiber? 42))

;;; --- type errors are catchable ---
(test-equal 'caught (guard (e (#t 'caught)) (channel-send 42 'v)))
(test-equal 'caught (guard (e (#t 'caught)) (channel-receive "not-a-channel")))
(test-equal 'caught (guard (e (#t 'caught)) (fiber-join 42)))
(test-equal 'caught (guard (e (#t 'caught)) (spawn 42)))

;;; --- yield ---
;; top-level yield with no scheduler is a no-op
(test-equal 'ok (begin (yield) 'ok))

;;; --- spawn / fiber-join ---
;; native procedures are now accepted as spawn thunks (#1155)
(test-equal #t (let ((f (spawn newline)))
                 (fiber-join f)
                 (fiber? f)))
(test-equal #t (fiber? (spawn (lambda () 1))))
(test-equal 42 (fiber-join (spawn (lambda () (* 6 7)))))
;; yield with a runnable scheduler is fine
(test-equal 'ok (begin (yield) 'ok))
;; join is memoized: joining twice returns the same result
(test-equal '(once once)
    (let ((f (spawn (lambda () 'once))))
      (list (fiber-join f) (fiber-join f))))
;; fibers spawning fibers
(test-equal 11 (fiber-join (spawn (lambda ()
                                    (+ 1 (fiber-join (spawn (lambda () 10))))))))
;; producer fiber wakes a blocked main receive
(test-equal 'hello (let ((ch (make-channel)))
                     (spawn (lambda () (channel-send ch 'hello)))
                     (channel-receive ch)))
;; two-stage pipeline through the scheduler
(test-equal 30 (let ((a (make-channel)) (b (make-channel)))
                 (spawn (lambda () (channel-send b (* 3 (channel-receive a)))))
                 (spawn (lambda () (channel-send a 10)))
                 (channel-receive b)))

;;; --- errors inside fibers ---
;; join re-raises the fiber's exception, with the error object intact
(test-equal '(caught "fiber-boom")
    (guard (e (#t (list 'caught (error-object-message e))))
      (fiber-join (spawn (lambda () (error "fiber-boom"))))))
;; re-raised on every join
(test-equal '(c1 c2)
    (let ((f (spawn (lambda () (error "boom2")))))
      (list (guard (e (#t 'c1)) (fiber-join f))
            (guard (e (#t 'c2)) (fiber-join f)))))
;; a guard inside the fiber handles its own error normally
(test-equal 'handled (fiber-join (spawn (lambda ()
                                          (guard (e (#t 'handled)) (error "x"))))))

;;; --- deadlock detection (each leaks a parked fiber; that is inherent) ---
;; joining a fiber blocked on a never-sent channel raises, not hangs
(test-equal 'deadlock-caught
    (guard (e (#t 'deadlock-caught))
      (let ((ch (make-channel)))
        (fiber-join (spawn (lambda () (channel-receive ch)))))))
;; cyclic join raises, not hangs
(test-equal 'deadlock-caught
    (guard (e (#t 'deadlock-caught))
      (letrec ((fa (spawn (lambda () (fiber-join fb))))
               (fb (spawn (lambda () (fiber-join fa)))))
        (fiber-join fa))))
;; deadlock errors carry a useful message
(test-equal #t (guard (e (#t (and (error-object? e)
                                  (> (string-length (error-object-message e)) 10))))
                 (channel-receive (make-channel))
                 #f))

;;; --- spawn limit — superseded by the growable fiber table (KEP-0001
;;; Phase 2, kaappi/kaappi#1440): the fixed MAX_FIBERS=64 table this test
;;; used to hit is gone, so 70 concurrently-parked spawns now succeed
;;; outright instead of erroring at the old ceiling.
(test-equal 'no-limit
    (guard (e (#t (list 'limit-hit (error-object? e))))
      (let loop ((i 0))
        (if (= i 70) 'no-limit
            (begin (spawn (lambda () (channel-receive (make-channel))))
                   (loop (+ i 1)))))))
;; sends/receives that need no new slot still work at the limit
(test-equal 1 (let ((ch (make-channel))) (channel-send ch 1) (channel-receive ch)))
;; With every slot holding a permanently-parked fiber, a top-level (yield)
;; used to raise a bare error whose message was just "error" (#1184): the
;; test macro's guard sits between the yield and the scheduler loop, and
;; with-exception-handler converted the in-flight Yielded unwind into a
;; contentless exception. Yield is advisory and must be a no-op here.
(test-equal 'yield-ok (begin (yield) 'yield-ok))

(let ((runner (test-runner-current)))
  (test-end "primitives_fiber audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
