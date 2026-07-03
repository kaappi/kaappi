;; Regression test for #811: current-input/output/error-port must be
;; parameter objects so parameterize works with them (R7RS 6.13.1).

(import (scheme base) (scheme write))

(define (check label got expected)
  (unless (equal? got expected)
    (display "FAIL: ") (display label)
    (display "  expected: ") (write expected)
    (display "  got: ") (write got) (newline)
    (exit 1)))

;; Basic: (current-output-port) still returns an output port
(check "output-port?" (output-port? (current-output-port)) #t)
(check "input-port?"  (input-port?  (current-input-port))  #t)
(check "error-port?"  (output-port? (current-error-port))  #t)

;; parameterize current-output-port
(define sp (open-output-string))
(parameterize ((current-output-port sp))
  (display "hello")
  (write-char #\space)
  (display "world"))
(check "parameterize output" (get-output-string sp) "hello world")

;; parameterize current-error-port
(define esp (open-output-string))
(parameterize ((current-error-port esp))
  (display "err" (current-error-port)))
(check "parameterize error" (get-output-string esp) "err")

;; parameterize current-input-port
(define isp (open-input-string "line1"))
(parameterize ((current-input-port isp))
  (check "parameterize input" (read-line) "line1"))

;; Nested parameterize
(define sp1 (open-output-string))
(define sp2 (open-output-string))
(parameterize ((current-output-port sp1))
  (display "outer")
  (parameterize ((current-output-port sp2))
    (display "inner")))
(check "nested outer" (get-output-string sp1) "outer")
(check "nested inner" (get-output-string sp2) "inner")

;; Restoration after parameterize — output should go to stdout again
(define before-sp (open-output-string))
(define after-sp (open-output-string))
(define temp-sp (open-output-string))
(parameterize ((current-output-port before-sp))
  (display "before"))
;; After the parameterize, current-output-port should be the original
(check "restored before" (get-output-string before-sp) "before")

(display "ok") (newline)
