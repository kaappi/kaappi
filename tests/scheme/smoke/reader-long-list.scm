(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

;; Build a string like "(1 2 3 ... 10000)" and read it via string port
(define (make-long-list-string n)
  (let ((p (open-output-string)))
    (display "(" p)
    (let loop ((i 1))
      (when (<= i n)
        (when (> i 1) (display " " p))
        (display i p)
        (loop (+ i 1))))
    (display ")" p)
    (get-output-string p)))

;; Test: read a flat list with 10000 elements
;; Previously this would stack-overflow due to recursive readListTail
(let* ((s (make-long-list-string 10000))
       (lst (read (open-input-string s))))
  (check "long list length" (length lst) 10000)
  (check "long list first" (car lst) 1)
  (check "long list last" (list-ref lst 9999) 10000))

;; Test: dotted pair in long list
(let* ((s (string-append (make-long-list-string 5000) ""))
       (lst (read (open-input-string s))))
  (check "long list dotted length" (length lst) 5000))

;; Test: nested lists still work
(check "nested list" (read (open-input-string "((1 2) (3 4) (5 6))"))
  '((1 2) (3 4) (5 6)))

;; Test: dotted pair
(check "dotted pair" (read (open-input-string "(1 . 2)"))
  (cons 1 2))

;; Test: dotted list tail
(check "dotted list" (read (open-input-string "(1 2 . 3)"))
  (cons 1 (cons 2 3)))

;; Test: empty list
(check "empty list" (read (open-input-string "()"))
  '())

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Reader long list tests failed" fail))
