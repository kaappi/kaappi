(define-library (srfi 235)
  (import (scheme base) (scheme case-lambda))
  (export constantly complement swap flip
          on each-of all-of any-of
          conjoin disjoin
          compose o)
  (begin
    (define (constantly . vals)
      (lambda args (apply values vals)))

    (define (complement pred)
      (lambda args (not (apply pred args))))

    (define (swap f)
      (lambda (a b . rest) (apply f b a rest)))

    (define (flip f)
      (lambda args (apply f (reverse args))))

    (define (on f g)
      (lambda args (apply f (map g args))))

    (define (each-of . procs)
      (lambda args
        (for-each (lambda (p) (apply p args)) procs)))

    (define (all-of pred)
      (lambda (lst) (let loop ((l lst))
                      (or (null? l) (and (pred (car l)) (loop (cdr l)))))))

    (define (any-of pred)
      (lambda (lst) (let loop ((l lst))
                      (and (not (null? l)) (or (pred (car l)) (loop (cdr l)))))))

    (define (conjoin . preds)
      (lambda args (let loop ((ps preds))
                     (or (null? ps) (and (apply (car ps) args) (loop (cdr ps)))))))

    (define (disjoin . preds)
      (lambda args (let loop ((ps preds))
                     (and (not (null? ps)) (or (apply (car ps) args) (loop (cdr ps)))))))

    (define (compose . procs)
      (if (null? procs) values
          (let ((f (car procs)) (rest (cdr procs)))
            (if (null? rest) f
                (let ((g (apply compose rest)))
                  (lambda args (call-with-values (lambda () (apply g args)) f)))))))

    (define o compose)))
