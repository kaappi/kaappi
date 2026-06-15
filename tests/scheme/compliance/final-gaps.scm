;;; Final R7RS compliance gap tests

;; string->vector
(display (string->vector "abc"))           ; => #(#\a #\b #\c)
(newline)
(display (string->vector "hello" 1 3))     ; => #(#\e #\l)
(newline)

;; Bytevector ports: open-input-bytevector / read-u8
(let ((p (open-input-bytevector #u8(10 20 30))))
  (display (read-u8 p))                    ; => 10
  (display " ")
  (display (read-u8 p))                    ; => 20
  (display " ")
  (display (read-u8 p))                    ; => 30
  (display " ")
  (display (eof-object? (read-u8 p))))     ; => #t
(newline)

;; open-output-bytevector / get-output-bytevector
(let ((out (open-output-bytevector)))
  (write-u8 1 out)
  (write-u8 2 out)
  (write-u8 3 out)
  (display (get-output-bytevector out)))    ; => #u8(1 2 3)
(newline)

;; read-bytevector!
(let ((bv (make-bytevector 3))
      (p2 (open-input-bytevector #u8(10 20 30))))
  (display (read-bytevector! bv p2))       ; => 3
  (display " ")
  (display bv))                            ; => #u8(10 20 30)
(newline)

;; read-bytevector! at EOF
(let ((bv (make-bytevector 5))
      (p (open-input-bytevector #u8())))
  (display (eof-object? (read-bytevector! bv p))))  ; => #t
(newline)

;; (scheme case-lambda) import
(import (scheme case-lambda))
(display "case-lambda-ok")
(newline)
