;;; Regression test for #640: SRFI-13 parseStartEnd and string-take/-drop
;;; silently clamp out-of-range start/end instead of erroring.

(import (scheme base) (scheme write) (srfi 13))

(define pass 0)
(define fail 0)

(define (check-error name thunk)
  (guard (exn
    (#t (set! pass (+ pass 1))))
    (thunk)
    (set! fail (+ fail 1))
    (display "FAIL: ") (display name)
    (display " — no error raised") (newline)))

(define (check name expected actual)
  (if (equal? expected actual)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display name) (newline)
      (display "  expected: ") (display expected) (newline)
      (display "  actual:   ") (display actual) (newline))))

;; Out-of-range must error
(check-error "string-take out of range" (lambda () (string-take "abc" 100)))
(check-error "string-drop out of range" (lambda () (string-drop "abc" 100)))
(check-error "string-take-right out of range" (lambda () (string-take-right "abc" 100)))
(check-error "string-drop-right out of range" (lambda () (string-drop-right "abc" 100)))
(check-error "string-contains start out of range" (lambda () (string-contains "abc" "x" 100)))
(check-error "string-index start out of range" (lambda () (string-index "abc" char-alphabetic? 100)))

;; Valid boundary cases still work
(check "string-take at length" "abc" (string-take "abc" 3))
(check "string-take 0" "" (string-take "abc" 0))
(check "string-drop at length" "" (string-drop "abc" 3))
(check "string-drop 0" "abc" (string-drop "abc" 0))
(check "string-take-right at length" "abc" (string-take-right "abc" 3))
(check "string-drop-right at length" "" (string-drop-right "abc" 3))

;; substring errors (pre-existing correct behavior, verify it's preserved)
(check-error "substring out of range" (lambda () (substring "abc" 10 12)))

(display pass) (display " pass, ") (display fail) (display " fail") (newline)
(when (> fail 0) (exit 1))
