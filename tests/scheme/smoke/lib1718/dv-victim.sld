;; Fixture for #1718: an ordinary, unrelated library with its own
;; define-values whose initializer uses `lambda`. Must load correctly
;; regardless of what other libraries the importing program has already
;; loaded.
(define-library (lib1718 dv-victim)
  (import (scheme base))
  (export dv-result)
  (begin
    (define-values (dv-result dv-extra)
      (values ((lambda (x) (* x 2)) 21) 'unused))))
