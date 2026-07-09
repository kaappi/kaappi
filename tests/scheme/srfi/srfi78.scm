;; SRFI-78 (lightweight testing) conformance tests
;; Tests check, check-ec, check-report, check-set-mode!, check-reset!,
;; check-passed? per the SRFI-78 specification.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 78))

(test-begin "srfi-78")

;; --- check-passed? returns boolean per spec ---
(check-reset!)
(check (+ 1 1) => 2)
(check (list 1 2) => (list 1 2))
(test-assert "check-passed? true for correct count" (check-passed? 2))
(test-assert "check-passed? false for low count" (not (check-passed? 1)))
(test-assert "check-passed? false for high count" (not (check-passed? 3)))

;; a failing check makes check-passed? return #f
(check (+ 1 1) => 3)
(test-assert "check-passed? false after failure" (not (check-passed? 2)))

;; check-failed? returns the fail count (Kaappi extension)
(test-equal "check-failed? returns count" 1 (check-failed?))

;; check-reset! zeroes both counters
(check-reset!)
(test-assert "check-passed? 0 after reset" (check-passed? 0))

;; custom equality via (=> equal)
(check-reset!)
(check 1.0 (=> =) 1)
(test-assert "custom equality" (check-passed? 1))

;; --- check-set-mode! ---
(check-reset!)
(check-set-mode! 'off)
(check (+ 1 1) => 2)
(test-assert "off mode skips checks" (check-passed? 0))

(check-set-mode! 'report)
(check (+ 1 1) => 2)
(test-assert "report mode runs checks" (check-passed? 1))

;; summary mode: checks run, no per-check output
(check-reset!)
(check-set-mode! 'summary)
(check (+ 1 1) => 2)
(test-assert "summary mode counts" (check-passed? 1))
(check-set-mode! 'report)

;; check-set-mode! rejects invalid modes
(test-error "invalid mode rejected" (check-set-mode! 'bogus))

;; --- check-ec ---
(check-reset!)
(check-ec (:range i 0 5) (* i i) => (* i i))
(test-assert "check-ec all pass" (check-passed? 1))

;; check-ec with list qualifier
(check-reset!)
(check-ec (:list x '(1 2 3)) (* x 2) => (+ x x))
(test-assert "check-ec list qualifier" (check-passed? 1))

;; check-ec with actual failure — stops at first mismatch
(check-reset!)
(check-ec (:range i 0 10) i => -1)
(test-assert "check-ec failure" (not (check-passed? 1)))
(test-equal "check-ec failure count" 1 (check-failed?))

;; check-ec with custom equality
(check-reset!)
(check-ec (:range i 0 3) (* 1.0 i) (=> =) i)
(test-assert "check-ec custom equality" (check-passed? 1))

;; check-ec zero qualifiers delegates to check
(check-reset!)
(check-ec (+ 2 3) => 5)
(test-assert "check-ec zero qualifiers" (check-passed? 1))

;; check-ec with trailing diagnostic arguments (accepted)
(check-reset!)
(check-ec (:range i 0 3) (* i i) => (* i i) (i))
(test-assert "check-ec with arguments" (check-passed? 1))

;; --- check-report exists and does not raise ---
(check-reset!)
(check (* 2 2) => 4)
(check-report)
(test-assert "check-report does not disturb counters" (check-passed? 1))

(let ((runner (test-runner-current)))
  (test-end "srfi-78")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
