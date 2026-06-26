;; Regression test for #49: markCyclesRec depth guard
;; Deep nesting should print without crashing (stack overflow).

(define (nest n acc) (if (= n 0) acc (nest (- n 1) (list acc))))

;; 200k deep nesting — previously overflowed the native stack in markCyclesRec.
;; With the depth guard, write truncates at MAX_PRINT_DEPTH instead of crashing.
(let ((deep (nest 200000 '())))
  (let ((port (open-output-string)))
    (write deep port)
    (let ((s (get-output-string port)))
      (display "PASS: deep nesting printed without crash, length=")
      (display (string-length s))
      (newline))))
