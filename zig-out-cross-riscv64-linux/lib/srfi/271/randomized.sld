;; SRFI 271: Random port libraries — randomized variant.
;;
;; A randomized random port is a binary input port that delivers
;; cryptographic-quality bytes drawn from the host operating system's entropy
;; source (getrandom / arc4random / RtlGenRandom). Its output is unpredictable
;; and not reproducible, and it exposes no inspectable state — hence this
;; library exports only make-random-port.
(define-library (srfi 271 randomized)
  ;; (kaappi primitives): the internal %-prefixed helpers this file calls
  ;; below. They used to arrive with (scheme base), which reserved their
  ;; names against every user library (kaappi#1856).
  (import (scheme base) (kaappi primitives))
  (export make-random-port)
  (begin

    (define (make-random-port)
      (%random-port-make-randomized))))
