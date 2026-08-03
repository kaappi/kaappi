;; Regression test for #425: (scheme write) should only export
;; display, write, write-shared, write-simple per R7RS

(import (scheme base) (scheme eval) (scheme process-context) (srfi 64))

;; Verify newline, write-char, write-string come from (scheme base)
(import (only (scheme base) newline write-char write-string))

;; Verify (scheme write) has exactly the R7RS set
(import (only (scheme write) display write write-shared write-simple))

(test-begin "scheme-write-exports")

(define (bound-in? lib name)
  (guard (e (#t #f))
    (eval name (environment lib))
    #t))

(for-each
  (lambda (name)
    (test-assert (string-append "(scheme write) exports "
                                (symbol->string name))
                 (bound-in? '(scheme write) name)))
  '(display write write-shared write-simple))

;; The other half of #425, which the imports above cannot show: the port-output
;; procedures belong to (scheme base) and must NOT also come from (scheme write).
(for-each
  (lambda (name)
    (test-assert (string-append "(scheme base) exports " (symbol->string name))
                 (bound-in? '(scheme base) name))
    (test-assert (string-append "(scheme write) does not export "
                                (symbol->string name))
                 (not (bound-in? '(scheme write) name))))
  '(newline write-char write-string))

(let ((runner (test-runner-current)))
  (test-end "scheme-write-exports")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
