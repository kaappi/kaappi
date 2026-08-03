;; Regression test for #859: prettyPrint hangs on cyclic structures
;; wider than 80 characters.
;;
;; Build a cyclic list long enough that its flat representation exceeds
;; 80 columns, then write it via write-shared (which triggers the
;; prettyPrint path in the REPL). If the depth/cycle guard is missing,
;; this test will hang instead of completing.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "prettyprint-cycle-859")

;; Build a long list and make it cyclic at the tail.
(define x (list 1 2 3 4 5 6 7 8 9 10
               11 12 13 14 15 16 17 18 19 20))
(set-cdr! (list-tail x 19) x)

;; write-shared must terminate and produce datum-label output.
(define out (open-output-string))
(write-shared x out)
(define result (get-output-string out))

(test-assert "write-shared on a wide cyclic list terminates with output"
             (> (string-length result) 0))
;; The datum label is what makes the output finite rather than merely short.
(test-assert "the output carries a datum label"
             (let loop ((i 0))
               (cond ((>= i (string-length result)) #f)
                     ((char=? (string-ref result i) #\#) #t)
                     (else (loop (+ i 1))))))

(let ((runner (test-runner-current)))
  (test-end "prettyprint-cycle-859")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
