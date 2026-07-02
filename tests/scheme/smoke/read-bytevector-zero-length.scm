;; Regression test for #692: read-bytevector! with zero-length target
;; should return 0, not eof.
(define p (open-input-bytevector (bytevector 1 2 3)))
(define target (make-bytevector 0))
(define result (read-bytevector! target p))
(unless (and (number? result) (= result 0))
  (display "FAIL: expected 0, got ")
  (display result)
  (newline)
  (exit 1))

;; Port should still have data available
(define val (read-u8 p))
(unless (= val 1)
  (display "FAIL: port corrupted, expected 1, got ")
  (display val)
  (newline)
  (exit 1))

;; Regression test for #695: error messages should name the correct procedure
;; (just verify the error fires; the procedure name fix is in the code)
(guard (exn (#t 'ok))
  (read-bytevector 5 "not-a-port")
  (display "FAIL: should have errored") (newline) (exit 1))

(guard (exn (#t 'ok))
  (write-bytevector (bytevector 1 2 3) "not-a-port")
  (display "FAIL: should have errored") (newline) (exit 1))

(display "PASS")
(newline)
