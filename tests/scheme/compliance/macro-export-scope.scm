;; Regression test for #1332: non-exported library macros leak to importers
;;
;; A library's non-exported define-syntax bindings should not be accessible
;; from importing code. Only explicitly exported macros should be visible.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

;; Library with exported macro `outer` that uses non-exported helper macro.
(define-library (test macro-scope)
  (import (scheme base))
  (export outer)
  (begin
    (define-syntax helper
      (syntax-rules ()
        ((helper x) (+ x 1))))
    (define-syntax outer
      (syntax-rules ()
        ((outer x) (helper x))))
    (define (secret) 42)))

(import (test macro-scope))

(test-begin "macro-export-scope")

;; Exported macro works correctly (expansion chains through helper)
(test-equal "exported macro expands" 6 (outer 5))

;; Non-exported macro should not be accessible as a value
(test-assert "non-exported macro not in globals"
  (guard (exn (#t #t))
    helper
    #f))

;; Non-exported procedure should not be accessible
(test-assert "non-exported procedure not in globals"
  (guard (exn (#t #t))
    (secret)
    #f))

;; --- Transitive case: exported macro references helper that references
;; another helper. Neither helper should leak.
(define-library (test deep-scope)
  (import (scheme base))
  (export deep-outer)
  (begin
    (define-syntax deep-helper-2
      (syntax-rules ()
        ((deep-helper-2 x) (* x x))))
    (define-syntax deep-helper-1
      (syntax-rules ()
        ((deep-helper-1 x) (deep-helper-2 x))))
    (define-syntax deep-outer
      (syntax-rules ()
        ((deep-outer x) (deep-helper-1 x))))))

(import (test deep-scope))

(test-equal "transitive exported macro works" 25 (deep-outer 5))

(test-assert "transitive helper-1 not in globals"
  (guard (exn (#t #t))
    deep-helper-1
    #f))

(test-assert "transitive helper-2 not in globals"
  (guard (exn (#t #t))
    deep-helper-2
    #f))

(let ((runner (test-runner-current)))
  (test-end "macro-export-scope")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
