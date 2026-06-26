(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; Redefine a library with the same name — must not crash
(define-library (my test) (export foo) (begin (define (foo) 1)))
(define-library (my test) (export bar) (begin (define (bar) 2)))
(import (my test))

(check "redefined library" (bar) 2)

;; Redefine again to exercise the path multiple times
(define-library (my test) (export baz) (begin (define (baz) 3)))
(import (my test))

(check "redefined library again" (baz) 3)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "library redefine tests failed" fail))
