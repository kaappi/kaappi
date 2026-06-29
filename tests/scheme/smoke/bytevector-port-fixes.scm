;; Regression tests for bytevector port fixes
;; #280: u8-ready? always returns #t
;; #281: read-bytevector returns EOF when k=0
;; #282: get-output-bytevector accepts string ports

(import (scheme base) (scheme write))

;; ---- #280: u8-ready? returns #f at EOF ----
(let ((p (open-input-bytevector #u8(1 2))))
  (read-u8 p) (read-u8 p)
  (display (u8-ready? p))          ; #f (port exhausted)
  (newline))

(let ((p (open-input-bytevector #u8(42))))
  (display (u8-ready? p))          ; #t (data available)
  (newline))

;; ---- #281: read-bytevector with k=0 ----
(let ((p (open-input-bytevector #u8(1 2 3))))
  (let ((bv (read-bytevector 0 p)))
    (display (bytevector? bv))     ; #t (not eof-object)
    (newline)
    (display (bytevector-length bv)) ; 0
    (newline)))

;; read-bytevector with k=0 should not consume any bytes
(let ((p (open-input-bytevector #u8(1 2 3))))
  (read-bytevector 0 p)
  (display (read-u8 p))           ; 1 (first byte still there)
  (newline))

;; ---- #282: get-output-bytevector rejects string ports ----
(let ((p (open-output-string)))
  (write-string "hello" p)
  (display
    (guard (exn (#t 'error))
      (get-output-bytevector p)))  ; error
  (newline))

;; get-output-bytevector still works on bytevector ports
(let ((p (open-output-bytevector)))
  (write-u8 65 p)
  (write-u8 66 p)
  (display (get-output-bytevector p))  ; #u8(65 66)
  (newline))

(display "all passed")
(newline)
