;; Tests for Phase 1 foundation SRFIs

;; SRFI-8: receive
(import (srfi 8))
(receive (a b c) (values 1 2 3)
  (display (+ a b c)))
(newline)
;; expect: 6

;; SRFI-2: and-let*
(import (srfi 2))
(display (and-let* ((x 10) (y (* x 2))) (+ x y)))
(newline)
;; expect: 30

(display (and-let* ((x #f)) x))
(newline)
;; expect: #f

;; SRFI-11: let-values (re-export of R7RS built-in)
(import (srfi 11))
(let-values (((a b) (values 1 2)))
  (display (+ a b)))
(newline)
;; expect: 3

;; SRFI-16: case-lambda (re-export)
(import (srfi 16))
(define f (case-lambda
            ((x) x)
            ((x y) (+ x y))))
(display (f 5))
(display " ")
(display (f 3 4))
(newline)
;; expect: 5 7

;; SRFI-28: format
(import (srfi 28))
(display (format "Hello ~a, you are ~a!" "world" 42))
(newline)
;; expect: Hello world, you are 42!

(display (format "~s ~% done" "test"))
(newline)
;; expect: "test"
;;  done

;; SRFI-31: rec
(import (srfi 31))
(display ((rec (f n) (if (= n 0) 1 (* n (f (- n 1))))) 5))
(newline)
;; expect: 120

;; SRFI-34: exception handling (alias)
(import (srfi 34))
(display (guard (exn (#t "caught"))
  (raise "oops")))
(newline)
;; expect: caught

;; SRFI-111: boxes
(import (srfi 111))
(let ((b (box 42)))
  (display (unbox b))
  (set-box! b 99)
  (display " ")
  (display (unbox b)))
(newline)
;; expect: 42 99

;; SRFI-145: assume
(import (srfi 145))
(assume #t "should pass")
(display "assume ok")
(newline)
;; expect: assume ok

;; SRFI-222: compound objects
(import (srfi 222))
(let ((c (make-compound 'a 'b 'c)))
  (display (compound? c))
  (display " ")
  (display (compound-length c))
  (display " ")
  (display (compound-ref c 1)))
(newline)
;; expect: #t 3 b

(display "All foundation SRFI tests passed!")
(newline)
