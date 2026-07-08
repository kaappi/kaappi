(define-library (srfi 41)
  (import (scheme base) (scheme lazy) (scheme write))
  (export stream-null stream-cons stream? stream-null? stream-pair?
          stream-car stream-cdr stream-lambda
          stream stream-unfold stream-map stream-for-each
          stream-filter stream-fold stream-take stream-drop
          stream-ref stream-length stream->list list->stream
          stream-append stream-zip
          define-stream stream-let
          stream-from stream-range stream-iterate stream-constant
          stream-take-while stream-drop-while
          stream-scan stream-reverse stream-concat
          port->stream stream-unfolds
          stream-match stream-of)
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
        ((stream) (delay '()))
        ((stream x rest ...)
         (stream-cons x (stream rest ...)))))

    (define (stream-unfold mapper pred gen seed)
      (define (unfold-loop s)
        (if (pred s)
            (stream-cons (mapper s) (unfold-loop (gen s)))
            stream-null))
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
      (define (any-null? ss)
        (and (not (null? ss))
             (or (stream-null? (car ss))
                 (any-null? (cdr ss)))))
      (define (zip-loop ss)
        (if (or (null? ss) (any-null? ss))
            stream-null
            (stream-cons (map stream-car ss)
                         (zip-loop (map stream-cdr ss)))))
      (zip-loop strms))

    ;; --- derived library (SRFI-41 §2) ---

    (define-syntax define-stream
      (syntax-rules ()
        ((define-stream (name . formals) body0 body1 ...)
         (define name (stream-lambda formals body0 body1 ...)))))

    (define-syntax stream-let
      (syntax-rules ()
        ((stream-let tag ((name val) ...) body0 body1 ...)
         ((letrec ((tag (stream-lambda (name ...) body0 body1 ...))) tag)
          val ...))))

    (define (stream-from first . step)
      (let ((delta (if (null? step) 1 (car step))))
        (stream-let loop ((n first))
          (stream-cons n (loop (+ n delta))))))

    (define (stream-range first past . step)
      (let* ((delta (cond ((pair? step) (car step))
                          ((< first past) 1)
                          (else -1)))
             (lt? (if (< 0 delta) < >)))
        (stream-let loop ((n first))
          (if (lt? n past)
              (stream-cons n (loop (+ n delta)))
              stream-null))))

    (define (stream-iterate proc base)
      (stream-let loop ((v base))
        (stream-cons v (loop (proc v)))))

    (define stream-constant
      (stream-lambda objs
        (cond ((null? objs) stream-null)
              ((null? (cdr objs))
               (stream-cons (car objs) (stream-constant (car objs))))
              (else
               (stream-cons (car objs)
                            (apply stream-constant
                                   (append (cdr objs)
                                           (list (car objs)))))))))

    (define (stream-take-while pred? strm)
      (stream-let loop ((s strm))
        (cond ((stream-null? s) stream-null)
              ((pred? (stream-car s))
               (stream-cons (stream-car s) (loop (stream-cdr s))))
              (else stream-null))))

    (define (stream-drop-while pred? strm)
      (stream-let loop ((s strm))
        (if (and (stream-pair? s) (pred? (stream-car s)))
            (loop (stream-cdr s))
            s)))

    (define (stream-scan proc base strm)
      (stream-let loop ((b base) (s strm))
        (if (stream-null? s)
            (stream b)
            (stream-cons b (loop (proc b (stream-car s))
                                 (stream-cdr s))))))

    (define (stream-reverse strm)
      (stream-let loop ((s strm) (rev stream-null))
        (if (stream-null? s)
            rev
            (loop (stream-cdr s)
                  (stream-cons (stream-car s) rev)))))

    (define (stream-concat strms)
      (stream-let loop ((ss strms))
        (cond ((stream-null? ss) stream-null)
              ((stream-null? (stream-car ss))
               (loop (stream-cdr ss)))
              (else
               (stream-cons
                (stream-car (stream-car ss))
                (loop (stream-cons (stream-cdr (stream-car ss))
                                   (stream-cdr ss))))))))

    (define (port->stream . args)
      (let ((p (if (null? args) (current-input-port) (car args))))
        (stream-let loop ((p p))
          (let ((c (read-char p)))
            (if (eof-object? c)
                stream-null
                (stream-cons c (loop p)))))))

    (define (stream-unfolds gen seed)
      (define (len-values gen seed)
        (call-with-values
          (lambda () (gen seed))
          (lambda vs (- (length vs) 1))))
      (define unfold-result-stream
        (stream-lambda (gen seed)
          (call-with-values
            (lambda () (gen seed))
            (lambda (next . results)
              (stream-cons results
                           (unfold-result-stream gen next))))))
      (define result-stream->output-stream
        (stream-lambda (result-stream i)
          (let ((result (list-ref (stream-car result-stream) (- i 1))))
            (cond ((pair? result)
                   (stream-cons
                    (car result)
                    (result-stream->output-stream
                     (stream-cdr result-stream) i)))
                  ((not result)
                   (result-stream->output-stream
                    (stream-cdr result-stream) i))
                  ((null? result) stream-null)
                  (else (error "stream-unfolds: unexpected result"))))))
      (define (result-stream->output-streams result-stream)
        (let loop ((i (len-values gen seed)) (outputs '()))
          (if (zero? i)
              (apply values outputs)
              (loop (- i 1)
                    (cons (result-stream->output-stream result-stream i)
                          outputs)))))
      (result-stream->output-streams (unfold-result-stream gen seed)))

    (define-syntax stream-match
      (syntax-rules ()
        ((stream-match strm-expr clause ...)
         (letrec-syntax
           ((smp
             (syntax-rules (_)
               ((smp s () body)
                (and (stream-null? s) body))
               ((smp s (_ . rest) body)
                (and (stream-pair? s)
                     (let ((tail (stream-cdr s)))
                       (smp tail rest body))))
               ((smp s (var . rest) body)
                (and (stream-pair? s)
                     (let ((var (stream-car s))
                           (tail (stream-cdr s)))
                       (smp tail rest body))))
               ((smp s _ body)
                body)
               ((smp s var body)
                (let ((var s)) body))))
            (smt
             (syntax-rules ()
               ((smt s (pattern fender expr))
                (smp s pattern (and fender (list expr))))
               ((smt s (pattern expr))
                (smp s pattern (list expr))))))
           (let ((strm strm-expr))
             (cond
              ((smt strm clause) => car) ...
              (else (error "stream-match: no matching pattern"))))))))

    (define-syntax stream-of-aux
      (syntax-rules (in is)
        ((stream-of-aux expr base)
         (stream-cons expr base))
        ((stream-of-aux expr base (var in strm) rest ...)
         (stream-let loop ((s strm))
           (if (stream-null? s)
               base
               (let ((var (stream-car s)))
                 (stream-of-aux expr (loop (stream-cdr s)) rest ...)))))
        ((stream-of-aux expr base (var is exp) rest ...)
         (let ((var exp)) (stream-of-aux expr base rest ...)))
        ((stream-of-aux expr base pred? rest ...)
         (if pred? (stream-of-aux expr base rest ...) base))))

    (define-syntax stream-of
      (syntax-rules ()
        ((stream-of expr rest ...)
         (stream-of-aux expr stream-null rest ...))))))
