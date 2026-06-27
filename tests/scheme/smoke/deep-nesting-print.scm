;; Regression test for #49: markCyclesRec depth guard
;; Deep nesting should print without crashing (stack overflow).

(define (nest n acc) (if (= n 0) acc (nest (- n 1) (list acc))))

;; 10k deep nesting — tests the depth guard without overflowing the native
;; stack in GC's recursive markValue (200k overflows in Debug builds).
(let ((deep (nest 10000 '())))
  (let ((port (open-output-string)))
    (write deep port)
    (let ((s (get-output-string port)))
      (display "PASS: deep nesting printed without crash, length=")
      (display (string-length s))
      (newline))))
