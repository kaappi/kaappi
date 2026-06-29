;; Regression tests for callWithArgs bounds checking
;; Issue #366: register bounds check used args.len instead of locals_count
;; Issue #367: @intCast to u8 panics when args.len > 255
(import (scheme base) (scheme write))

;; Test 1: call-with-values with many values (>255) should not panic
(guard (e (#t (display "PASS: >255 values handled gracefully") (newline)))
  (call-with-values
    (lambda () (apply values (make-list 300 #t)))
    (lambda args (display "PASS: >255 values accepted") (newline))))

;; Test 2: A closure with many locals called via apply should work
(define (many-locals x)
  (let* ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7) (h 8)
         (i 9) (j 10) (k 11) (l 12) (m 13) (n 14) (o 15) (p 16))
    (+ x a b c d e f g h i j k l m n o p)))

(let ((result (apply many-locals '(0))))
  (if (= result 136)
      (begin (display "PASS: many-locals via apply") (newline))
      (begin (display "FAIL: many-locals via apply, got ") (display result) (newline))))

;; Test 3: map with a closure that has many locals
(define (transform val)
  (let* ((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7) (h 8))
    (+ val a b c d e f g h)))

(let ((result (map transform '(0 10 20))))
  (if (equal? result '(36 46 56))
      (begin (display "PASS: map with many-locals closure") (newline))
      (begin (display "FAIL: map with many-locals, got ") (display result) (newline))))
