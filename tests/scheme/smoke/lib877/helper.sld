;; Fixture for #877: an exported macro (`outer`) that expands into a private,
;; unexported helper macro (`inner`) defined in the same library body. An
;; importer of `outer` must still be able to expand it, which requires the
;; transitively-referenced helper macro to be made available at the use site —
;; without `inner` being independently importable.
(define-library (lib877 helper)
  (import (scheme base))
  (export outer)
  (begin
    (define-syntax inner
      (syntax-rules () ((_ x) (+ x 100))))
    (define-syntax outer
      (syntax-rules () ((_ x) (inner x))))))
