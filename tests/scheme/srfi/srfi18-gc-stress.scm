;; SRFI-18 cross-thread GC stress test
;; Tests that values are correctly deep-copied across thread boundaries.

(import (srfi 18) (scheme base) (scheme write))

(define (check desc ok?)
  (unless ok? (error (string-append "FAIL: " desc))))

;; Thread returning a list
(let ((t (make-thread (lambda ()
          (let loop ((i 0) (acc '()))
            (if (= i 100) acc (loop (+ i 1) (cons i acc))))))))
  (thread-start! t)
  (let ((result (thread-join! t)))
    (check "list length" (= (length result) 100))
    (check "list car" (= (car result) 99))
    (display "list: ok") (newline)))

;; Thread returning a string
(let ((t (make-thread (lambda () (string-append "hello" " " "world")))))
  (thread-start! t)
  (let ((result (thread-join! t)))
    (check "string content" (string=? result "hello world"))
    (display "string: ok") (newline)))

;; Thread returning a vector
(let ((t (make-thread (lambda ()
          (let ((v (make-vector 50 0)))
            (do ((i 0 (+ i 1))) ((= i 50) v)
              (vector-set! v i (* i i))))))))
  (thread-start! t)
  (let ((result (thread-join! t)))
    (check "vector element" (= (vector-ref result 7) 49))
    (display "vector: ok") (newline)))

;; Thread returning a number
(let ((t (make-thread (lambda () (* 6 7)))))
  (thread-start! t)
  (check "number" (= (thread-join! t) 42))
  (display "number: ok") (newline))

;; Multiple threads
(let ((threads (map (lambda (n)
                (make-thread (lambda ()
                  (let loop ((i 0) (acc '()))
                    (if (= i 50) (cons n acc) (loop (+ i 1) (cons i acc)))))))
              '(1 2 3))))
  (for-each thread-start! threads)
  (let ((results (map thread-join! threads)))
    (check "multi-thread count" (= (length results) 3))
    (for-each (lambda (r) (check "thread result length" (= (length r) 51))) results)
    (display "multi-thread: ok") (newline)))

(display "All SRFI-18 GC stress tests passed.") (newline)
