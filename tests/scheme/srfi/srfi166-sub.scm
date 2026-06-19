(import (scheme base) (scheme write) (srfi 166))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; Pretty
(import (srfi 166 pretty))
(check "pretty" (show #f (pretty '(1 2 3))) "(1 2 3)")
(check "pretty str" (show #f (pretty "hello")) "\"hello\"")

;;; Color
(import (srfi 166 color))
(let ((s (show #f (as-red "hello"))))
  (check-true "as-red has escape" (> (string-length s) 5))
  (check-true "as-red contains hello" (let loop ((i 0))
    (if (> i (- (string-length s) 5)) #f
        (if (equal? (substring s i (+ i 5)) "hello") #t
            (loop (+ i 1)))))))

(let ((s (show #f (as-bold "bold"))))
  (check-true "as-bold has escape" (> (string-length s) 4)))

(let ((s (show #f (on-blue "bg"))))
  (check-true "on-blue has escape" (> (string-length s) 2)))

;;; Unicode
(import (srfi 166 unicode))
(check "upcased" (show #f (upcased "hello")) "HELLO")
(check "downcased" (show #f (downcased "HELLO")) "hello")
(check "terminal-width" (string-terminal-width "hello") 5)

;;; Columnar
(import (srfi 166 columnar))
(let ((s (show #f (wrapped/list '("hello" "world" "foo" "bar")))))
  (check-true "wrapped/list" (> (string-length s) 0)))

(check "line-numbers"
  (show #f (line-numbers))
  "    1 ")

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 166 sub-library tests failed" fail))
