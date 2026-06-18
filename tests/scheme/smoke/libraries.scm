;; Phase 6: Libraries tests
(import (scheme base) (scheme inexact) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "libraries")

;; Basic import (scheme base already imported)
(test-eqv "basic +" 3 (+ 1 2))

;; Import only specific bindings
(import (only (scheme base) + -))
(test-eqv "only +" 15 (+ 10 5))
(test-eqv "only -" 7 (- 10 3))

;; Import with rename
(import (rename (scheme base) (+ add) (- subtract)))
(test-eqv "renamed add" 7 (add 3 4))
(test-eqv "renamed subtract" 7 (subtract 10 3))

;; Import with prefix
(import (prefix (scheme base) s:))
(test-eqv "prefixed s:+" 300 (s:+ 100 200))

;; Import from scheme inexact
(test-approximate "sin 0" 0.0 (sin 0) 0.0001)

;; Import multiple libraries
(test-eqv "multi-library expr" 2 (+ 1 (exact (cos 0))))

;; Define and use a custom library
(define-library (mylib)
  (import (scheme base))
  (export double triple)
  (begin
    (define (double x) (* x 2))
    (define (triple x) (* x 3))))

(import (mylib))
(test-eqv "custom lib double" 42 (double 21))
(test-eqv "custom lib triple" 30 (triple 10))

;; Define a library with dotted name
(define-library (my utils)
  (import (scheme base))
  (export add5)
  (begin
    (define (add5 x) (+ x 5))))

(import (my utils))
(test-eqv "dotted name lib" 15 (add5 10))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "libraries")
(if (> %test-fail-count 0) (exit 1))
