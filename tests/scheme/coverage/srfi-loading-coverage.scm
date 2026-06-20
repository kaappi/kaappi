(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; Exercise various SRFI library loading to cover vm_library.zig file loading paths

;; SRFI 2 (and-let*)
(import (srfi 2))
(check "srfi 2" (and-let* ((x 10) (y (+ x 20))) y) 30)

;; SRFI 11 (let-values)
(import (srfi 11))
(check "srfi 11" (let-values (((a b) (values 1 2))) (+ a b)) 3)

;; SRFI 16 (case-lambda)
(import (srfi 16))
(check-true "srfi 16 loaded" #t)

;; SRFI 28 (format)
(import (srfi 28))
(check "srfi 28 format" (format "~a + ~a = ~a" 1 2 3) "1 + 2 = 3")

;; SRFI 31 (rec)
(import (srfi 31))
(check "srfi 31 rec"
  ((rec f (lambda (n) (if (= n 0) 1 (* n (f (- n 1)))))) 5)
  120)

;; SRFI 34 (exception handling)
(import (srfi 34))
(check-true "srfi 34 loaded" #t)

;; SRFI 48 (format)
(import (srfi 48))
(check "srfi 48 format" (format #f "~a" 42) "42")

;; SRFI 98 (environment access)
(import (srfi 98))
(check-true "srfi 98 loaded" #t)

;; SRFI 111 (boxes)
(import (srfi 111))
(let ((b (box 42)))
  (check-true "srfi 111 box?" (box? b))
  (check "srfi 111 unbox" (unbox b) 42)
  (set-box! b 99)
  (check "srfi 111 set-box!" (unbox b) 99))

;; SRFI 125 (hash tables)
(import (srfi 125))
(check-true "srfi 125 loaded" #t)

;; SRFI 128 (comparators)
(import (srfi 128))
(check-true "srfi 128 loaded" (comparator? (make-default-comparator)))

;; SRFI 132 (sort)
(import (srfi 132))
(check "srfi 132 sort" (list-sort < '(3 1 4 1 5 9)) '(1 1 3 4 5 9))

;; SRFI 141 (integer division)
(import (srfi 141))
(check-true "srfi 141 loaded" #t)

;; SRFI 145 (assume)
(import (srfi 145))
(check-true "srfi 145 loaded" #t)

;; SRFI 151 (bitwise)
(import (srfi 151))
(check "srfi 151 bitwise-and" (bitwise-and 12 10) 8)
(check "srfi 151 bitwise-ior" (bitwise-ior 12 10) 14)
(check "srfi 151 bitwise-xor" (bitwise-xor 12 10) 6)
(check "srfi 151 bitwise-not" (bitwise-not 0) -1)
(check "srfi 151 bit-count" (bit-count 13) 3)
(check "srfi 151 arithmetic-shift" (arithmetic-shift 1 10) 1024)

;; SRFI 152 (string library)
(import (srfi 152))
(check-true "srfi 152 loaded" (string? (string-upcase "hello")))

;; SRFI 158 (generators)
(import (srfi 158))
(let ((g (circular-generator 1 2 3)))
  (check "srfi 158 gen1" (g) 1)
  (check "srfi 158 gen2" (g) 2)
  (check "srfi 158 gen3" (g) 3)
  (check "srfi 158 gen4" (g) 1))

;; SRFI 174 (POSIX timespecs)
(import (srfi 174))
(check-true "srfi 174 loaded" #t)

;; SRFI 175 (ASCII)
(import (srfi 175))
(check-true "srfi 175 loaded" (ascii-alphabetic? 65))

;; SRFI 195 (multiple values)
(import (srfi 195))
(check-true "srfi 195 loaded" #t)

;; SRFI 219 (define higher-order)
(import (srfi 219))
(check-true "srfi 219 loaded" #t)

;; SRFI 232 (flexible curried procedures)
(import (srfi 232))
(check-true "srfi 232 loaded" #t)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI loading coverage tests failed" fail))
