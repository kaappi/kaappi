;; A library that defines and exports its own sqrt while importing only
;; (scheme base). Legal under R7RS: sqrt is an inexact library procedure
;; (§6.2.6), exported by (scheme inexact) and absent from (scheme base), so
;; there is no redefinition of an imported binding here.
(define-library (lib2504 mathlib)
  (import (scheme base))
  (export sqrt hypot-ish)
  (begin
    (define (sqrt x) (list 'lib-mine x))
    ;; A same-library caller resolves to the library's own definition, not
    ;; the built-in it never imported.
    (define (hypot-ish a b) (sqrt (+ (* a a) (* b b))))))
