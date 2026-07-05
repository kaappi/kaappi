;; SRFI-78 (lightweight testing) conformance tests — audit Phase 3d
;; check-passed? has the wrong signature and check-ec/check-set-mode! are
;; missing (#1220). Kaappi's count accessors are used below as extensions.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi78.scm

(import (scheme base) (srfi 78) (chibi test))

(test-begin "srfi-78")

;; passing checks accumulate (Kaappi extension: zero-arg count accessors)
(check-reset!)
(check (+ 1 1) => 2)
(check (list 1 2) => (list 1 2))
(test 2 (check-passed?))
(test 0 (check-failed?))

;; a failing check counts as failed, does not raise
(check (+ 1 1) => 3)
(test 2 (check-passed?))
(test 1 (check-failed?))

;; check-reset! zeroes both counters
(check-reset!)
(test 0 (check-passed?))
(test 0 (check-failed?))

;; check-report exists and does not raise
(check (* 2 2) => 4)
(check-report)
(test 1 (check-passed?))

;;; --- SRFI-78 API shape ---
;; "(check-passed? expected-total-count) ... #t if there were no failed
;;  checks and expected-total-count correct checks, #f otherwise"
;; FAIL: #1220 (check-passed? takes no arguments and returns a count)
;; (test #t (begin (check-reset!) (check 1 => 1) (check-passed? 1)))
;; FAIL: #1220 (check-set-mode! and check-ec are not exported)
;; (test 'ok (begin (check-set-mode! 'off) 'ok))

(test-end "srfi-78")
