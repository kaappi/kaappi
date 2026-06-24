;;; Kaappi WASM smoke test
;;; Tests core R7RS features without requiring external library files.

;; Arithmetic
(display (+ 1 2 3))
(newline)
(display (* 6 7))
(newline)

;; Strings
(display (string-append "Hello" " " "WASM!"))
(newline)
(display (string-length "kaappi"))
(newline)

;; Lists
(display (car '(a b c)))
(newline)
(display (cdr '(1 2 3)))
(newline)
(display (map (lambda (x) (* x x)) '(1 2 3 4 5)))
(newline)

;; Higher-order functions
(display (apply + '(1 2 3 4 5)))
(newline)

;; Define and call
(define (factorial n)
  (if (<= n 1) 1 (* n (factorial (- n 1)))))
(display (factorial 10))
(newline)

;; Let bindings
(display (let ((x 10) (y 20)) (+ x y)))
(newline)

;; Tail recursion
(define (loop n acc)
  (if (= n 0) acc (loop (- n 1) (+ acc 1))))
(display (loop 100000 0))
(newline)

;; call/cc
(display (call-with-current-continuation (lambda (k) (k 42))))
(newline)

;; Macros
(define-syntax my-when
  (syntax-rules ()
    ((_ test body ...)
     (if test (begin body ...)))))
(display (my-when #t "macro-works"))
(newline)

;; Boolean and predicates
(display (and #t #t #t))
(newline)
(display (or #f #f 99))
(newline)

;; Vectors
(display (vector-ref #(10 20 30) 1))
(newline)

;; Multiple values
(call-with-values (lambda () (values 1 2 3))
  (lambda (a b c) (display (+ a b c)) (newline)))
