(define-library (lib1479 worker)
  (export do-work)
  (import (scheme base))
  (begin
    ;; A helper bound in THIS library's own scope -- do-work must resolve it
    ;; through its own lib_env even when called from a child thread.
    (define (helper x) (* x 2))
    (define (do-work x) (+ (helper x) 1))))
