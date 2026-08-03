;; Regression test for #851: exact-integer-sqrt hangs on large bignums.

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "exact-integer-sqrt-851")

;; These should complete instantly, not hang
(let-values (((s r) (exact-integer-sqrt (expt 2 1100))))
  (test-assert "s*s + r = 2^1100" (= (+ (* s s) r) (expt 2 1100))))

(let-values (((s r) (exact-integer-sqrt (expt 2 3000))))
  (test-assert "s*s + r = 2^3000" (= (+ (* s s) r) (expt 2 3000))))

(let ((runner (test-runner-current)))
  (test-end "exact-integer-sqrt-851")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
