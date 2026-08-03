;; Regression tests for bytevector port fixes
;; #281: read-bytevector returns EOF when k=0
;; #282: get-output-bytevector accepts string ports

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "bytevector-port-fixes")

;; ---- #281: read-bytevector with k=0 ----
(let ((p (open-input-bytevector #u8(1 2 3))))
  (let ((bv (read-bytevector 0 p)))
    (test-assert "(read-bytevector 0 p) is a bytevector, not the eof object"
                 (bytevector? bv))
    (test-equal "(read-bytevector 0 p) is empty" 0 (bytevector-length bv))))

;; read-bytevector with k=0 should not consume any bytes
(let ((p (open-input-bytevector #u8(1 2 3))))
  (read-bytevector 0 p)
  (test-equal "(read-bytevector 0 p) consumes nothing" 1 (read-u8 p)))

;; ---- #282: get-output-bytevector rejects string ports ----
(let ((p (open-output-string)))
  (write-string "hello" p)
  (test-equal "get-output-bytevector on a string port raises"
              'error
              (guard (exn (#t 'error))
                (get-output-bytevector p))))

;; get-output-bytevector still works on bytevector ports
(let ((p (open-output-bytevector)))
  (write-u8 65 p)
  (write-u8 66 p)
  (test-equal "get-output-bytevector on a bytevector port"
              #u8(65 66)
              (get-output-bytevector p)))

(let ((runner (test-runner-current)))
  (test-end "bytevector-port-fixes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
