(define-library (srfi 60)
  (import (scheme base) (srfi 151))
  (export logand logior logxor lognot
          bitwise-if logtest logbit?
          ash integer-length logcount
          bit-field bitwise-merge)
  (begin
    (define logand bitwise-and)
    (define logior bitwise-ior)
    (define logxor bitwise-xor)
    (define lognot bitwise-not)
    (define ash arithmetic-shift)
    (define logcount bit-count)
    (define logtest any-bit-set?)
    (define logbit? bit-set?)
    (define bitwise-merge bitwise-if)))
