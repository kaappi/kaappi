;; Fixture for percent-name-user-library-1856.scm: a user library that
;; defines its own %-prefixed helpers and exports them.
(define-library (lib1856 ffi)
  (import (scheme base))
  (export %length %record-ref %make-record)
  (begin
    (define (%length s) (string-length s))
    (define (%record-ref . args) 'user-record-ref)
    (define (%make-record . args) 'user-make-record)))
