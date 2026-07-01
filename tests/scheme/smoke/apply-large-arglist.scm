;; Regression test for #649: apply with >256 arguments fails with
;; misleading OutOfMemory error instead of succeeding.

(import (scheme base) (scheme write) (scheme process-context))

(define (mk n) (if (= n 0) '() (cons n (mk (- n 1)))))

;; 256 args — worked before
(let ((result (apply + (mk 256))))
  (when (not (= result 32896))
    (display "FAIL: apply with 256 args")
    (newline)
    (exit 1)))

;; 257 args — previously failed with OutOfMemory
(let ((result (apply + (mk 257))))
  (when (not (= result 33153))
    (display "FAIL: apply with 257 args")
    (newline)
    (exit 1)))

;; 500 args — well beyond old limit
(let ((result (apply + (mk 500))))
  (when (not (= result 125250))
    (display "FAIL: apply with 500 args")
    (newline)
    (exit 1)))

;; apply with individual args + trailing list > 256 total
(let ((result (apply + 1 2 3 (mk 260))))
  (when (not (= result 33936))
    (display "FAIL: apply with mixed args > 256")
    (newline)
    (exit 1)))

(display "PASS")
(newline)
