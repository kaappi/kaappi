;; Regression test for #1983: unguarded float->int conversions in SRFI-18
;; aborted the process (exit 134, uncatchable), and timeoutToDeadlineNs is
;; shared with (kaappi fibers), so channel timeouts died the same way.
;;
;; Post-fix contract:
;;   - seconds->time RAISES catchably on values no time object can represent
;;     (it constructs an observable value; clamping would silently lie).
;;   - timeouts SATURATE: a duration/deadline beyond the u64 nanosecond
;;     clock means "never times out", matching the SRFI-18 convention that
;;     +inf.0 as a timeout means wait without bound.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (srfi 64) (kaappi fibers))

(test-begin "srfi18-timeout-saturation-1983")

;; --- seconds->time: catchable rejection, exact boundary -------------------

(define (rejects? x)
  (eq? 'caught (guard (e (#t 'caught)) (seconds->time x) 'accepted)))

(test-assert "seconds->time +inf.0 raises catchably (used to abort)" (rejects? +inf.0))
(test-assert "seconds->time -inf.0 raises catchably" (rejects? -inf.0))
(test-assert "seconds->time +nan.0 raises catchably" (rejects? +nan.0))
(test-assert "seconds->time 9.3e18 raises catchably (issue's aborting cliff)" (rejects? 9.3e18))
;; 2^63 exactly: the first unrepresentable value. A guard written against
;; @floatFromInt(maxInt(i64)) re-admits it (#1907's off-by-one-ULP shape).
(test-assert "seconds->time 2^63 raises catchably" (rejects? 9223372036854775808.0))

(test-equal "seconds->time 9.2e18 round-trips (issue's last-safe control)"
            9.2e18 (time->seconds (seconds->time 9.2e18)))
(test-equal "seconds->time -2^63 round-trips (minInt IS representable)"
            -9223372036854775808.0
            (time->seconds (seconds->time -9223372036854775808.0)))
(test-approximate "seconds->time ordinary value round-trips" 1.5
                  (time->seconds (seconds->time 1.5)) 1e-9)

;; --- timeouts: saturate, never abort --------------------------------------

(define m (make-mutex))
(test-assert "mutex-lock! with the issue's catchable control 1.8e10"
             (mutex-lock! m 1.8e10))
(mutex-unlock! m)
(test-assert "mutex-lock! with a 1e300 timeout (used to abort the process)"
             (mutex-lock! m 1e300))
(mutex-unlock! m)
(test-assert "mutex-lock! with +inf.0 (never times out)"
             (mutex-lock! m +inf.0))
(mutex-unlock! m)
(test-assert "mutex-lock! with a far-future time object (u64 multiply overflowed)"
             (mutex-lock! m (seconds->time 9.2e18)))
(mutex-unlock! m)

(define t (thread-start! (make-thread (lambda () 42))))
(test-equal "thread-join! with +inf.0 timeout" 42 (thread-join! t +inf.0))

;; --- the fibers blast radius ----------------------------------------------

(define ch (make-channel 0))
(spawn (lambda () (channel-send ch 41)))
(test-equal "channel-receive with a 1e300 timeout (used to abort)"
            42 (+ 1 (channel-receive ch 1e300)))

(let ((runner (test-runner-current)))
  (test-end "srfi18-timeout-saturation-1983")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
