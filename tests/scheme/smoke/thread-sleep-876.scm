;; Regression test for #876: thread-sleep! must actually sleep.
;;
;; This file used to display the answer and exit 0 either way, so it passed
;; under the very regression it was written to catch: with (thread-sleep! 0)
;; substituted for the sleep it printed `#f` and still exited 0. Neither
;; runner noticed -- run-all.sh's stdout safety net looks for a failure
;; *count* ("3 fail", "unexpected failures 3") and a bare `#f` has none, and
;; `kaappi test` reported `PASS (0 tests)`. It is now a SRFI-64 file with the
;; exit-on-fail epilogue (audit v2 phase 5E).
;;
;; Both assertions are LOWER bounds on elapsed time, which is the only
;; direction that is safe on an emulated CI leg: a slow machine can only
;; make the measured interval longer. The 0.09 s tolerance on a 0.1 s sleep
;; is for clock granularity, not for scheduling slack.

(import (scheme base) (srfi 18) (srfi 64))

(test-begin "thread-sleep-876")

(let* ((s0 (time->seconds (current-time)))
       (ignored (thread-sleep! 0.1))
       (s1 (time->seconds (current-time))))
  (test-assert "thread-sleep! 0.1 blocks for at least 90 ms"
    (>= (- s1 s0) 0.09)))

;; The SRFI-18 absolute-deadline form of the same call: thread-sleep! also
;; accepts a time object, meaning "sleep until then".
(let* ((s0 (time->seconds (current-time)))
       (ignored (thread-sleep! (seconds->time (+ s0 0.1))))
       (s1 (time->seconds (current-time))))
  (test-assert "thread-sleep! to an absolute time blocks for at least 90 ms"
    (>= (- s1 s0) 0.09)))

(let ((runner (test-runner-current)))
  (test-end "thread-sleep-876")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
