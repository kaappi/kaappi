;; SRFI 271: Random port libraries.
;;
;; The bare (srfi 271) name is an alias for the randomized library, so a plain
;; (import (srfi 271)) gives cryptographic-quality random ports. For
;; reproducible, state-bearing ports import (srfi 271 determinized); for the
;; randomized ports explicitly, import (srfi 271 randomized).
(define-library (srfi 271)
  (import (srfi 271 randomized))
  (export make-random-port))
