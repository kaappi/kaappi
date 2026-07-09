;; Regression test for #1187: FFI call-time errors carry descriptive messages
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "ffi-error-messages")

(define lib (ffi-open #f))
(define c-abs (ffi-fn lib "abs" '(int) 'int))
(define c-sqrt (ffi-fn lib "sqrt" '(double) 'double))
(define c-strlen (ffi-fn lib "strlen" '(string) 'size_t))

;; Wrong argument type: flonum for int
(test-assert "type error names function and expected type"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "abs")
                       (string-contains msg "int")))))
    (c-abs -3.0)
    #f))

;; Wrong argument type: string for int
(test-assert "type error names actual type"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "abs")
                       (string-contains msg "string")))))
    (c-abs "x")
    #f))

;; Arity mismatch: too many arguments
(test-assert "arity mismatch names function and counts"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "sqrt")
                       (string-contains msg "1")
                       (string-contains msg "2")))))
    (c-sqrt 1.0 2.0)
    #f))

;; NUL byte in string argument
(test-assert "NUL-in-string error names function"
  (guard (e (#t (let ((msg (error-object-message e)))
                  (and (string-contains msg "strlen")
                       (string-contains msg "NUL")))))
    (c-strlen (string #\a #\null #\b))
    #f))

(let ((runner (test-runner-current)))
  (test-end "ffi-error-messages")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
