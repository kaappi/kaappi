;; A library that imports both (scheme base) and the %-defining library above,
;; and uses the forms whose desugarings reference the internal helpers those
;; names used to collide with.
(define-library (lib1856 user)
  (import (scheme base) (lib1856 ffi))
  (export byte-length pick point-x make-point user-helpers)
  (begin
    (define (byte-length s) (%length s))
    ;; case-lambda's arity dispatch must count arguments with the real
    ;; list-length, not the one-argument %length imported above (#1714).
    (define pick (case-lambda ((a) 'one) ((a b) 'two) ((a b . r) 'many)))
    ;; define-record-type's desugaring must use the real record primitives,
    ;; not the imported %record-ref / %make-record.
    (define-record-type point (make-point x y) point? (x point-x) (y point-y))
    (define (user-helpers) (list (%record-ref 0 0 0) (%make-record)))))
