;; SRFI-23 (error reporting mechanism) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi23.scm

(import (scheme base) (srfi 23) (scheme process-context) (srfi 64))

(test-begin "srfi-23")

;; error raises a catchable condition
(test-equal #t (guard (e (#t (error-object? e))) (error "boom") #f))

;; message and irritants are preserved
(test-equal "boom" (guard (e (#t (error-object-message e))) (error "boom" 1 2)))
(test-equal '(1 2) (guard (e (#t (error-object-irritants e))) (error "boom" 1 2)))
(test-equal '() (guard (e (#t (error-object-irritants e))) (error "no-irritants")))

;; irritants keep arbitrary structure
(test-equal '((a b) #(1) "s")
            (guard (e (#t (error-object-irritants e)))
              (error "msg" '(a b) #(1) "s")))

;; error unwinds from nested expressions
(test-equal 'deep (guard (e (#t 'deep)) (+ 1 (error "inside"))))

;; the raised object is not an ordinary value
(test-equal #f (guard (e (#t (string? e))) (error "boom") #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-23")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
