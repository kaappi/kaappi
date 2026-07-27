;; Fixture for #1718: exports its own define-record-type macro (the
;; SRFI-136/131/57-style extended-record-syntax pattern), here a trivial
;; passthrough. Importing this must not affect how an unrelated library's
;; OWN plain define-record-type is compiled later in the same program.
(define-library (lib1718 drt-shadow)
  (import (scheme base))
  (export define-record-type)
  (begin
    (define-syntax define-record-type
      (syntax-rules ()
        ((_ args ...) (define-record-type args ...))))))
