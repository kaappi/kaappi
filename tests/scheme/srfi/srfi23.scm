;; SRFI-23 (error reporting mechanism) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi23.scm

(import (scheme base) (srfi 23) (chibi test))

(test-begin "srfi-23")

;; error raises a catchable condition
(test #t (guard (e (#t (error-object? e))) (error "boom") #f))

;; message and irritants are preserved
(test "boom" (guard (e (#t (error-object-message e))) (error "boom" 1 2)))
(test '(1 2) (guard (e (#t (error-object-irritants e))) (error "boom" 1 2)))
(test '() (guard (e (#t (error-object-irritants e))) (error "no-irritants")))

;; irritants keep arbitrary structure
(test '((a b) #(1) "s")
      (guard (e (#t (error-object-irritants e)))
        (error "msg" '(a b) #(1) "s")))

;; error unwinds from nested expressions
(test 'deep (guard (e (#t 'deep)) (+ 1 (error "inside"))))

;; the raised object is not an ordinary value
(test #f (guard (e (#t (string? e))) (error "boom") #f))

(test-end "srfi-23")
