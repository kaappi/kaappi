(define-library (srfi 27)
  (import (scheme base))
  (export random-integer random-real
          default-random-source random-source?
          make-random-source
          random-source-make-integers random-source-make-reals
          random-source-randomize! random-source-pseudo-randomize!
          random-source-state-ref random-source-state-set!)
  (begin

    (define default-random-source (%default-random-source))

    (define (random-source-make-integers rs)
      (lambda (n) (%rs-next-int rs n)))

    (define (random-source-make-reals rs . rest)
      (if (pair? rest)
          (let ((unit (car rest)))
            (if (not (and (real? unit) (> unit 0) (< unit 1)))
                (error "random-source-make-reals: unit must satisfy 0 < unit < 1" unit)
                (if (exact? unit)
                    ;; n = max x with x*unit < 1 (ceil(1/unit)-1); subtract 1 only when 1/unit is integral, to exclude the 1.0 endpoint
                    (let* ((recip (/ 1 unit))
                           (n (if (integer? recip)
                                  (- recip 1)
                                  (floor recip))))
                      (lambda () (* unit (+ 1 (%rs-next-int rs n)))))
                    (lambda () (%rs-next-real rs)))))
          (lambda () (%rs-next-real rs))))

    ))
