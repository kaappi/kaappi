(define-library (srfi 27)
  (import (scheme base))
  (export random-integer random-real
          default-random-source random-source?
          make-random-source
          random-source-make-integers random-source-make-reals
          random-source-randomize! random-source-pseudo-randomize!
          random-source-state-ref random-source-state-set!)
  (begin

    (define (random-source-make-integers rs)
      (lambda (n) (%rs-next-int rs n)))

    (define (random-source-make-reals rs . rest)
      (when (and (pair? rest)
                 (not (and (real? (car rest))
                           (> (car rest) 0)
                           (< (car rest) 1))))
        (error "random-source-make-reals: unit must satisfy 0 < unit < 1" (car rest)))
      (lambda () (%rs-next-real rs)))

    ))
