;;; Bytevector compliance tests (R7RS 6.9)

;; bytevector?
(display (bytevector? #u8(1 2 3)))  ; => #t
(newline)
(display (bytevector? "hello"))     ; => #f
(newline)

;; make-bytevector
(display (make-bytevector 3))       ; => #u8(0 0 0)
(newline)
(display (make-bytevector 3 255))   ; => #u8(255 255 255)
(newline)

;; bytevector
(display (bytevector 0 1 2 3))      ; => #u8(0 1 2 3)
(newline)

;; bytevector-length
(display (bytevector-length #u8(1 2 3)))  ; => 3
(newline)

;; bytevector-u8-ref
(display (bytevector-u8-ref #u8(10 20 30) 1))  ; => 20
(newline)

;; bytevector-u8-set!
(let ((bv (bytevector 1 2 3)))
  (bytevector-u8-set! bv 1 42)
  (display bv))  ; => #u8(1 42 3)
(newline)

;; bytevector-copy
(display (bytevector-copy #u8(1 2 3 4 5) 1 3))  ; => #u8(2 3)
(newline)

;; bytevector-append
(display (bytevector-append #u8(1 2) #u8(3 4)))  ; => #u8(1 2 3 4)
(newline)

;; bytevector-copy!
(let ((to (bytevector 0 0 0 0 0))
      (from (bytevector 10 20 30)))
  (bytevector-copy! to 1 from)
  (display to))  ; => #u8(0 10 20 30 0)
(newline)

;; bytevector literal
(display #u8(0 127 255))  ; => #u8(0 127 255)
(newline)

;; utf8->string
(display (utf8->string #u8(104 101 108 108 111)))  ; => hello
(newline)

;; string->utf8
(display (string->utf8 "hello"))  ; => #u8(104 101 108 108 111)
(newline)

;; Binary I/O
(display (u8-ready?))  ; => #t
(newline)
