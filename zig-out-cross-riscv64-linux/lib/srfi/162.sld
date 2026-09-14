(define-library (srfi 162)
  (import (scheme base) (scheme case-lambda) (scheme char) (srfi 128))
  (export comparator-max comparator-min
          comparator-max-in-list comparator-min-in-list
          default-comparator
          boolean-comparator real-comparator
          char-comparator char-ci-comparator
          string-comparator string-ci-comparator
          pair-comparator list-comparator vector-comparator
          eq-comparator eqv-comparator equal-comparator)
  (begin
    (define (comparator-max cmp . args)
      (let ((ordering (comparator-ordering-predicate cmp)))
        (let loop ((best (car args)) (rest (cdr args)))
          (if (null? rest)
              best
              (loop (if (ordering best (car rest)) (car rest) best)
                    (cdr rest))))))

    (define (comparator-min cmp . args)
      (let ((ordering (comparator-ordering-predicate cmp)))
        (let loop ((best (car args)) (rest (cdr args)))
          (if (null? rest)
              best
              (loop (if (ordering (car rest) best) (car rest) best)
                    (cdr rest))))))

    (define (comparator-max-in-list cmp lst)
      (apply comparator-max cmp lst))

    (define (comparator-min-in-list cmp lst)
      (apply comparator-min cmp lst))

    (define default-comparator (make-default-comparator))

    (define boolean-comparator
      (make-comparator boolean? boolean=?
                       (lambda (a b) (and (not a) b))
                       boolean-hash))

    (define real-comparator
      (make-comparator real? = < number-hash))

    (define char-comparator
      (make-comparator char? char=? char<? char-hash))

    (define char-ci-comparator
      (make-comparator char? char-ci=? char-ci<? char-ci-hash))

    (define string-comparator
      (make-comparator string? string=? string<? string-hash))

    (define string-ci-comparator
      (make-comparator string? string-ci=? string-ci<? string-ci-hash))

    (define (%pair-ordering a b)
      (let ((cmp default-comparator))
        (let ((oa (comparator-ordering-predicate cmp)))
          (cond
            ((oa (car a) (car b)) #t)
            ((oa (car b) (car a)) #f)
            (else (oa (cdr a) (cdr b)))))))

    (define pair-comparator
      (make-comparator pair? equal? %pair-ordering default-hash))

    (define (%list-ordering a b)
      (let ((oa (comparator-ordering-predicate default-comparator)))
        (cond
          ((and (null? a) (null? b)) #f)
          ((null? a) #t)
          ((null? b) #f)
          ((oa (car a) (car b)) #t)
          ((oa (car b) (car a)) #f)
          (else (%list-ordering (cdr a) (cdr b))))))

    (define list-comparator
      (make-comparator list? equal? %list-ordering default-hash))

    (define (%vector-ordering a b)
      (let ((la (vector-length a))
            (lb (vector-length b))
            (oa (comparator-ordering-predicate default-comparator)))
        (let loop ((i 0))
          (cond
            ((= i la) (< la lb))
            ((= i lb) #f)
            ((oa (vector-ref a i) (vector-ref b i)) #t)
            ((oa (vector-ref b i) (vector-ref a i)) #f)
            (else (loop (+ i 1)))))))

    (define vector-comparator
      (make-comparator vector? equal? %vector-ordering default-hash))

    (define eq-comparator (make-eq-comparator))
    (define eqv-comparator (make-eqv-comparator))
    (define equal-comparator (make-equal-comparator))))
