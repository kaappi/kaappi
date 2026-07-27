;; Fixture for #1718: another unrelated library with its own plain
;; define-record-type (not shadowed within its own scope). Must be
;; compiled by the builtin handler, not silently dropped, regardless of
;; whether some other library the program imported exports its own
;; define-record-type macro.
(define-library (lib1718 drt-victim)
  (import (scheme base))
  (export make-color color? color-r)
  (begin
    (define-record-type <color>
      (make-color r)
      color?
      (r color-r))))
