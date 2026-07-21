(define-library (srfi 221)
  (import (scheme base) (scheme case-lambda)
          (srfi 1) (srfi 41) (srfi 158))
  (export accumulate-generated-values
          gdelete-duplicates
          genumerate
          gcompose-left gcompose-right
          gchoice
          generator->stream stream->generator)
  (begin
    (define (accumulate-generated-values acc gen)
      (let ((value (gen)))
        (if (eof-object? value)
            (acc value)
            (begin
              (acc value)
              (accumulate-generated-values acc gen)))))

    (define gdelete-duplicates
      (case-lambda
        ((gen) (gdelete-duplicates* gen equal?))
        ((gen =) (gdelete-duplicates* gen =))))

    (define (gdelete-duplicates* gen =)
      (define seen '())
      (define (=* a b) (= b a))
      (lambda ()
        (let loop ((value (gen)))
          (cond
            ((eof-object? value) value)
            ((member value seen =*)
             (loop (gen)))
            (else
             (set! seen (cons value seen))
             value)))))

    (define (genumerate gen)
      (gmap cons (make-range-generator 0) gen))

    (define (gcompose-left constr . ops)
      (let loop ((gen (constr)) (ops ops))
        (if (null? ops)
            gen
            (loop ((car ops) gen) (cdr ops)))))

    (define (gcompose-right . args)
      (apply gcompose-left (reverse args)))

    (define (gchoice choice-gen . source-gens)
      (define source-gens-v (list->vector source-gens))
      (define l (vector-length source-gens-v))
      (define exhausted-count 0)
      (lambda ()
        (let loop ((i (choice-gen)))
          (cond
            ((= exhausted-count l) (eof-object))
            ((eof-object? i) (eof-object))
            (else
             (let ((gen (vector-ref source-gens-v i)))
               (if (not gen)
                   (loop (choice-gen))
                   (let ((value (gen)))
                     (if (eof-object? value)
                         (begin
                           (vector-set! source-gens-v i #f)
                           (set! exhausted-count (+ 1 exhausted-count))
                           (loop (choice-gen)))
                         value)))))))))

    (define (generator->stream gen)
      (define gen-stream
        (stream-lambda ()
          (stream-cons (gen) (gen-stream))))
      (stream-take-while
        (lambda (value) (not (eof-object? value)))
        (gen-stream)))

    (define (stream->generator stream)
      (let ((s stream))
        (lambda ()
          (if (stream-null? s)
              (eof-object)
              (let ((value (stream-car s)))
                (set! s (stream-cdr s))
                value)))))))
