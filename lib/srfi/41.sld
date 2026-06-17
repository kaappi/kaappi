(define-library (srfi 41)
  (import (scheme base) (scheme lazy) (scheme write))
  (export stream-null stream-cons stream? stream-null? stream-pair?
          stream-car stream-cdr stream-lambda
          stream stream-unfold stream-map stream-for-each
          stream-filter stream-fold stream-take stream-drop
          stream-ref stream-length stream->list list->stream
          stream-append stream-zip)
  (begin
    (define stream-null (delay '()))

    (define-syntax stream-cons
      (syntax-rules ()
        ((stream-cons obj strm)
         (delay (cons obj (delay strm))))))

    (define (stream? x)
      (and (promise? x)
           (let ((v (force x)))
             (or (null? v) (pair? v)))))

    (define (stream-null? x) (null? (force x)))
    (define (stream-pair? x) (pair? (force x)))
    (define (stream-car strm) (car (force strm)))
    (define (stream-cdr strm) (force (cdr (force strm))))

    (define-syntax stream-lambda
      (syntax-rules ()
        ((stream-lambda formals body ...)
         (lambda formals (delay (begin body ...))))))

    (define-syntax stream
      (syntax-rules ()
        ((stream) stream-null)
        ((stream x rest ...)
         (stream-cons x (stream rest ...)))))

    (define (stream-unfold mapper pred gen seed)
      (define (unfold-loop s)
        (if (pred s)
            stream-null
            (stream-cons (mapper s) (unfold-loop (gen s)))))
      (unfold-loop seed))

    (define (stream-map proc strm)
      (define (map-loop s)
        (if (stream-null? s)
            stream-null
            (stream-cons (proc (stream-car s))
                         (map-loop (stream-cdr s)))))
      (map-loop strm))

    (define (stream-for-each proc strm)
      (if (not (stream-null? strm))
          (begin (proc (stream-car strm))
                 (stream-for-each proc (stream-cdr strm)))))

    (define (stream-filter pred strm)
      (define (filter-loop s)
        (if (stream-null? s)
            stream-null
            (if (pred (stream-car s))
                (stream-cons (stream-car s)
                             (filter-loop (stream-cdr s)))
                (filter-loop (stream-cdr s)))))
      (filter-loop strm))

    (define (stream-fold proc base strm)
      (if (stream-null? strm)
          base
          (stream-fold proc
                       (proc base (stream-car strm))
                       (stream-cdr strm))))

    (define (stream-take n strm)
      (define (take-loop k s)
        (if (or (= k 0) (stream-null? s))
            stream-null
            (stream-cons (stream-car s)
                         (take-loop (- k 1) (stream-cdr s)))))
      (take-loop n strm))

    (define (stream-drop n strm)
      (define (drop-loop k s)
        (if (or (= k 0) (stream-null? s))
            s
            (drop-loop (- k 1) (stream-cdr s))))
      (drop-loop n strm))

    (define (stream-ref strm n)
      (if (= n 0)
          (stream-car strm)
          (stream-ref (stream-cdr strm) (- n 1))))

    (define (stream-length strm)
      (stream-fold (lambda (acc x) (+ acc 1)) 0 strm))

    (define (stream->list strm)
      (if (stream-null? strm)
          '()
          (cons (stream-car strm)
                (stream->list (stream-cdr strm)))))

    (define (list->stream lst)
      (if (null? lst)
          stream-null
          (stream-cons (car lst) (list->stream (cdr lst)))))

    (define (stream-append . strms)
      (define (append2 s1 s2)
        (if (stream-null? s1)
            s2
            (stream-cons (stream-car s1)
                         (append2 (stream-cdr s1) s2))))
      (if (null? strms) stream-null
          (if (null? (cdr strms)) (car strms)
              (append2 (car strms)
                       (apply stream-append (cdr strms))))))

    (define (stream-zip . strms)
      (define (zip-loop ss)
        (if (or (null? ss) (stream-null? (car ss)))
            stream-null
            (stream-cons (map stream-car ss)
                         (zip-loop (map stream-cdr ss)))))
      (zip-loop strms))))
