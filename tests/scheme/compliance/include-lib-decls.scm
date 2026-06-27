;; Test include-library-declarations — R7RS §5.3.2

(define-library (test include-lib-decls)
  (import (scheme base))
  (include-library-declarations "include-lib-decls-exports.scm")
  (begin
    (define (my-add a b) (+ a b))
    (define (my-mul a b) (* a b))))

(import (scheme base) (scheme write) (test include-lib-decls))

(display (my-add 3 4))
(newline)
;; Expected: 7

(display (my-mul 5 6))
(newline)
;; Expected: 30

(display "include-lib-decls-ok")
(newline)
