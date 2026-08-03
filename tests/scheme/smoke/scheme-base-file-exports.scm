;; Regression test for #422: open-binary-* should be in (scheme file), not (scheme base)

(import (scheme base) (scheme eval) (scheme write) (scheme process-context) (srfi 64))

;; These should come from (scheme file), not (scheme base)
(import (only (scheme file) open-binary-input-file open-binary-output-file))

(test-begin "scheme-base-file-exports")

(test-assert "(scheme file) exports open-binary-input-file"
             (procedure? open-binary-input-file))
(test-assert "(scheme file) exports open-binary-output-file"
             (procedure? open-binary-output-file))

;; The other half of #422, which the import above cannot show: the names must
;; NOT also be reachable from (scheme base).
(define (bound-in-base? name)
  (guard (e (#t #f))
    (eval name (environment '(scheme base)))
    #t))

(test-assert "(scheme base) does not export open-binary-input-file"
             (not (bound-in-base? 'open-binary-input-file)))
(test-assert "(scheme base) does not export open-binary-output-file"
             (not (bound-in-base? 'open-binary-output-file)))
;; Control: a name (scheme base) really does export.
(test-assert "the probe finds a name (scheme base) does export"
             (bound-in-base? 'car))

(let ((runner (test-runner-current)))
  (test-end "scheme-base-file-exports")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
