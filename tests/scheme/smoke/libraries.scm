; Phase 6: Libraries tests

; Basic import
(import (scheme base))
(display (+ 1 2))
(newline)
; => 3

; Import only specific bindings
(import (only (scheme base) + -))
(display (+ 10 5))
(newline)
; => 15

(display (- 10 3))
(newline)
; => 7

; Import with rename
(import (rename (scheme base) (+ add) (- subtract)))
(display (add 3 4))
(newline)
; => 7

(display (subtract 10 3))
(newline)
; => 7

; Import with prefix
(import (prefix (scheme base) s:))
(display (s:+ 100 200))
(newline)
; => 300

; Import from scheme inexact
(import (scheme inexact))
(display (sin 0))
(newline)
; => 0.0

; Import multiple libraries
(import (scheme base) (scheme inexact))
(display (+ 1 (exact (cos 0))))
(newline)
; => 2

; Define and use a custom library
(define-library (mylib)
  (import (scheme base))
  (export double triple)
  (begin
    (define (double x) (* x 2))
    (define (triple x) (* x 3))))

(import (mylib))
(display (double 21))
(newline)
; => 42

(display (triple 10))
(newline)
; => 30

; Define a library with dotted name
(define-library (my utils)
  (import (scheme base))
  (export add5)
  (begin
    (define (add5 x) (+ x 5))))

(import (my utils))
(display (add5 10))
(newline)
; => 15

(display "All Phase 6 tests passed!")
(newline)
