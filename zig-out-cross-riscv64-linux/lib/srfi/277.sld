;; SRFI 277: Cyclic ports.
;;
;; A cyclic port is an ordinary input port over a string or bytevector that
;; delivers its elements in order, repeatedly, forever — it never produces an
;; end-of-file object. Kaappi's constructors wrap the built-in string-port
;; machinery with a cycle flag (see the SRFI 277 section in
;; docs/dev/srfi-implementation-notes.md); this library adds the spec's
;; argument checks and exports the two public names.
(define-library (srfi 277)
  ;; (kaappi primitives): the internal %-prefixed helpers this file calls
  ;; below. They used to arrive with (scheme base), which reserved their
  ;; names against every user library (kaappi#1856).
  (import (scheme base) (kaappi primitives))
  (export open-cyclic-input-string
          open-cyclic-input-bytevector)
  (begin

    (define (open-cyclic-input-string string)
      (cond
        ((not (string? string))
         (error "open-cyclic-input-string: expected a string" string))
        ((zero? (string-length string))
         (error "open-cyclic-input-string: the string must not be empty" string))
        (else (%open-cyclic-input-string string))))

    (define (open-cyclic-input-bytevector bytevector)
      (cond
        ((not (bytevector? bytevector))
         (error "open-cyclic-input-bytevector: expected a bytevector" bytevector))
        ((zero? (bytevector-length bytevector))
         (error "open-cyclic-input-bytevector: the bytevector must not be empty" bytevector))
        (else (%open-cyclic-input-bytevector bytevector))))

    ))
