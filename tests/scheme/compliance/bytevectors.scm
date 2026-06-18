;;; Bytevector compliance tests (R7RS 6.9, SRFI 64)

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "bytevectors")

(test-group "bytevector?"
  (test-assert "bytevector? on bytevector" (bytevector? #u8(1 2 3)))
  (test-eqv "bytevector? on string" #f (bytevector? "hello")))

(test-group "make-bytevector"
  (test-equal "make-bytevector default fill" #u8(0 0 0) (make-bytevector 3))
  (test-equal "make-bytevector with fill" #u8(255 255 255) (make-bytevector 3 255)))

(test-group "bytevector"
  (test-equal "bytevector constructor" #u8(0 1 2 3) (bytevector 0 1 2 3)))

(test-group "bytevector-length"
  (test-eqv "bytevector-length" 3 (bytevector-length #u8(1 2 3))))

(test-group "bytevector-u8-ref"
  (test-eqv "bytevector-u8-ref" 20 (bytevector-u8-ref #u8(10 20 30) 1)))

(test-group "bytevector-u8-set!"
  (test-equal "bytevector-u8-set! mutates"
    #u8(1 42 3)
    (let ((bv (bytevector 1 2 3)))
      (bytevector-u8-set! bv 1 42)
      bv)))

(test-group "bytevector-copy"
  (test-equal "bytevector-copy with start/end"
    #u8(2 3)
    (bytevector-copy #u8(1 2 3 4 5) 1 3)))

(test-group "bytevector-append"
  (test-equal "bytevector-append"
    #u8(1 2 3 4)
    (bytevector-append #u8(1 2) #u8(3 4))))

(test-group "bytevector-copy!"
  (test-equal "bytevector-copy! mutates target"
    #u8(0 10 20 30 0)
    (let ((to (bytevector 0 0 0 0 0))
          (from (bytevector 10 20 30)))
      (bytevector-copy! to 1 from)
      to)))

(test-group "bytevector literal"
  (test-equal "bytevector literal" #u8(0 127 255) #u8(0 127 255)))

(test-group "utf8<->string"
  (test-equal "utf8->string" "hello" (utf8->string #u8(104 101 108 108 111)))
  (test-equal "string->utf8" #u8(104 101 108 108 111) (string->utf8 "hello")))

(test-group "binary I/O"
  (test-assert "u8-ready? on stdin" (u8-ready?)))

(define %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "bytevectors")
(if (> %test-fail-count 0) (exit 1))
