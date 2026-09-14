(define-library (srfi 252)
  (import (scheme base)
          (scheme case-lambda)
          (scheme complex)
          (srfi 1)
          (srfi 64)
          (srfi 158)
          (srfi 194))
  (export test-property test-property-expect-fail test-property-skip
          test-property-error test-property-error-type
          property-test-runner
          boolean-generator bytevector-generator
          char-generator string-generator symbol-generator
          exact-complex-generator exact-integer-generator
          exact-number-generator exact-rational-generator
          exact-real-generator
          exact-integer-complex-generator
          inexact-complex-generator inexact-integer-generator
          inexact-number-generator inexact-rational-generator
          inexact-real-generator
          complex-generator integer-generator
          number-generator rational-generator
          real-generator
          list-generator-of pair-generator-of procedure-generator-of
          vector-generator-of)
  (begin

    (define default-runs 100)

    (define max-exact (expt 2 24))
    (define min-exact (- (expt 2 24)))

    (define max-inexact 3.4e38)
    (define min-inexact -3.4e38)

    (define max-size 64)
    (define max-char #x110000)

    (define special-number
      (append
       '(0 1 -1)
       (cond-expand (exact-complex '(0+i 0-i 1+i 1-i -1+i -1-i))
                    (else '()))
       '(0.0 -0.0 0.5 -0.5 1.0 -1.0)
       '(0.0+1.0i 0.0-1.0i -0.0+1.0i -0.0-1.0i
         0.5+0.5i 0.5-0.5i -0.5+0.5i -0.5-0.5i
         1.0+1.0i 1.0-1.0i -1.0+1.0i -1.0-1.0i
         +inf.0+inf.0i +inf.0-inf.0i -inf.0+inf.0i -inf.0-inf.0i
         +nan.0+nan.0i)
       '(+inf.0 -inf.0 +nan.0)))

    (define (boolean-generator)
      (gcons* #t #f (make-random-boolean-generator)))

    (define (bytevector-generator)
      (let ((gen (make-random-u8-generator)))
        (gcons* (bytevector)
                (gmap (lambda (len)
                        (let ((bv (make-bytevector len)))
                          (do ((i 0 (+ i 1)))
                              ((= i len) bv)
                            (bytevector-u8-set! bv i (gen)))))
                      (make-random-integer-generator 0 max-size)))))

    (define (char-generator)
      (gcons* #\null
              (gmap integer->char
                    (gfilter (lambda (x)
                               (or (< x #xD800) (> x #xDFFF)))
                             (make-random-integer-generator 0 max-char)))))

    (define (string-generator)
      (gcons* ""
              (gmap (lambda (n)
                      (generator->string (gdrop (char-generator) 1) n))
                    (make-random-integer-generator 1 max-size))))

    (define (symbol-generator)
      (gmap string->symbol (string-generator)))

    (define (exact-complex-generator)
      (cond-expand (exact-complex
                    (gappend (gfilter (lambda (x)
                                        (and (complex? x)
                                             (exact? (real-part x))
                                             (exact? (imag-part x))))
                                      (list->generator special-number))
                             (gmap make-rectangular
                                   (exact-real-generator)
                                   (exact-real-generator))))
                   (else (error "Exact complex is not supported."))))

    (define (exact-integer-generator)
      (gappend (gfilter (lambda (x)
                          (and (exact? x) (integer? x)))
                        (list->generator special-number))
               (make-random-integer-generator min-exact max-exact)))

    (define (exact-number-generator)
      (gappend
       (gfilter exact? (list->generator special-number))
       (cond-expand
        (exact-complex
         (gsampling (gmap make-rectangular
                          (exact-real-generator) (exact-real-generator))
                    (make-random-integer-generator min-exact max-exact)))
        (else
         (make-random-integer-generator min-exact max-exact)))))

    (define (exact-rational-generator)
      (gappend
       (gfilter (lambda (x)
                  (and (rational? x) (exact? x)))
                (list->generator special-number))
       (make-random-integer-generator min-exact max-exact)))

    (define (exact-real-generator)
      (gappend
       (gfilter (lambda (x)
                  (and (real? x) (exact? x)))
                (list->generator special-number))
       (make-random-integer-generator min-exact max-exact)))

    (define (exact-integer-complex-generator)
      (cond-expand
       (exact-complex
        (gappend (gfilter (lambda (x)
                            (and (complex? x)
                                 (exact? (real-part x))
                                 (exact? (imag-part x))
                                 (integer? (real-part x))
                                 (integer? (imag-part x))))
                          (list->generator special-number))
                 (gmap make-rectangular
                       (make-random-integer-generator min-exact max-exact)
                       (make-random-integer-generator min-exact max-exact))))
       (else (error "Exact complex is not supported."))))

    (define (inexact-complex-generator)
      (gappend (gfilter (lambda (x)
                          (and (complex? x)
                               (inexact? (real-part x))
                               (inexact? (imag-part x))))
                        (list->generator special-number))
               (make-random-rectangular-generator min-inexact max-inexact
                                                  min-inexact max-inexact)))

    (define (inexact-integer-generator)
      (gmap inexact (exact-integer-generator)))

    (define (inexact-number-generator)
      (gappend (gfilter inexact? (list->generator special-number))
               (gsampling (make-random-rectangular-generator
                           min-inexact max-inexact min-inexact max-inexact)
                          (make-random-real-generator min-inexact max-inexact))))

    (define (inexact-rational-generator)
      (gappend (gfilter (lambda (x)
                          (and (rational? x)
                               (inexact? x)))
                        (list->generator special-number))
               (make-random-real-generator min-inexact max-inexact)))

    (define (inexact-real-generator)
      (gappend (gfilter (lambda (x)
                          (and (real? x)
                               (inexact? x)))
                        (list->generator special-number))
               (make-random-real-generator min-inexact max-inexact)))

    (define (complex-generator)
      (cond-expand (exact-complex
                    (gsampling (exact-complex-generator)
                               (inexact-complex-generator)))
                   (else
                    (inexact-complex-generator))))

    (define (integer-generator)
      (gsampling (exact-integer-generator)
                 (inexact-integer-generator)))

    (define (number-generator)
      (gsampling (exact-number-generator)
                 (inexact-number-generator)))

    (define (rational-generator)
      (gsampling (exact-rational-generator)
                 (inexact-rational-generator)))

    (define (real-generator)
      (gsampling (exact-real-generator)
                 (inexact-real-generator)))

    (define list-generator-of
      (case-lambda
        ((gen)
         (gcons* '()
                 (gmap (lambda (len)
                         (generator->list gen len))
                       (make-random-integer-generator 1 max-size))))
        ((gen max-length)
         (gcons* '()
                 (gmap (lambda (len)
                         (generator->list gen len))
                       (make-random-integer-generator 1 max-length))))))

    (define pair-generator-of
      (case-lambda
        ((gen1) (gmap cons gen1 gen1))
        ((gen1 gen2) (gmap cons gen1 gen2))))

    (define (procedure-generator-of gen)
      (gmap (lambda (x)
              (lambda _ x))
            gen))

    (define vector-generator-of
      (case-lambda
        ((gen)
         (gcons* (vector)
                 (gmap (lambda (len)
                         (generator->vector gen len))
                       (make-random-integer-generator 0 max-size))))
        ((gen max-length)
         (gcons* (vector)
                 (gmap (lambda (len)
                         (generator->vector gen len))
                       (make-random-integer-generator 0 max-length))))))

    (define (property-test-runner)
      (let ((runner (test-runner-simple)))
        runner))

    (define (prop-test property generators runs)
      (for-each
       (lambda (n)
         (test-assert
             (apply property
                    (let ((args (map (lambda (gen) (gen)) generators))
                          (runner (test-runner-current)))
                      (test-result-set! runner 'property-test-arguments args)
                      (test-result-set! runner 'property-test-iteration
                                        (+ n 1))
                      (test-result-set! runner 'property-test-iterations runs)
                      args))))
       (iota runs)))

    (define (prop-test-error type property generators runs)
      (for-each
       (lambda (n)
         (test-error
          type
          (apply property
                 (let ((args (map (lambda (gen) (gen)) generators))
                       (runner (test-runner-current)))
                   (test-result-set! runner 'property-test-arguments args)
                   (test-result-set! runner 'property-test-iteration (+ n 1))
                   (test-result-set! runner 'property-test-iterations runs)
                   args))))
       (iota runs)))

    (define test-property-error
      (case-lambda
        ((property generators)
         (prop-test-error #t property generators default-runs))
        ((property generators n)
         (prop-test-error #t property generators n))))

    (define test-property-error-type
      (case-lambda
        ((type property generators)
         (prop-test-error type property generators default-runs))
        ((type property generators n)
         (prop-test-error type property generators n))))

    (define test-property-skip
      (case-lambda
        ((property generators)
         (begin (test-skip default-runs)
                (prop-test property generators default-runs)))
        ((property generators n)
         (begin (test-skip n)
                (prop-test property generators n)))))

    (define test-property-expect-fail
      (case-lambda
        ((property generators)
         (begin (test-expect-fail default-runs)
                (prop-test property generators default-runs)))
        ((property generators n)
         (begin (test-expect-fail n)
                (prop-test property generators n)))))

    (define test-property
      (case-lambda
        ((property generators)
         (prop-test property generators default-runs))
        ((property generators n)
         (prop-test property generators n))))))
