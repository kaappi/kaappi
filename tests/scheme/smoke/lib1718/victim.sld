;; Fixture for #1718: an ordinary, unrelated library with its own
;; define-record-type. Must load correctly regardless of what other
;; libraries the importing program has already loaded.
(define-library (lib1718 victim)
  (import (scheme base))
  (export make-point point? point-x point-y)
  (begin
    (define-record-type <point>
      (make-point x y)
      point?
      (x point-x)
      (y point-y))))
