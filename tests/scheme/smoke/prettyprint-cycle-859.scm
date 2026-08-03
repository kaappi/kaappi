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
;; Match the whole `#0=` opener, not a bare `#`: any cycle marker or printer
;; fallback contains a `#`, so that weaker check would pass without a label.
(test-assert "the output opens with the datum label #0="
             (and (>= (string-length result) 3)
                  (string=? (substring result 0 3) "#0=")))
;; and closes the cycle by referring back to it
(test-assert "the output refers back to the label"
             (let loop ((i 0))
               (cond ((> (+ i 3) (string-length result)) #f)
                     ((string=? (substring result i (+ i 3)) "#0#") #t)
                     (else (loop (+ i 1))))))

(let ((runner (test-runner-current)))
  (test-end "prettyprint-cycle-859")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
